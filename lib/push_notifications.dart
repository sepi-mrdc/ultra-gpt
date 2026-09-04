import "dart:async";

import "package:device_info_plus/device_info_plus.dart";
import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:flutter_inappwebview/flutter_inappwebview.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:permission_handler/permission_handler.dart";

import "app_urls.dart";
import "fcm_device_api.dart";

const ultraGptNotificationChannelId = "ultragpt_notifications";
const ultraGptNotificationChannelName = "UltraGPT";
const ultraGptNotificationChannelDescription = "UltraGPT notifications";

bool get isAndroidPushSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

@pragma("vm:entry-point")
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
}

class UltraGptPushNotifications {
  UltraGptPushNotifications._({
    required FcmDeviceApi api,
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
    CookieManager? cookieManager,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _cookieManager = cookieManager ?? CookieManager.instance(),
       _registration = FcmRegistrationCoordinator(api: api);

  static final UltraGptPushNotifications instance =
      UltraGptPushNotifications._(api: FcmDeviceApi());

  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final CookieManager _cookieManager;
  final FcmRegistrationCoordinator _registration;

  final _subscriptions = <StreamSubscription<dynamic>>[];
  void Function(Uri url)? _onOpenUrl;
  Uri? _pendingUrl;
  String? _fcmToken;
  bool _initialized = false;

  void setOpenUrlHandler(void Function(Uri url)? handler) {
    _onOpenUrl = handler;
    final pending = _pendingUrl;
    if (handler != null && pending != null) {
      _pendingUrl = null;
      handler(pending);
    }
  }

  Uri? consumePendingUrl() {
    final pending = _pendingUrl;
    _pendingUrl = null;
    return pending;
  }

  Future<void> initialize() async {
    if (!isAndroidPushSupported || _initialized) return;

    await _initializeLocalNotifications();
    await _createNotificationChannel();
    await _requestNotificationPermission();

    _registration.setDeviceMetadata(
      deviceId: await _readDeviceId(),
      appVersion: await _readAppVersion(),
    );

    _subscriptions.add(_messaging.onTokenRefresh.listen(_onTokenRefresh));
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen(_onForegroundMessage),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp),
    );

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _queueNotificationUrl(initialMessage.data["url"]);
    }

    try {
      _fcmToken = await _messaging.getToken();
    } catch (_) {
      _fcmToken = null;
    }

    _initialized = true;
  }

  Future<void> syncRegistration({WebUri? currentUrl}) async {
    if (!isAndroidPushSupported || !_initialized) return;

    final sessionToken = await readSessionToken(currentUrl: currentUrl);
    await _registration.sync(sessionToken: sessionToken, fcmToken: _fcmToken);
  }

  Future<String?> readSessionToken({WebUri? currentUrl}) async {
    final origins = <String>{
      "https://${UltraGptUrls.host}",
      "https://${UltraGptUrls.apiHost}",
      "https://${UltraGptUrls.stagingHost}",
    };

    final current = currentUrl?.toString();
    if (current != null) {
      final uri = Uri.tryParse(current);
      if (uri != null &&
          (uri.scheme == "http" || uri.scheme == "https") &&
          uri.host.isNotEmpty) {
        origins.add("${uri.scheme}://${uri.host}");
      }
    }

    for (final origin in origins) {
      try {
        final cookie = await _cookieManager.getCookie(
          url: WebUri(origin),
          name: UltraGptUrls.sessionCookieName,
        );
        final value = cookie?.value;
        if (value == null) continue;
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) return trimmed;
      } catch (_) {
        // Cookie lookup is best-effort per origin.
      }
    }

    return null;
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _onOpenUrl = null;
  }

  Future<void> _onTokenRefresh(String token) async {
    _fcmToken = token;
    await _registration.sync(
      sessionToken: await readSessionToken(),
      fcmToken: token,
    );
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    await _showLocalNotification(message);
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    _queueNotificationUrl(message.data["url"]);
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title?.trim();
    final body = notification?.body?.trim();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    final url = message.data["url"];
    final payload = url is String ? url : null;
    final id = _localNotificationId(message);

    try {
      await _localNotifications.show(
        id,
        title == null || title.isEmpty ? "UltraGPT" : title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            ultraGptNotificationChannelId,
            ultraGptNotificationChannelName,
            channelDescription: ultraGptNotificationChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: "ic_notification",
          ),
        ),
        payload: payload,
      );
    } catch (_) {
      // Foreground display is best-effort.
    }
  }

  int _localNotificationId(RemoteMessage message) {
    final notificationId = message.data["notificationId"];
    if (notificationId is String && notificationId.isNotEmpty) {
      return notificationId.hashCode & 0x7fffffff;
    }
    return message.hashCode & 0x7fffffff;
  }

  void _onLocalNotificationTap(NotificationResponse response) {
    _queueNotificationUrl(response.payload);
  }

  void _queueNotificationUrl(String? raw) {
    final url = UltraGptUrls.resolveNotificationUrl(raw);
    if (url == null) return;

    final handler = _onOpenUrl;
    if (handler == null) {
      _pendingUrl = url;
      return;
    }
    handler(url);
  }

  Future<void> _initializeLocalNotifications() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings("ic_notification"),
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _queueNotificationUrl(launchDetails?.notificationResponse?.payload);
    }
  }

  Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      ultraGptNotificationChannelId,
      ultraGptNotificationChannelName,
      description: ultraGptNotificationChannelDescription,
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await Permission.notification.request();
    } catch (_) {
      // permission_handler may be unavailable on some Android versions.
    }

    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {
      // FCM permission request is best-effort.
    }
  }

  Future<String?> _readDeviceId() async {
    if (!isAndroidPushSupported) return null;

    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final id = info.id.trim();
      if (id.isEmpty || id.toLowerCase() == "unknown") return null;
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      return version.isEmpty ? null : version;
    } catch (_) {
      return null;
    }
  }
}
