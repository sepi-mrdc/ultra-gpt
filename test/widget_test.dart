import 'package:flutter_test/flutter_test.dart';
import 'package:ultragpt3/app_urls.dart';

void main() {
  test('opens chat unless a share link launched the app', () {
    expect(UltraGptUrls.startUri().toString(), UltraGptUrls.defaultChatUrl);
    expect(
      UltraGptUrls.startUri(
        incoming: Uri.parse('https://app.ultragpt.pro/en/share/abc'),
      ).toString(),
      'https://app.ultragpt.pro/en/share/abc',
    );
    expect(
      UltraGptUrls.startUri(
        incoming: Uri.parse('https://staging-app.ultragpt.pro/share/abc'),
      ).toString(),
      'https://staging-app.ultragpt.pro/share/abc',
    );
  });
}
