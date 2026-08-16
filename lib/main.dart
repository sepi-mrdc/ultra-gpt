import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.camera.request();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFF3F4F6),
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

enum PageLoadFailureKind { generic, network, timeout, server, ssl }

class _WebViewPageState extends State<WebViewPage> with WidgetsBindingObserver {
  final WebUri _initialUrl = WebUri("https://app.ultragpt.pro/en/chat");
  final WebUri _blankUrl = WebUri("about:blank");

  bool isInitialLoading = true;
  bool isNavigating = false;
  bool hasLoadedInitialPage = false;
  bool hasNetworkSignal = true;
  bool pageLoadFailed = false;
  int pageProgress = 0;
  PageLoadFailureKind pageLoadFailureKind = PageLoadFailureKind.generic;
  WebUri? currentMainFrameUrl;
  late final StreamSubscription connectivitySubscription;
  InAppWebViewController? webViewController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    Future.delayed(Duration.zero, _setCustomUiMode);

    connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (!mounted) return;

      setState(() {
        hasNetworkSignal = !results.contains(ConnectivityResult.none);
      });
    });
  }

  void _setCustomUiMode() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    Future.delayed(const Duration(seconds: 2), _setCustomUiMode);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
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
        backgroundColor: const Color(0xFFF3F4F6),
        body: SafeArea(
          child: Stack(
            children: [
              _buildWebView(),
              if (pageLoadFailed)
                Positioned.fill(child: _buildNoInternetView()),
            ],
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
            cacheMode: CacheMode.LOAD_DEFAULT,
            supportZoom: false,
            builtInZoomControls: false,
            displayZoomControls: false,
            verticalScrollBarEnabled: false,
            horizontalScrollBarEnabled: false,
            overScrollMode: OverScrollMode.NEVER,
            safeBrowsingEnabled: true,
            disableDefaultErrorPage: true,
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;
          },
          onProgressChanged: (_, progress) {
            if (pageLoadFailed) return;

            setState(() {
              pageProgress = progress;
              isNavigating = !isInitialLoading && progress < 100;
            });
          },
          onLoadStart: (_, url) {
            if (_isBlankUrl(url) && pageLoadFailed) {
              setState(() {
                isInitialLoading = false;
                isNavigating = false;
              });
              return;
            }

            setState(() {
              if (!_isBlankUrl(url)) {
                currentMainFrameUrl = url;
              }
              isInitialLoading = !hasLoadedInitialPage;
              isNavigating = hasLoadedInitialPage;
              pageProgress = 0;
              pageLoadFailed = false;
            });
          },
          onLoadStop: (_, __) {
            if (pageLoadFailed) {
              setState(() {
                isInitialLoading = false;
                isNavigating = false;
              });
              return;
            }

            setState(() {
              hasLoadedInitialPage = true;
              isInitialLoading = false;
              isNavigating = false;
              pageProgress = 100;
              pageLoadFailed = false;
            });
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
        if (isInitialLoading && !pageLoadFailed)
          Container(
            color: const Color(0xFFF3F4F6),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.blueGrey),
            ),
          ),
        if (isNavigating && !pageLoadFailed)
          LinearProgressIndicator(
            value: pageProgress > 0 ? pageProgress / 100 : null,
            minHeight: 3,
            color: Colors.blueGrey,
            backgroundColor: Colors.blueGrey.withValues(alpha: 0.12),
          ),
      ],
    );
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
      isNavigating = false;
      pageProgress = 0;
      pageLoadFailed = true;
      pageLoadFailureKind = kind;
    });
  }

  Future<void> _retryLoad() async {
    setState(() {
      pageLoadFailed = false;
      isInitialLoading = !hasLoadedInitialPage;
      isNavigating = hasLoadedInitialPage;
      pageProgress = 0;
    });

    final controller = webViewController;
    if (controller != null) {
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_failureIcon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            _failureMessage,
            style: TextStyle(fontSize: 18, color: Colors.grey[800]),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _retryLoad, child: const Text("Retry")),
        ],
      ),
    );
  }
}
