class UltraGptUrls {
  static const host = "app.ultragpt.pro";
  static const stagingHost = "staging-app.ultragpt.pro";
  static const shareHosts = {host, stagingHost};
  static const customScheme = "ultragpt";
  static const defaultChatUrl = "https://$host/en/chat";
  static const _defaultShareLocale = "en";

  static final _sharePathPattern = RegExp(
    r"^/(?:[a-z]{2}/)?share(?:/.*)?$",
    caseSensitive: false,
  );

  static Uri get defaultChatUri => Uri.parse(defaultChatUrl);

  static bool isSharePath(String path) => _sharePathPattern.hasMatch(path);

  static bool isShareHttpUrl(Uri uri) {
    if (uri.scheme != "http" && uri.scheme != "https") return false;
    if (!shareHosts.contains(uri.host.toLowerCase())) return false;
    return isSharePath(uri.path);
  }

  static String? shareTokenFromCustomScheme(Uri uri) {
    if (uri.scheme != customScheme) return null;

    final queryToken = uri.queryParameters["token"]?.trim();
    final hasShareHost = uri.host.toLowerCase() == "share";
    final hasSharePath =
        uri.pathSegments.isNotEmpty && uri.pathSegments.first.toLowerCase() == "share";

    if (hasShareHost) {
      final token = uri.pathSegments.where((part) => part.isNotEmpty).join("/");
      if (token.isNotEmpty) return token;
      if (queryToken != null && queryToken.isNotEmpty) return queryToken;
      return null;
    }

    if (hasSharePath) {
      final token = uri.pathSegments
          .skip(1)
          .where((part) => part.isNotEmpty)
          .join("/");
      if (token.isNotEmpty) return token;
      if (queryToken != null && queryToken.isNotEmpty) return queryToken;
      return null;
    }

    return null;
  }

  static Uri publicShareUri(String token, {String locale = _defaultShareLocale}) {
    return Uri(
      scheme: "https",
      host: host,
      path: "/$locale/share/${token.trim()}",
    );
  }

  /// Maps an incoming OS link to a public UltraGPT share URL, or null if it
  /// is not a conversation share link.
  static Uri? resolveIncomingShare(Uri uri) {
    if (isShareHttpUrl(uri)) {
      return uri.replace(scheme: "https");
    }

    final token = shareTokenFromCustomScheme(uri);
    if (token == null) return null;
    return publicShareUri(token);
  }

  static Uri startUri({Uri? incoming}) {
    if (incoming == null) return defaultChatUri;
    return resolveIncomingShare(incoming) ?? defaultChatUri;
  }
}
