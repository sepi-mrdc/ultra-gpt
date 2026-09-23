import "package:flutter_test/flutter_test.dart";
import "package:ultragpt3/startup_load.dart";

void main() {
  group("StartupLoadCoordinator", () {
    test("does nothing after the first page has already been revealed", () {
      final coordinator = StartupLoadCoordinator();

      expect(
        coordinator.decideWatchdog(
          alreadyRevealed: true,
          pageLooksReady: false,
          loadHasStarted: false,
          isFinalChance: true,
        ),
        StartupWatchdogAction.none,
      );
    });

    test("reveals when the WebView already painted a page", () {
      final coordinator = StartupLoadCoordinator();

      expect(
        coordinator.decideWatchdog(
          alreadyRevealed: false,
          pageLooksReady: true,
          loadHasStarted: true,
          isFinalChance: false,
        ),
        StartupWatchdogAction.reveal,
      );
    });

    test("recovers immediately when no load events arrived", () {
      final coordinator = StartupLoadCoordinator();

      expect(
        coordinator.decideWatchdog(
          alreadyRevealed: false,
          pageLooksReady: false,
          loadHasStarted: false,
          isFinalChance: false,
        ),
        StartupWatchdogAction.recoverByClearingCache,
      );
      expect(coordinator.didCacheRecovery, isTrue);
    });

    test("waits when a load is in progress on the first watchdog", () {
      final coordinator = StartupLoadCoordinator();

      expect(
        coordinator.decideWatchdog(
          alreadyRevealed: false,
          pageLooksReady: false,
          loadHasStarted: true,
          isFinalChance: false,
        ),
        StartupWatchdogAction.none,
      );
      expect(coordinator.didCacheRecovery, isFalse);
    });

    test("recovers a started but unfinished load on the final watchdog", () {
      final coordinator = StartupLoadCoordinator();

      expect(
        coordinator.decideWatchdog(
          alreadyRevealed: false,
          pageLooksReady: false,
          loadHasStarted: true,
          isFinalChance: true,
        ),
        StartupWatchdogAction.recoverByClearingCache,
      );
    });

    test("reloads after a recovery already ran", () {
      final coordinator = StartupLoadCoordinator()..didCacheRecovery = true;

      expect(
        coordinator.decideWatchdog(
          alreadyRevealed: false,
          pageLooksReady: false,
          loadHasStarted: true,
          isFinalChance: true,
        ),
        StartupWatchdogAction.reload,
      );
    });

    test("recovers only once across watchdog passes", () {
      final coordinator = StartupLoadCoordinator();

      expect(
        coordinator.decideWatchdog(
          alreadyRevealed: false,
          pageLooksReady: false,
          loadHasStarted: false,
          isFinalChance: false,
        ),
        StartupWatchdogAction.recoverByClearingCache,
      );
      expect(
        coordinator.decideWatchdog(
          alreadyRevealed: false,
          pageLooksReady: false,
          loadHasStarted: false,
          isFinalChance: true,
        ),
        StartupWatchdogAction.reload,
      );
    });
  });

  test("recovery script drops service workers without touching storage", () {
    expect(recoverStuckStartupJavaScript, contains("serviceWorker"));
    expect(recoverStuckStartupJavaScript, contains("unregister"));
    expect(recoverStuckStartupJavaScript, contains("caches.delete"));
    expect(recoverStuckStartupJavaScript, isNot(contains("localStorage")));
    expect(recoverStuckStartupJavaScript, isNot(contains("cookie")));
  });
}
