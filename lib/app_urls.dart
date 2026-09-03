class UltraGptUrls {
  static const host = "app.ultragpt.pro";
  static const stagingHost = "staging-app.ultragpt.pro";
  static const apiHost = "api.ultragpt.pro";
  static const shareHosts = {host, stagingHost};
  static const customScheme = "ultragpt";
  static const defaultChatUrl = "https://$host/en/chat";
  static const googleWebClientId =
      "46935507532-e2dh61dg8pn669828g8u8q1f2crrc26s.apps.googleusercontent.com";
  static const googleAuthHost = "accounts.google.com";
  static const _defaultShareLocale = "en";
  static final _authCallbackPathPattern = RegExp(
    r"^/(?:[a-z]{2}/)?auth/callback/?$",
    caseSensitive: false,
  );

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

  static bool isAppHttpUrl(Uri uri) {
    if (uri.scheme != "http" && uri.scheme != "https") return false;
    return shareHosts.contains(uri.host.toLowerCase());
  }

  static bool isGoogleAuthStartUrl(Uri uri) {
    if (uri.scheme != "http" && uri.scheme != "https") return false;

    final host = uri.host.toLowerCase();
    if (host == googleAuthHost) return true;

    if (host != apiHost) return false;

    return uri.path.toLowerCase() == "/auth/google";
  }

  static bool isOAuthCallbackUrl(Uri uri) {
    if (!isAppHttpUrl(uri)) return false;
    return _authCallbackPathPattern.hasMatch(uri.path);
  }

  static Uri apiGoogleCallbackUri(String code) {
    return Uri(
      scheme: "https",
      host: apiHost,
      path: "/auth/google/callback",
      queryParameters: {"code": code},
    );
  }

  static Uri get apiGoogleMobileUri {
    return Uri(
      scheme: "https",
      host: apiHost,
      path: "/auth/google/mobile",
    );
  }

  static String? localeFromAppUrl(Uri uri) {
    if (!isAppHttpUrl(uri)) return null;

    final segments = uri.pathSegments.where((part) => part.isNotEmpty);
    if (segments.isEmpty) return null;

    final locale = segments.first;
    if (RegExp(r"^[a-z]{2}$").hasMatch(locale)) return locale;
    return null;
  }

  static String? shareTokenFromCustomScheme(Uri uri) {
    if (uri.scheme != customScheme) return null;

    final queryToken = uri.queryParameters["token"]?.trim();
    final hasShareHost = uri.host.toLowerCase() == "share";
    final hasSharePath =
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first.toLowerCase() == "share";

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

  static Uri publicShareUri(
    String token, {
    String locale = _defaultShareLocale,
  }) {
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

  /// Maps incoming OS links back to UltraGPT pages, including OAuth callback
  /// URLs that should reopen inside the WebView after authentication.
  static Uri? resolveIncomingAppUrl(Uri uri) {
    if (isAppHttpUrl(uri)) {
      return uri.replace(scheme: "https");
    }

    return resolveIncomingShare(uri);
  }

  /// Cold-start destination: only conversation share links override chat.
  static Uri startUri({Uri? incoming}) {
    if (incoming == null) return defaultChatUri;
    return resolveIncomingShare(incoming) ?? defaultChatUri;
  }
}
