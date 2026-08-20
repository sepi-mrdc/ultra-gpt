import "dart:async";

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

  factory GoogleAuthException.exchangeFailed(int statusCode) {
    return GoogleAuthException(
      "UltraGPT could not complete Google sign-in (HTTP $statusCode).",
    );
  }

  factory GoogleAuthException.unexpectedCallback(Uri uri) {
    return GoogleAuthException(
      "Unexpected auth redirect: ${uri.host}${uri.path}",
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

  /// Runs native Google sign-in and resolves the UltraGPT callback URL that
  /// contains the session token.
  Future<Uri?> signInAndResolveAppCallbackUri({String locale = "en"}) async {
    await warmUp();

    final account = await _interactiveSignIn();
    if (account == null) return null;

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
    final cached = _googleSignIn.currentUser;
    if (cached != null) {
      final cachedCode = cached.serverAuthCode;
      if (cachedCode == null || cachedCode.isEmpty) {
        await _googleSignIn.signOut();
      }
    }

    return _googleSignIn.signIn();
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
/// URL (`/auth/callback?token=...`) by following the API redirect chain.
Future<Uri> resolveAppCallbackFromApiCode(
  String serverAuthCode, {
  String locale = "en",
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final shouldCloseClient = client == null;

  try {
    final response = await httpClient
        .get(UltraGptUrls.apiGoogleCallbackUri(serverAuthCode))
        .timeout(const Duration(seconds: 30));

    final resolvedUri = response.request?.url;
    if (resolvedUri != null && UltraGptUrls.isOAuthCallbackUrl(resolvedUri)) {
      return resolvedUri;
    }

    final location = response.headers["location"];
    if (location != null) {
      final redirectUri = Uri.parse(location);
      if (UltraGptUrls.isOAuthCallbackUrl(redirectUri)) {
        return redirectUri;
      }
    }

    if (response.statusCode >= 400) {
      throw GoogleAuthException.exchangeFailed(response.statusCode);
    }

    throw GoogleAuthException.unexpectedCallback(
      resolvedUri ?? UltraGptUrls.apiGoogleCallbackUri(serverAuthCode),
    );
  } on GoogleAuthException {
    rethrow;
  } on TimeoutException {
    throw GoogleAuthException("Google sign-in timed out while contacting UltraGPT.");
  } finally {
    if (shouldCloseClient) {
      httpClient.close();
    }
  }
}
