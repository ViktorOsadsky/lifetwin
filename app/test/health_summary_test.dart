import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/health/health_sample.dart';
import 'package:lifesim/health/health_summary.dart';

final now = DateTime(2026, 10, 24, 12);

HealthSample s(String type, DateTime start, {DateTime? end, num? value}) =>
    HealthSample(type: type, start: start, end: end ?? start, value: value);

HealthCandidate? pick(List<HealthCandidate> cs, HealthField f) =>
    cs.where((c) => c.field == f).firstOrNull;

void main() {
  test('height and weight use the latest reading within a year, in metric', () {
    final cs = summarize([
      s('HEIGHT', DateTime(2026, 3, 1), value: 1.73),
      s('WEIGHT', DateTime(2026, 1, 1), value: 80),
      s('WEIGHT', DateTime(2026, 10, 20), value: 78.04),
    ], now);
    expect(pick(cs, HealthField.heightCm)!.value, 173.0);
    expect(pick(cs, HealthField.weightKg)!.value, 78.0);
    expect(pick(cs, HealthField.weightKg)!.measuredAt, DateTime(2026, 10, 20));
  });

  test('readings older than a year are ignored so the mascot asks instead', () {
    final cs = summarize([s('WEIGHT', DateTime(2025, 9, 1), value: 80)], now);
    expect(pick(cs, HealthField.weightKg), isNull);
  });

  test('exercise is a weekly average over 28 days, counting overlaps once', () {
    final day = DateTime(2026, 10, 10, 9);
    final cs = summarize([
      // 60 minutes on the Watch, and the iPhone logs an overlapping 30.
      s('EXERCISE_TIME', day, end: day.add(const Duration(minutes: 60))),
      s('EXERCISE_TIME', day.add(const Duration(minutes: 15)), end: day.add(const Duration(minutes: 45))),
      s('EXERCISE_TIME', DateTime(2026, 10, 20, 9), end: DateTime(2026, 10, 20, 10, 0)),
    ], now);
    expect(pick(cs, HealthField.exerciseMinutesWeekly)!.value, 30); // 120 min / 4 weeks
  });

  test('sleep is the median night and splits nights at midday', () {
    final samples = <HealthSample>[];
    for (final (day, hours) in [(18, 6), (19, 7), (20, 8)]) {
      final start = DateTime(2026, 10, day, 23);
      samples.add(s('SLEEP_LIGHT', start, end: start.add(Duration(hours: hours))));
    }
    // A REM stage inside night 19 must not be double counted.
    samples.add(s('SLEEP_REM', DateTime(2026, 10, 20, 1), end: DateTime(2026, 10, 20, 2)));
    final c = pick(summarize(samples, now), HealthField.sleepHours)!;
    expect(c.value, 7.0);
    expect(c.periodDays, 14);
  });

  test('fewer than three nights of sleep gives no suggestion', () {
    final start = DateTime(2026, 10, 20, 23);
    final cs = summarize([s('SLEEP_ASLEEP', start, end: start.add(const Duration(hours: 7)))], now);
    expect(pick(cs, HealthField.sleepHours), isNull);
  });

  test('blood pressure averages the last three readings within 90 days', () {
    final cs = summarize([
      s('BLOOD_PRESSURE_SYSTOLIC', DateTime(2026, 5, 1), value: 170), // too old
      s('BLOOD_PRESSURE_SYSTOLIC', DateTime(2026, 9, 1), value: 150), // fourth newest
      s('BLOOD_PRESSURE_SYSTOLIC', DateTime(2026, 10, 1), value: 130),
      s('BLOOD_PRESSURE_SYSTOLIC', DateTime(2026, 10, 10), value: 126),
      s('BLOOD_PRESSURE_SYSTOLIC', DateTime(2026, 10, 20), value: 122),
      s('BLOOD_PRESSURE_DIASTOLIC', DateTime(2026, 10, 20), value: 81),
    ], now);
    expect(pick(cs, HealthField.systolicBp)!.value, 126);
    expect(pick(cs, HealthField.diastolicBp)!.value, 81);
  });

  test('future-dated samples are ignored', () {
    final cs = summarize([s('WEIGHT', DateTime(2026, 11, 1), value: 70)], now);
    expect(cs, isEmpty);
  });

  test('agent payload keeps readings but no source or device names', () {
    final payload = agentSamplesPayload([
      HealthSample(type: 'STEPS', start: DateTime.utc(2026, 10, 20), end: DateTime.utc(2026, 10, 20, 1),
          value: 1200, unit: 'COUNT', recordingMethod: 'automatic'),
    ], windowDays: 30);
    final sample = (payload['samples'] as List).single as Map;
    expect(sample, {
      'type': 'STEPS',
      'start': '2026-10-20T00:00:00.000Z',
      'end': '2026-10-20T01:00:00.000Z',
      'value': 1200,
      'unit': 'COUNT',
      'recording_method': 'automatic',
    });
    expect(payload['window_days'], 30);
  });
}
