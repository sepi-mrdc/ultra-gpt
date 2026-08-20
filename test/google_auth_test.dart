import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:ultragpt3/google_auth.dart";

void main() {
  group("resolveAppCallbackFromApiCode", () {
    test("returns the app callback URL after API redirect", () async {
      final client = MockClient((request) async {
        if (request.url.host == "api.ultragpt.pro") {
          expect(
            request.url.toString(),
            "https://api.ultragpt.pro/auth/google/callback?code=abc123",
          );

          return http.Response(
            "",
            302,
            headers: {
              "location":
                  "https://app.ultragpt.pro/en/auth/callback?token=session-token",
            },
          );
        }

        return http.Response("", 200);
      });

      final resolved = await resolveAppCallbackFromApiCode(
        "abc123",
        client: client,
      );

      expect(
        resolved.toString(),
        "https://app.ultragpt.pro/en/auth/callback?token=session-token",
      );
    });

    test("throws when the API response does not reach the app callback", () async {
      final client = MockClient((request) async {
        return http.Response("error", 500);
      });

      expect(
        () => resolveAppCallbackFromApiCode("bad-code", client: client),
        throwsA(isA<GoogleAuthException>()),
      );
    });
  });
}
