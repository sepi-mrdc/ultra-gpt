import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:ultragpt3/fcm_device_api.dart";

void main() {
  group("FcmDeviceApi", () {
    test("registers the FCM token with the session bearer token", () async {
      final client = MockClient((request) async {
        expect(request.method, "POST");
        expect(
          request.url.toString(),
          "https://api.ultragpt.pro/mobile/devices/fcm",
        );
        expect(request.headers["Authorization"], "Bearer session-abc");
        expect(request.headers["Content-Type"], "application/json");
        expect(jsonDecode(request.body), {
          "token": "fcm-token",
          "platform": "android",
          "deviceId": "device-1",
          "appVersion": "1.0.0",
        });
        return http.Response(
          jsonEncode({
            "message": "ok",
            "data": {"id": "1", "platform": "android", "active": true},
          }),
          200,
          headers: {"content-type": "application/json"},
        );
      });

      final api = FcmDeviceApi(client: client);
      expect(
        await api.register(
          token: "fcm-token",
          sessionToken: "session-abc",
          deviceId: "device-1",
          appVersion: "1.0.0",
        ),
        isTrue,
      );
    });

    test("omits empty optional register fields", () async {
      final client = MockClient((request) async {
        expect(jsonDecode(request.body), {
          "token": "fcm-token",
          "platform": "android",
        });
        return http.Response("{}", 200);
      });

      final api = FcmDeviceApi(client: client);
      expect(
        await api.register(token: "fcm-token", sessionToken: "session-abc"),
        isTrue,
      );
    });

    test("unregisters the FCM token with the session bearer token", () async {
      final client = MockClient((request) async {
        expect(request.method, "DELETE");
        expect(
          request.url.toString(),
          "https://api.ultragpt.pro/mobile/devices/fcm",
        );
        expect(request.headers["Authorization"], "Bearer session-abc");
        expect(jsonDecode(request.body), {"token": "fcm-token"});
        return http.Response("{}", 200);
      });

      final api = FcmDeviceApi(client: client);
      expect(
        await api.unregister(token: "fcm-token", sessionToken: "session-abc"),
        isTrue,
      );
    });

    test("treats non-2xx register responses as failure", () async {
      final api = FcmDeviceApi(
        client: MockClient((request) async => http.Response("nope", 401)),
      );

      expect(
        await api.register(token: "fcm-token", sessionToken: "bad"),
        isFalse,
      );
    });
  });

  group("FcmRegistrationCoordinator", () {
    test("registers once and skips duplicate session/token pairs", () async {
      var posts = 0;
      final api = FcmDeviceApi(
        client: MockClient((request) async {
          if (request.method == "POST") posts++;
          return http.Response("{}", 200);
        }),
      );
      final coordinator = FcmRegistrationCoordinator(api: api);

      await coordinator.sync(sessionToken: "session", fcmToken: "token");
      await coordinator.sync(sessionToken: "session", fcmToken: "token");

      expect(posts, 1);
      expect(coordinator.registeredToken, "token");
    });

    test("registers a refreshed FCM token while the session is active", () async {
      final tokens = <String>[];
      final api = FcmDeviceApi(
        client: MockClient((request) async {
          if (request.method == "POST") {
            tokens.add(jsonDecode(request.body)["token"] as String);
          }
          return http.Response("{}", 200);
        }),
      );
      final coordinator = FcmRegistrationCoordinator(api: api);

      await coordinator.sync(sessionToken: "session", fcmToken: "token-1");
      await coordinator.sync(sessionToken: "session", fcmToken: "token-2");

      expect(tokens, ["token-1", "token-2"]);
      expect(coordinator.registeredToken, "token-2");
    });

    test("unregisters on logout and does not repeat the delete", () async {
      var posts = 0;
      var deletes = 0;
      final api = FcmDeviceApi(
        client: MockClient((request) async {
          if (request.method == "POST") posts++;
          if (request.method == "DELETE") deletes++;
          return http.Response("{}", 200);
        }),
      );
      final coordinator = FcmRegistrationCoordinator(api: api);

      await coordinator.sync(sessionToken: "session", fcmToken: "token");
      await coordinator.sync(sessionToken: null, fcmToken: "token");
      await coordinator.sync(sessionToken: null, fcmToken: "token");

      expect(posts, 1);
      expect(deletes, 1);
      expect(coordinator.registeredToken, isNull);
    });

    test("does not mark a failed registration as complete", () async {
      var posts = 0;
      final api = FcmDeviceApi(
        client: MockClient((request) async {
          posts++;
          return http.Response("error", 500);
        }),
      );
      final coordinator = FcmRegistrationCoordinator(api: api);

      await coordinator.sync(sessionToken: "session", fcmToken: "token");
      await coordinator.sync(sessionToken: "session", fcmToken: "token");

      expect(posts, 2);
      expect(coordinator.registeredToken, isNull);
    });
  });
}
