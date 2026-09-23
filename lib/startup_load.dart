const Duration startupRecoverTimeout = Duration(seconds: 8);
const Duration startupGiveUpTimeout = Duration(seconds: 18);
const Duration startupPostRecoverTimeout = Duration(seconds: 10);

enum StartupWatchdogAction {
  none,
  reveal,
  recoverByClearingCache,
  reload,
}

/// Decides how to unstick the first-launch splash without changing the UI.
///
/// The overlay stays up until the WebView reports a ready page. After a few
/// close/reopen cycles Android WebView can stop delivering load events (stale
/// HTTP/service-worker cache, or CookieManager work during WebView init).
/// This policy reveals a page that is already painted, otherwise clears the
/// WebView cache once and reloads while the existing splash stays on screen.
class StartupLoadCoordinator {
  bool didCacheRecovery = false;

  StartupWatchdogAction decideWatchdog({
    required bool alreadyRevealed,
    required bool pageLooksReady,
    required bool loadHasStarted,
    required bool isFinalChance,
  }) {
    if (alreadyRevealed) return StartupWatchdogAction.none;
    if (pageLooksReady) return StartupWatchdogAction.reveal;

    if (!didCacheRecovery && (!loadHasStarted || isFinalChance)) {
      didCacheRecovery = true;
      return StartupWatchdogAction.recoverByClearingCache;
    }

    if (isFinalChance) return StartupWatchdogAction.reload;
    return StartupWatchdogAction.none;
  }
}

/// Best-effort cleanup of a stuck service worker / Cache Storage.
/// Does not touch cookies or localStorage, so the session survives.
const recoverStuckStartupJavaScript = r'''
(function () {
  try {
    if (navigator.serviceWorker) {
      navigator.serviceWorker.getRegistrations().then(function (regs) {
        regs.forEach(function (reg) {
          try { reg.unregister(); } catch (e) {}
        });
      });
    }
  } catch (e) {}
  try {
    if (window.caches) {
      caches.keys().then(function (keys) {
        keys.forEach(function (key) {
          try { caches.delete(key); } catch (e) {}
        });
      });
    }
  } catch (e) {}
  return true;
})();
''';
