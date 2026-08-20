import "package:google_sign_in/google_sign_in.dart";

import "app_urls.dart";

/// Native Google Sign-In for UltraGPT.
///
/// Uses the web OAuth client as [serverClientId] so Google returns a server auth
/// code that [UltraGptUrls.apiGoogleCallbackUri] can exchange via the existing
/// backend callback endpoint.
class UltraGptGoogleAuth {
  UltraGptGoogleAuth({GoogleSignIn? googleSignIn})
    : _googleSignIn =
          googleSignIn ??
          GoogleSignIn(
            scopes: const ["email", "profile"],
            serverClientId: UltraGptUrls.googleWebClientId,
          );

  final GoogleSignIn _googleSignIn;

  Future<Uri?> signInAndBuildApiCallbackUri() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;

    final serverAuthCode = account.serverAuthCode;
    if (serverAuthCode == null || serverAuthCode.isEmpty) {
      throw StateError(
        "Google did not return a server auth code. "
        "Check the Android SHA-1 / iOS bundle ID in Google Cloud Console.",
      );
    }

    return UltraGptUrls.apiGoogleCallbackUri(serverAuthCode);
  }

  Future<void> signOut() => _googleSignIn.signOut();
}
