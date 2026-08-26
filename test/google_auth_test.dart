import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:ultragpt3/google_auth.dart";

void main() {
  group("resolveAppCallbackFromApiCode", () {
    test("posts the server auth code and returns the callback URL", () async {
      final client = MockClient((request) async {
        expect(request.method, "POST");
        expect(
          request.url.toString(),
          "https://api.ultragpt.pro/auth/google/mobile",
        );
        expect(request.headers["Content-Type"], "application/json");
        expect(jsonDecode(request.body), {"code": "abc123"});

        return http.Response(
          jsonEncode({
            "token": "session-token",
            "callbackUrl":
                "https://app.ultragpt.pro/auth/callback?token=session-token",
            "statusCode": 200,
          }),
          200,
          headers: {"content-type": "application/json"},
        );
      });

      final resolved = await resolveAppCallbackFromApiCode(
        "abc123",
        client: client,
      );

      expect(
        resolved.toString(),
        "https://app.ultragpt.pro/auth/callback?token=session-token",
      );
    });

    test("throws when the backend returns a non-200 status", () async {
      final client = MockClient((request) async {
        return http.Response("error", 500);
      });

      expect(
        () => resolveAppCallbackFromApiCode("bad-code", client: client),
        throwsA(
          isA<GoogleAuthException>().having(
            (error) => error.message,
            "message",
            contains("HTTP 500"),
          ),
        ),
      );
    });

    test("throws when callbackUrl is missing", () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({"token": "session-token", "statusCode": 200}),
          200,
        );
      });

      expect(
        () => resolveAppCallbackFromApiCode("abc123", client: client),
        throwsA(isA<GoogleAuthException>()),
      );
    });

    test("throws when callbackUrl is not an UltraGPT auth callback", () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            "token": "session-token",
            "callbackUrl": "https://example.com/not-callback",
            "statusCode": 200,
          }),
          200,
        );
      });

      expect(
        () => resolveAppCallbackFromApiCode("abc123", client: client),
        throwsA(isA<GoogleAuthException>()),
      );
    });
  });
}
