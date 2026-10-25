import 'package:flutter/foundation.dart';

import '../twin/twin_model.dart' show HealthScoreStatus;

/// Presentation snapshots only. The twin repository remains the health-data owner.
/// No screen may derive a health score or write a profile/history value.
@immutable
class WellnessDay {
  const WellnessDay({
    required this.date,
    this.values = const [],
  });
  final DateTime date;
  final List<HistoryValue> values;
}

enum ValueSource {
  youSaid('You said'),
  appleHealth('Apple Health'),
  document('Document'),
  mochiChange('Mochi conversation'),
  wristband('Wristband');

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

/// The health score as the repository gives it: Viktor's `log_relative_hazard_score`
/// as is (lower is better, 0 is the survey average, roughly -3 to +3). Never derived,
/// rescaled or banded here.
@immutable
class WellnessSnapshot {
  const WellnessSnapshot({
    this.healthScore,
    this.status,
    this.ageGroupPercentile,
    this.message,
  });

  final double? healthScore;

  /// Null before a profile.
  final HealthScoreStatus? status;

  /// Healthier than this many (0-100) of people your age in the survey.
  final double? ageGroupPercentile;

  /// The model's message when there is no number.
  final String? message;

  /// A number is shown only when the model gave one for an adult.
  double? get displayScore => status != null && status!.hasScore ? healthScore : null;
  bool get roughGuide => displayScore != null && status == HealthScoreStatus.extrapolated;
  bool get underAge => status == HealthScoreStatus.underAge;
}

/// Signed, one decimal, with a true minus sign: "−0.4", "+1.2", "0.0".
String formatHealthScore(double score) {
  final text = score.abs().toStringAsFixed(1);
  if (text == '0.0') return text;
  return score < 0 ? '−$text' : '+$text';
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
