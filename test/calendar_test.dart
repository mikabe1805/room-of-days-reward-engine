// Ported from the app's test/audit_regressions_test.dart (1.0.4, build 49):
// the tests there that exercise the reward engine and its day keys.
import 'package:room_of_days_rewards/room_of_days_rewards.dart';
import 'package:test/test.dart';

void main() {
  tearDown(Clock.reset);

  test('calendar gaps stay correct across daylight-saving boundaries', () {
    final state = RewardEngine()..streakFreezes = 0;
    final quest = Quest(title: 'Walk', stat: Stat.vit, difficulty: 2);

    Clock.freeze(DateTime(2026, 3, 7, 12));
    state.commit(state.roll(quest));
    expect(state.streakDays, 1);

    // In New York this interval contains a 23-hour day. It is still two
    // calendar dates apart, with one genuinely open day between them.
    Clock.freeze(DateTime(2026, 3, 9, 12));
    final comeback = state.roll(quest);
    expect(comeback.comebackMult, isNotNull);
    expect(comeback.revivesHearth, isTrue);
    state.commit(comeback);
    expect(state.streakDays, 1);
    expect(state.comebacks, 1);
    expect(Days.between(DateTime(2026, 3, 7), DateTime(2026, 3, 9)), 2);
  });

  test('hearth ignition is reserved for first spark and real comeback', () {
    final state = RewardEngine()..streakFreezes = 0;
    final quest = Quest(title: 'Tend the fire', stat: Stat.dis, difficulty: 2);

    Clock.freeze(DateTime(2026, 7, 20, 9));
    final firstSpark = state.roll(quest);
    expect(firstSpark.revivesHearth, isTrue);
    state.commit(firstSpark);

    Clock.freeze(DateTime(2026, 7, 21, 9));
    final continued = state.roll(quest);
    expect(continued.firstOfDay, isTrue);
    expect(continued.revivesHearth, isFalse);
    state.commit(continued);

    Clock.freeze(DateTime(2026, 7, 23, 9));
    final comeback = state.roll(quest);
    expect(comeback.revivesHearth, isTrue);
  });

  test('damaged day keys are refused instead of normalized', () {
    expect(Days.tryParse('2026-02-31'), isNull);
    expect(Days.tryParse('not-a-day'), isNull);
    expect(Days.validKey('broken'), isNull);
    expect(Days.validKey('2026-03-01'), '2026-03-01');
    expect(() => Days.parse('2026-02-31'), throwsFormatException);
  });
}
