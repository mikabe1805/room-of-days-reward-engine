/// Day-key helpers — periods are computed from local wall-clock dates.
abstract final class Days {
  static final _keyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Strict, non-normalizing parser for persisted day keys. `DateTime` would
  /// otherwise quietly turn 2026-02-31 into March, hiding a damaged save.
  static DateTime? tryParse(Object? value) {
    if (value is! String || !_keyPattern.hasMatch(value)) return null;
    final p = value.split('-');
    final year = int.tryParse(p[0]);
    final month = int.tryParse(p[1]);
    final day = int.tryParse(p[2]);
    if (year == null || month == null || day == null) return null;
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static DateTime parse(String value) =>
      tryParse(value) ??
      (throw FormatException('Invalid Room of Days day', value));

  /// Keeps a valid persisted key and drops a drifted one to null.
  static String? validKey(Object? value) =>
      tryParse(value) == null ? null : value as String;

  /// Calendar-day distance, independent of 23/25-hour daylight-saving days.
  static int between(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }
}
