// Plays the day in the App Store screenshots: the account at level 18 with a
// 12-day streak finishes today's three Quests, then misses a day and
// comes back. Run with: dart run example/screenshot_day.dart
import 'dart:math';

import 'package:room_of_days_rewards/room_of_days_rewards.dart';

/// Never rolls a critical hit, so the numbers match the screenshots.
class _NoCrit implements Random {
  @override
  double nextDouble() => 0.99;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

void main() {
  var now = DateTime(2026, 8, 8, 18);
  Clock.use(() => now);

  final engine = RewardEngine(rng: _NoCrit())
    ..level = 18
    ..xp = 284
    ..streakDays = 12
    ..bestStreak = 12
    ..lastCompletionDay = '2026-08-08'
    ..lastActiveDay = '2026-08-08'
    ..streakFreezes = 3
    ..freezeLevelBonusGranted = true;
  engine.stats.addAll({
    Stat.str: 88,
    Stat.vit: 72,
    Stat.intl: 116,
    Stat.foc: 94,
    Stat.soc: 61,
    Stat.dis: 103,
  });

  final today = [
    Quest(title: 'Read ten pages', stat: Stat.intl, difficulty: 4),
    Quest(
      title: 'Clear the kitchen counter',
      stat: Stat.dis,
      difficulty: 5,
      dread: true,
    ),
    Quest(title: 'Message someone I miss', stat: Stat.soc, difficulty: 4),
  ];

  print(
    'Saturday, Aug 8. Level ${engine.level}, ${engine.streakDays}-day '
    'streak, ${engine.streakFreezes} freezes ready.\n',
  );
  for (final quest in today) {
    _finish(engine, quest);
  }

  // Sunday passes with nothing done. Monday, one Quest.
  now = DateTime(2026, 8, 10, 9);
  engine.rollover();
  print('\nMonday, Aug 10. Sunday was missed.');
  final gap = engine.pendingStreakGap;
  print('Gap of ${gap.days} day, covered by freezes: ${gap.covered}\n');
  _finish(
    engine,
    Quest(title: 'Walk after lunch', stat: Stat.vit, difficulty: 2),
  );

  print(
    '\nStreak ${engine.streakDays} days, ${engine.streakFreezes} freezes '
    'left, frozen days: ${engine.frozenStreakDays.join(', ')}',
  );
}

void _finish(RewardEngine engine, Quest quest) {
  final bundle = engine.roll(quest);
  engine.commit(bundle);
  final level = engine.applyLevelUps();
  final parts = [
    '+${bundle.xp} XP',
    '+${bundle.embers} Glimmers',
    '+${bundle.statGain} ${bundle.stat.label}',
    if (bundle.streakMult != null)
      'streak ×${bundle.streakMult!.toStringAsFixed(1)}',
    if (bundle.freezesUsed > 0) '${bundle.freezesUsed} freeze held the gap',
    if (bundle.freezeEarned) 'freeze earned',
  ];
  print('${quest.title.padRight(28)} ${parts.join(' · ')}');
  if (level.leveledTo != null) {
    print(
      '  Level up: ${level.previousLevel} to ${level.leveledTo} '
      'after ${level.questsSince ?? '?'} Quests',
    );
  }
}
