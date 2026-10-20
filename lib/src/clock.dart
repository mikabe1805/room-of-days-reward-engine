/// A single seam for "now" so the engine's day-rollover, streak, and
/// period-reset logic is deterministically testable (multi-day case-study
/// simulations) — and so all time logic flows through one place.
/// Production uses the real wall clock; tests freeze or advance it.
abstract final class Clock {
  static DateTime Function() _now = DateTime.now;

  static DateTime now() => _now();

  /// Freeze time at [t] (tests).
  static void freeze(DateTime t) => _now = () => t;

  /// Drive time from a mutable supplier (tests).
  static void use(DateTime Function() supplier) => _now = supplier;

  /// Back to the real wall clock.
  static void reset() => _now = DateTime.now;
}
