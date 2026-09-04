import "dart:convert";

import "package:http/http.dart" as http;

import "app_urls.dart";

class FcmDeviceApi {
  FcmDeviceApi({http.Client? client, this.timeout = const Duration(seconds: 20)})
    : _client = client ?? http.Client();

  static const platformAndroid = "android";

  final http.Client _client;
  final Duration timeout;

  Future<bool> register({
    required String token,
    required String sessionToken,
    String? deviceId,
    String? appVersion,
  }) async {
    final body = <String, String>{
      "token": token,
      "platform": platformAndroid,
    };
    if (deviceId != null && deviceId.isNotEmpty) {
      body["deviceId"] = deviceId;
    }
    if (appVersion != null && appVersion.isNotEmpty) {
      body["appVersion"] = appVersion;
    }

    try {
      final response = await _client
          .post(
            UltraGptUrls.apiFcmDevicesUri,
            headers: _headers(sessionToken),
            body: jsonEncode(body),
          )
          .timeout(timeout);
      return _isSuccess(response.statusCode);
    } catch (_) {
      return false;
    }
  }

  Future<bool> unregister({
    required String token,
    required String sessionToken,
  }) async {
    try {
      final response = await _client
          .delete(
            UltraGptUrls.apiFcmDevicesUri,
            headers: _headers(sessionToken),
            body: jsonEncode({"token": token}),
          )
          .timeout(timeout);
      return _isSuccess(response.statusCode);
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _headers(String sessionToken) {
    return {
      "Authorization": "Bearer $sessionToken",
      "Content-Type": "application/json",
    };
  }

  bool _isSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;
}

/// Registers the current FCM token once per session and unregisters on logout.
class FcmRegistrationCoordinator {
  FcmRegistrationCoordinator({required FcmDeviceApi api}) : _api = api;

  final FcmDeviceApi _api;

  String? _registeredToken;
  String? _registeredSession;
  String? _deviceId;
  String? _appVersion;
  Future<void> _inFlight = Future<void>.value();

  String? get registeredToken => _registeredToken;

  void setDeviceMetadata({String? deviceId, String? appVersion}) {
    _deviceId = deviceId;
    _appVersion = appVersion;
  }

  Future<void> sync({
    required String? sessionToken,
    required String? fcmToken,
  }) {
    final previous = _inFlight;
    _inFlight = () async {
      try {
        await previous;
      } catch (_) {}
      await _sync(sessionToken: sessionToken, fcmToken: fcmToken);
    }();
    return _inFlight;
  }

  Future<void> _sync({
    required String? sessionToken,
    required String? fcmToken,
  }) async {
    final session = sessionToken?.trim();
    final token = fcmToken?.trim();

    if (session == null || session.isEmpty) {
      await _unregisterIfNeeded();
      return;
    }

    if (token == null || token.isEmpty) return;

    if (_registeredToken == token && _registeredSession == session) {
      return;
    }

    final registered = await _api.register(
      token: token,
      sessionToken: session,
      deviceId: _deviceId,
      appVersion: _appVersion,
    );
    if (!registered) return;

    _registeredToken = token;
    _registeredSession = session;
  }

  Future<void> _unregisterIfNeeded() async {
    final token = _registeredToken;
    final session = _registeredSession;
    if (token == null || session == null) return;

    final unregistered = await _api.unregister(
      token: token,
      sessionToken: session,
    );
    if (!unregistered) return;

    _registeredToken = null;
    _registeredSession = null;
  }
}
