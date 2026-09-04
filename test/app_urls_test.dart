import "package:flutter_test/flutter_test.dart";
import "package:ultragpt3/app_urls.dart";
import "package:ultragpt3/web_share_bridge.dart";

void main() {
  group("UltraGptUrls", () {
    test("treats localized and bare share paths as share links", () {
      expect(
        UltraGptUrls.isShareHttpUrl(
          Uri.parse("https://app.ultragpt.pro/en/share/abc"),
        ),
        isTrue,
      );
      expect(
        UltraGptUrls.isShareHttpUrl(
          Uri.parse("https://app.ultragpt.pro/ru/share/abc"),
        ),
        isTrue,
      );
      expect(
        UltraGptUrls.isShareHttpUrl(
          Uri.parse("https://app.ultragpt.pro/share/abc"),
        ),
        isTrue,
      );
      expect(
        UltraGptUrls.isShareHttpUrl(
          Uri.parse("https://app.ultragpt.pro/en/chat"),
        ),
        isFalse,
      );
      expect(
        UltraGptUrls.isShareHttpUrl(Uri.parse("https://app.ultragpt.pro/")),
        isFalse,
      );
      expect(
        UltraGptUrls.isShareHttpUrl(
          Uri.parse("https://app.ultragpt.pro/en/auth/callback?code=123"),
        ),
        isFalse,
      );
      expect(
        UltraGptUrls.isShareHttpUrl(
          Uri.parse("https://app.ultragpt.pro/login"),
        ),
        isFalse,
      );
      expect(
        UltraGptUrls.isShareHttpUrl(
          Uri.parse("https://staging-app.ultragpt.pro/share/abc"),
        ),
        isTrue,
      );
    });

    test("maps https share links to a public https URL", () {
      final resolved = UltraGptUrls.resolveIncomingShare(
        Uri.parse("http://app.ultragpt.pro/en/share/test"),
      );

      expect(resolved?.toString(), "https://app.ultragpt.pro/en/share/test");

      expect(
        UltraGptUrls.resolveIncomingShare(
          Uri.parse("https://staging-app.ultragpt.pro/share/abc-123"),
        )?.toString(),
        "https://staging-app.ultragpt.pro/share/abc-123",
      );
      expect(
        UltraGptUrls.resolveIncomingShare(
          Uri.parse("https://app.ultragpt.pro/en/chat"),
        ),
        isNull,
      );
      expect(
        UltraGptUrls.resolveIncomingShare(
          Uri.parse("https://app.ultragpt.pro/en/auth/callback?code=123"),
        ),
        isNull,
      );
    });

    test("maps custom-scheme share links to the public share page", () {
      expect(
        UltraGptUrls.resolveIncomingShare(
          Uri.parse("ultragpt://share/abc-123"),
        )?.toString(),
        "https://app.ultragpt.pro/en/share/abc-123",
      );
      expect(
        UltraGptUrls.resolveIncomingShare(
          Uri.parse("ultragpt:///share/abc-123"),
        )?.toString(),
        "https://app.ultragpt.pro/en/share/abc-123",
      );
      expect(
        UltraGptUrls.resolveIncomingShare(
          Uri.parse("ultragpt://share?token=abc-123"),
        )?.toString(),
        "https://app.ultragpt.pro/en/share/abc-123",
      );
      expect(
        UltraGptUrls.resolveIncomingShare(
          Uri.parse("ultragpt://open?token=abc-123"),
        ),
        isNull,
      );
    });

    test("maps app links to UltraGPT pages", () {
      expect(
        UltraGptUrls.resolveIncomingAppUrl(
          Uri.parse(
            "http://app.ultragpt.pro/en/auth/callback?code=123&state=abc",
          ),
        )?.toString(),
        "https://app.ultragpt.pro/en/auth/callback?code=123&state=abc",
      );
      expect(
        UltraGptUrls.resolveIncomingAppUrl(
          Uri.parse(
            "https://app.ultragpt.pro/en/auth/callback?token=abc123",
          ),
        )?.toString(),
        "https://app.ultragpt.pro/en/auth/callback?token=abc123",
      );
      expect(
        UltraGptUrls.resolveIncomingAppUrl(
          Uri.parse("https://staging-app.ultragpt.pro/en/chat"),
        )?.toString(),
        "https://staging-app.ultragpt.pro/en/chat",
      );
      expect(
        UltraGptUrls.resolveIncomingAppUrl(
          Uri.parse("https://example.com/en/chat"),
        ),
        isNull,
      );
    });

    test("detects Google auth start and callback URLs", () {
      expect(
        UltraGptUrls.isGoogleAuthStartUrl(
          Uri.parse("https://accounts.google.com/o/oauth2/v2/auth"),
        ),
        isTrue,
      );
      expect(
        UltraGptUrls.isGoogleAuthStartUrl(
          Uri.parse("https://api.ultragpt.pro/auth/google"),
        ),
        isTrue,
      );
      expect(
        UltraGptUrls.isGoogleAuthStartUrl(
          Uri.parse("https://api.ultragpt.pro/auth/google/callback?code=1"),
        ),
        isFalse,
      );
      expect(
        UltraGptUrls.isOAuthCallbackUrl(
          Uri.parse("https://app.ultragpt.pro/en/auth/callback?token=abc"),
        ),
        isTrue,
      );
      expect(
        UltraGptUrls.apiGoogleCallbackUri("server-code").toString(),
        "https://api.ultragpt.pro/auth/google/callback?code=server-code",
      );
      expect(
        UltraGptUrls.apiGoogleMobileUri.toString(),
        "https://api.ultragpt.pro/auth/google/mobile",
      );
      expect(
        UltraGptUrls.apiFcmDevicesUri.toString(),
        "https://api.ultragpt.pro/mobile/devices/fcm",
      );
      expect(UltraGptUrls.sessionCookieName, "session-token");
      expect(
        UltraGptUrls.localeFromAppUrl(
          Uri.parse("https://app.ultragpt.pro/en/chat"),
        ),
        "en",
      );
    });

    test("starts on chat unless the incoming link is a share URL", () {
      expect(UltraGptUrls.startUri().toString(), UltraGptUrls.defaultChatUrl);
      expect(
        UltraGptUrls.startUri(
          incoming: Uri.parse("https://example.com"),
        ).toString(),
        UltraGptUrls.defaultChatUrl,
      );
      expect(
        UltraGptUrls.startUri(
          incoming: Uri.parse("https://app.ultragpt.pro/"),
        ).toString(),
        UltraGptUrls.defaultChatUrl,
      );
      expect(
        UltraGptUrls.startUri(
          incoming: Uri.parse("https://app.ultragpt.pro/en/chat"),
        ).toString(),
        UltraGptUrls.defaultChatUrl,
      );
      expect(
        UltraGptUrls.startUri(
          incoming: Uri.parse("https://app.ultragpt.pro/en/share/ready"),
        ).toString(),
        "https://app.ultragpt.pro/en/share/ready",
      );
      expect(
        UltraGptUrls.startUri(
          incoming: Uri.parse("https://app.ultragpt.pro/share/ready"),
        ).toString(),
        "https://app.ultragpt.pro/share/ready",
      );
      expect(
        UltraGptUrls.startUri(
          incoming: Uri.parse("https://staging-app.ultragpt.pro/share/ready"),
        ).toString(),
        "https://staging-app.ultragpt.pro/share/ready",
      );
      expect(
        UltraGptUrls.startUri(
          incoming: Uri.parse("ultragpt://share/abc-123"),
        ).toString(),
        "https://app.ultragpt.pro/en/share/abc-123",
      );
      expect(
        UltraGptUrls.startUri(
          incoming: Uri.parse(
            "https://app.ultragpt.pro/en/auth/callback?code=123",
          ),
        ).toString(),
        UltraGptUrls.defaultChatUrl,
      );
    });
  });

  group("resolveNotificationUrl", () {
    test("accepts safe relative UltraGPT paths", () {
      expect(
        UltraGptUrls.resolveNotificationUrl(
          "/en/account/notifications",
        )?.toString(),
        "https://app.ultragpt.pro/en/account/notifications",
      );
      expect(
        UltraGptUrls.resolveNotificationUrl(
          "/en/chat?conversation=abc",
        )?.toString(),
        "https://app.ultragpt.pro/en/chat?conversation=abc",
      );
      expect(
        UltraGptUrls.resolveNotificationUrl("  /ru/account/notifications  ")
            ?.toString(),
        "https://app.ultragpt.pro/ru/account/notifications",
      );
    });

    test("rejects unsafe or absolute notification URLs", () {
      expect(UltraGptUrls.resolveNotificationUrl(null), isNull);
      expect(UltraGptUrls.resolveNotificationUrl(""), isNull);
      expect(UltraGptUrls.resolveNotificationUrl("en/chat"), isNull);
      expect(
        UltraGptUrls.resolveNotificationUrl("//evil.example/phish"),
        isNull,
      );
      expect(
        UltraGptUrls.resolveNotificationUrl("https://evil.example/phish"),
        isNull,
      );
      expect(
        UltraGptUrls.resolveNotificationUrl("javascript:alert(1)"),
        isNull,
      );
      expect(
        UltraGptUrls.resolveNotificationUrl("/en/chat /elsewhere"),
        isNull,
      );
      expect(
        UltraGptUrls.resolveNotificationUrl("/en\\chat"),
        isNull,
      );
      expect(
        UltraGptUrls.resolveNotificationUrl(
          "https://app.ultragpt.pro/en/account/notifications",
        ),
        isNull,
      );
      expect(
        UltraGptUrls.resolveNotificationUrl(
          "//app.ultragpt.pro/en/account/notifications",
        ),
        isNull,
      );
    });
  });

  group("shareTextFromWebPayload", () {
    test("joins title, text, and url without duplicating the same value", () {
      expect(
        shareTextFromWebPayload({
          "title": "My chat",
          "text": "My chat",
          "url": "https://app.ultragpt.pro/en/share/abc",
        }),
        "My chat\nhttps://app.ultragpt.pro/en/share/abc",
      );
      expect(shareTextFromWebPayload({"url": "  "}), isNull);
    });
  });
}
