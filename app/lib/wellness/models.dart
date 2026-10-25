import 'package:flutter/foundation.dart';

/// Presentation snapshots only. The twin repository remains the health-data owner.
/// No screen may derive a health score or write a profile/history value.
@immutable
class WellnessDay {
  const WellnessDay({
    required this.date,
    this.healthScore,
    this.logged = false,
    this.values = const [],
  });
  final DateTime date;
  final int? healthScore;
  final bool logged;
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

@immutable
class WellnessSnapshot {
  const WellnessSnapshot({
    this.healthScore,
    this.days = const [],
    this.goodWeeks = 0,
  });

  /// Null until Track A provides the health-score contract. Never inferred here.
  final int? healthScore;
  final List<WellnessDay> days;

  /// Supplied by TwinRepository.goodWeeks(), never a streak or a resettable count.
  final int goodWeeks;

  int? get displayScore => validHealthScore(healthScore);
}

int? validHealthScore(int? value) =>
    value != null && value >= 0 && value <= 100 ? value : null;

DateTime localDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Seven local calendar days; missing values remain unknown, not zero.
List<WellnessDay> lastSevenDays(List<WellnessDay> history, DateTime now) {
  final today = localDay(now);
  final byDate = {for (final day in history) localDay(day.date): day};
  return [
    for (var offset = 6; offset >= 0; offset--)
      byDate[DateTime(today.year, today.month, today.day - offset)] ??
          WellnessDay(
            date: DateTime(today.year, today.month, today.day - offset),
          ),
  ];
}

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
