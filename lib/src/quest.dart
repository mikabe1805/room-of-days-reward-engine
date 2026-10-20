import 'stat.dart';

/// The parts of a Quest the reward engine reads. The app's Quest also has a
/// schedule, a timer, goal links, a mastery ladder and more; none of those
/// change what a completion pays, so they are left out here.
class Quest {
  Quest({
    required this.title,
    required this.stat,
    required this.difficulty,
    this.dread = false,
    this.custom = false,
    this.lastDoneDay,
    this.createdDay,
  });

  final String title;

  /// Which life stat this Quest trains.
  Stat stat;

  /// 1 (a small thing) to 10 (a big one). The XP on the card is how the app
  /// shows it.
  int difficulty;

  /// The Quest the person keeps putting off. Pays ×1.35 and +3 to the stat.
  final bool dread;

  /// Written by the person rather than picked from the app's catalog.
  final bool custom;

  /// Day key of the last completion. Null if never done.
  String? lastDoneDay;

  /// Day key the Quest was created, for the day-one damp on custom Quests.
  String? createdDay;
}
