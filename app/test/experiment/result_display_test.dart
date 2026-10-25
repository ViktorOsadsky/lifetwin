import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/experiment/experiment_copy.dart';
import 'package:lifesim/experiment/result_display.dart';
import 'package:lifesim/experiment/widgets/experiment_curve.dart';
import 'package:lifesim/ui/widgets/survival_curve.dart';
import 'package:lifesim/twin/twin_experiment.dart';
import 'package:lifesim/twin/twin_model.dart';

/// An `available` result: today's 5-year survival [current] percent and a raw difference [d5].
ExperimentResult available(double d5, {double current = 89.46, bool extrapolated = false}) => ExperimentResult(
  status: 'available',
  differenceByYear: {1: d5 / 8, 2: d5 / 4, 3: d5 / 2, 4: d5 * 0.8, 5: d5},
  currentPercentByYear: {1: current + 8, 2: current + 6, 3: current + 4, 4: current + 2, 5: current},
  alternativePercentByYear: {5: current + d5},
  extrapolated: extrapolated,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('survival is labelled and a comparison is labelled, in words a screen reader hears too', () {
    final rows = ResultDisplay.of(available(4.15)).rows;
    expect(ExperimentCurve.describe(rows), startsWith('Modeled survival of similar people. '));
    expect(SurvivalCurve.describe({1: 0.98, 5: 0.9}), startsWith('Modeled survival of similar people. '));
    expect(ExperimentCopy.subtitle, 'Modeled difference between profiles');
    expect(ResultDisplay.title, 'Modeled difference between profiles');
  });

  group('rounding rule (design y_gen.py)', () {
    test('half-up, on one decimal and on whole numbers', () {
      expect(ExperimentCopy.roundHalfUp(89.46), 89);
      expect(ExperimentCopy.roundHalfUp(89.5), 90);
      expect(ExperimentCopy.roundHalfUp(0.95, 1), 1.0);
      expect(ExperimentCopy.roundHalfUp(0.05, 1), 0.1);
      expect(ExperimentCopy.roundHalfUp(0.049, 1), 0.0);
      expect(ExperimentCopy.roundHalfUp(-0.05, 1), -0.1);
      expect(ExperimentCopy.roundHalfUp(2.86), 3);
    });

    test('d1 of 1.0 or more: "About N more in 100", at least 1, with arrays', () {
      var d = ResultDisplay.of(available(4.15));
      expect((d.kind, d.gap, d.today, d.whatIf, d.headline), (ResultKind.big, 4, 89, 93, 'About 4 more in 100'));
      expect(d.showsArrays, isTrue);
      // 0.95 rounds up to 1.0, so it is "1 more" with arrays, never "0".
      d = ResultDisplay.of(available(0.95));
      expect((d.kind, d.gap), (ResultKind.big, 1));
      expect(ResultDisplay.of(available(1.0)).gap, 1);
      expect(ResultDisplay.of(available(1.49)).gap, 1);
      expect(ResultDisplay.of(available(1.5)).gap, 2);
    });

    test('what-if is today plus the rounded gap, never round(alternative)', () {
      // 89.46 -> 89 and d 4.15 -> 4 give 93, although 93.61 alone would round to 94.
      final d = ResultDisplay.of(available(4.15));
      expect(d.whatIf, 93);
      expect(d.whatIf, d.today! + d.gap!);
      expect(ExperimentCopy.roundHalfUp(89.46 + 4.15), 94);
    });

    test('0.1 to 0.9: "Less than 1 more in 100", no arrays, exact figure behind (i)', () {
      for (final (diff, exact) in [
        (0.5206, 'About 5 in 1,000. Too small for a 100-bear picture.'),
        (0.107, 'About 1 in 1,000. Too small for a 100-bear picture.'),
        (0.0562, 'Less than 1 in 1,000. Too small for a 100-bear picture.'),
        (0.94, 'About 9 in 1,000. Too small for a 100-bear picture.'),
      ]) {
        final d = ResultDisplay.of(available(diff));
        expect(d.kind, ResultKind.tiny, reason: '$diff');
        expect(d.headline, 'Less than 1 more in 100');
        expect(d.whatIfText, 'A tiny bit more');
        expect(d.exactFigure, exact, reason: '$diff');
        expect(d.showsArrays, isFalse);
        expect(d.gap, isNull);
        expect(d.whatIf, isNull);
      }
    });

    test('under 0.1 either way: "About the same", no number', () {
      for (final diff in [0.0094, 0.0, 0.0499, -0.0499]) {
        final d = ResultDisplay.of(available(diff));
        expect(d.kind, ResultKind.same, reason: '$diff');
        expect(d.headline, 'About the same');
        expect(d.showsArrays, isFalse);
        expect(d.exactFigure, isNull);
      }
    });

    test('-0.1 or lower: "About N fewer in 100", never offered as an arrays picture', () {
      final d = ResultDisplay.of(available(-1.4));
      expect((d.kind, d.headline, d.showsArrays), (ResultKind.lower, 'About 1 fewer in 100', false));
      expect(ResultDisplay.of(available(-0.1)).headline, 'About 1 fewer in 100');
    });

    test('today at 99.5 or more reads "More than 99", never 100', () {
      final d = ResultDisplay.of(available(0.0562, current: 99.76));
      expect(d.todayMoreThan99, isTrue);
      expect(d.todayText, 'More than 99');
      expect(ResultDisplay.of(available(0.5, current: 99.4)).todayText, 'About 99');
    });

    test('years 1 to 5: today round(p), what-if today plus round(gap); a gap under 1 says so', () {
      final rows = ResultDisplay.of(available(4.15)).rows;
      expect(rows.map((r) => r.year), [1, 2, 3, 4, 5]);
      for (final r in rows) {
        expect(r.whatIf, r.today + r.gap);
      }
      // d / 8 = 0.52 in year 1: rounds to 1 here; with a smaller d it is "less than 1 more".
      final small = ResultDisplay.of(available(2.0)).rows;
      expect(small.first.gap, 0);
      expect(small.first.gapIsTiny, isTrue);
      expect(small.last.gapIsTiny, isFalse);
      expect(small.last.gap, 2);
    });

    test('a Rough guide (extrapolated) result carries the engine caveat verbatim', () {
      final d = ResultDisplay.of(available(4.2, extrapolated: true));
      expect(d.caveat, extrapolationCaveat);
      expect(ResultDisplay.of(available(4.2)).caveat, isNull);
      // Beside the Rough guide badge the tiny headline is the short one (Y-17).
      expect(ResultDisplay.of(available(0.3, extrapolated: true)).headline, 'Under 1 more in 100');
    });
  });

  group('status gating: a number only when available', () {
    const flags = [LeverFlag(id: LeverId.sitting, counted: false, reason: LeverReason.counterIntuitive)];
    final results = {
      'no_change': const ExperimentResult(status: 'no_change'),
      'not_counted': const ExperimentResult(status: 'not_counted', levers: flags),
      'current_unavailable': const ExperimentResult(status: 'current_unavailable', message: 'Needs ages 30-85.'),
      'alternative_unavailable': const ExperimentResult(status: 'alternative_unavailable', message: 'Withheld.'),
      'invalid_input': const ExperimentResult(status: 'invalid_input', message: 'More than 24 hours.'),
      // Even if numbers sneak into an unavailable result, none is shown.
      'current_unavailable + numbers': ExperimentResult(
        status: 'current_unavailable',
        differenceByYear: const {5: 4.0},
        currentPercentByYear: const {5: 90},
      ),
      'no_change + numbers': ExperimentResult(
        status: 'no_change',
        differenceByYear: const {5: 4.0},
        currentPercentByYear: const {5: 90},
      ),
    };

    test('every status but available has no number, headline or arrays', () {
      for (final e in results.entries) {
        final d = ResultDisplay.of(e.value);
        expect(d.hasNumber, isFalse, reason: e.key);
        expect(d.headline, isNull, reason: e.key);
        expect(d.today, isNull, reason: e.key);
        expect(d.gap, isNull, reason: e.key);
        expect(d.showsArrays, isFalse, reason: e.key);
        expect(d.rows, isEmpty, reason: e.key);
      }
    });

    test('each status has its own look', () {
      ResultKind kind(String s) => ResultDisplay.of(results[s]!).kind;
      expect(kind('no_change'), ResultKind.noChange);
      expect(kind('not_counted'), ResultKind.notCounted);
      expect(kind('current_unavailable'), ResultKind.noNumber);
      expect(kind('alternative_unavailable'), ResultKind.noNumber);
      expect(kind('invalid_input'), ResultKind.invalid);
      expect(ResultDisplay.of(results['alternative_unavailable']!).message, 'Withheld.');
      expect(ResultDisplay.of(results['not_counted']!).notCounted, flags);
    });

    test('an available result with no year numbers shows no number', () {
      expect(ResultDisplay.of(const ExperimentResult(status: 'available')).hasNumber, isFalse);
    });

    test('an unknown status never shows a number', () {
      expect(ResultDisplay.of(const ExperimentResult(status: 'something_new')).hasNumber, isFalse);
    });
  });

  group('the result is one comparison of the whole what-if twin', () {
    late TwinModelService model;
    late LeverRanking ranking;
    setUpAll(() async {
      model = await TwinModelService.load();
      ranking = await loadLeverRanking();
    });

    const smoker = {
      'age': 66,
      'sex': 'male',
      'height_cm': 175.0,
      'weight_kg': 80.0,
      'sleep_hours': 6,
      'smoking_status': 'current',
      'diabetes': false,
      'hypertension_diagnosed': false,
      'general_health': 3,
      'vigorous_recreation_min_week': 0,
      'moderate_recreation_min_week': 30,
      'sedentary_min_day': 480,
    };

    test('the card is never the sum of the per-lever numbers', () {
      TwinExperiment fresh() {
        final a = model.assess(smoker);
        return TwinExperiment(
          model: model,
          current: a,
          appProfile: smoker,
          order: ranking.orderFor(age: 66, sexNhanes: 1),
        );
      }

      double diffOf(void Function(TwinExperiment) moves) {
        final e = fresh();
        moves(e);
        expect(e.result.status, 'available');
        return e.result.difference5!;
      }

      final quit = diffOf((e) => e.set(LeverId.smoking, 1));
      final vigorous = diffOf((e) => e.set(LeverId.vigorous, 150));
      final both = diffOf((e) {
        e.set(LeverId.smoking, 1);
        e.set(LeverId.vigorous, 150);
      });
      expect(both, isNot(closeTo(quit + vigorous, 1e-9)));
      final a = fresh().current;
      final c = model.compare({
        'current_profile': a.profileUsed,
        'alternative_profile': {...a.profileUsed, LeverId.smoking: 1.0, LeverId.vigorous: 150.0},
      });
      expect(both, closeTo(TwinAssessment.yearMap(c['modeled_difference_percentage_points'])[5]!, 1e-9));
      final e = fresh()
        ..set(LeverId.smoking, 1)
        ..set(LeverId.vigorous, 150);
      expect(ResultDisplay.of(e.result).gap, ExperimentCopy.roundHalfUp(both));
    });

    test('sleep never goes above 8 hours and weight is never a lever', () {
      final a = model.assess({...smoker, 'sleep_hours': 5});
      final e = TwinExperiment(model: model, current: a, appProfile: smoker);
      expect(e.lever(LeverId.sleepHours).max, 8);
      e.set(LeverId.sleepHours, 9);
      expect(e.lever(LeverId.sleepHours).value, 8);
      expect(e.levers.where((l) => l.id == LeverId.weightKg && l.supported), isEmpty);
    });
  });
}
