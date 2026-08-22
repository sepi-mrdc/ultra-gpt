import "download_service.dart";

const downloadBlobHandlerName = "downloadBlob";

const downloadBridgeJavaScript = """
(function () {
  if (window.__ultraGptDownloadBridgeInstalled) return;
  window.__ultraGptDownloadBridgeInstalled = true;

  function callNativeDownload(payload) {
    return window.flutter_inappwebview.callHandler("$downloadBlobHandlerName", payload || {});
  }

  function downloadBlobUrl(href, suggestedName, mimeType) {
    return fetch(href)
      .then(function (response) {
        return response.blob().then(function (blob) {
          return new Promise(function (resolve, reject) {
            var reader = new FileReader();
            reader.onload = function () {
              var result = reader.result || "";
              var commaIndex = result.indexOf(",");
              var base64 = commaIndex >= 0 ? result.slice(commaIndex + 1) : result;
              resolve(
                callNativeDownload({
                  filename: suggestedName || "download",
                  mimeType: mimeType || blob.type || "application/octet-stream",
                  data: base64,
                })
              );
            };
            reader.onerror = function () {
              reject(reader.error || new Error("Failed to read blob."));
            };
            reader.readAsDataURL(blob);
          });
        });
      });
  }

  document.addEventListener(
    "click",
    function (event) {
      var anchor = event.target && event.target.closest
        ? event.target.closest("a[href]")
        : null;
      if (!anchor || !anchor.href) return;

      if (anchor.href.indexOf("blob:") !== 0) return;

      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();

      downloadBlobUrl(
        anchor.href,
        anchor.download || anchor.getAttribute("download") || "download",
        anchor.type || ""
      ).catch(function (error) {
        console.error("UltraGPT blob download failed", error);
      });
    },
    true
  );

  var originalCreateObjectURL = URL.createObjectURL;
  URL.createObjectURL = function (blob) {
    var url = originalCreateObjectURL.call(this, blob);
    try {
      Object.defineProperty(blob, "__ultraGptObjectUrl", {
        value: url,
        configurable: true,
      });
    } catch (_) {}
    return url;
  };
})();
""";

Future<void> downloadBlobFromWeb(
  Object? payload,
  UltraGptDownloadService downloadService,
) async {
  if (payload is! Map) {
    throw FormatException("Invalid blob download payload.");
  }

  final rawFileName = payload["filename"]?.toString();
  final mimeType = payload["mimeType"]?.toString();
  final base64Data = payload["data"]?.toString();

  if (base64Data == null || base64Data.isEmpty) {
    throw FormatException("Blob download payload is missing data.");
  }

  await downloadService.saveBase64Payload(
    base64Data: base64Data,
    fileName: rawFileName ?? "download",
    mimeType: mimeType,
  );
}
