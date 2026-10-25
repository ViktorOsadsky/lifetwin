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
    this.missingCount = 0,
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

  /// Rough with answers missing (1 or 2 inputs marginalised): "Rough guide: N answers missing".
  final int missingCount;

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

/// The health score as the repository gives it (`repo.healthScore`, the centred score): 0 is the
/// middle of people your age and sex, above 0 is healthier, below 0 less healthy. Never derived,
/// inverted, rescaled or banded here.
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
    this.missingCount = 0,
  });

  /// The questions the estimate still needs ("Answer N more questions"); with 1 or 2 missing
  /// inputs the score is rough ([HealthScoreStatus.roughMissing]).
  final int missingCount;

  /// The score is a rough guide because answers are missing.
  bool get roughMissing => displayScore != null && status == HealthScoreStatus.roughMissing;

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

  /// `repo.healthGroupLabel`, e.g. "women 59–69": the group 0 is the middle of.
  final String? groupLabel;

  /// The model's message when there is no number.
  final String? message;

  /// A number is shown only when the model gave one for an adult.
  double? get displayScore => status != null && status!.hasScore ? healthScore : null;
  bool get roughGuide => displayScore != null && status == HealthScoreStatus.extrapolated;
  bool get underAge => status == HealthScoreStatus.underAge;
}

/// The health score (the centred score, ln of the index): signed, two decimals, with a real minus
/// sign. 0 is the middle of the person's group; above 0 is healthier. 0.5 -> "+0.50", -0.4 ->
/// "−0.40", exactly 0 (or anything that rounds to it) -> "0.00", no sign. The one formatter for a
/// score value.
String formatHealthScore(double score) {
  final n = score.abs().toStringAsFixed(2);
  if (n == '0.00') return n;
  return '${score < 0 ? '−' : '+'}$n';
}

/// The score for a screen reader: "plus 0.50", "minus 0.40", "0.00".
String spokenHealthScore(double score) {
  final t = formatHealthScore(score);
  if (t.startsWith('+')) return 'plus ${t.substring(1)}';
  if (t.startsWith('−')) return 'minus ${t.substring(1)}';
  return t;
}

/// A change in the score: a sign and two decimals ("+0.05", "−0.03", with a real minus sign), or
/// "No change" when it rounds to 0.
String formatScoreDelta(double delta) {
  final n = delta.abs().toStringAsFixed(2);
  if (n == '0.00') return 'No change';
  return '${delta < 0 ? '−' : '+'}$n';
}

/// "Health score plus 0.50. Above 0 is healthier; 0 is the middle of people your age. Healthier
/// than 79 of 100 people your age." (the last sentence only with a [percentile]).
String healthScoreSemantics(double score, {double? percentile}) =>
    'Health score ${spokenHealthScore(score)}. Above 0 is healthier; 0 is the middle of people your age.'
    '${percentile == null ? '' : ' Healthier than ${percentile.round()} of 100 people your age.'}';

enum ScoreChange { better, lower, same }

/// Better at +0.005 or more, lower at -0.005 or less, otherwise about the same (the weight guard's 0
/// included).
ScoreChange scoreChangeOf(double delta) =>
    delta >= 0.005 ? ScoreChange.better : (delta <= -0.005 ? ScoreChange.lower : ScoreChange.same);

/// "New health score plus 0.55, up 0.05 from plus 0.50" / "down 0.03 from ..." / "..., about the same".
String newScoreSemantics(double from, double delta) {
  final now = spokenHealthScore(from + delta);
  switch (scoreChangeOf(delta)) {
    case ScoreChange.same:
      return 'New health score $now, about the same';
    case ScoreChange.better:
      return 'New health score $now, up ${formatScoreDelta(delta).substring(1)} from ${spokenHealthScore(from)}';
    case ScoreChange.lower:
      return 'New health score $now, down ${formatScoreDelta(delta).substring(1)} from ${spokenHealthScore(from)}';
  }
}

/// The sheet behind the card's circled i.
String healthScoreSheetBody(String? groupLabel) =>
    '0 is the middle of ${groupLabel ?? 'people your age'} in the study. Above 0 is healthier, below 0 is less '
    'healthy. It compares risk; it is not a chance of living or dying.';
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
