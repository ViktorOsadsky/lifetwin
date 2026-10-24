/// One reading from Apple Health, in the plugin's units.
///
/// [toAgentJson] is what gets sent to LifeTwin's agents (raw samples, per the
/// team decision on issue #6). It deliberately leaves out source and device
/// names such as "Daniel's Apple Watch", which identify a person but carry no
/// health information.
class HealthSample {
  const HealthSample({
    required this.type,
    required this.start,
    required this.end,
    this.value,
    this.unit,
    this.workoutType,
    this.recordingMethod,
  });

  /// Plugin type name, e.g. `WEIGHT`, `SLEEP_DEEP`, `WORKOUT`.
  final String type;
  final DateTime start;
  final DateTime end;
  final num? value;

  /// Plugin unit name, e.g. `KILOGRAM`, `METER`, `MINUTE`, `COUNT`.
  final String? unit;
  final String? workoutType;

  /// `automatic`, `manual`, `active` or `unknown`.
  final String? recordingMethod;

  Duration get duration => end.difference(start);

  Map<String, Object?> toAgentJson() => {
        'type': type,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        if (value != null) 'value': value,
        if (unit != null) 'unit': unit,
        if (workoutType != null) 'workout_type': workoutType,
        if (recordingMethod != null) 'recording_method': recordingMethod,
      };
}

/// The payload proposed for the server (needs a Track B contract before use).
Map<String, Object?> agentSamplesPayload(List<HealthSample> samples, {required int windowDays}) => {
      'schema': 'apple_health_samples.v0',
      'window_days': windowDays,
      'samples': [for (final s in samples) s.toAgentJson()],
    };
