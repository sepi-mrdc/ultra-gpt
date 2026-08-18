import "package:share_plus/share_plus.dart";

const shareConversationHandlerName = "shareConversation";

const shareBridgeJavaScript = """
(function () {
  if (window.__ultraGptShareBridgeInstalled) return;
  window.__ultraGptShareBridgeInstalled = true;

  window.ultraGptNativeShare = function (data) {
    return window.flutter_inappwebview.callHandler("$shareConversationHandlerName", data || {});
  };

  navigator.share = function (data) {
    return window.ultraGptNativeShare(data);
  };
})();
""";

String? shareTextFromWebPayload(Object? payload) {
  if (payload is! Map) return null;

  final title = payload["title"]?.toString().trim();
  final text = payload["text"]?.toString().trim();
  final url = payload["url"]?.toString().trim();

  final parts = <String>[
    if (title != null && title.isNotEmpty) title,
    if (text != null && text.isNotEmpty) text,
    if (url != null && url.isNotEmpty) url,
  ];

  if (parts.isEmpty) return null;
  return parts.toSet().join("\n");
}

Future<void> shareConversationFromWeb(Object? payload) async {
  final content = shareTextFromWebPayload(payload);
  if (content == null) return;

  await Share.share(content);
}
