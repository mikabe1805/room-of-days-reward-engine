// Tests written for this repo. The first group checks the engine against the
// receipts in the App Store screenshots; the rest pin one rule each.
import 'dart:math';

import 'package:room_of_days_rewards/room_of_days_rewards.dart';
import 'package:test/test.dart';

/// Hands out fixed values, so a critical hit happens exactly when a test
/// asks for one.
class ScriptedRandom implements Random {
  ScriptedRandom(this.values);

  final List<double> values;
  var _next = 0;

  @override
  double nextDouble() => values[_next++ % values.length];

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

/// Never rolls a critical hit (crit chance is at most 0.10).
Random noCrit() => ScriptedRandom([0.99]);

/// The account in the App Store screenshots: level 18, a 12-day streak with
/// today already active, three freezes ready.
RewardEngine screenshotAccount() {
  final engine = RewardEngine(rng: noCrit())
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
  return engine;
}

void main() {
  setUp(() => Clock.freeze(DateTime(2026, 8, 8, 18)));
  tearDown(Clock.reset);

  group('the App Store screenshot account', () {
    test('Read ten pages pays +26 XP, +8 Glimmers and +6 Mind at ×1.6', () {
      final engine = screenshotAccount();
      final read = Quest(
        title: 'Read ten pages',
        stat: Stat.intl,
        difficulty: 4,
      );

      expect(engine.xpPreview(read), 26);
      final bundle = engine.roll(read);

      expect(bundle.xp, 26);
      expect(bundle.embers, 8);
      expect(bundle.stat, Stat.intl);
      expect(bundle.statGain, 6);
      expect(bundle.streakMult!.toStringAsFixed(1), '1.6');
      expect(bundle.firstOfDay, isFalse);
    });

    test('the dreaded counter pays +41 XP, +13 Glimmers and +11 Home', () {
      final engine = screenshotAccount();
      final counter = Quest(
        title: 'Clear the kitchen counter',
        stat: Stat.dis,
        difficulty: 5,
        dread: true,
      );

      final bundle = engine.roll(counter);

      expect(bundle.xp, 41);
      expect(bundle.embers, 13);
      expect(bundle.statGain, 11, reason: 'round(7.5) is 8, and dread adds 3');
    });

    test('the stat tags on the portfolio board read from these numbers', () {
      final engine = screenshotAccount();

      expect(engine.intXpMult.toStringAsFixed(2), '1.09'); // Mind 116
      expect(engine.disNeglectMult.toStringAsFixed(2), '1.13'); // Home 103
      expect(engine.activeDaysPerFreeze, 2); // Care 72
      expect(engine.critChance, closeTo(0.052, 1e-9)); // Body 88
    });
  });

  group('streak', () {
    test('the multiplier ramps to ×1.5 over a week and caps at ×2.0', () {
      final engine = RewardEngine();

      expect(engine.streakMultFor(0), 1.0);
      expect(engine.streakMultFor(7), 1.5);
      expect(engine.streakMultFor(30), 2.0);
      expect(engine.streakMultFor(365), 2.0);
      for (var day = 1; day <= 30; day++) {
        expect(
          engine.streakMultFor(day),
          greaterThan(engine.streakMultFor(day - 1)),
        );
      }
    });

    test('a comeback pays at the new streak, not the broken one', () {
      Clock.freeze(DateTime(2026, 8, 10, 9));
      final engine = RewardEngine(rng: noCrit())
        ..streakDays = 30
        ..bestStreak = 30
        ..lastCompletionDay = '2026-08-05'
        ..streakFreezes = 0;
      final walk = Quest(title: 'Walk', stat: Stat.vit, difficulty: 2);

      // The card never promises more than the roll will pay, and it leaves
      // the welcome-back bonus as a surprise.
      expect(engine.xpPreview(walk), 11); // 10 × 1.07
      final bundle = engine.roll(walk);

      expect(bundle.xp, 16, reason: '10 × 1.07 × 1.5, not 10 × 2.0 × 1.5');
      expect(bundle.comebackMult, RewardEngine.comebackBonus);
      expect(bundle.streakMult, engine.streakMultFor(1));

      engine.commit(bundle);
      expect(engine.streakDays, 1);
      expect(engine.bestStreak, 30, reason: 'the best run is kept');
    });

    test('a milestone chest is paid once, however many Quests that day', () {
      Clock.freeze(DateTime(2026, 8, 10, 9));
      final engine = RewardEngine(rng: noCrit())
        ..streakDays = 6
        ..lastCompletionDay = '2026-08-09';

      var receipts = 0;
      for (final title in ['Water', 'Stretch', 'Read', 'Tidy']) {
        final bundle = engine.roll(
          Quest(title: title, stat: Stat.vit, difficulty: 3),
        );
        receipts += bundle.embers;
        engine.commit(bundle);
      }

      expect(engine.streakDays, 7);
      expect(engine.embers, receipts + RewardEngine.streakMilestones[7]!);
    });
  });

  group('anti-grind', () {
    test('the same Quest again today pays 100%, 50%, 25%, then 10%', () {
      final engine = RewardEngine(rng: noCrit())
        ..streakDays = 1
        ..lastCompletionDay = Days.key(Clock.now());

      final paid = <int>[];
      for (var i = 0; i < 5; i++) {
        final bundle = engine.roll(
          Quest(title: 'Push-ups', stat: Stat.str, difficulty: 4),
        );
        paid.add(bundle.xp);
        engine.commit(bundle);
      }

      // 15 × 1.07 = 16.1, then halved, quartered, and 10% from there on.
      expect(paid, [16, 8, 4, 2, 2]);
    });

    test('XP past 250 today is halved and past 400 quartered', () {
      final engine = RewardEngine(rng: noCrit());
      final big = Quest(title: 'Move house', stat: Stat.dis, difficulty: 10);

      expect(engine.xpPreview(big), 30);
      engine.todayXp = 250;
      expect(engine.xpPreview(big), 15);
      engine.todayXp = 400;
      expect(engine.xpPreview(big), 8); // 7.5 rounds up
      expect(engine.roll(big).xp, 8);
    });

    test('past 40 of one stat today, that stat grows at half speed', () {
      final engine = RewardEngine(rng: noCrit());
      engine.todayStats[Stat.str] = 40;

      final bundle = engine.roll(
        Quest(title: 'Run', stat: Stat.str, difficulty: 4),
      );

      expect(bundle.statGain, 3); // 4 × 1.5 = 6, halved
    });

    test('a custom Quest made today pays half on its first completion', () {
      final today = Days.key(Clock.now());
      final engine = RewardEngine(rng: noCrit());
      final fresh = Quest(
        title: 'Practice scales',
        stat: Stat.foc,
        difficulty: 4,
        custom: true,
        createdDay: today,
      );

      final first = engine.roll(fresh);
      expect(first.xp, 6); // 15 × 0.85 × 0.5

      final older = Quest(
        title: 'Practice chords',
        stat: Stat.foc,
        difficulty: 4,
        custom: true,
        createdDay: '2026-08-01',
      );
      expect(engine.roll(older).xp, 13); // 15 × 0.85
    });
  });

  group('stat bends', () {
    test('a Quest left alone pays more, up to +50%, and Home amplifies it', () {
      final engine = RewardEngine(rng: noCrit());
      Quest idle() => Quest(
        title: 'Water the plants',
        stat: Stat.vit,
        difficulty: 4,
        lastDoneDay: '2026-07-29', // ten days ago
      );

      expect(engine.roll(idle()).xp, 23); // 15 × 1.5 = 22.5

      engine.stats[Stat.dis] = 200;
      expect(engine.roll(idle()).xp, 24); // 15 × (1 + 0.5 × 1.25)
    });

    test('Body raises the crit chance from 3% to at most 10%', () {
      final engine = RewardEngine();
      expect(engine.critChance, 0.03);
      engine.stats[Stat.str] = 200;
      expect(engine.critChance, closeTo(0.08, 1e-9));
      engine.stats[Stat.str] = 1000;
      expect(engine.critChance, 0.10);
    });

    test('a critical hit multiplies by 1.5 to 3 and is on the receipt', () {
      // First draw 0.01 is under the 3% chance; the second sets the size.
      final engine = RewardEngine(rng: ScriptedRandom([0.01, 0.5]));

      final bundle = engine.roll(
        Quest(title: 'Lift', stat: Stat.str, difficulty: 4),
      );

      expect(bundle.critMult, 2.25);
      expect(bundle.xp, 34); // 15 × 2.25 = 33.75
    });

    test('a timed completion pays ×1.2', () {
      final engine = RewardEngine(rng: noCrit());

      final bundle = engine.roll(
        Quest(title: 'Focus block', stat: Stat.foc, difficulty: 4),
        verified: true,
      );

      expect(bundle.verifiedMult, RewardEngine.verifiedBonus);
      expect(bundle.xp, 18);
    });
  });

  group('roll and commit', () {
    test('roll changes nothing the player can see; commit applies it', () {
      final engine = RewardEngine(rng: noCrit());
      final quest = Quest(title: 'Read', stat: Stat.intl, difficulty: 4);

      final bundle = engine.roll(quest);
      expect(engine.xp, 0);
      expect(engine.stats[Stat.intl], 0);
      expect(engine.streakDays, 0);
      expect(quest.lastDoneDay, Days.key(Clock.now()));

      engine.commit(bundle);
      expect(engine.xp, bundle.xp);
      expect(engine.embers, bundle.embers);
      expect(engine.stats[Stat.intl], bundle.statGain);
      expect(engine.streakDays, 1);
      expect(engine.todayXp, bundle.xp);
    });

    test('rollover starts a fresh haul on a new day', () {
      final engine = RewardEngine(rng: noCrit());
      engine.rollover();
      engine.commit(
        engine.roll(Quest(title: 'Read', stat: Stat.intl, difficulty: 4)),
      );
      expect(engine.rollover(), isFalse);
      expect(engine.todayXp, greaterThan(0));

      Clock.freeze(DateTime(2026, 8, 9, 7));
      expect(engine.rollover(), isTrue);
      expect(engine.todayXp, 0);
      expect(engine.todayTitleCounts, isEmpty);
    });

    test('history keeps 180 days and never drops today', () {
      final engine = RewardEngine(rng: noCrit());
      final today = DateTime(2026, 8, 8);
      // An imported save with 300 days, all later than today's clock.
      for (var i = 1; i <= 300; i++) {
        engine.history[Days.key(today.add(Duration(days: i)))] = 1;
      }

      engine.commit(
        engine.roll(Quest(title: 'Read', stat: Stat.intl, difficulty: 4)),
      );

      expect(engine.history.length, 180);
      expect(engine.history[Days.key(today)], 1);
    });
  });
}
