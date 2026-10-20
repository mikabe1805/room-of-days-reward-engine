import 'dart:math';

import 'clock.dart';
import 'days.dart';
import 'quest.dart';
import 'reward_bundle.dart';
import 'stat.dart';

// Cut down from `GameState` in the app's lib/engine.dart, Room of Days 1.0.4
// (49). The formula, the streak and freeze rules and
// the comments on them are the app's. The app's class also handles loot
// drops, reward messages, goals, achievements, the room and saving; those
// parts are left out, so it is a plain class here rather than a Flutter
// ChangeNotifier.

/// The game engine. XP = base × difficulty × dread × streak × proof × crit
/// (RESEARCH.md §5). Period resets happen in [rollover].
class RewardEngine {
  RewardEngine({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  int level = 1;
  int xp = 0;
  int totalXp = 0;
  final Map<Stat, int> stats = {for (final s in Stat.values) s: 0};

  /// Shown in the app as Glimmers.
  int embers = 0;

  /// Completions per day key: the calendar and history view.
  final Map<String, int> history = {};
  String? lastActiveDay;

  // ── streak (real now: consecutive days with ≥1 completion) ──────
  int streakDays = 0;
  int bestStreak = 0;
  String? lastCompletionDay;

  /// Streak freezes are available from the beginning. Each one quietly holds
  /// one day away, but is spent only when the whole gap can be covered.
  static const starterStreakFreezes = 3;
  static const maxStreakFreezes = 7;
  static const _baseFreezeCapacity = 5;
  int streakFreezes = starterStreakFreezes;
  int streakFreezeProgress = 0;
  bool freezeLevelBonusGranted = false;
  final Set<String> frozenStreakDays = {};

  /// Level 6 opens enough room to hold a full week; freezes still work before
  /// then, so the app never withholds its safety net from a new keeper.
  int get streakFreezeCapacity =>
      level >= 6 ? maxStreakFreezes : _baseFreezeCapacity;

  /// Ordinary active days replenish the reserve. CARE bends this loop in a
  /// deterministic, legible way instead of hiding a random reward chance.
  int get activeDaysPerFreeze => (stats[Stat.vit] ?? 0) >= 40 ? 2 : 3;

  /// A small public preview for UI. Nothing is spent until a quest is actually
  /// completed, and an under-covered gap never wastes the reserve.
  ({int days, bool covered}) get pendingStreakGap {
    final situation = _streakSituation();
    return (days: situation.days.length, covered: situation.covered);
  }

  int totalCompletions = 0;

  /// [totalCompletions] when the last level was reached, so a level-up can
  /// say what earned it. Null for older saves until their next level.
  int? completionsAtLastLevel = 0;
  int comebacks = 0; // returns after a missed day

  /// Ember chest payouts for each streak milestone (DESIGN.md §7).
  static const streakMilestones = <int, int>{
    7: 50, // a week — a warm chest
    30: 200, // a month — a proper haul
    100: 800, // a season — legendary
  };

  // ── today's haul (the night recap's raw material; reset on rollover) ──
  int todayXp = 0;
  final Map<Stat, int> todayStats = {};

  /// Same-title completion counts today (anti-grind decay). Cleared on rollover.
  final Map<String, int> todayTitleCounts = {};

  /// Unlock ladder: level → unlock name. Every level-up reveals the next
  /// system or cosmetic tier, so there's always a visible "next thing"
  /// (RESEARCH-momentum.md §7). Levels 2-6 are core systems; 8-15 are
  /// cosmetic and quality-of-life expansions that keep the ladder alive
  /// past the initial onboarding burst.
  static const unlocks = <int, String>{
    2: 'STAT DETAILS',
    3: 'CHARACTER SHEET',
    4: 'EVIDENCE ARCHIVE',
    5: 'THEMES',
    6: 'WEEK-LONG FREEZE RESERVE',
    8: 'TODAY’S BONUS',
    12: 'WINDOW VIEWS',
    14: 'ROOM STYLES+',
    15: 'GILDED SKIN',
  };

  /// Rising XP-per-level curve; level 2 lands in the first session.
  int xpNeeded(int forLevel) => 60 + (forLevel - 1) * 45;

  /// Streak multiplier for an arbitrary day count — ramps 1.0 → 1.5 over 7
  /// days, caps at 2.0 (day 30).
  double streakMultFor(int days) {
    if (days <= 0) return 1.0;
    if (days <= 7) return 1.0 + 0.5 * days / 7;
    return min(2.0, 1.5 + 0.5 * (days - 7) / 23);
  }

  double get streakMult => streakMultFor(streakDays);

  /// How this completion sits against the streak: is there a gap since the
  /// last active day, which quiet dates sit inside it, and can freezes bridge
  /// every one? Partial coverage is deliberately refused so no freeze is ever
  /// spent without preserving the streak.
  /// Read identically by [roll] (for messaging) and [commit] (to apply) —
  /// both run before lastCompletionDay is bumped, so they agree.
  ({bool gap, List<String> days, bool covered}) _streakSituation() {
    final last = lastCompletionDay;
    final now = Clock.now();
    if (last == null || last == Days.key(now)) {
      return (gap: false, days: const <String>[], covered: false);
    }
    final d = Days.parse(last);
    final missed = Days.between(d, now) - 1;
    if (missed <= 0) {
      return (gap: false, days: const <String>[], covered: false);
    }
    final days = [
      for (var i = 1; i <= missed; i++)
        Days.key(DateTime(d.year, d.month, d.day + i)),
    ];
    return (gap: true, days: days, covered: streakFreezes >= days.length);
  }

  /// Verified completions (timer proof) pay ×1.2 — proof multiplies,
  /// never gates (RESEARCH.md §5).
  static const verifiedBonus = 1.2;

  /// Custom (user-forged) quests pay ×0.85 — anti-abuse damping; honesty
  /// keeps the magic (DESIGN.md round-3).
  static const customDamp = 0.85;

  /// First completion back after a gap pays ×1.5 — the fragile
  /// re-engagement moment is rewarded, never scolded (RESEARCH-momentum.md §4).
  static const comebackBonus = 1.5;

  /// Soft daily XP ceilings (ROADMAP Phase 1 anti-grind). Past the first
  /// threshold further XP is halved; past the second, quartered. Effort is
  /// never discarded — just gently soft-capped.
  static const dailyXpSoft = 250;
  static const dailyXpHard = 400;

  /// Same-task same-day repeat decay: 100% → 50% → 25% → 10% (ROADMAP §1).
  static double sameDayDecay(int priorSameTitleToday) =>
      switch (priorSameTitleToday) {
        0 => 1.0,
        1 => 0.5,
        2 => 0.25,
        _ => 0.1,
      };

  /// Per-stat daily soft-cap: after this much of one stat today, further
  /// gains to that stat are halved (anti-farm; still never zeroed).
  static const dailyStatSoft = 40;

  /// Base crit chance; STR bends this upward (DESIGN.md §4).
  double get critChance =>
      (0.03 + (stats[Stat.str]! / 200) * 0.05).clamp(0.03, 0.10);

  /// INT bends XP rate — up to +15% at high Intellect.
  double get intXpMult =>
      (1.0 + (stats[Stat.intl]! / 200) * 0.15).clamp(1.0, 1.15);

  /// DIS amplifies neglect bonus (dreaded / long-idle tasks pay more).
  double get disNeglectMult =>
      (1.0 + (stats[Stat.dis]! / 200) * 0.25).clamp(1.0, 1.25);

  /// How many days since this quest was last cleared (0 if never / today).
  int _neglectDays(Quest q, String nowKey) {
    final last = q.lastDoneDay;
    if (last == null || last == nowKey) return 0;
    final d = Days.parse(last);
    final now = Days.parse(nowKey);
    return Days.between(d, now).clamp(0, 30);
  }

  /// Neglect payout: up to +50% after ~10 idle days, scaled by DIS.
  double _neglectMult(Quest q, String nowKey) {
    final days = _neglectDays(q, nowKey);
    if (days <= 0) return 1.0;
    final raw = 1.0 + min(0.5, days * 0.05);
    return 1.0 + (raw - 1.0) * disNeglectMult;
  }

  /// Today's soft-cap multiplier given XP already banked today.
  double _dailyXpMult() {
    if (todayXp >= dailyXpHard) return 0.25;
    if (todayXp >= dailyXpSoft) return 0.5;
    return 1.0;
  }

  /// Day-one damp for a custom quest forged today (can't farm a fresh
  /// self-entered task for full XP on day one).
  double _dayOneDamp(Quest q, String nowKey) {
    if (!q.custom) return 1.0;
    final created = q.createdDay;
    if (created == null || created != nowKey) return 1.0;
    // first completion of a brand-new custom quest today
    if (q.lastDoneDay != null) return 1.0;
    return 0.5;
  }

  /// Pure roll: computes the reward and marks the quest done for its
  /// period, but does NOT mutate xp/stats — [commit] does that later so the
  /// bar fill and chip pulses can be staged after the reward receipt.
  RewardBundle roll(Quest q, {bool verified = false}) {
    final now = Clock.now();
    final nowKey = Days.key(now);
    // How a gap (if any) resolves: freezes bridge it quietly, otherwise
    // it's a true lapse and the return earns a warm comeback bonus. Read
    // before we stamp anything (mirrors [commit]'s decision).
    final sit = _streakSituation();
    final shieldHeld = sit.gap && sit.covered;
    final isComeback = sit.gap && !sit.covered;
    // the FIRST completion of the day (no completion committed yet today)
    final firstOfDay = lastCompletionDay != nowKey;
    final freezesUsed = shieldHeld ? sit.days.length : 0;
    final reserveAfterHeldDays = streakFreezes - freezesUsed;

    final priorSame = todayTitleCounts[q.title] ?? 0;
    final neglect = _neglectMult(q, nowKey);
    final dayOne = _dayOneDamp(q, nowKey);

    q.lastDoneDay = nowKey;

    // A comeback resets the streak to 1 in commit — pay this completion at the
    // POST-reset multiplier, not the stale lapsed streak (else a broken 30-day
    // streak pays ×2.0 stacked with the comeback bonus; bug-hunt §10).
    final effStreakMult = isComeback ? streakMultFor(1) : streakMult;
    // Base scales with continuous difficulty: d1 ≈ 0.6×, d10 ≈ 3×.
    final base = 10 * (0.5 + q.difficulty * 0.25);
    var earned = base * effStreakMult;
    if (q.dread) earned *= 1.35;
    if (q.custom) earned *= customDamp;
    if (verified) earned *= verifiedBonus;
    if (isComeback) earned *= comebackBonus;
    earned *= neglect;
    earned *= dayOne;
    earned *= sameDayDecay(priorSame);
    earned *= intXpMult;
    earned *= _dailyXpMult();

    // Critical hit: STR-bent chance, ×1.5–×3, always announced with the roll.
    double? crit;
    if (_rng.nextDouble() < critChance) {
      crit = 1.5 + _rng.nextDouble() * 1.5;
      earned *= crit;
    }

    // anti-abuse damp covers stats too — they drive the aura/title/radar.
    // Per-stat daily soft-cap halves further gains past the threshold.
    var gain = q.difficulty * 1.5;
    if (q.custom) gain *= customDamp;
    gain *= dayOne;
    gain *= sameDayDecay(priorSame);
    if ((todayStats[q.stat] ?? 0) >= dailyStatSoft) gain *= 0.5;
    final projectedVit =
        stats[Stat.vit]! +
        (q.stat == Stat.vit ? max(1, gain.round() + (q.dread ? 3 : 0)) : 0);
    final freezeCadenceAfter = projectedVit >= 40 ? 2 : 3;
    final freezeEarnedAfterCommit =
        firstOfDay &&
        reserveAfterHeldDays < streakFreezeCapacity &&
        streakFreezeProgress + 1 >= freezeCadenceAfter;
    final finalFreezeBalance = min(
      streakFreezeCapacity,
      reserveAfterHeldDays + (freezeEarnedAfterCommit ? 1 : 0),
    );
    final freezeProgressAfter = freezeEarnedAfterCommit
        ? 0
        : min(freezeCadenceAfter - 1, streakFreezeProgress + 1);

    return RewardBundle(
      xp: earned.round(),
      // embers track XP (~a third, min 1) — the one source for both the
      // receipt bubble and what commit() banks
      embers: max(1, earned.round() ~/ 3),
      stat: q.stat,
      statGain: max(1, gain.round() + (q.dread ? 3 : 0)),
      questTitle: q.title,
      difficulty: q.difficulty,
      dread: q.dread,
      custom: q.custom,
      critMult: crit,
      // report the multiplier actually applied (post-reset on a comeback)
      streakMult: isComeback
          ? effStreakMult
          : (streakDays > 0 ? streakMult : null),
      verifiedMult: verified ? verifiedBonus : null,
      comebackMult: isComeback ? comebackBonus : null,
      freezesUsed: freezesUsed,
      freezeEarned: freezeEarnedAfterCommit,
      freezeBalanceAfter: finalFreezeBalance,
      freezeProgressAfter: freezeProgressAfter,
      freezeCadenceAfter: freezeCadenceAfter,
      firstOfDay: firstOfDay,
    );
  }

  /// XP a quest will pay (sans crit luck) — shown on the card so the reward
  /// IS the difficulty signal (DESIGN.md §11.4). Advertises the BASE
  /// (honor) payout — the ×1.2 is the timer's upside, not a promise.
  int xpPreview(Quest q) {
    // mirror roll(): on a comeback day streakDays still holds the stale lapsed
    // value until the first commit resets it, so preview at the multiplier
    // roll() will ACTUALLY pay (post-reset) — never over-promise ×2.0 on the
    // exact fragile re-engagement day the card is trying to win back.
    final nowKey = Days.key(Clock.now());
    final sit = _streakSituation();
    final effMult = (sit.gap && !sit.covered) ? streakMultFor(1) : streakMult;
    final priorSame = todayTitleCounts[q.title] ?? 0;
    var earned = 10 * (0.5 + q.difficulty * 0.25) * effMult;
    if (q.dread) earned *= 1.35;
    if (q.custom) earned *= customDamp;
    earned *= _neglectMult(q, nowKey);
    earned *= _dayOneDamp(q, nowKey);
    earned *= sameDayDecay(priorSame);
    earned *= intXpMult;
    earned *= _dailyXpMult();
    return earned.round();
  }

  /// Applies a rolled bundle to xp/stats/streak/counters — the moment the
  /// bar fills and the stat chip pulses.
  void commit(RewardBundle b) {
    xp += b.xp;
    totalXp += b.xp;
    // bank the embers the roll computed (shown in the receipt) — the shop
    // currency for "Your Space"; every win nudges the balance up.
    embers += b.embers;
    stats[b.stat] = stats[b.stat]! + b.statGain;

    // Streak: active days count upward; freezes hold calendar days away without
    // pretending those days were active. Full-save undo restores this whole
    // transaction, including reserve, progress, and the exact frozen dates.
    final now = Clock.now();
    final today = Days.key(now);
    if (lastCompletionDay != today) {
      final sit = _streakSituation();
      if (!sit.gap) {
        streakDays += 1; // first ever, or yesterday → continues
      } else if (sit.covered) {
        streakFreezes -= sit.days.length;
        frozenStreakDays.addAll(sit.days);
        streakDays += 1;
      } else {
        comebacks++; // a real lapse — reset, but the return is celebrated
        streakDays = 1;
      }
      lastCompletionDay = today;

      // Showing up replenishes freezes without asking for a perfect board.
      // Progress can sit one day from ready while the reserve is full; if a
      // later completion spends a freeze, that same active day may refill it.
      streakFreezes = b.freezeBalanceAfter;
      streakFreezeProgress = min(
        b.freezeCadenceAfter - 1,
        b.freezeProgressAfter,
      );

      // streak milestone — a 7/30/100 day CROSSING queues a chest. This lives
      // INSIDE the day-change block on purpose: a milestone can only be
      // crossed when the streak increments, so the second+ completion of a
      // milestone day must NOT re-pay the chest (day 30 × 6 quests once paid
      // 1,200 embers and staged the takeover six times — the exact currency
      // inflation the shop economy can't take).
      if (streakMilestones.containsKey(streakDays)) {
        embers += streakMilestones[streakDays]!;
      }
    }
    if (streakDays > bestStreak) bestStreak = streakDays;

    // counters + calendar history
    totalCompletions++;
    history[today] = (history[today] ?? 0) + 1;
    todayTitleCounts[b.questTitle] = (todayTitleCounts[b.questTitle] ?? 0) + 1;

    // today's haul (night recap)
    todayXp += b.xp;
    todayStats[b.stat] = (todayStats[b.stat] ?? 0) + b.statGain;

    // trim history to 180 days — never evict TODAY's just-written entry (guards
    // a backward clock / future-dated restore from deleting it; bug-hunt §14).
    // A while-loop, not a single removal: an oversized imported/legacy save
    // must drain to the cap in one commit, not one day per completion.
    if (history.length > 180) {
      final keys = (history.keys.toList()..sort())
          .where((k) => k != today)
          .toList();
      var i = 0;
      while (history.length > 180 && i < keys.length) {
        history.remove(keys[i++]);
      }
    }
  }

  /// Consume XP into level-ups. Overflow always carries (no wasted
  /// progress). Returns the highest level reached this application, if any.
  /// Deliberately does NOT notify — the UI reveals the pour on its own
  /// schedule (DESIGN.md §6).
  LevelResult applyLevelUps() {
    int? reached;
    final from = level;
    while (xp >= xpNeeded(level + 1)) {
      xp -= xpNeeded(level + 1);
      level++;
      reached = level;
    }
    // Lv 6 widens the reserve to a full week and places two freezes inside it.
    if (level >= 6 && !freezeLevelBonusGranted) {
      freezeLevelBonusGranted = true;
      streakFreezes = (streakFreezes + 2).clamp(0, streakFreezeCapacity);
    }
    if (reached == null) {
      return LevelResult(leveledTo: null, unlock: null);
    }
    final since = completionsAtLastLevel == null
        ? null
        : totalCompletions - completionsAtLastLevel!;
    completionsAtLastLevel = totalCompletions;
    return LevelResult(
      leveledTo: reached,
      unlock: unlocks[reached],
      previousLevel: from,
      questsSince: since == null || since < 0 ? null : since,
    );
  }

  /// Day rollover: clears today's haul when the active day changes. (The
  /// app's version also drops finished one-time Quests and keeps yesterday's
  /// haul for the night recap.) Returns true if the active day changed.
  bool rollover() {
    final today = Days.key(Clock.now());
    final changed = lastActiveDay != today;
    if (changed) {
      todayXp = 0;
      todayStats.clear();
      todayTitleCounts.clear();
    }
    lastActiveDay = today;
    return changed;
  }
}
