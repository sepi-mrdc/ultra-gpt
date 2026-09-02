import "dart:ui";

const themeUserScriptGroupName = "ultragptTheme";

String colorModeForBrightness(Brightness brightness) {
  return brightness == Brightness.dark ? "dark" : "light";
}

String themeSyncJavaScript(String colorMode) {
  final mode = colorMode == "dark" ? "dark" : "light";
  final other = mode == "dark" ? "light" : "dark";

  return """
(function () {
  var mode = "$mode";
  var other = "$other";
  try {
    localStorage.setItem("nuxt-color-mode", mode);
  } catch (e) {}

  var root = document.documentElement;
  if (root) {
    root.classList.remove("light", "dark");
    root.classList.add(mode);
  }

  var api = window.__NUXT_COLOR_MODE__;
  if (!api) return;

  api.preference = mode;
  api.value = mode;
  if (typeof api.removeColorScheme === "function") {
    api.removeColorScheme(other);
  }
  if (typeof api.addColorScheme === "function") {
    api.addColorScheme(mode);
  }
})();
""";
}
