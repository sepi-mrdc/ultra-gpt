import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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

class _WebViewPageState extends State<WebViewPage> with WidgetsBindingObserver {
  bool isLoading = true;
  bool hasInternet = true;
  late final StreamSubscription connectivitySubscription;
  InAppWebViewController? webViewController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    Future.delayed(Duration.zero, _setCustomUiMode);

    connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) {
      setState(() {
        hasInternet = result != ConnectivityResult.none;
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
          child: hasInternet ? _buildWebView() : _buildNoInternetView(),
        ),
      ),
    );
  }

  Widget _buildWebView() {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri("https://app.ultragpt.pro/en/chat"),
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;
            _setupFilePickerHandler(controller);
          },
          onLoadStart: (_, __) => setState(() => isLoading = true),
          onLoadStop: (controller, _) async {
            setState(() => isLoading = false);
            await _injectFilePickerScript(controller);
          },
        ),
        if (isLoading)
          Container(
            color: const Color(0xFFF3F4F6),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.blueGrey),
            ),
          ),
      ],
    );
  }

  void _setupFilePickerHandler(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: "pickFile",
      callback: (args) async {
        FilePickerResult? result = await FilePicker.platform.pickFiles();
        if (result != null && result.files.isNotEmpty) {
          final filePath = result.files.single.path!;
          controller.evaluateJavascript(
            source:
                "window.flutterFilePicked && window.flutterFilePicked('$filePath')",
          );
        }
      },
    );
  }

  Future<void> _injectFilePickerScript(
    InAppWebViewController controller,
  ) async {
    await controller.evaluateJavascript(
      source: """
        document.querySelectorAll('input[type=file]').forEach(function(input) {
          input.addEventListener('click', function(e) {
            e.preventDefault();
            window.flutter_inappwebview.callHandler('pickFile');
          });
        });
      """,
    );
  }

  Widget _buildNoInternetView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            "اتصال به اینترنت برقرار نیست",
            style: TextStyle(fontSize: 18, color: Colors.grey[800]),
          ),
        ],
      ),
    );
  }
}
