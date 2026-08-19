import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';

import 'app_urls.dart';
import 'web_share_bridge.dart';

const Color _startupBackgroundColor = Color(0xFF010822);
const Color _startupForegroundColor = Color(0xFFE8ECF8);
const double _splashLogoSize = 240;
const Duration _startupRevealFadeDuration = Duration(milliseconds: 220);
const Duration _pageReadyTimeout = Duration(seconds: 3);
const Duration _pageReadyPollInterval = Duration(milliseconds: 80);
const Duration _pageReadyEvaluationTimeout = Duration(milliseconds: 250);

const SystemUiOverlayStyle _systemUiOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(_systemUiOverlayStyle);

  Uri? launchLink;
  try {
    launchLink = await AppLinks().getInitialLink();
  } catch (_) {
    launchLink = null;
  }

  runApp(
    MyApp(
      initialUrl: WebUri(
        UltraGptUrls.startUri(incoming: launchLink).toString(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.initialUrl});

  final WebUri? initialUrl;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _startupBackgroundColor,
        colorScheme: const ColorScheme.dark(
          surface: _startupBackgroundColor,
          primary: _startupForegroundColor,
        ),
      ),
      home: WebViewPage(initialUrl: initialUrl),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, this.initialUrl});

  final WebUri? initialUrl;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

enum PageLoadFailureKind { generic, network, timeout, server, ssl }

enum WebPermissionFallbackAction { none, retry, settings }

class WebPermissionResult {
  const WebPermissionResult({
    required this.granted,
    this.fallbackAction = WebPermissionFallbackAction.none,
    this.message,
    this.permission,
    this.permissionName,
  });

  final bool granted;
  final WebPermissionFallbackAction fallbackAction;
  final String? message;
  final Permission? permission;
  final String? permissionName;
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebUri _initialUrl;
  final WebUri _blankUrl = WebUri("about:blank");
  final AppLinks _appLinks = AppLinks();

  bool isInitialLoading = true;
  bool showStartupOverlay = true;
  bool isNavigating = false;
  bool hasLoadedInitialPage = false;
  bool hasNetworkSignal = true;
  bool pageLoadFailed = false;
  int pageProgress = 0;
  int pageLoadGeneration = 0;
  bool _isWaitingForReveal = false;
  PageLoadFailureKind pageLoadFailureKind = PageLoadFailureKind.generic;
  WebUri? currentMainFrameUrl;
  late final StreamSubscription connectivitySubscription;
  StreamSubscription<Uri>? appLinkSubscription;
  InAppWebViewController? webViewController;

  @override
  void initState() {
    super.initState();

    _initialUrl = widget.initialUrl ?? WebUri(UltraGptUrls.defaultChatUrl);
    currentMainFrameUrl = _initialUrl;

    connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (!mounted) return;

      setState(() {
        hasNetworkSignal = !results.contains(ConnectivityResult.none);
      });
    });

    appLinkSubscription = _appLinks.uriLinkStream.listen(_onIncomingAppLink);
  }

  @override
  void dispose() {
    pageLoadGeneration++;
    connectivitySubscription.cancel();
    appLinkSubscription?.cancel();
    super.dispose();
  }

  void _onIncomingAppLink(Uri uri) {
    final resolved = UltraGptUrls.resolveIncomingShare(uri);
    if (resolved == null) return;

    final nextUrl = WebUri(resolved.toString());
    if (nextUrl.toString() == currentMainFrameUrl?.toString() ||
        (nextUrl.toString() == _initialUrl.toString() &&
            !hasLoadedInitialPage)) {
      return;
    }

    final controller = webViewController;
    currentMainFrameUrl = nextUrl;
    if (controller == null) return;

    unawaited(controller.loadUrl(urlRequest: URLRequest(url: nextUrl)));
  }

  Future<void> _installShareBridge(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(source: shareBridgeJavaScript);
    } catch (_) {
      // The share polyfill is best-effort and should not block page load.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemUiOverlayStyle,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;

          final controller = webViewController;
          if (controller != null && await controller.canGoBack()) {
            await controller.goBack();
          } else {
            SystemNavigator.pop();
          }
        },
        child: Scaffold(
          backgroundColor: _startupBackgroundColor,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                _buildWebView(),
                if (pageLoadFailed)
                  Positioned.fill(child: _buildNoInternetView()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebView() {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: _initialUrl),
          initialSettings: InAppWebViewSettings(
            domStorageEnabled: true,
            databaseEnabled: true,
            cacheEnabled: true,
            clearCache: false,
            cacheMode: CacheMode.LOAD_DEFAULT,
            javaScriptEnabled: true,
            thirdPartyCookiesEnabled: true,
            sharedCookiesEnabled: true,
            loadsImagesAutomatically: true,
            offscreenPreRaster: true,
            useShouldOverrideUrlLoading: true,
            useOnDownloadStart: true,
            supportMultipleWindows: true,
            javaScriptCanOpenWindowsAutomatically: true,
            mediaPlaybackRequiresUserGesture: false,
            supportZoom: false,
            builtInZoomControls: false,
            displayZoomControls: false,
            verticalScrollBarEnabled: false,
            horizontalScrollBarEnabled: false,
            overScrollMode: OverScrollMode.NEVER,
            safeBrowsingEnabled: true,
            disableDefaultErrorPage: true,
            transparentBackground: false,
            underPageBackgroundColor: _startupBackgroundColor,
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;
            try {
              controller.addJavaScriptHandler(
                handlerName: shareConversationHandlerName,
                callback: (args) async {
                  await shareConversationFromWeb(
                    args.isEmpty ? null : args.first,
                  );
                  return true;
                },
              );
            } catch (_) {
              // Handler may already exist if the WebView is recreated.
            }

            final pendingShareUrl = currentMainFrameUrl;
            if (pendingShareUrl != null &&
                pendingShareUrl.toString() != _initialUrl.toString()) {
              unawaited(
                controller.loadUrl(
                  urlRequest: URLRequest(url: pendingShareUrl),
                ),
              );
            }
          },
          shouldOverrideUrlLoading: (_, navigationAction) async {
            final url = navigationAction.request.url;

            if (url == null || _isBlankUrl(url) || _isWebUrl(url)) {
              return NavigationActionPolicy.ALLOW;
            }

            await _openExternalUrl(url);
            return NavigationActionPolicy.CANCEL;
          },
          onDownloadStartRequest: (_, downloadStartRequest) async {
            await _openExternalUrl(downloadStartRequest.url);
          },
          onCreateWindow: (controller, createWindowAction) async {
            final url = createWindowAction.request.url;

            if (url == null) return false;

            if (_isWebUrl(url)) {
              await controller.loadUrl(urlRequest: URLRequest(url: url));
            } else {
              await _openExternalUrl(url);
            }

            return true;
          },
          onPermissionRequest: (_, request) async {
            final grantedResources = <PermissionResourceType>[];
            WebPermissionResult? blockedPermission;

            for (final resource in request.resources) {
              final result = await _requestWebPermission(resource);

              if (result.granted) {
                grantedResources.add(resource);
              } else {
                blockedPermission ??= result;
              }
            }

            final canGrantAll =
                grantedResources.length == request.resources.length;

            final response = PermissionResponse(
              resources: grantedResources,
              action: canGrantAll
                  ? PermissionResponseAction.GRANT
                  : PermissionResponseAction.DENY,
            );

            if (!canGrantAll && blockedPermission != null) {
              _showPermissionFallback(blockedPermission);
            }

            return response;
          },
          onProgressChanged: (controller, progress) {
            if (pageLoadFailed) return;

            setState(() {
              pageProgress = progress;
              isNavigating = !isInitialLoading && progress < 100;
            });

            if (!hasLoadedInitialPage && progress >= 85) {
              _revealInitialPageWhenReady(controller, pageLoadGeneration);
            }
          },
          onLoadStart: (_, url) {
            pageLoadGeneration++;
            _isWaitingForReveal = false;

            if (_isBlankUrl(url) && pageLoadFailed) {
              setState(() {
                isInitialLoading = false;
                showStartupOverlay = false;
                isNavigating = false;
              });
              return;
            }

            setState(() {
              if (!_isBlankUrl(url)) {
                currentMainFrameUrl = url;
              }
              isInitialLoading = !hasLoadedInitialPage;
              showStartupOverlay = !hasLoadedInitialPage;
              isNavigating = hasLoadedInitialPage;
              pageProgress = 0;
              pageLoadFailed = false;
            });
          },
          onLoadStop: (controller, __) {
            unawaited(_installShareBridge(controller));

            if (pageLoadFailed) {
              setState(() {
                isInitialLoading = false;
                showStartupOverlay = false;
                isNavigating = false;
              });
              return;
            }

            final loadGeneration = pageLoadGeneration;

            setState(() {
              isNavigating = false;
              pageProgress = 100;
              pageLoadFailed = false;
            });

            if (!hasLoadedInitialPage) {
              _revealInitialPageWhenReady(controller, loadGeneration);
            }
          },
          onPageCommitVisible: (controller, _) {
            if (!hasLoadedInitialPage) {
              _revealInitialPageWhenReady(controller, pageLoadGeneration);
            }
          },
          onReceivedError: (_, request, error) {
            if (_isMainFrameLoadError(request)) {
              _showLoadFailure(
                _classifyWebResourceError(error),
                failedUrl: request.url,
              );
            }
          },
          onReceivedHttpError: (_, request, errorResponse) {
            if (_isMainFrameLoadError(request) &&
                _shouldShowRetryForHttpStatus(errorResponse.statusCode)) {
              _showLoadFailure(
                PageLoadFailureKind.server,
                failedUrl: request.url,
              );
            }
          },
          onReceivedServerTrustAuthRequest: (_, __) async {
            _showLoadFailure(
              PageLoadFailureKind.ssl,
              failedUrl: currentMainFrameUrl ?? _initialUrl,
            );

            return ServerTrustAuthResponse(
              action: ServerTrustAuthResponseAction.CANCEL,
            );
          },
        ),
        if (showStartupOverlay && !pageLoadFailed)
          _StartupLoadingView(
            visible: isInitialLoading,
            onHidden: () {
              if (!mounted || isInitialLoading) return;

              setState(() {
                showStartupOverlay = false;
              });
            },
          ),
        if (isNavigating && !pageLoadFailed)
          LinearProgressIndicator(
            value: pageProgress > 0 ? pageProgress / 100 : null,
            minHeight: 3,
            color: _startupForegroundColor,
            backgroundColor: _startupForegroundColor.withValues(alpha: 0.12),
          ),
      ],
    );
  }

  Future<void> _revealInitialPageWhenReady(
    InAppWebViewController controller,
    int loadGeneration,
  ) async {
    if (_isWaitingForReveal ||
        hasLoadedInitialPage ||
        pageLoadFailed ||
        !mounted ||
        loadGeneration != pageLoadGeneration) {
      return;
    }

    _isWaitingForReveal = true;
    try {
      final isReady = await _waitForVisualReadiness(controller, loadGeneration);

      if (!mounted ||
          pageLoadFailed ||
          hasLoadedInitialPage ||
          loadGeneration != pageLoadGeneration) {
        return;
      }

      setState(() {
        hasLoadedInitialPage = true;
        isInitialLoading = false;
        isNavigating = false;
        pageProgress = isReady ? 100 : pageProgress;
        pageLoadFailed = false;
      });
    } finally {
      if (loadGeneration == pageLoadGeneration) {
        _isWaitingForReveal = false;
      }
    }
  }

  Future<bool> _waitForVisualReadiness(
    InAppWebViewController controller,
    int loadGeneration,
  ) async {
    final deadline = DateTime.now().add(_pageReadyTimeout);

    while (mounted &&
        !pageLoadFailed &&
        loadGeneration == pageLoadGeneration &&
        DateTime.now().isBefore(deadline)) {
      if (await _isPageVisuallyReady(controller)) {
        return true;
      }

      await Future<void>.delayed(_pageReadyPollInterval);
    }

    return false;
  }

  Future<bool> _isPageVisuallyReady(InAppWebViewController controller) async {
    try {
      final result = await controller
          .evaluateJavascript(
            source: '''
          (function () {
            var body = document.body;
            if (!body) return false;

            var readyState = document.readyState;
            if (readyState !== "interactive" && readyState !== "complete") {
              return false;
            }

            var root =
              document.getElementById("__nuxt") ||
              document.getElementById("app") ||
              document.getElementById("root") ||
              document.querySelector("[data-server-rendered]");

            if (
              root &&
              (root.childElementCount > 0 ||
                (root.innerText || "").trim().length > 0)
            ) {
              return true;
            }

            if (body.childElementCount > 1) return true;
            return (body.innerText || "").trim().length >= 16;
          })();
        ''',
          )
          .timeout(_pageReadyEvaluationTimeout, onTimeout: () => false);

      return result == true || result == 1 || result == "true";
    } catch (_) {
      return false;
    }
  }

  bool _isMainFrameLoadError(WebResourceRequest request) {
    final requestUrl = request.url.toString();

    return request.isForMainFrame == true ||
        requestUrl == currentMainFrameUrl?.toString() ||
        requestUrl == _initialUrl.toString();
  }

  bool _isBlankUrl(WebUri? url) {
    return url?.toString() == _blankUrl.toString();
  }

  bool _isWebUrl(WebUri url) {
    return url.scheme == "http" || url.scheme == "https";
  }

  Future<void> _openExternalUrl(WebUri url) async {
    final uri = Uri.parse(url.toString());

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _showExternalOpenFailure();
      }
    } catch (_) {
      _showExternalOpenFailure();
    }
  }

  Future<WebPermissionResult> _requestWebPermission(
    PermissionResourceType resource,
  ) async {
    if (resource == PermissionResourceType.CAMERA) {
      return _requestNativePermission(
        Permission.camera,
        permissionName: "Camera",
      );
    }

    if (resource == PermissionResourceType.MICROPHONE) {
      return _requestNativePermission(
        Permission.microphone,
        permissionName: "Microphone",
      );
    }

    if (resource == PermissionResourceType.CAMERA_AND_MICROPHONE) {
      final cameraResult = await _requestNativePermission(
        Permission.camera,
        permissionName: "Camera",
      );
      if (!cameraResult.granted) return cameraResult;

      final microphoneResult = await _requestNativePermission(
        Permission.microphone,
        permissionName: "Microphone",
      );
      if (!microphoneResult.granted) return microphoneResult;

      return const WebPermissionResult(granted: true);
    }

    return WebPermissionResult(
      granted: false,
      message: "${resource.toValue()} is not supported in this app.",
    );
  }

  Future<WebPermissionResult> _requestNativePermission(
    Permission permission, {
    required String permissionName,
  }) async {
    final currentStatus = await permission.status;

    if (currentStatus.isGranted) {
      return const WebPermissionResult(granted: true);
    }

    if (currentStatus.isPermanentlyDenied) {
      return WebPermissionResult(
        granted: false,
        fallbackAction: WebPermissionFallbackAction.settings,
        message:
            "$permissionName permission is blocked. Enable it in App Settings.",
        permission: permission,
        permissionName: permissionName,
      );
    }

    final requestedStatus = await permission.request();

    if (requestedStatus.isGranted) {
      return const WebPermissionResult(granted: true);
    }

    if (requestedStatus.isPermanentlyDenied) {
      return WebPermissionResult(
        granted: false,
        fallbackAction: WebPermissionFallbackAction.settings,
        message:
            "$permissionName permission is blocked. Enable it in App Settings.",
        permission: permission,
        permissionName: permissionName,
      );
    }

    return WebPermissionResult(
      granted: false,
      fallbackAction: WebPermissionFallbackAction.retry,
      message: "$permissionName permission is needed to use Voice Stream.",
      permission: permission,
      permissionName: permissionName,
    );
  }

  void _showPermissionFallback(WebPermissionResult? result) {
    if (!mounted || result?.message == null) return;

    final fallbackAction =
        result?.fallbackAction ?? WebPermissionFallbackAction.none;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result!.message!),
        action: fallbackAction == WebPermissionFallbackAction.settings
            ? SnackBarAction(label: "Settings", onPressed: openAppSettings)
            : fallbackAction == WebPermissionFallbackAction.retry
            ? SnackBarAction(
                label: "Try again",
                onPressed: () => _retryPermissionRequest(result),
              )
            : null,
      ),
    );
  }

  Future<void> _retryPermissionRequest(WebPermissionResult result) async {
    final permission = result.permission;
    final permissionName = result.permissionName ?? "Permission";

    if (permission == null) return;

    final status = await permission.request();

    if (!mounted) return;

    if (status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("$permissionName granted. Tap microphone again."),
        ),
      );
      return;
    }

    if (status.isPermanentlyDenied) {
      _showPermissionFallback(
        WebPermissionResult(
          granted: false,
          fallbackAction: WebPermissionFallbackAction.settings,
          message:
              "$permissionName permission is blocked. Enable it in App Settings.",
          permission: permission,
          permissionName: permissionName,
        ),
      );
      return;
    }

    _showPermissionFallback(result);
  }

  void _showExternalOpenFailure() {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("No app can open this link")));
  }

  bool _shouldShowRetryForHttpStatus(int? statusCode) {
    if (statusCode == null) return false;

    return statusCode == 408 || (statusCode >= 500 && statusCode <= 599);
  }

  PageLoadFailureKind _classifyWebResourceError(WebResourceError error) {
    final type = error.type;

    if (type == WebResourceErrorType.TIMEOUT) {
      return PageLoadFailureKind.timeout;
    }

    if (type == WebResourceErrorType.HOST_LOOKUP ||
        type == WebResourceErrorType.CANNOT_CONNECT_TO_HOST ||
        type == WebResourceErrorType.NOT_CONNECTED_TO_INTERNET ||
        type == WebResourceErrorType.NETWORK_CONNECTION_LOST ||
        type == WebResourceErrorType.SERVER_UNREACHABLE) {
      return PageLoadFailureKind.network;
    }

    if (type == WebResourceErrorType.FAILED_SSL_HANDSHAKE ||
        type == WebResourceErrorType.SECURE_CONNECTION_FAILED ||
        type == WebResourceErrorType.SERVER_CERTIFICATE_HAS_BAD_DATE ||
        type == WebResourceErrorType.SERVER_CERTIFICATE_HAS_UNKNOWN_ROOT ||
        type == WebResourceErrorType.SERVER_CERTIFICATE_NOT_YET_VALID ||
        type == WebResourceErrorType.SERVER_CERTIFICATE_UNTRUSTED) {
      return PageLoadFailureKind.ssl;
    }

    if (type == WebResourceErrorType.BAD_SERVER_RESPONSE) {
      return PageLoadFailureKind.server;
    }

    return PageLoadFailureKind.generic;
  }

  void _showLoadFailure(PageLoadFailureKind kind, {WebUri? failedUrl}) {
    setState(() {
      if (failedUrl != null && !_isBlankUrl(failedUrl)) {
        currentMainFrameUrl = failedUrl;
      }
      isInitialLoading = false;
      showStartupOverlay = false;
      isNavigating = false;
      pageProgress = 0;
      pageLoadFailed = true;
      pageLoadFailureKind = kind;
      _isWaitingForReveal = false;
    });
  }

  Future<void> _retryLoad() async {
    setState(() {
      pageLoadFailed = false;
      isInitialLoading = !hasLoadedInitialPage;
      showStartupOverlay = !hasLoadedInitialPage;
      isNavigating = hasLoadedInitialPage;
      pageProgress = 0;
    });

    final controller = webViewController;
    if (controller != null) {
      await controller.setSettings(
        settings: InAppWebViewSettings(cacheMode: CacheMode.LOAD_DEFAULT),
      );
      await controller.loadUrl(
        urlRequest: URLRequest(url: currentMainFrameUrl ?? _initialUrl),
      );
    }
  }

  IconData get _failureIcon {
    if (!hasNetworkSignal) return Icons.wifi_off;

    switch (pageLoadFailureKind) {
      case PageLoadFailureKind.network:
        return Icons.wifi_off;
      case PageLoadFailureKind.timeout:
        return Icons.timer_off;
      case PageLoadFailureKind.server:
        return Icons.cloud_off;
      case PageLoadFailureKind.ssl:
        return Icons.security;
      case PageLoadFailureKind.generic:
        return Icons.refresh;
    }
  }

  String get _failureMessage {
    if (!hasNetworkSignal) return "No internet connection";

    switch (pageLoadFailureKind) {
      case PageLoadFailureKind.network:
        return "Could not reach the server";
      case PageLoadFailureKind.timeout:
        return "Connection timed out";
      case PageLoadFailureKind.server:
        return "Server is temporarily unavailable";
      case PageLoadFailureKind.ssl:
        return "Secure connection failed";
      case PageLoadFailureKind.generic:
        return "Page could not load";
    }
  }

  Widget _buildNoInternetView() {
    return ColoredBox(
      color: _startupBackgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_failureIcon, size: 64, color: _startupForegroundColor),
            const SizedBox(height: 16),
            Text(
              _failureMessage,
              style: const TextStyle(
                fontSize: 18,
                color: _startupForegroundColor,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _retryLoad, child: const Text("Retry")),
          ],
        ),
      ),
    );
  }
}

class _StartupLoadingView extends StatelessWidget {
  const _StartupLoadingView({required this.visible, required this.onHidden});

  final bool visible;
  final VoidCallback onHidden;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: _startupRevealFadeDuration,
      curve: Curves.easeOutCubic,
      onEnd: visible ? null : onHidden,
      child: const ColoredBox(
        color: _startupBackgroundColor,
        child: Center(
          child: ClipOval(
            child: Image(
              image: AssetImage("assets/splash_logo.png"),
              width: _splashLogoSize,
              height: _splashLogoSize,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}
