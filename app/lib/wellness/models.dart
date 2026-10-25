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

  String get provenance =>
      '${source?.label ?? 'Source not recorded'}${estimated ? ' · Estimated' : ''}';
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
  });

  final int expectedAge;
  final int p25Age;
  final int p75Age;
  final int expectedYear;
  final String? caveat;

  /// The person is outside ages 35-79, where the model was checked.
  final bool roughGuide;
}

/// The health score as the repository gives it (`repo.healthScore`): higher is better, 0 is
/// average, roughly -3 to +3. Never derived, negated, rescaled or banded here.
@immutable
class WellnessSnapshot {
  const WellnessSnapshot({
    this.healthScore,
    this.status,
    this.ageGroupPercentile,
    this.message,
    this.lifespan,
    this.lifespanRevealSeen = false,
  });

  final double? healthScore;

  /// Null until the engine gives one (the block is then hidden).
  final LifespanReveal? lifespan;

  /// The one-time reveal after onboarding was already shown.
  final bool lifespanRevealSeen;

  /// Null before a profile.
  final HealthScoreStatus? status;

  /// Healthier than this many (0-100) of people your age in the survey.
  final double? ageGroupPercentile;

  /// The model's message when there is no number.
  final String? message;

  /// A number is shown only when the model gave one for an adult.
  double? get displayScore =>
      status != null && status!.hasScore ? healthScore : null;
  bool get roughGuide =>
      displayScore != null && status == HealthScoreStatus.extrapolated;
  bool get underAge => status == HealthScoreStatus.underAge;
}

/// Signed, two decimals, with a true minus sign: "−0.04", "+1.20", "0.00".
String formatHealthScore(double score) {
  final text = score.abs().toStringAsFixed(2);
  if (text == '0.00') return text;
  return score < 0 ? '−$text' : '+$text';
}

/// "Health score plus 0.04. Higher is better. 0 is average." (built from the value).
String healthScoreSemantics(double score) {
  final text = score.abs().toStringAsFixed(2);
  final sign = text == '0.00' ? '' : (score < 0 ? 'minus ' : 'plus ');
  return 'Health score $sign$text. Higher is better. 0 is average.';
}

DateTime localDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

@immutable
class WellnessSettings {
  const WellnessSettings({
    this.reminderMinutes = 600,
    this.memoryConsent = false,
    this.personalSuggestions = false,
  });

  /// Local wall-clock minutes, default 10:00. Scheduling belongs to CheckinScheduler.
  final int reminderMinutes;
  final bool memoryConsent;
  final bool personalSuggestions;

  WellnessSettings copyWith({
    int? reminderMinutes,
    bool? memoryConsent,
    bool? personalSuggestions,
  }) => WellnessSettings(
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    memoryConsent: memoryConsent ?? this.memoryConsent,
    personalSuggestions: personalSuggestions ?? this.personalSuggestions,
  );
}
