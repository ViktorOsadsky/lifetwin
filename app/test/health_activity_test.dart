import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/health/health_sample.dart';
import 'package:lifesim/health/health_summary.dart';
import 'package:lifesim/health/readback.dart';

final now = DateTime.utc(2026, 10, 24, 12);

HealthSample sample(String type, {num? value, String? workoutType, int daysAgo = 1}) {
  final start = now.subtract(Duration(days: daysAgo, hours: 1));
  return HealthSample(
    type: type,
    start: start,
    end: start.add(const Duration(minutes: 30)),
    value: value,
    workoutType: workoutType,
  );
}

void main() {
  test('no data or denied read leaves all three model inputs unknown', () {
    final summary = summarizeWithAvailability([], now);
    expect(summary.candidates, isEmpty);
    expect(summary.unavailableActivity.keys.toSet(), modelActivityFields);
    expect(summary.unavailableActivity.values, everyElement(HealthActivityUnavailableReason.noData));
  });

  test('moderate-only exercise evidence does not invent a vigorous zero or recreation', () {
    // A real native workout has an activity type, not recreational context or
    // validated moderate/vigorous active minutes. Even a walking workout plus
    // Exercise Time is insufficient to fill either recreational model input.
    final summary = summarizeWithAvailability([
      sample('WORKOUT', workoutType: 'WALKING'),
      sample('EXERCISE_TIME', value: 30),
    ], now);
    expect(summary.candidates.where((c) => modelActivityFields.contains(c.field)), isEmpty);
    for (final field in [HealthField.moderateRecreationMinWeek, HealthField.vigorousRecreationMinWeek]) {
      expect(summary.unavailableActivity[field], HealthActivityUnavailableReason.recreationAndIntensityNotEstablished);
    }
    // The older exercise suggestion is preserved, apart from the new inputs.
    expect(summary.candidates.single.field, HealthField.exerciseMinutesWeekly);
    expect(summary.candidates.single.value, 8);
  });

  test('running and heart rate do not establish recreational active minutes', () {
    final summary = summarizeWithAvailability([
      sample('WORKOUT', workoutType: 'RUNNING'),
      sample('HEART_RATE', value: 160),
      sample('ACTIVITY_INTENSITY', value: 30),
    ], now);
    expect(summary.candidates, isEmpty);
    expect(
      summary.unavailableActivity[HealthField.vigorousRecreationMinWeek],
      HealthActivityUnavailableReason.recreationAndIntensityNotEstablished,
    );
  });

  test('stand hours, standing duration, steps and sleep cannot yield awake sitting', () {
    final summary = summarizeWithAvailability([
      sample('APPLE_STAND_HOUR', value: 1),
      sample('APPLE_STAND_TIME', value: 600),
      sample('STEPS', value: 2000),
      sample('SLEEP_ASLEEP', value: 30),
    ], now);
    expect(summary.candidates.where((c) => c.field == HealthField.sedentaryMinDay), isEmpty);
    expect(
      summary.unavailableActivity[HealthField.sedentaryMinDay],
      HealthActivityUnavailableReason.awakeSittingNotMeasured,
    );
  });

  test('old, future and malformed activity samples do not count as recent evidence', () {
    final summary = summarizeWithAvailability([
      sample('WORKOUT', workoutType: 'WALKING', daysAgo: 29),
      sample('WORKOUT', workoutType: 'RUNNING', daysAgo: -1),
      HealthSample(type: 'WORKOUT', start: now, end: now.subtract(const Duration(minutes: 1))),
      sample('HEART_RATE', value: double.nan),
    ], now);
    expect(summary.unavailableActivity.values, everyElement(HealthActivityUnavailableReason.noData));
  });

  test('new confirmation wording names the source, context, unit and four-week period', () {
    expect(modelActivityWindowDays, 28);
    for (final field in modelActivityFields) {
      final candidate = HealthCandidate(field: field, value: 90, basis: 'average', periodDays: 28);
      final text = readBack(candidate, imperial: false, now: now);
      expect(text, startsWith('Apple Health says'));
      expect(text, contains('on average over the last 4 weeks'));
      expect(text, endsWith('Is this accurate?'));
      expect(
        text,
        contains(field == HealthField.sedentaryMinDay ? 'sitting while awake a day' : 'recreational activity a week'),
      );
    }
  });

  test('availability results contain no raw data or fabricated model values', () {
    final input = [sample('WORKOUT', workoutType: 'WALKING')];
    final summary = summarizeWithAvailability(input, now);
    expect(summary.candidates, isEmpty);
    expect(summary.unavailableActivity.length, 3);
    expect(() => summary.unavailableActivity.clear(), throwsUnsupportedError);
    // The separate pre-existing raw-sample payload remains unchanged. No new
    // activity evidence/metadata or model fields are added to it by this API.
    expect((agentSamplesPayload(input, windowDays: 30)['samples'] as List).single, input.single.toAgentJson());
  });
}
