// Ported from the app's test/audit_regressions_test.dart (1.0.4, build 49).
// "A save from before the count existed" is set up directly here, because
// the save code is left out of this sample.
import 'package:room_of_days_rewards/room_of_days_rewards.dart';
import 'package:test/test.dart';

void main() {
  test('a level-up names the quests that earned it, and never guesses', () {
    final state = RewardEngine()..totalCompletions = 7;
    state.xp = state.xpNeeded(2);
    final first = state.applyLevelUps();
    expect(first.previousLevel, 1);
    expect(first.questsSince, 7);

    state.totalCompletions = 12;
    state.xp = state.xpNeeded(3);
    expect(state.applyLevelUps().questsSince, 5);

    // A save from before the count existed cannot know; it says nothing
    // rather than inventing a number, then counts from this level onward.
    state
      ..completionsAtLastLevel = null
      ..totalCompletions = 20;
    state.xp = state.xpNeeded(state.level + 1);
    expect(state.applyLevelUps().questsSince, isNull);
    state.totalCompletions = 23;
    state.xp = state.xpNeeded(state.level + 1);
    expect(state.applyLevelUps().questsSince, 3);
  });

  test('overflow XP carries through several levels at once', () {
    final state = RewardEngine();
    // 105 for level 2, 150 for level 3, 195 for level 4, then 20 left over.
    state.xp = 105 + 150 + 195 + 20;

    final result = state.applyLevelUps();

    expect(result.leveledTo, 4);
    expect(result.previousLevel, 1);
    expect(result.unlock, 'EVIDENCE ARCHIVE');
    expect(state.level, 4);
    expect(state.xp, 20);
  });

  test('no level-up reports nothing and spends nothing', () {
    final state = RewardEngine()..xp = 59;

    final result = state.applyLevelUps();

    expect(result.leveledTo, isNull);
    expect(result.unlock, isNull);
    expect(state.xp, 59);
  });
}
