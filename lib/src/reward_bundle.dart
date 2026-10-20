import 'stat.dart';

/// What one completion earns: the receipt the app shows before anything is
/// applied. [RewardEngine.roll] builds it and [RewardEngine.commit] applies
/// exactly these numbers.
class RewardBundle {
  RewardBundle({
    required this.xp,
    required this.stat,
    required this.statGain,
    required this.questTitle,
    required this.difficulty,
    this.embers = 0,
    this.dread = false,
    this.custom = false,
    this.critMult,
    this.streakMult,
    this.verifiedMult,
    this.comebackMult,
    this.freezesUsed = 0,
    this.freezeEarned = false,
    this.freezeBalanceAfter = 0,
    this.freezeProgressAfter = 0,
    this.freezeCadenceAfter = 3,
    this.firstOfDay = false,
  });

  final int xp;
  final Stat stat;
  final int statGain;

  /// Glimmers earned by this completion — the shop currency (round-48: shown in
  /// the receipt so the earn loop is felt, not silent).
  final int embers;

  /// Which quest earned this (for the ledger and the epic overlay).
  final String questTitle;

  final int difficulty;
  final bool dread;
  final bool custom;

  /// e.g. 2.3 when a crit rolled, null otherwise.
  final double? critMult;

  /// e.g. 1.4 when a streak bonus applied, null otherwise.
  final double? streakMult;

  /// 1.2 when the completion was proof-verified (timer), null otherwise.
  final double? verifiedMult;

  /// Set when this is the first completion back after a gap — a warm
  /// comeback bonus, never a scold (never-punish; RESEARCH-momentum.md §4).
  final double? comebackMult;

  /// Number of quiet days automatically covered by streak freezes on this
  /// completion. A freeze is only spent when the entire gap can be held.
  final int freezesUsed;

  /// True when this active day completed the ordinary show-up cadence and
  /// banked another freeze. This is intentionally not tied to a perfect day.
  final bool freezeEarned;

  /// Freeze reserve after this completion applies both the held days and any
  /// newly earned freeze. The receipt can therefore tell the exact truth.
  final int freezeBalanceAfter;

  /// Ordinary active-day progress remaining after this completion. Carrying
  /// the value through the staged reward keeps roll and commit identical even
  /// if this quest itself crosses the CARE-40 cadence threshold.
  final int freezeProgressAfter;

  /// Cadence used to compute [freezeProgressAfter]. This closes the last seam
  /// between a staged roll and a commit that itself crosses CARE 40.
  final int freezeCadenceAfter;

  /// Compatibility name for the existing completion motion path.
  bool get shieldHeld => freezesUsed > 0;

  /// The day's FIRST completion — gets a notch-brighter beat ("first ember
  /// lit today"). One step above a normal completion, never a takeover.
  final bool firstOfDay;

  /// The fire was genuinely cold before this completion: either this is the
  /// keep's first-ever spark, or the player has returned after a real gap.
  /// A normal first completion on the next day continues an existing fire and
  /// should not replay the larger ignition beat.
  bool get revivesHearth =>
      comebackMult != null || (firstOfDay && streakMult == null);
}

/// Result of applying XP to the level model.
class LevelResult {
  LevelResult({
    required this.leveledTo,
    required this.unlock,
    this.previousLevel,
    this.questsSince,
  });

  /// Null when no level-up happened.
  final int? leveledTo;

  /// The unlock revealed at this level, if any.
  final String? unlock;

  /// The level before this application, and the Quests finished since that
  /// level was reached (null when an older save cannot know).
  final int? previousLevel;
  final int? questsSince;
}
