import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/twin_experiment.dart';
import 'package:lifesim/twin/twin_history.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_state.dart';
import 'package:lifesim/ui/twin_assets.dart';

/// 55-year-old man who smokes, sleeps 6 h, little exercise, sits a lot, BMI 30.
const smoker = {
  'age': 55,
  'sex': 'male',
  'height_cm': 175.0,
  'weight_kg': 91.875,
  'sleep_hours': 6,
  'smoking_status': 'current',
  'diabetes': false,
  'hypertension_diagnosed': true,
  'general_health': 3,
  'vigorous_recreation_min_week': 0,
  'moderate_recreation_min_week': 60,
  'sedentary_min_day': 480,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  late LeverRanking ranking;
  setUpAll(() async {
    model = await TwinModelService.load();
    ranking = await loadLeverRanking();
  });

  TwinExperiment experimentFor(Map<String, dynamic> p) {
    final a = model.assess(p);
    return TwinExperiment(
      model: model,
      current: a,
      appProfile: p,
      order: ranking.orderFor(age: a.profileUsed['age'] as num?, sexNhanes: a.profileUsed['sex_nhanes'] as num?),
    );
  }

  group('lever ranking (docs/model-sensitivity.json)', () {
    test('the bundled file ranks quit smoking, vigorous, moderate, sleep, sitting for every group', () {
      for (final (age, sex) in [(40, 1), (55, 2), (70, 1), (null, null)]) {
        expect(ranking.orderFor(age: age, sexNhanes: sex), [
          LeverId.smoking,
          LeverId.vigorous,
          LeverId.moderate,
          LeverId.sleepHours,
          LeverId.sitting,
        ]);
      }
    });

    test('the bundled copy is the sensitivity commit 65acf39 output for this model', () {
      final json = jsonDecode(File('assets/model/model-sensitivity.json').readAsStringSync()) as Map;
      expect(json['model_version'], model.modelVersion);
      expect(json['causal_interpretation'], isFalse);
    });

    test('an unreadable or empty file falls back to the default order', () {
      expect(LeverRanking.fromJson(null).orderFor(age: 50, sexNhanes: 1), defaultLeverOrder);
      expect(
        LeverRanking.fromJson({
          'groups': {
            'all': {
              'recommendable_levers_ranked': [
                {'lever': 'quit_smoking'},
              ],
            },
          },
        }).orderFor(),
        [LeverId.smoking],
      );
    });
  });

  group('TwinExperiment', () {
    test('levers: ranked order, ranges, steps, units; weight never offered', () {
      final e = experimentFor(smoker);
      expect(e.current.available, isTrue);
      expect(e.result.status, 'no_change');
      final levers = e.levers;
      expect(levers.map((l) => l.id), [
        LeverId.smoking,
        LeverId.vigorous,
        LeverId.moderate,
        LeverId.sleepHours,
        LeverId.sitting,
        LeverId.weightKg,
      ]);
      String spec(ExperimentLever l) => '${l.id} ${l.min}-${l.max} step ${l.step} ${l.unit} now ${l.current}';
      expect(levers.map(spec), [
        'smoking_status 1.0-2.0 step 1.0 choice now 2.0',
        'vigorous_recreation_min_week 0.0-300.0 step 15.0 min/week now 0.0',
        'moderate_recreation_min_week 60.0-600.0 step 15.0 min/week now 60.0',
        'sleep_hours 6.0-8.0 step 0.5 h/night now 6.0',
        'sedentary_min_day 60.0-480.0 step 30.0 min/day now 480.0',
        'weight_kg 91.875-91.875 step 0.0 kg now 91.875',
      ]);
      final weight = e.lever(LeverId.weightKg);
      expect(weight.supported, isFalse);
      expect(weight.reason, LeverReason.weightNotALever);
      expect(weight.caveat, contains('not evidence that gaining weight helps'));
      e.set(LeverId.weightKg, 80);
      expect(e.lever(LeverId.weightKg).value, 91.875);
      expect(e.result.status, 'no_change');
    });

    test('weight is never a lever, at BMI 20 or at BMI 25', () {
      for (final bmi in [20.0, 25.0]) {
        final e = experimentFor({...smoker, 'weight_kg': bmi * 1.75 * 1.75});
        final w = e.lever(LeverId.weightKg);
        expect(w.supported, isFalse, reason: 'BMI $bmi');
        expect(w.reason, LeverReason.weightNotALever, reason: 'BMI $bmi');
        e.set(LeverId.weightKg, w.current! - 5);
        expect(e.lever(LeverId.weightKg).value, w.current);
        expect(e.result.status, 'no_change');
      }
    });

    test('an exercise value off the 15-minute grid: near it snaps back to the person\'s own value', () {
      final e = experimentFor({...smoker, 'moderate_recreation_min_week': 100});
      final l = e.lever(LeverId.moderate);
      expect((l.current, l.min, l.step), (100, 100, 15));
      e.set(LeverId.moderate, 106); // within half a step of 100
      expect(e.lever(LeverId.moderate).value, 100);
      expect(e.result.status, 'no_change');
      e.set(LeverId.moderate, 130); // nearest grid value is 135
      expect(e.lever(LeverId.moderate).value, 135);
      e.set(LeverId.moderate, 90); // below the person's own value: back to 100
      expect(e.lever(LeverId.moderate).value, 100);
      expect(e.result.status, 'no_change');
    });

    test('set snaps to the step and stays in range; only the healthy direction', () {
      final e = experimentFor(smoker);
      e.set(LeverId.moderate, 10000);
      expect(e.lever(LeverId.moderate).value, 600);
      e.set(LeverId.moderate, 0); // less exercise is not offered
      expect(e.lever(LeverId.moderate).value, 60);
      e.set(LeverId.moderate, 97);
      expect(e.lever(LeverId.moderate).value, 90);
      e.set(LeverId.sitting, 1000);
      expect(e.lever(LeverId.sitting).value, 480);
      e.set(LeverId.sleepHours, 7.2);
      expect(e.lever(LeverId.sleepHours).value, 7);
      e.set(LeverId.smoking, 0); // never-smoker is not reachable
      expect(e.lever(LeverId.smoking).value, 2);
      e.reset();
      expect(e.levers.where((l) => l.changed), isEmpty);
      expect(e.result.status, 'no_change');
    });

    test('quitting: the modeled difference in raw percentage points, from compare()', () {
      final e = experimentFor(smoker);
      var notified = 0;
      e.addListener(() => notified++);
      e.set(LeverId.smoking, 1);
      final r = e.result;
      expect(notified, 1);
      expect(r.status, 'available');
      expect(ExperimentResult.title, 'Modeled difference between profiles');
      expect(r.causalInterpretation, isFalse);
      final direct = model.engine.compare({
        'current_profile': e.current.profileUsed,
        'alternative_profile': {...e.current.profileUsed, 'smoking_status': 1.0},
      });
      final pp = (direct['modeled_difference_percentage_points'] as Map)['5'] as double;
      expect(r.difference5, pp); // unrounded
      expect(r.difference5, greaterThan(0));
      expect(r.differenceByYear.keys, [1, 2, 3, 4, 5]);
      expect(r.alternativePercentByYear[5]! - r.currentPercentByYear[5]!, closeTo(pp, 1e-9));
      expect(r.levers.single.counted, isTrue);
      expect(r.interpretation, contains('not the benefit of changing a habit'));
    });

    test('several levers are one compare() of the whole alternative, not a sum', () {
      final e = experimentFor(smoker)
        ..set(LeverId.vigorous, 60)
        ..set(LeverId.moderate, 150)
        ..set(LeverId.sitting, 420);
      final base = e.current.profileUsed;
      final whole = model.engine.compare({
        'current_profile': base,
        'alternative_profile': {
          ...base,
          'vigorous_recreation_min_week': 60.0,
          'moderate_recreation_min_week': 150.0,
          'sedentary_min_day': 420.0,
        },
      });
      expect(e.result.difference5, (whole['modeled_difference_percentage_points'] as Map)['5']);
      expect(e.result.levers.map((l) => l.counted), [true, true, true]);
      expect(e.result.warnings.single, contains('do not estimate intervention effects')); // sitting
    });

    test('sleep: only short sleepers, and never above 8 h', () {
      final e = experimentFor(smoker)..set(LeverId.sleepHours, 9);
      expect(e.lever(LeverId.sleepHours).value, 8); // capped at 8 h
      expect(e.result.status, 'available');
      expect(e.result.levers.single.counted, isTrue);
      final at8 = e.result.difference5!;
      e.set(LeverId.sleepHours, 7);
      expect(e.result.status, 'available');
      expect(e.result.difference5, greaterThan(0));
      expect(at8, closeTo(e.result.difference5!, 1e-9)); // 7–8 h is the model's flat range

      final rested = experimentFor({...smoker, 'sleep_hours': 7.5, 'smoking_status': 'former'});
      expect(rested.lever(LeverId.sleepHours).reason, LeverReason.notShortSleeper);
      expect(rested.lever(LeverId.smoking).reason, LeverReason.notASmoker);
      expect(rested.levers.where((l) => l.supported).map((l) => l.id), [
        LeverId.vigorous,
        LeverId.moderate,
        LeverId.sitting,
      ]);
    });

    test('an alternative outside the model support shows the package status and no number', () {
      // Found by scanning: 40, BMI 20, 4 h sleep, smoker, poor health with diabetes and high
      // blood pressure; 300 min of hard exercise leaves the training profiles.
      final e = experimentFor({
        'age': 40,
        'sex': 'male',
        'height_cm': 175.0,
        'weight_kg': 61.25,
        'sleep_hours': 4,
        'smoking_status': 'current',
        'diabetes': true,
        'hypertension_diagnosed': true,
        'general_health': 'poor',
        'vigorous_recreation_min_week': 0,
        'moderate_recreation_min_week': 0,
        'sedentary_min_day': 480,
      });
      expect(e.current.available, isTrue);
      e.set(LeverId.vigorous, 300);
      expect(e.result.status, 'alternative_unavailable');
      expect(e.result.message, 'Annual estimates are withheld for this profile.');
      expect(e.result.supportIssues, isNotEmpty);
      expect(e.result.differenceByYear, isEmpty);
    });

    test('changes that do not fit in a day ask for smaller changes, with no number', () {
      final e = experimentFor({...smoker, 'sedentary_min_day': 900})
        ..set(LeverId.sleepHours, 8)
        ..set(LeverId.moderate, 600);
      expect(e.result.status, 'invalid_input');
      expect(e.result.differenceByYear, isEmpty);
    });

    test('an 84-year-old experiments with an extrapolated, flagged difference', () {
      final e = experimentFor({...smoker, 'age': 84})..set(LeverId.smoking, 1);
      expect(e.current.extrapolated, isTrue);
      expect(e.result.status, 'available');
      expect(e.result.extrapolated, isTrue);
      expect(e.result.caveat, extrapolationCaveat);
      expect(
        e.result.alternativePercentByYear[5]! - e.result.currentPercentByYear[5]!,
        closeTo(e.result.difference5!, 1e-9),
      );
      expect(e.result.currentPercentByYear[5], closeTo(e.current.percentByYear[5]!, 1e-9));
      expect(experimentFor(smoker).result.extrapolated, isFalse);
    });

    test('with answers missing, levers say which input and there is no number', () {
      final e = experimentFor({...smoker, 'sedentary_min_day': null, 'general_health': null});
      expect(e.result.status, 'current_unavailable');
      expect(e.result.missingInputs, ['sedentary_min_day', 'general_health']);
      final sitting = e.lever(LeverId.sitting);
      expect(sitting.supported, isFalse);
      expect(sitting.reason, LeverReason.missingInput);
      expect(sitting.missingInput, 'sedentary_min_day');
      e.set(LeverId.smoking, 1);
      expect(e.result.status, 'current_unavailable');
      expect(e.result.difference5, isNull);
    });
  });

  group('TwinState', () {
    final now = DateTime(2026, 10, 26, 9);
    CheckinRecord daily(String date, Map<String, dynamic> a) => CheckinRecord(kind: 'daily', date: date, answers: a);

    test('each input maps to one mood and an existing pose', () {
      final steady = model.assess({
        ...smoker,
        'smoking_status': 'never',
        'sleep_hours': 7,
        'moderate_recreation_min_week': 200,
        'sedentary_min_day': 300,
      });
      final exploring = model.assess(smoker);
      expect(steady.opportunities, isEmpty);
      expect(exploring.opportunities, ['smoking', 'activity', 'sleep']);
      final cases = <(TwinState, TwinMood, TwinPose, TwinStateReason)>[
        (
          TwinState.derive(assessment: steady, emergency: true, now: now),
          TwinMood.concerned,
          TwinPose.stand,
          TwinStateReason.emergency,
        ),
        (
          TwinState.derive(
            assessment: steady,
            checkins: [
              daily('2026-10-26', {'wellbeing': 'not_great', 'exercise_minutes_today': 45}),
            ],
            now: now,
          ),
          TwinMood.cozy,
          TwinPose.sit,
          TwinStateReason.notFeelingGreat,
        ),
        (
          TwinState.derive(
            assessment: steady,
            checkins: [
              daily('2026-10-25', {'sleep_hours_last_night': 5}),
            ],
            now: now,
          ),
          TwinMood.sleepy,
          TwinPose.stretch,
          TwinStateReason.shortSleep,
        ),
        (
          TwinState.derive(
            assessment: steady,
            checkins: [
              daily('2026-10-26', {'exercise_minutes_today': 30}),
            ],
            now: now,
          ),
          TwinMood.cheerful,
          TwinPose.jump,
          TwinStateReason.active,
        ),
        (
          TwinState.derive(
            assessment: steady,
            checkins: [
              daily('2026-10-26', {'wellbeing': 'good'}),
            ],
            now: now,
          ),
          TwinMood.cheerful,
          TwinPose.wave,
          TwinStateReason.feelingGood,
        ),
        (
          TwinState.derive(assessment: exploring, now: now),
          TwinMood.curious,
          TwinPose.think,
          TwinStateReason.exploring,
        ),
        (
          TwinState.derive(assessment: model.assess({'age': 50}), now: now),
          TwinMood.content,
          TwinPose.wave,
          TwinStateReason.needsInput,
        ),
        (TwinState.derive(now: now), TwinMood.content, TwinPose.wave, TwinStateReason.needsInput),
        (TwinState.derive(assessment: steady, now: now), TwinMood.content, TwinPose.stand, TwinStateReason.steady),
      ];
      for (final (s, mood, pose, reason) in cases) {
        expect((s.mood, s.pose, s.reason), (mood, pose, reason));
        expect(twinAsset(TwinType.bear, TwinLook.calHat, s.pose), startsWith('assets/twin/bear/pose/'));
        expect(File(twinAsset(TwinType.bear, TwinLook.calHat, s.pose)).existsSync(), isTrue);
      }
    });

    test('old check-ins are ignored; a weekly one counts for a week', () {
      final s = TwinState.derive(
        checkins: [
          daily('2026-10-23', {'wellbeing': 'not_great', 'sleep_hours_last_night': 4}),
        ],
        now: now,
      );
      expect(s.wellbeing, isNull);
      expect(s.recentSleepHours, isNull);
      final w = TwinState.derive(
        checkins: [
          const CheckinRecord(kind: 'weekly', date: '2026-10-20', answers: {'sleep_hours': 5.5, 'wellbeing': 'okay'}),
        ],
        now: now,
      );
      expect((w.mood, w.wellbeing, w.recentSleepHours), (TwinMood.sleepy, 'okay', 5.5));
    });

    test('kind: a diagnosis or poor health never makes a sad, dizzy or shrugging bear', () {
      final ill = model.assess({...smoker, 'diabetes': true, 'hypertension_diagnosed': true, 'general_health': 'poor'});
      for (final checkins in [
        <CheckinRecord>[],
        [
          daily('2026-10-26', {'wellbeing': 'okay'}),
        ],
      ]) {
        final s = TwinState.derive(assessment: ill, checkins: checkins, now: now);
        expect(s.mood, isNot(anyOf(TwinMood.concerned, TwinMood.cozy)));
        expect(s.pose, isNot(anyOf(TwinPose.dizzy, TwinPose.shrug)));
      }
      expect(TwinMood.values.map((m) => m.name), isNot(contains('sad')));
    });
  });
}
