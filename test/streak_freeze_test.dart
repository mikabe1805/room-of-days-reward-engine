// Ported from the app's test/streak_freeze_test.dart (1.0.4, build 49).
// The two tests about loading old saves are left out with the save code.
import 'package:room_of_days_rewards/room_of_days_rewards.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;

  setUp(() => Clock.use(() => now));
  tearDown(Clock.reset);

  RewardBundle complete(RewardEngine state, String title) {
    final bundle = state.roll(
      Quest(title: title, stat: Stat.vit, difficulty: 2),
    );
    state.commit(bundle);
    return bundle;
  }

  test('freezes begin generous: three ready, room for five', () {
    final fresh = RewardEngine();
    expect(fresh.streakFreezes, RewardEngine.starterStreakFreezes);
    expect(fresh.streakFreezeCapacity, 5);
  });

  test(
    'one quiet day is frozen, recorded, and the active-day count continues',
    () {
      now = DateTime(2026, 8, 3, 9);
      final state = RewardEngine()
        ..streakDays = 10
        ..bestStreak = 10
        ..lastCompletionDay = '2026-08-01'
        ..streakFreezes = 3;

      final bundle = complete(state, 'Drink water');

      expect(bundle.freezesUsed, 1);
      expect(bundle.shieldHeld, isTrue);
      expect(bundle.comebackMult, isNull);
      expect(bundle.freezeBalanceAfter, 2);
      expect(state.streakDays, 11);
      expect(state.bestStreak, 11);
      expect(state.streakFreezes, 2);
      expect(state.frozenStreakDays, {'2026-08-02'});
    },
  );

  test(
    'a multi-day gap uses one freeze per day when the whole span is held',
    () {
      now = DateTime(2026, 8, 5, 9);
      final state = RewardEngine()
        ..streakDays = 6
        ..bestStreak = 6
        ..lastCompletionDay = '2026-08-02'
        ..streakFreezes = 2;

      final bundle = complete(state, 'Step outside');

      expect(bundle.freezesUsed, 2);
      expect(state.streakDays, 7);
      expect(state.streakFreezes, 0);
      expect(state.frozenStreakDays, {'2026-08-03', '2026-08-04'});
    },
  );

  test(
    'an under-covered gap preserves every freeze and begins a warm return',
    () {
      now = DateTime(2026, 8, 6, 9);
      final state = RewardEngine()
        ..streakDays = 9
        ..bestStreak = 9
        ..lastCompletionDay = '2026-08-01'
        ..streakFreezes = 3;

      final preview = state.pendingStreakGap;
      expect(preview.days, 4);
      expect(preview.covered, isFalse);

      final bundle = complete(state, 'Open the curtains');

      expect(bundle.freezesUsed, 0);
      expect(bundle.comebackMult, RewardEngine.comebackBonus);
      expect(state.streakDays, 1);
      expect(state.bestStreak, 9);
      expect(state.comebacks, 1);
      expect(
        state.streakFreezes,
        3,
        reason: 'partial coverage is never wasted',
      );
      expect(state.frozenStreakDays, isEmpty);
    },
  );

  test('ordinary active days replenish a freeze without a perfect board', () {
    now = DateTime(2026, 8, 10, 9);
    final state = RewardEngine()..streakFreezes = 0;

    final first = complete(state, 'Day one');
    expect(first.freezeEarned, isFalse);
    expect(state.streakFreezeProgress, 1);

    now = DateTime(2026, 8, 11, 9);
    final second = complete(state, 'Day two');
    expect(second.freezeEarned, isFalse);
    expect(state.streakFreezeProgress, 2);

    now = DateTime(2026, 8, 12, 9);
    final third = complete(state, 'Day three');
    expect(third.freezeEarned, isTrue);
    expect(third.freezeBalanceAfter, 1);
    expect(state.streakFreezes, 1);
    expect(state.streakFreezeProgress, 0);
  });

  test('CARE 40 shortens the ordinary cadence to two active days', () {
    now = DateTime(2026, 8, 10, 9);
    final state = RewardEngine()..streakFreezes = 0;
    state.stats[Stat.vit] = 40;

    complete(state, 'Day one');
    expect(state.streakFreezeProgress, 1);
    now = DateTime(2026, 8, 11, 9);
    final second = complete(state, 'Day two');

    expect(second.freezeEarned, isTrue);
    expect(state.streakFreezes, 1);
    expect(state.streakFreezeProgress, 0);
  });

  test('the completion that reaches CARE 40 uses the shorter cadence', () {
    now = DateTime(2026, 8, 11, 9);
    final state = RewardEngine()
      ..streakFreezes = 0
      ..streakFreezeProgress = 1;
    state.stats[Stat.vit] = 37;

    final bundle = complete(state, 'Care for myself');

    expect(state.stats[Stat.vit], greaterThanOrEqualTo(40));
    expect(bundle.freezeCadenceAfter, 2);
    expect(bundle.freezeEarned, isTrue);
    expect(state.streakFreezes, 1);
    expect(state.streakFreezeProgress, 0);
  });

  test('level six widens the reserve to a week and grants two freezes', () {
    final state = RewardEngine()
      ..level = 5
      ..streakFreezes = 5;
    state.xp = state.xpNeeded(6);

    final result = state.applyLevelUps();

    expect(result.leveledTo, 6);
    expect(result.unlock, 'WEEK-LONG FREEZE RESERVE');
    expect(state.streakFreezeCapacity, 7);
    expect(state.streakFreezes, 7);
    expect(state.freezeLevelBonusGranted, isTrue);
  });
}
