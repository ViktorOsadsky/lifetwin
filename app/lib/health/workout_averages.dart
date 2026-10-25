import 'dart:async';

import 'package:flutter/services.dart';

/// App-only native contract. No raw workouts, identifiers, dates or metadata are
/// accepted here, and there is deliberately no network serializer.
class WorkoutAverages {
  const WorkoutAverages._({
    required this.moderateWeeklyMinutes,
    required this.vigorousWeeklyMinutes,
    required this.eligibleWorkoutCount,
    required this.excludedCounts,
    required this.truncated,
  });

  static const schema = 'apple_health_workout_averages.v0';
  static const method = 'whole_workout_mean_mets';
  static const exclusionKeys = {'missing_metadata', 'duration', 'overlap', 'boundary', 'light_intensity', 'duplicate'};
  static const _keys = {
    'schema',
    'window_days',
    'method',
    'moderate_weekly_minutes',
    'vigorous_weekly_minutes',
    'eligible_workout_count',
    'excluded_counts',
    'truncated',
    'requires_recreation_confirmation',
  };

  final double? moderateWeeklyMinutes;
  final double? vigorousWeeklyMinutes;
  final int eligibleWorkoutCount;
  final Map<String, int> excludedCounts;
  final bool truncated;

  bool get hasReturnedWorkouts => eligibleWorkoutCount + excludedCounts.values.fold(0, (a, b) => a + b) > 0;

  factory WorkoutAverages.parse(Object? value) {
    Never invalid() => throw const FormatException('Invalid Apple Health workout averages');
    bool exactKeys(Map value, Set<String> keys) => value.length == keys.length && value.keys.every(keys.contains);
    if (value is! Map || !exactKeys(value, _keys)) invalid();
    if (value['schema'] != schema ||
        value['method'] != method ||
        value['window_days'] != 28 ||
        value['window_days'] is! int ||
        value['requires_recreation_confirmation'] != true ||
        value['truncated'] is! bool) {
      invalid();
    }
    int count(Object? v) => v is int && v >= 0 && v <= 2000 ? v : invalid();
    double? minutes(Object? v) => v == null
        ? null
        : v is num && v.isFinite && v > 0 && v <= 10080
        ? v.toDouble()
        : invalid();
    final eligible = count(value['eligible_workout_count']);
    final rawExcluded = value['excluded_counts'];
    if (rawExcluded is! Map || !exactKeys(rawExcluded, exclusionKeys)) invalid();
    final excluded = {for (final key in exclusionKeys) key: count(rawExcluded[key])};
    final moderate = minutes(value['moderate_weekly_minutes']);
    final vigorous = minutes(value['vigorous_weekly_minutes']);
    final truncated = value['truncated'] as bool;
    final totalCount = eligible + excluded.values.fold(0, (a, b) => a + b);
    final bucketCount = (moderate == null ? 0 : 1) + (vigorous == null ? 0 : 1);
    if (totalCount > 2000 ||
        (moderate ?? 0) + (vigorous ?? 0) > 10080 ||
        (moderate?.round() ?? 0) + (vigorous?.round() ?? 0) > 10080 ||
        (eligible == 0) != (bucketCount == 0) ||
        eligible < bucketCount ||
        (truncated && (eligible != 0 || bucketCount != 0))) {
      invalid();
    }
    return WorkoutAverages._(
      moderateWeeklyMinutes: moderate,
      vigorousWeeklyMinutes: vigorous,
      eligibleWorkoutCount: eligible,
      excludedCounts: Map.unmodifiable(excluded),
      truncated: truncated,
    );
  }
}

/// Uses already-requested read-only workout authorization. Native values stay on
/// the phone; only this bounded aggregate crosses the native/Dart boundary.
class WorkoutActivityReader {
  const WorkoutActivityReader({this.channel = const MethodChannel('lifetwin/health_activity')});
  final MethodChannel channel;

  Future<WorkoutAverages> read({required DateTime now}) async {
    final value = await channel
        .invokeMethod<Object?>('readWorkoutAverages', {'end_ms': now.toUtc().millisecondsSinceEpoch})
        .timeout(const Duration(seconds: 6));
    return WorkoutAverages.parse(value);
  }
}
