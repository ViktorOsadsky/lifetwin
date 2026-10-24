import 'package:health/health.dart';

import 'health_sample.dart';

/// Types used to suggest profile answers.
const profileTypes = [
  HealthDataType.HEIGHT,
  HealthDataType.WEIGHT,
  HealthDataType.EXERCISE_TIME,
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_REM,
  HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
  HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
];

/// Activity trackers the twin reacts to. Kept apart from the confirmed profile.
const trackerTypes = [
  HealthDataType.STEPS,
  HealthDataType.ACTIVE_ENERGY_BURNED,
  HealthDataType.WORKOUT,
  HealthDataType.RESTING_HEART_RATE,
];

/// Units the summary rules expect. Passed explicitly so a plugin default can never
/// switch a reading to pounds or centimeters without us noticing.
const _units = {
  HealthDataType.HEIGHT: HealthDataUnit.METER,
  HealthDataType.WEIGHT: HealthDataUnit.KILOGRAM,
  HealthDataType.EXERCISE_TIME: HealthDataUnit.MINUTE,
  HealthDataType.BLOOD_PRESSURE_SYSTOLIC: HealthDataUnit.MILLIMETER_OF_MERCURY,
  HealthDataType.BLOOD_PRESSURE_DIASTOLIC: HealthDataUnit.MILLIMETER_OF_MERCURY,
};

/// Read-only access to Apple Health. LifeTwin never writes.
class HealthReader {
  final Health _health = Health();
  bool _configured = false;

  Future<void> _configure() async {
    if (!_configured) await _health.configure();
    _configured = true;
  }

  /// Shows Apple's permission sheet. iOS never says which types were refused,
  /// so a refused type simply returns no samples.
  Future<bool> requestAccess() async {
    await _configure();
    final types = [...profileTypes, ...trackerTypes];
    return _health.requestAuthorization(types, permissions: [for (final _ in types) HealthDataAccess.READ]);
  }

  /// Height and weight look back a year; everything else looks back [days].
  Future<List<HealthSample>> read({required DateTime now, int days = 30}) async {
    await _configure();
    final recent = await _health.getHealthDataFromTypes(
      types: [...profileTypes.where((t) => t != HealthDataType.HEIGHT && t != HealthDataType.WEIGHT), ...trackerTypes],
      preferredUnits: _units,
      startTime: now.subtract(Duration(days: days)),
      endTime: now,
    );
    final body = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.HEIGHT, HealthDataType.WEIGHT],
      preferredUnits: _units,
      startTime: now.subtract(const Duration(days: 365)),
      endTime: now,
    );
    return [for (final p in _health.removeDuplicates([...recent, ...body])) _toSample(p)];
  }
}

HealthSample _toSample(HealthDataPoint p) {
  final v = p.value;
  return HealthSample(
    type: p.type.name,
    start: p.dateFrom,
    end: p.dateTo,
    value: v is NumericHealthValue ? v.numericValue : null,
    unit: p.unit.name,
    workoutType: v is WorkoutHealthValue ? v.workoutActivityType.name : null,
    recordingMethod: p.recordingMethod.name,
  );
}
