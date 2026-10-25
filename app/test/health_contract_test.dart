import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/health/health_sample.dart';
import 'package:lifesim/health/health_summary.dart';

/// Every Apple Health answer must land on a real profile field, with the type and
/// range the server accepts. Otherwise the import is rejected and the person is stuck.
void main() {
  final schema = jsonDecode(File('../contracts/profile.schema.json').readAsStringSync()) as Map;
  final props = schema['properties'] as Map;

  Map<String, dynamic> rule(String key) {
    final p = props[key] as Map;
    return Map<String, dynamic>.from((p['anyOf'] as List?)?.firstWhere((o) => (o as Map)['type'] != 'null') ?? p);
  }

  test('every Health field is a profile field', () {
    for (final f in HealthField.values) {
      expect(props.containsKey(f.profileKey), isTrue, reason: f.profileKey);
    }
  });

  test('plausible ranges sit inside the server limits', () {
    for (final f in HealthField.values) {
      final r = rule(f.profileKey);
      final (lo, hi) = plausibleRange[f]!;
      expect(lo, greaterThanOrEqualTo(r['minimum'] as num), reason: f.profileKey);
      expect(hi, lessThanOrEqualTo(r['maximum'] as num), reason: f.profileKey);
    }
  });

  test('a realistic Health summary produces values the server schema accepts', () {
    final now = DateTime(2026, 10, 24, 12);
    final samples = <HealthSample>[
      HealthSample(type: 'HEIGHT', start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 1), value: 1.73),
      HealthSample(type: 'WEIGHT', start: DateTime(2026, 10, 20), end: DateTime(2026, 10, 20), value: 78.4),
      HealthSample(type: 'EXERCISE_TIME', start: DateTime(2026, 10, 10, 9), end: DateTime(2026, 10, 10, 10)),
      HealthSample(
        type: 'BLOOD_PRESSURE_SYSTOLIC',
        start: DateTime(2026, 10, 20),
        end: DateTime(2026, 10, 20),
        value: 126,
      ),
      HealthSample(
        type: 'BLOOD_PRESSURE_DIASTOLIC',
        start: DateTime(2026, 10, 20),
        end: DateTime(2026, 10, 20),
        value: 81,
      ),
      for (final d in [18, 19, 20])
        HealthSample(type: 'SLEEP_LIGHT', start: DateTime(2026, 10, d, 23), end: DateTime(2026, 10, d + 1, 6)),
    ];
    final values = {for (final c in summarize(samples, now)) c.field.profileKey: c.value};
    expect(
      values.keys.toSet(),
      HealthField.values.where((f) => !modelActivityFields.contains(f)).map((f) => f.profileKey).toSet(),
    );
    // Current HealthKit data cannot establish the three recreational/sitting
    // inputs. Valid schema fields are not evidence that the phone measured them.
    for (final field in modelActivityFields) {
      expect(values.containsKey(field.profileKey), isFalse);
    }
    for (final MapEntry(:key, :value) in values.entries) {
      final r = rule(key);
      if (r['type'] == 'integer') expect(value, isA<int>(), reason: '$key must be a whole number');
      expect(value, inInclusiveRange(r['minimum'] as num, r['maximum'] as num), reason: key);
    }
  });

  test('impossible readings are dropped instead of offered', () {
    final now = DateTime(2026, 10, 24, 12);
    final cs = summarize([
      // Height entered in centimeters as if meters, and a swapped blood pressure.
      HealthSample(type: 'HEIGHT', start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 1), value: 173),
      HealthSample(
        type: 'BLOOD_PRESSURE_SYSTOLIC',
        start: DateTime(2026, 10, 20),
        end: DateTime(2026, 10, 20),
        value: 80,
      ),
      HealthSample(
        type: 'BLOOD_PRESSURE_DIASTOLIC',
        start: DateTime(2026, 10, 20),
        end: DateTime(2026, 10, 20),
        value: 120,
      ),
      HealthSample(type: 'WEIGHT', start: DateTime(2026, 10, 20), end: DateTime(2026, 10, 20), value: 78),
    ], now);
    expect(cs.map((c) => c.field), [HealthField.weightKg]);
  });
}
