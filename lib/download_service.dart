import "dart:convert";
import "dart:io";

import "package:flutter/services.dart";
import "package:flutter_inappwebview/flutter_inappwebview.dart";
import "package:http/http.dart" as http;
import "package:path_provider/path_provider.dart";
import "package:permission_handler/permission_handler.dart";

const ultraGptDownloadFolderName = "Ultra GPT";

const _androidDownloadsChannel = MethodChannel(
  "com.example.ultragpt3/downloads",
);

class DownloadResult {
  const DownloadResult({
    required this.fileName,
    required this.displayPath,
  });

  final String fileName;
  final String displayPath;
}

class UltraGptDownloadService {
  Future<DownloadResult> downloadFromRequest(
    DownloadStartRequest request,
  ) async {
    final url = request.url;
    final urlString = url.toString();

    if (urlString.startsWith("blob:")) {
      throw UnsupportedError(
        "Blob downloads must be handled by the download bridge.",
      );
    }

    if (urlString.startsWith("data:")) {
      return _saveDataUrl(urlString, request.suggestedFilename);
    }

    final fileName = resolveFileName(
      suggestedFilename: request.suggestedFilename,
      contentDisposition: request.contentDisposition,
      url: urlString,
      mimeType: request.mimeType,
    );
    final mimeType = request.mimeType ?? guessMimeType(fileName);

    final headers = await _buildRequestHeaders(request);
    final tempFile = await _downloadToTempFile(urlString, headers);

    try {
      final displayPath = await _saveTempFile(
        tempFile.path,
        fileName: fileName,
        mimeType: mimeType,
      );
      return DownloadResult(fileName: fileName, displayPath: displayPath);
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<DownloadResult> saveBytes({
    required List<int> bytes,
    required String fileName,
    String? mimeType,
  }) async {
    final resolvedName = resolveFileName(
      suggestedFilename: fileName,
      mimeType: mimeType,
    );
    final resolvedMimeType = mimeType ?? guessMimeType(resolvedName);

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      "${tempDir.path}/ultragpt_${DateTime.now().millisecondsSinceEpoch}",
    );
    await tempFile.writeAsBytes(bytes, flush: true);

    try {
      final displayPath = await _saveTempFile(
        tempFile.path,
        fileName: resolvedName,
        mimeType: resolvedMimeType,
      );
      return DownloadResult(
        fileName: resolvedName,
        displayPath: displayPath,
      );
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<DownloadResult> saveBase64Payload({
    required String base64Data,
    required String fileName,
    String? mimeType,
  }) {
    return saveBytes(
      bytes: base64Decode(base64Data),
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  Future<DownloadResult> _saveDataUrl(
    String dataUrl,
    String? suggestedFilename,
  ) async {
    final match = RegExp(r"^data:([^;,]+)?(?:;charset=[^;,]+)?;base64,(.+)$")
        .firstMatch(dataUrl);
    if (match == null) {
      throw FormatException("Unsupported data URL.");
    }

    final mimeType = match.group(1);
    final base64Data = match.group(2)!;
    final fileName = resolveFileName(
      suggestedFilename: suggestedFilename,
      mimeType: mimeType,
    );

    return saveBase64Payload(
      base64Data: base64Data,
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  Future<Map<String, String>> _buildRequestHeaders(
    DownloadStartRequest request,
  ) async {
    final headers = <String, String>{};

    final userAgent = request.userAgent;
    if (userAgent != null && userAgent.isNotEmpty) {
      headers["User-Agent"] = userAgent;
    }

    final cookies = await CookieManager.instance().getCookies(
      url: request.url,
    );
    if (cookies.isNotEmpty) {
      headers["Cookie"] = cookies
          .map((cookie) => "${cookie.name}=${cookie.value}")
          .join("; ");
    }

    return headers;
  }

  Future<File> _downloadToTempFile(
    String url,
    Map<String, String> headers,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request("GET", Uri.parse(url));
      if (headers.isNotEmpty) {
        request.headers.addAll(headers);
      }

      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          "Download failed with status ${response.statusCode}.",
          uri: request.url,
        );
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        "${tempDir.path}/ultragpt_${DateTime.now().millisecondsSinceEpoch}",
      );
      final sink = tempFile.openWrite();
      await response.stream.pipe(sink);
      await sink.flush();
      await sink.close();
      return tempFile;
    } finally {
      client.close();
    }
  }

  Future<String> _saveTempFile(
    String sourcePath, {
    required String fileName,
    required String mimeType,
  }) async {
    if (Platform.isAndroid) {
      await _ensureLegacyAndroidStoragePermission();
      final displayPath = await _androidDownloadsChannel.invokeMethod<String>(
        "saveDownload",
        {
          "sourcePath": sourcePath,
          "fileName": fileName,
          "mimeType": mimeType,
        },
      );
      if (displayPath == null || displayPath.isEmpty) {
        throw StateError("Android download save returned no path.");
      }
      return displayPath;
    }

    final folder = await _localDownloadFolder();
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final destination = await _uniqueFileInDirectory(folder, fileName);
    await File(sourcePath).copy(destination.path);
    return destination.path;
  }

  Future<Directory> _localDownloadFolder() async {
    if (Platform.isIOS) {
      final documentsDir = await getApplicationDocumentsDirectory();
      return Directory("${documentsDir.path}/$ultraGptDownloadFolderName");
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        throw StateError("Downloads directory is unavailable.");
      }
      return Directory("${downloadsDir.path}/$ultraGptDownloadFolderName");
    }

    final appDir = await getApplicationDocumentsDirectory();
    return Directory("${appDir.path}/$ultraGptDownloadFolderName");
  }

  Future<void> _ensureLegacyAndroidStoragePermission() async {
    if (!Platform.isAndroid) return;

    final sdkInt = await _androidDownloadsChannel.invokeMethod<int>(
      "getAndroidSdkInt",
    );
    if (sdkInt == null || sdkInt >= 29) return;

    final status = await Permission.storage.status;
    if (status.isGranted) return;

    final result = await Permission.storage.request();
    if (!result.isGranted) {
      throw StateError("Storage permission is required to save downloads.");
    }
  }
}

String resolveFileName({
  String? suggestedFilename,
  String? contentDisposition,
  String? url,
  String? mimeType,
}) {
  final candidates = <String?>[
    suggestedFilename,
    _fileNameFromContentDisposition(contentDisposition),
    _fileNameFromUrl(url),
  ];

  for (final candidate in candidates) {
    final sanitized = _sanitizeFileName(candidate);
    if (sanitized != null) {
      return sanitized;
    }
  }

  final extension = _extensionForMimeType(mimeType);
  return "download_${DateTime.now().millisecondsSinceEpoch}$extension";
}

String? _fileNameFromContentDisposition(String? contentDisposition) {
  if (contentDisposition == null || contentDisposition.isEmpty) {
    return null;
  }

  final filenameStar = RegExp(
    r"filename\*\s*=\s*([^']*)''([^;]+)",
    caseSensitive: false,
  ).firstMatch(contentDisposition);
  if (filenameStar != null) {
    return Uri.decodeFull(filenameStar.group(2)!);
  }

  final filename = RegExp(
    r'filename\s*=\s*"?(?<name>[^";]+)"?',
    caseSensitive: false,
  ).firstMatch(contentDisposition);
  return filename?.namedGroup("name");
}

String? _fileNameFromUrl(String? url) {
  if (url == null || url.isEmpty) return null;

  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
  if (segments.isEmpty) return null;

  return segments.last;
}

String? _sanitizeFileName(String? rawName) {
  if (rawName == null) return null;

  var name = rawName.trim();
  if (name.isEmpty) return null;

  name = name.replaceAll("\\", "/");
  if (name.contains("/")) {
    name = name.split("/").last;
  }

  name = name.replaceAll(RegExp(r'[<>:"|?*]'), "_");
  name = name.replaceAll(RegExp(r"\s+"), " ").trim();

  return name.isEmpty ? null : name;
}

String guessMimeType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith(".pdf")) return "application/pdf";
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".gif")) return "image/gif";
  if (lower.endsWith(".csv")) return "text/csv";
  if (lower.endsWith(".txt")) return "text/plain";
  if (lower.endsWith(".json")) return "application/json";
  if (lower.endsWith(".zip")) return "application/zip";
  if (lower.endsWith(".doc")) return "application/msword";
  if (lower.endsWith(".docx")) {
    return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  }
  if (lower.endsWith(".xls")) return "application/vnd.ms-excel";
  if (lower.endsWith(".xlsx")) {
    return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
  }
  if (lower.endsWith(".mp4")) return "video/mp4";
  if (lower.endsWith(".mp3")) return "audio/mpeg";
  return "application/octet-stream";
}

String _extensionForMimeType(String? mimeType) {
  switch (mimeType) {
    case "application/pdf":
      return ".pdf";
    case "image/png":
      return ".png";
    case "image/jpeg":
      return ".jpg";
    case "text/plain":
      return ".txt";
    case "text/csv":
      return ".csv";
    case "application/json":
      return ".json";
    case "application/zip":
      return ".zip";
    default:
      return "";
  }
}

Future<File> _uniqueFileInDirectory(
  Directory directory,
  String fileName,
) async {
  var candidate = File("${directory.path}/$fileName");
  if (!await candidate.exists()) {
    return candidate;
  }

  final dotIndex = fileName.lastIndexOf(".");
  final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  final extension = dotIndex > 0 ? fileName.substring(dotIndex) : "";

  var suffix = 1;
  while (await candidate.exists()) {
    candidate = File("${directory.path}/$baseName ($suffix)$extension");
    suffix++;
  }

  return candidate;
}
