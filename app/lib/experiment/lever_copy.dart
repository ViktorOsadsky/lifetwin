import 'package:flutter/material.dart';

import '../twin/twin_experiment.dart';
import 'experiment_copy.dart';

/// Plain words, icons and units for the levers, by engine id (`LeverId`). Levers the engine
/// offers that this table does not know are not shown. There is no weight here: weight is
/// never a lever (`weight_not_a_lever`), only the info card.
class LeverCopy {
  const LeverCopy({
    required this.short,
    required this.full,
    required this.icon,
    required this.unit,
    required this.bubble,
    required this.wellnessCard,
  });

  /// The hub row's name ("Hard", "Moderate").
  final String short;

  /// The lever's name in a sentence and on a chip ("Hard exercise").
  final String full;
  final IconData icon;

  /// After the value: "a week", "a night", "a day".
  final String unit;

  /// Mochi's line before a change is made.
  final String bubble;

  /// The engine wellness card this lever belongs to (`activity`, `sleep`, ...).
  final String wellnessCard;

  static const _table = {
    LeverId.smoking: LeverCopy(
      short: 'Smoking',
      full: 'Smoking',
      icon: Icons.smoke_free_rounded,
      unit: '',
      bubble: "I'm cheering for you!",
      wellnessCard: 'smoking',
    ),
    LeverId.vigorous: LeverCopy(
      short: 'Hard',
      full: 'Hard exercise',
      icon: Icons.directions_run_rounded,
      unit: 'a week',
      bubble: 'A little puff, together?',
      wellnessCard: 'activity',
    ),
    LeverId.moderate: LeverCopy(
      short: 'Moderate',
      full: 'Moderate exercise',
      icon: Icons.directions_walk_rounded,
      unit: 'a week',
      bubble: 'A brisk walk, maybe?',
      wellnessCard: 'activity',
    ),
    LeverId.sleepHours: LeverCopy(
      short: 'Sleep',
      full: 'Sleep',
      icon: Icons.bedtime_outlined,
      unit: 'a night',
      bubble: 'A little more rest for us?',
      wellnessCard: 'sleep',
    ),
    LeverId.sitting: LeverCopy(
      short: 'Sitting',
      full: 'Sitting',
      icon: Icons.event_seat_outlined,
      unit: 'a day',
      bubble: 'A stand and stretch?',
      wellnessCard: 'sitting',
    ),
  };

  static LeverCopy? of(String id) => _table[id];

  /// A value in words: "5½ h" (sleep), "2 h" (minutes of exercise or sitting), "Quit".
  static String value(ExperimentLever l, double v) => switch (l.id) {
    LeverId.smoking => v == 1 ? 'Quit' : 'Smoke now',
    LeverId.sleepHours => ExperimentCopy.hours(v),
    _ => ExperimentCopy.duration(v),
  };

  /// "5½ h a night", "30 min a week".
  static String withUnit(ExperimentLever l, double v) {
    final c = of(l.id)!;
    return c.unit.isEmpty ? value(l, v) : '${value(l, v)} ${c.unit}';
  }

  /// The hub row's second line: "Today 30 min a week", "Today smoking".
  static String today(ExperimentLever l) =>
      l.id == LeverId.smoking ? 'Today smoking' : 'Today ${withUnit(l, l.current ?? 0)}';

  /// The what-if value on the hub row; null when it is still today's.
  static String? whatIf(ExperimentLever l) => l.changed ? withUnit(l, l.value!) : null;

  /// A value as it is spoken: "6 and a half hours", "30 minutes".
  static String spoken(String s) =>
      s.replaceAll('½', ' and a half').replaceAll(' h', ' hours').replaceAll('min', 'minutes');

  /// What a screen reader hears for a hub row.
  static String rowLabel(ExperimentLever l) {
    final c = of(l.id)!;
    final now = LeverCopy.spoken(l.id == LeverId.smoking ? 'smoking' : withUnit(l, l.current ?? 0));
    final then = !l.changed ? 'the same' : LeverCopy.spoken(l.id == LeverId.smoking ? 'quit' : withUnit(l, l.value!));
    return '${c.full}, today $now, what-if $then. Opens ${c.full}.';
  }

  /// The stepper's right-hand caption: "+1 hour", "+30 min", "1 h less".
  static String change(ExperimentLever l, double v) {
    final cur = l.current ?? v;
    final diff = v - cur;
    if (diff == 0) return 'Same as today';
    final sign = diff > 0 ? '+' : '-';
    if (l.id == LeverId.sleepHours) {
      final a = diff.abs();
      final text = a == 0.5
          ? '30 min'
          : a == 1
          ? '1 hour'
          : '${ExperimentCopy.hours(a).replaceAll(' h', '')} hours';
      return '$sign$text';
    }
    return '$sign${ExperimentCopy.duration(diff.abs())}';
  }

  /// Screen-reader labels for the stepper buttons.
  static String minusLabel(ExperimentLever l) => _step(l, less: true);
  static String plusLabel(ExperimentLever l) => _step(l, less: false);

  static String _step(ExperimentLever l, {required bool less}) {
    final what = switch (l.id) {
      LeverId.sleepHours => 'sleep',
      LeverId.vigorous => 'hard exercise',
      LeverId.moderate => 'moderate exercise',
      _ => 'sitting',
    };
    final amount = switch (l.id) {
      LeverId.sleepHours => 'Half an hour',
      LeverId.sitting => '30 minutes',
      _ => '15 minutes',
    };
    return '$amount ${less ? 'less' : 'more'} $what';
  }
}
