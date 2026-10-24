import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';

import 'activity_math.dart';

/// Outcome of an Apple Health import. Raw samples never leave the importer;
/// only the four weekly totals are returned.
sealed class HealthImportResult {
  const HealthImportResult();
}

class HealthImported extends HealthImportResult {
  const HealthImported(this.weekly);

  /// Active minutes per week, oldest first (four entries).
  final List<int> weekly;

  int get average => weeklyAverage(weekly);
}

/// Authorised, but nothing to read in the last 28 days.
class HealthNoData extends HealthImportResult {
  const HealthNoData();
}

class HealthDenied extends HealthImportResult {
  const HealthDenied();
}

/// Not iOS, no HealthKit, or the read failed.
class HealthUnavailable extends HealthImportResult {
  const HealthUnavailable();
}

abstract class HealthImporter {
  Future<HealthImportResult> importLast28Days(DateTime now);
}

/// Reads workouts and exercise time (READ only) and reduces them to weekly
/// totals on the device. Nothing is written to Apple Health and nothing is
/// logged.
class DeviceHealthImporter implements HealthImporter {
  final Health _health = Health();

  static const _types = [HealthDataType.EXERCISE_TIME, HealthDataType.WORKOUT];
  static const _access = [HealthDataAccess.READ, HealthDataAccess.READ];

  @override
  Future<HealthImportResult> importLast28Days(DateTime now) async {
    if (!Platform.isIOS) return const HealthUnavailable();
    try {
      await _health.configure();
      final granted = await _health.requestAuthorization(
        _types,
        permissions: _access,
      );
      if (!granted) return const HealthDenied();

      final points = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: now.subtract(const Duration(days: activityWindowDays)),
        endTime: now,
      );

      final exercise = <TimedMinutes>[];
      final workouts = <TimedMinutes>[];
      for (final p in points) {
        if (p.type == HealthDataType.EXERCISE_TIME) {
          final v = p.value;
          if (v is NumericHealthValue) {
            exercise.add(TimedMinutes(p.dateFrom, v.numericValue.toDouble()));
          }
        } else if (p.type == HealthDataType.WORKOUT) {
          workouts.add(
            TimedMinutes(
              p.dateFrom,
              p.dateTo.difference(p.dateFrom).inSeconds / 60,
            ),
          );
        }
      }
      // Exercise time already covers workouts, so use one source to avoid
      // counting the same minutes twice.
      final chosen = exercise.isNotEmpty ? exercise : workouts;
      if (chosen.isEmpty) return const HealthNoData();
      return HealthImported(weeklyBuckets(chosen, now));
    } catch (_) {
      return const HealthUnavailable();
    }
  }
}

final healthImporterProvider = Provider<HealthImporter>(
  (ref) => DeviceHealthImporter(),
);
