import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/health/health_reader.dart';
import 'package:lifesim/health/health_sample.dart';
import 'package:lifesim/health/health_summary.dart';
import 'package:lifesim/health/readback.dart';
import 'package:lifesim/health/workout_averages.dart';

final now = DateTime.utc(2026, 10, 24, 12);
const channel = MethodChannel('lifetwin/health_activity');

Map<String, Object?> payload({double? moderate = 30, double? vigorous, bool truncated = false}) => {
  'schema': WorkoutAverages.schema,
  'window_days': 28,
  'method': WorkoutAverages.method,
  'moderate_weekly_minutes': moderate,
  'vigorous_weekly_minutes': vigorous,
  'eligible_workout_count': (moderate == null ? 0 : 1) + (vigorous == null ? 0 : 1),
  'excluded_counts': {for (final key in WorkoutAverages.exclusionKeys) key: 0},
  'truncated': truncated,
  'requires_recreation_confirmation': true,
};

class SummaryReader extends HealthReader {
  SummaryReader() : super(activityReader: const WorkoutActivityReader(channel: channel));

  @override
  Future<List<HealthSample>> read({required DateTime now, int days = 30}) async => [
    HealthSample(type: 'WEIGHT', start: now, end: now, value: 78),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('strict native aggregate becomes an estimate pending explicit recreational confirmation', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readWorkoutAverages');
      expect(call.arguments, {'end_ms': now.millisecondsSinceEpoch});
      return payload(moderate: 30, vigorous: 15);
    });
    final result = await SummaryReader().readSummary(now: now);
    expect(result.candidates.map((c) => c.field), [
      HealthField.weightKg,
      HealthField.moderateRecreationMinWeek,
      HealthField.vigorousRecreationMinWeek,
    ]);
    for (final c in result.candidates.where((c) => modelActivityFields.contains(c.field))) {
      expect(c.isEstimate, isTrue);
      expect(c.periodDays, 28);
      expect(c.basis, WorkoutAverages.method);
      expect(result.unavailableActivity.containsKey(c.field), isFalse);
      final words = readBack(c, imperial: false, now: now);
      expect(words, contains('each whole workout'));
      expect(words, contains('not time measured in effort zones'));
      expect(words, contains('Were these recreational activities'));
      expect(words, contains('represent your usual weekly'));
      expect(words, contains('Some workouts may be missing'));
      expect(words, endsWith('Is this accurate?'));
    }
    expect(result.unavailableActivity.keys, [HealthField.sedentaryMinDay]);
  });

  test('moderate-only aggregate offers no vigorous zero and never supplies sitting', () {
    final result = summarizeWithAvailability([], now, workoutAverages: WorkoutAverages.parse(payload()));
    expect(result.candidates.single.field, HealthField.moderateRecreationMinWeek);
    expect(result.candidates.single.value, 30);
    expect(
      result.unavailableActivity[HealthField.vigorousRecreationMinWeek],
      HealthActivityUnavailableReason.noQualifyingWorkoutEstimate,
    );
    expect(result.unavailableActivity, contains(HealthField.sedentaryMinDay));
  });

  test('empty, sub-minute and truncated data leave absent inputs unanswered', () {
    final empty = summarizeWithAvailability([], now, workoutAverages: WorkoutAverages.parse(payload(moderate: null)));
    expect(empty.candidates, isEmpty);
    expect(empty.unavailableActivity[HealthField.vigorousRecreationMinWeek], HealthActivityUnavailableReason.noData);
    final tiny = summarizeWithAvailability([], now, workoutAverages: WorkoutAverages.parse(payload(moderate: 0.1)));
    expect(tiny.candidates, isEmpty);
    final truncated = summarizeWithAvailability(
      [],
      now,
      workoutAverages: WorkoutAverages.parse(payload(moderate: null, truncated: true)),
    );
    expect(truncated.candidates, isEmpty);
    expect(
      truncated.unavailableActivity[HealthField.moderateRecreationMinWeek],
      HealthActivityUnavailableReason.workoutQueryTruncated,
    );
    expect(
      truncated.unavailableActivity[HealthField.sedentaryMinDay],
      HealthActivityUnavailableReason.awakeSittingNotMeasured,
    );
  });

  final mutations = <String, void Function(Map<String, Object?>)>{
    'unknown schema': (p) => p['schema'] = 'v2',
    'unknown method': (p) => p['method'] = 'time_in_zones',
    'wrong window': (p) => p['window_days'] = 7,
    'non-integer window': (p) => p['window_days'] = 28.0,
    'raw metadata': (p) => p['metadata'] = {'name': 'not accepted'},
    'missing field': (p) => p.remove('method'),
    'numeric string': (p) => p['moderate_weekly_minutes'] = '30',
    'zero bucket': (p) => p['vigorous_weekly_minutes'] = 0,
    'negative': (p) => p['moderate_weekly_minutes'] = -1,
    'nonfinite': (p) => p['moderate_weekly_minutes'] = double.nan,
    'oversized': (p) => p['moderate_weekly_minutes'] = 10081,
    'combined oversized': (p) {
      p['moderate_weekly_minutes'] = 6000;
      p['vigorous_weekly_minutes'] = 6000;
      p['eligible_workout_count'] = 2;
    },
    'rounded combined oversized': (p) {
      p['moderate_weekly_minutes'] = 6000.5;
      p['vigorous_weekly_minutes'] = 4079.5;
      p['eligible_workout_count'] = 2;
    },
    'no qualifying count': (p) => p['eligible_workout_count'] = 0,
    'count overflow': (p) => p['eligible_workout_count'] = 2001,
    'unknown exclusion': (p) => p['excluded_counts'] = {'unknown': 1},
    'negative exclusion': (p) => (p['excluded_counts'] as Map)['overlap'] = -1,
    'truncated with estimates': (p) => p['truncated'] = true,
    'confirmation bypass': (p) => p['requires_recreation_confirmation'] = false,
  };
  for (final mutation in mutations.entries) {
    test('rejects ${mutation.key} rather than accepting an unsafe native estimate', () {
      final p = payload();
      mutation.value(p);
      expect(() => WorkoutAverages.parse(p), throwsFormatException);
    });
  }

  test('invalid/native-error responses preserve generic candidates and precise availability', () async {
    for (final invalid in [false, true]) {
      messenger.setMockMethodCallHandler(channel, (_) async {
        if (invalid) return {...payload(), 'moderate_weekly_minutes': -2};
        throw PlatformException(code: 'read_failed');
      });
      final result = await SummaryReader().readSummary(now: now);
      expect(result.candidates.single.field, HealthField.weightKg);
      expect(
        result.unavailableActivity[HealthField.moderateRecreationMinWeek],
        HealthActivityUnavailableReason.nativeEstimateUnavailable,
      );
      expect(
        result.unavailableActivity[HealthField.vigorousRecreationMinWeek],
        HealthActivityUnavailableReason.nativeEstimateUnavailable,
      );
      expect(result.unavailableActivity, contains(HealthField.sedentaryMinDay));
    }
  });
}
