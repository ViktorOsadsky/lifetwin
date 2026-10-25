import 'package:flutter/foundation.dart';

import '../twin/twin_model.dart' show HealthScoreStatus;

/// Presentation snapshots only. The twin repository remains the health-data owner.
/// No screen may derive a health score or write a profile/history value.
@immutable
class WellnessDay {
  const WellnessDay({required this.date, this.values = const []});
  final DateTime date;
  final List<HistoryValue> values;
}

enum ValueSource {
  youSaid('You said'),
  appleHealth('Apple Health'),
  document('Document'),
  mochiChange('Mochi conversation'),
  wristband('Activity band');

  const ValueSource(this.label);
  final String label;

  static ValueSource? fromWire(String? source) => switch (source) {
    'you_said' => youSaid,
    'apple_health' => appleHealth,
    'document' => document,
    'mochi_change' => mochiChange,
    'wristband' => wristband,
    _ => null,
  };
}

@immutable
class HistoryValue {
  const HistoryValue({
    required this.label,
    required this.value,
    this.source,
    this.estimated = false,
    this.previousValue,
    this.recordedAt,
    this.status,
    this.forDay,
  });
  final String label;
  final String value;
  final ValueSource? source;
  final bool estimated;
  final String? previousValue;
  final String? recordedAt;
  final String? status;
  final DateTime? forDay;

  String get provenance => '${source?.label ?? 'Source not recorded'}${estimated ? ' · Estimated' : ''}';
}

/// A rough lifespan statement for the reveal, from the engine's `repo.lifespanEstimate`
/// (`{expectedAge, p25Age, p75Age, expectedYear, status, caveat}`). Years and ages only: never a day.
@immutable
class LifespanReveal {
  const LifespanReveal({
    required this.expectedAge,
    required this.p25Age,
    required this.p75Age,
    required this.expectedYear,
    this.caveat,
    this.roughGuide = false,
    this.p25OpenEnded = false,
    this.openEnded = false,
    this.p75OpenEnded = false,
  });

  final int expectedAge;
  final int p25Age;
  final int p75Age;
  final int expectedYear;
  final String? caveat;

  /// The life table has the bigger weight (ages 18-39 and 75-85). The lifespan is shown as a
  /// rough guide whatever this says (see [lifespanCaption]); it only mirrors the engine's status.
  final bool roughGuide;

  /// The engine's flags: that end of the range is the end of the table, shown "110+".
  final bool p25OpenEnded;
  final bool openEnded;
  final bool p75OpenEnded;

  /// "age 87–109", or "age 89–110+" when the top end is open. Never a day or a date.
  String get rangeText {
    final lo = '$p25Age${p25OpenEnded ? '+' : ''}';
    if (p25OpenEnded) return 'age $lo';
    return 'age $lo–$p75Age${p75OpenEnded ? '+' : ''}';
  }

  /// "Around 2051".
  String get yearText => 'Around $expectedYear';

  /// Spoken form of the estimate: always says it is a rough guide.
  String get semantics => '$yearText, $rangeText. $lifespanCaption.';
}

/// Shown on every lifespan surface, whatever the engine's rough flag says.
const lifespanCaption = 'Estimate, rough guide';

/// The health score as the repository gives it (`repo.healthScore`, the health index):
/// higher is better, 1.0 is the middle of people your age and sex, always above 0. Never
/// derived, inverted, rescaled or banded here.
@immutable
class WellnessSnapshot {
  const WellnessSnapshot({
    this.healthScore,
    this.status,
    this.ageGroupPercentile,
    this.groupLabel,
    this.message,
    this.lifespan,
    this.lifespanRevealSeen = false,
    this.history = const [],
  });

  final double? healthScore;

  /// Null until the engine gives one (the block is then hidden).
  final LifespanReveal? lifespan;

  /// The one-time reveal after onboarding was already shown.
  final bool lifespanRevealSeen;

  /// Recent displayed scores (higher is better), oldest first, for the sparkline.
  final List<double> history;

  /// Null before a profile.
  final HealthScoreStatus? status;

  /// Healthier than this many (0-100) of people your age in the survey.
  final double? ageGroupPercentile;

  /// `repo.healthGroupLabel`, e.g. "women 59–69": the group 1.0 is the middle of.
  final String? groupLabel;

  /// The model's message when there is no number.
  final String? message;

  /// A number is shown only when the model gave one for an adult.
  double? get displayScore => status != null && status!.hasScore ? healthScore : null;
  bool get roughGuide => displayScore != null && status == HealthScoreStatus.extrapolated;
  bool get underAge => status == HealthScoreStatus.underAge;
}

/// The health index, two decimals, no sign: 1.653 -> "1.65". The one formatter for a score.
String formatHealthScore(double score) => score.toStringAsFixed(2);

/// A change in the index: a sign and two decimals ("+0.05", "−0.03", with a real minus sign), or
/// "No change" when it rounds to 0.
String formatScoreDelta(double delta) {
  final n = delta.abs().toStringAsFixed(2);
  if (n == '0.00') return 'No change';
  return '${delta < 0 ? '−' : '+'}$n';
}

/// "Health score 1.65. Higher is better; 1.0 is the middle of people your age. Healthier than 79
/// of 100 people your age." (the last sentence only with a [percentile]).
String healthScoreSemantics(double score, {double? percentile}) =>
    'Health score ${formatHealthScore(score)}. Higher is better; 1.0 is the middle of people your age.'
    '${percentile == null ? '' : ' Healthier than ${percentile.round()} of 100 people your age.'}';

/// The Experiment's line above the survival rows: "Health score 1.65 → 1.70 (+0.05)".
String scoreChangeLine(double from, double delta) =>
    'Health score ${formatHealthScore(from)} → ${formatHealthScore(from + delta)} (${formatScoreDelta(delta)})';

/// "Health score would go from 1.65 to 1.70, up 0.05." (or "down", or "would not change").
String scoreChangeSemantics(double from, double delta) {
  final to = formatHealthScore(from + delta);
  final d = formatScoreDelta(delta);
  final f = formatHealthScore(from);
  if (d == 'No change') return 'Health score would stay at $f.';
  return 'Health score would go from $f to $to, ${delta < 0 ? 'down' : 'up'} ${d.substring(1)}.';
}

/// The sheet behind the card's circled i.
String healthScoreSheetBody(String? groupLabel) =>
    '1.0 is the middle of ${groupLabel ?? 'people your age'} in the study. Higher is better. '
    'It compares risk; it is not a chance of living or dying.';
const healthScoreSheetNote = 'Habit ticks and check-ins don’t change it; your confirmed answers do.';
const healthScoreSheetLinked = 'Linked, not proven.';

DateTime localDay(DateTime value) => DateTime(value.year, value.month, value.day);

@immutable
class WellnessSettings {
  const WellnessSettings({this.reminderMinutes = 600, this.memoryConsent = false, this.personalSuggestions = false});

  /// Local wall-clock minutes, default 10:00. Scheduling belongs to CheckinScheduler.
  final int reminderMinutes;
  final bool memoryConsent;
  final bool personalSuggestions;

  WellnessSettings copyWith({int? reminderMinutes, bool? memoryConsent, bool? personalSuggestions}) => WellnessSettings(
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    memoryConsent: memoryConsent ?? this.memoryConsent,
    personalSuggestions: personalSuggestions ?? this.personalSuggestions,
  );
}
