import "dart:async";
import "dart:convert";

import "package:google_sign_in/google_sign_in.dart";
import "package:http/http.dart" as http;

import "app_urls.dart";

class GoogleAuthException implements Exception {
  GoogleAuthException(this.message);

  final String message;

  factory GoogleAuthException.noServerAuthCode() {
    return GoogleAuthException(
      "Google did not return a server auth code. "
      "Verify the Android OAuth client and SHA-1 in Google Cloud Console.",
    );
  }

  factory GoogleAuthException.exchangeFailed(
    int statusCode, {
    String? errorCode,
    String? requestId,
  }) {
    final details = [
      "HTTP $statusCode",
      if (errorCode != null) errorCode,
    ].join(", ");
    final reference = requestId == null ? "" : " Request ID: $requestId";
    return GoogleAuthException(
      "UltraGPT could not complete Google sign-in ($details).$reference",
    );
  }

  factory GoogleAuthException.unexpectedCallback(Uri uri) {
    return GoogleAuthException(
      "Unexpected auth redirect: ${uri.host}${uri.path}",
    );
  }

  factory GoogleAuthException.invalidCallback() {
    return GoogleAuthException(
      "UltraGPT did not return a valid sign-in callback URL.",
    );
  }

  factory GoogleAuthException.networkFailed() {
    return GoogleAuthException(
      "Could not complete Google sign-in. Check your connection and try again.",
    );
  }

  @override
  String toString() => message;
}

/// Native Google Sign-In for UltraGPT.
class UltraGptGoogleAuth {
  factory UltraGptGoogleAuth() => _instance;

  UltraGptGoogleAuth._({GoogleSignIn? googleSignIn})
    : _googleSignIn =
          googleSignIn ??
          GoogleSignIn(
            scopes: const ["email", "profile"],
            serverClientId: UltraGptUrls.googleWebClientId,
            forceCodeForRefreshToken: true,
          );

  static final UltraGptGoogleAuth _instance = UltraGptGoogleAuth._();

  final GoogleSignIn _googleSignIn;
  Future<void>? _warmUpFuture;

  /// Initializes the Google Sign-In plugin early so the account picker opens
  /// faster when the user taps "Continue with Google".
  Future<void> warmUp() {
    return _warmUpFuture ??= _doWarmUp();
  }

  Future<void> _doWarmUp() async {
    try {
      await _googleSignIn.isSignedIn();
    } catch (_) {
      // Warm-up is best-effort.
    }
  }

  /// Runs native Google sign-in and resolves the UltraGPT app callback URL that
  /// contains the session token.
  Future<Uri?> signInAndResolveAppCallbackUri({
    String locale = "en",
    void Function()? onAccountSelected,
  }) async {
    await warmUp();

    final account = await _interactiveSignIn();
    if (account == null) return null;

    onAccountSelected?.call();

    final serverAuthCode = await _readServerAuthCode(account);
    if (serverAuthCode == null || serverAuthCode.isEmpty) {
      throw GoogleAuthException.noServerAuthCode();
    }

    return resolveAppCallbackFromApiCode(
      serverAuthCode,
      locale: locale,
    );
  }

  Future<GoogleSignInAccount?> _interactiveSignIn() async {
    // Server auth codes are one-time. signOut() drops the cached account so
    // signIn() requests a new code. Without forceCodeForRefreshToken,
    // /auth/google/mobile rejects the code with INVALID_GOOGLE_IDENTITY.
    // disconnect() is avoided: revoking the grant on every sign-in led to
    // HTTP 429 from the same endpoint.
    await _clearNativeGoogleSession();
    return _googleSignIn.signIn();
  }

  Future<void> _clearNativeGoogleSession() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Best-effort reset before requesting a new serverAuthCode.
    }
  }

  Future<String?> _readServerAuthCode(GoogleSignInAccount account) async {
    final directCode = account.serverAuthCode;
    if (directCode != null && directCode.isNotEmpty) {
      return directCode;
    }

    return null;
  }

  Future<void> signOut() => _googleSignIn.signOut();
}

/// Exchanges the native Google server auth code for the UltraGPT app callback
/// URL (`/auth/callback?token=...`) via the mobile auth endpoint.
Future<Uri> resolveAppCallbackFromApiCode(
  String serverAuthCode, {
  String locale = "en",
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final shouldCloseClient = client == null;

  try {
    final response = await httpClient
        .post(
          UltraGptUrls.apiGoogleMobileUri,
          headers: const {"Content-Type": "application/json"},
          body: jsonEncode({"code": serverAuthCode}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      final error = _decodeErrorBody(response.body);
      throw GoogleAuthException.exchangeFailed(
        response.statusCode,
        errorCode: error["code"],
        requestId: error["requestId"],
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw GoogleAuthException.invalidCallback();
    }

    final callbackUrl = decoded["callbackUrl"];
    if (callbackUrl is! String || callbackUrl.trim().isEmpty) {
      throw GoogleAuthException.invalidCallback();
    }

    final callbackUri = Uri.tryParse(callbackUrl.trim());
    if (callbackUri == null || !UltraGptUrls.isOAuthCallbackUrl(callbackUri)) {
      throw GoogleAuthException.unexpectedCallback(
        callbackUri ?? Uri.parse(callbackUrl),
      );
    }

    final token = callbackUri.queryParameters["token"]?.trim();
    if (token == null || token.isEmpty) {
      throw GoogleAuthException.unexpectedCallback(callbackUri);
    }

    return callbackUri.replace(scheme: "https");
  } on GoogleAuthException {
    rethrow;
  } on TimeoutException {
    throw GoogleAuthException(
      "Google sign-in timed out while contacting UltraGPT.",
    );
  } on FormatException {
    throw GoogleAuthException.invalidCallback();
  } catch (_) {
    throw GoogleAuthException.networkFailed();
  } finally {
    if (shouldCloseClient) {
      httpClient.close();
    }
  }
}

Map<String, String> _decodeErrorBody(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const {};
    return {
      for (final key in const ["code", "requestId"])
        if (decoded[key] is String && (decoded[key] as String).isNotEmpty)
          key: decoded[key] as String,
    };
  } on FormatException {
    return const {};
  }
}
