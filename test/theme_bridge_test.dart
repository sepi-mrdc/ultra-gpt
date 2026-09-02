import "dart:ui";

import "package:flutter_test/flutter_test.dart";
import "package:ultragpt3/theme_bridge.dart";

void main() {
  test("maps Android brightness to Nuxt color-mode values", () {
    expect(colorModeForBrightness(Brightness.light), "light");
    expect(colorModeForBrightness(Brightness.dark), "dark");
  });

  test("writes nuxt-color-mode and the matching html class", () {
    final darkScript = themeSyncJavaScript("dark");
    expect(
      darkScript,
      contains('localStorage.setItem("nuxt-color-mode", mode)'),
    );
    expect(darkScript, contains('var mode = "dark"'));
    expect(darkScript, contains('root.classList.remove("light", "dark")'));
    expect(darkScript, contains("root.classList.add(mode)"));

    final lightScript = themeSyncJavaScript("light");
    expect(lightScript, contains('var mode = "light"'));
    expect(lightScript, isNot(contains('var mode = "dark"')));
  });
}
