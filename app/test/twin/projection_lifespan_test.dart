// The centred health score, the projection-based lifespan estimate, the weight guard and the
// score history's engine tag.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/demo/demo_seed.dart' show rosaProfile;
import 'package:lifesim/twin/lifespan.dart' show estimateLifespanForProfile, lifespanEndAge, lifespanProjectionWeight;
import 'package:lifesim/twin/profile_mapping.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/wellness/repository_adapter.dart';

import 'store_and_checkin_test.dart' show fullProfile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  late Map<String, dynamic> rosaGolden;
  setUpAll(() async {
    model = await TwinModelService.load();
    rosaGolden =
        jsonDecode(File('test/twin/rosa_projection_golden.json').readAsStringSync()) as Map<String, dynamic>;
  });

  Map<String, dynamic> rosa() => Map<String, dynamic>.from(rosaGolden['profile'] as Map);

  group('vendored package', () {
    test('neural_hazard.dart, projection.dart and neural_model.json are the handoff files, unchanged', () {
      for (final f in ['lib/src/neural_hazard.dart', 'lib/src/projection.dart', 'assets/neural_model.json']) {
        expect(
          File('packages/lifetwin_on_device/$f').readAsBytesSync(),
          File('../model_handoff/lifetwin_on_device/$f').readAsBytesSync(),
          reason: f,
        );
      }
    });
  });

  group('health score (Cox, centred on the age group median)', () {
    // The support reference rows, scored as AgeGroupReference does (no age or sex term),
    // decoded back to model profiles with the same score.
    late List<({double age, bool female, double s, Map<String, dynamic> profile})> rows;
    setUpAll(() {
      final spec = model.engine.model.spec;
      final coef = [for (final c in spec['coefficients'] as List) (c as num).toDouble()];
      final centre = [for (final c in spec['feature_center'] as List) (c as num).toDouble()];
      final bytes = gzip.decode(File('packages/lifetwin_on_device/assets/support_reference.f64.gz').readAsBytesSync());
      final view = ByteData.sublistView(Uint8List.fromList(bytes));
      final n = coef.length;
      rows = [];
      for (var r = 0; r < view.lengthInBytes ~/ (8 * n); r++) {
        final x = [for (var i = 0; i < n; i++) view.getFloat64((r * n + i) * 8, Endian.little)];
        var s = 0.0;
        for (var i = 0; i < n; i++) {
          if (i != 0 && i != 8) s += (x[i] - centre[i]) * coef[i];
        }
        var health = 1;
        for (var level = 2; level <= 5; level++) {
          if (x[11 + level] == 1) health = level;
        }
        rows.add((
          age: x[0] * 10 + 55,
          female: x[8] == 1,
          s: s,
          profile: {
            'bmi': x[1] > 0 ? 23 - 5 * x[1] : (x[2] > 0 ? 35 + 5 * x[2] : 25.0),
            'sleep_hours': x[3] > 0 ? 7 - x[3] : (x[4] > 0 ? 8 + x[4] : 7.5),
            'vigorous_recreation_min_week': math.exp(x[5] * math.log(76)) - 1,
            'moderate_recreation_min_week': math.exp(x[6] * math.log(151)) - 1,
            'sedentary_min_day': 360 + 120 * x[7],
            'smoking_status': x[10] == 1 ? 2 : (x[9] == 1 ? 1 : 0),
            'diabetes_diagnosed': x[11].round(),
            'hypertension_diagnosed': x[12].round(),
            'general_health': health,
          },
        ));
      }
    });

    test('is exactly 0 for a profile whose score equals the group median (Rosa\'s group)', () {
      final a = model.assessModel(rosa());
      final low = int.parse(a.ageGroupBand!.split('–').first), high = int.parse(a.ageGroupBand!.split('–').last);
      final band = [
        for (final r in rows)
          if (r.female && r.age >= low && r.age <= high) r,
      ]..sort((p, q) => p.s.compareTo(q.s));
      expect(band.length, a.ageGroupSize);
      final median = band[(band.length + 1) ~/ 2 - 1];
      final m = model.assessModel({...median.profile, 'age': 64, 'sex_nhanes': 2});
      expect(m.healthScoreStatus, HealthScoreStatus.available);
      expect(m.ageGroupBand, a.ageGroupBand);
      expect(m.healthScore, closeTo(0, 1e-9));
      expect(m.healthGroupLabel, 'women ${a.ageGroupBand}');
    });

    test('is group median − s, s being exactly what the percentile ranks', () {
      final a = model.assessModel(rosa());
      final better = model.assessModel({...rosa(), 'vigorous_recreation_min_week': 150});
      final worse = model.assessModel({...rosa(), 'smoking_status': 2});
      expect(better.healthScore!, greaterThan(a.healthScore!));
      expect(worse.healthScore!, lessThan(a.healthScore!));
      // Same band and same median: the difference of two scores is −Δ raw score.
      expect(
        better.healthScore! - a.healthScore!,
        closeTo(a.rawLogRelativeHazard! - better.rawLogRelativeHazard!, 1e-12),
      );
    });

    test('above 0 exactly when the percentile is above 50: 200+ profiles, ages 18–85, both sexes', () {
      final base = rosa();
      final variants = <Map<String, dynamic>>[
        {},
        {'smoking_status': 2, 'general_health': 4},
        {'vigorous_recreation_min_week': 150, 'general_health': 1, 'sleep_hours': 7.5},
        {'bmi': 21.0, 'sedentary_min_day': 720, 'diabetes_diagnosed': 1},
        {'bmi': 33.0, 'hypertension_diagnosed': 1, 'moderate_recreation_min_week': 300},
        {'smoking_status': 1, 'sleep_hours': 5.5, 'general_health': 2},
      ];
      var checked = 0, below = 0, above = 0;
      for (var age = 18; age <= 85; age += 3) {
        for (final sex in [1, 2]) {
          for (final v in variants) {
            final a = model.assessModel({...base, ...v, 'age': age, 'sex_nhanes': sex});
            if (a.rawLogRelativeHazard == null) {
              expect(a.healthScore, isNull);
              continue;
            }
            checked++;
            final index = a.healthScore!, pct = a.ageGroupPercentile!;
            expect(a.healthGroupLabel, '${sex == 2 ? 'women' : 'men'} ${a.ageGroupBand}');
            expect(a.extrapolated, age < 35 || age > 79, reason: 'Rough guide flag, age $age');
            if (index == 0) continue; // an exact tie at the median
            expect(index > 0, pct > 50, reason: 'age $age sex $sex $v: score $index, percentile $pct');
            index > 0 ? above++ : below++;
          }
        }
      }
      expect(checked, greaterThanOrEqualTo(200));
      expect(below, greaterThan(20));
      expect(above, greaterThan(20));
    });

    test('ages 18–34 use the percentile\'s nearest band and extrapolation (Rough guide)', () {
      final a = model.assessModel({...rosa(), 'age': 30});
      expect(a.extrapolated, isTrue);
      expect(a.healthScoreStatus, HealthScoreStatus.extrapolated);
      expect(a.ageGroupNearestBand, isTrue);
      expect(a.healthScore, isNotNull);
      expect(a.healthGroupLabel, 'women 35–45');
      expect(a.healthGroupLabel, 'women ${a.ageGroupBand}');
    });

    test('is null whenever the model gives no number', () {
      final p = rosa();
      for (final a in [
        model.assessModel({...p}..remove('bmi')..remove('sleep_hours')..remove('sedentary_min_day')), // 3 missing inputs (1-2 give a rough number)
        model.assessModel({...p, 'age': 86}), // unsupported age
        model.assessModel({...p, 'age': 17}), // under age
        model.assessModel({...p, 'bmi': 60, 'sedentary_min_day': 1200, 'sleep_hours': 2}), // unsupported
        model.assessModel({...p, 'sleep_hours': 30}), // invalid input
      ]) {
        expect(a.rawLogRelativeHazard, isNull, reason: a.status);
        expect(a.healthScore, isNull, reason: a.status);
        expect(a.healthGroupLabel, isNull, reason: a.status);
        expect(a.ageGroupPercentile, isNull, reason: a.status);
      }
      expect(model.assessModel({...p, 'age': 17}).healthScoreStatus, HealthScoreStatus.underAge);
    });

    test('the repository passes it through, and null before a profile or without a score', () async {
      final empty = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
      expect(empty.healthScore, isNull);
      expect(empty.healthGroupLabel, isNull);
      expect(empty.lifespanEstimate, isNull);

      final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
      await repo.saveConversationProfile(Map<String, dynamic>.from(fullProfile));
      expect(repo.healthScore, isNotNull);
      expect(repo.healthScore, repo.current!.healthScore);
      expect(repo.healthGroupLabel, 'men ${repo.ageGroupBand}');
      expect(repo.healthScoreHistory().last.score, repo.healthScore);

      final partial = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
      // 3 missing: no number (1-2 give a rough one).
      await partial.saveConversationProfile(
        Map<String, dynamic>.from(fullProfile)
          ..remove('sedentary_min_day')
          ..remove('sleep_hours')
          ..remove('general_health'),
      );
      expect(partial.healthScoreStatus, HealthScoreStatus.missingInputs);
      expect(partial.healthScore, isNull);
      expect(partial.healthGroupLabel, isNull);
      expect(partial.lifespanEstimate, isNull);
      expect(partial.healthScoreHistory().last.score, isNull);
    });
  });

  group('lifespan from the yearly projection', () {
    test('Rosa (64 F) matches model_handoff\'s LifeTwinProjectionLab exactly', () {
      final e = LifespanEstimate.forProfile(rosa(), currentYear: 2026, lab: model.projection)!;
      final points = [for (final p in rosaGolden['points'] as List) p as List];
      expect(e.annualCurve.length, points.length);
      for (var i = 0; i < points.length; i++) {
        expect(e.annualCurve[i].age, points[i][0]);
        expect(e.annualCurve[i].survivalPercent, closeTo((points[i][1] as num).toDouble(), 1e-9));
        expect(e.annualCurve[i].extrapolated, points[i][2]);
      }
      expect(e.expectedAge, closeTo((rosaGolden['median_crossing_age'] as num).toDouble(), 1e-9));
      expect(e.medianCrossingExtrapolated, rosaGolden['median_crossing_extrapolated']);
      // 75% and 25% crossings, interpolated between whole ages as the lab does for 50%.
      double cross(double pct) {
        for (var i = 1; i < points.length; i++) {
          final a = (points[i - 1][1] as num).toDouble(), b = (points[i][1] as num).toDouble();
          if (a > pct && b <= pct) return (points[i][0] as int) - 1 + (a - pct) / (a - b);
        }
        throw StateError('no crossing');
      }

      expect(e.p25Age, closeTo(cross(75), 1e-9));
      expect(e.p75Age, closeTo(cross(25), 1e-9));
      expect(LifespanEstimate.crossingAge(e.annualCurve, 50), closeTo(e.expectedAge, 1e-9));
      expect(e.expectedYear, 2026 + (e.expectedAge - 64 + 0.5).floor());
      expect(e.status, LifespanStatus.available);
      expect(e.caveat, contains('Proof of concept'));
      expect(e.caveat, contains('only checked up to age 79'));
    });

    test('the seeded Rosa profile (height and weight) gives the same estimate through the model', () {
      final a = model.assessModel(toModelProfile(rosaProfile));
      final e = LifespanEstimate.forProfile(a.profileUsed, currentYear: 2026, lab: model.projection)!;
      expect(e.expectedAge, closeTo((rosaGolden['median_crossing_age'] as num).toDouble(), 1e-6));
    });

    test('p25 ≤ expected ≤ p75, never missing for a scored profile, and no day or date anywhere', () {
      final datePattern = RegExp(
        r'\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{2,4}|\b(January|February|March|April|May|June|July|August|'
        r'September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\b',
      );
      final base = rosa();
      var checked = 0, open = 0;
      for (final sex in [1, 2]) {
        for (final age in [18, 25, 34, 35, 45, 55, 64, 72, 79, 80, 85]) {
          for (final change in <Map<String, dynamic>>[
            {},
            {'smoking_status': 2},
            {'diabetes_diagnosed': 1, 'general_health': 4},
            {'vigorous_recreation_min_week': 150, 'general_health': 1, 'sleep_hours': 7.5},
          ]) {
            final p = {...base, ...change, 'age': age, 'sex_nhanes': sex};
            expect(model.assessModel(p).healthScore, isNotNull);
            final e = LifespanEstimate.forProfile(p, currentYear: 2026, lab: model.projection);
            expect(e, isNotNull, reason: '$p'); // no estimate goes missing for being healthy
            checked++;
            if (e!.p75OpenEnded) open++;
            expect(e.p25Age, lessThanOrEqualTo(e.expectedAge));
            expect(e.expectedAge, lessThanOrEqualTo(e.p75Age));
            expect(e.expectedAge, greaterThan(age));
            expect(e.p75Age, lessThanOrEqualTo(lifespanEndAge));
            expect(e.expectedYear, 2026 + (e.expectedAge - age + 0.5).floor());
            for (final text in [e.headline, e.caveat, '${e.expectedYear}']) {
              expect(datePattern.hasMatch(text), isFalse, reason: text);
            }
          }
        }
      }
      expect(checked, 88);
      expect(open, greaterThan(0), reason: 'the sweep must include open-ended profiles');
    });

    test('open-ended: a curve above 25% (or 50%) at 110 reports 110 with its flag', () {
      // Rosa after her seeded weeks: about 25.7% at 110 with Cox v3.
      final healthy = {...rosa(), 'sleep_hours': 6.9, 'sedentary_min_day': 420.0, 'moderate_recreation_min_week': 120.0};
      final e = LifespanEstimate.forProfile(healthy, currentYear: 2026, lab: model.projection)!;
      expect(e.annualCurve.last.age, 110);
      expect(e.annualCurve.last.survivalPercent, greaterThan(25));
      expect((e.p75Age, e.p75OpenEnded), (110.0, true));
      expect(e.openEnded, isFalse);
      expect(e.expectedAge, lessThan(110));
      expect(e.headline, contains('110+'));
      expect(e.caveat, contains('110+'));

      // A very healthy woman of 50 (pure projection): even 50% is not reached by 110.
      final best = {
        ...rosa(),
        'age': 50,
        'bmi': 25.0,
        'vigorous_recreation_min_week': 300,
        'moderate_recreation_min_week': 600,
        'general_health': 1,
        'sleep_hours': 7.5,
        'sedentary_min_day': 120,
      };
      expect(model.assessModel(best).healthScoreStatus, HealthScoreStatus.available);
      final b = LifespanEstimate.forProfile(best, currentYear: 2026, lab: model.projection)!;
      expect(b.annualCurve.last.survivalPercent, greaterThan(50));
      expect((b.expectedAge, b.openEnded, b.p75Age, b.p75OpenEnded), (110.0, true, 110.0, true));
      expect(b.p25Age, lessThanOrEqualTo(110));
      expect(b.expectedYear, 2026 + 60); // follows from expectedAge = 110
      expect(b.headline, contains('about 110+'));

      // Closed ends carry no flag.
      final r = LifespanEstimate.forProfile(rosa(), currentYear: 2026, lab: model.projection)!;
      expect((r.p25OpenEnded, r.openEnded, r.p75OpenEnded), (false, false, false));
      expect(r.caveat, isNot(contains('110+')));
    });

    test('the blend: life table below 35 and from 79, projection 45–70, linear in between', () {
      expect([for (final a in [18, 34, 35, 40, 44.5, 45, 64, 70, 74.5, 75, 79, 79.5, 80, 85]) lifespanProjectionWeight(a)], [
        0,
        0,
        0,
        0.5,
        0.95,
        1,
        1,
        1,
        0.5,
        4 / 9,
        0,
        0,
        0,
        0,
      ]);
      for (final sex in [1, 2]) {
        for (final age in [18, 34, 35, 38, 40, 44, 45, 64, 70, 72, 75, 79, 80, 85]) {
          final p = {...rosa(), 'age': age, 'sex_nhanes': sex};
          final e = LifespanEstimate.forProfile(p, currentYear: 2026, lab: model.projection)!;
          final w = lifespanProjectionWeight(age);
          final curve = estimateLifespanForProfile(p);
          final annual = model.projection!.assess(p, includeExtrapolation: true)['annual'] as Map?;
          final reason = 'sex $sex age $age';
          expect(e.projectionWeight, w, reason: reason);
          if (w == 0) {
            expect(e.expectedAge, closeTo(curve.expectedAgeAtDeath, 1e-12), reason: reason);
            expect(e.p25Age, closeTo(curve.age25thPercentile, 1e-12), reason: reason);
            expect(e.p75Age, closeTo(curve.age75thPercentile, 1e-12), reason: reason);
          } else {
            final proj = (annual!['median_crossing_age'] as num?)?.toDouble() ?? 110.0;
            expect(e.expectedAge, closeTo((1 - w) * curve.expectedAgeAtDeath + w * proj, 1e-9), reason: reason);
          }
          expect(e.p25Age, lessThanOrEqualTo(e.expectedAge), reason: reason);
          expect(e.expectedAge, lessThanOrEqualTo(e.p75Age), reason: reason);
          expect(e.expectedYear, 2026 + (e.expectedAge - age + 0.5).floor(), reason: reason);
          // Rough guide only where the life table has the larger weight.
          expect(e.extrapolated, w < 0.5, reason: reason);
          expect(e.caveat.contains('even rougher'), w < 0.5, reason: reason);
          expect(e.caveat, contains('Proof of concept'));
          expect(e.caveat.contains('outside the ages'), age < 35 || age > 79, reason: reason);
        }
      }
      // Pure life table works without the projection lab; where the projection has weight it
      // is needed.
      expect(LifespanEstimate.forProfile({...rosa(), 'age': 30}, currentYear: 2026, lab: null), isNotNull);
      expect(LifespanEstimate.forProfile({...rosa(), 'age': 79}, currentYear: 2026, lab: null), isNotNull);
      expect(LifespanEstimate.forProfile({...rosa(), 'age': 40}, currentYear: 2026, lab: null), isNull);
      expect(LifespanEstimate.forProfile(rosa(), currentYear: 2026, lab: null), isNull);
    });

    test('at a zero projection weight (exactly 35 and 79) the text describes the life table', () {
      for (final sex in [1, 2]) {
        for (final age in [35, 79]) {
          final p = {...rosa(), 'age': age, 'sex_nhanes': sex};
          final withLab = LifespanEstimate.forProfile(p, currentYear: 2026, lab: model.projection)!;
          final tableOnly = LifespanEstimate.forProfile(p, currentYear: 2026, lab: null)!;
          final reason = 'sex $sex age $age';
          expect(withLab.projectionWeight, 0, reason: reason);
          // The numbers are the life table's, so the method note must be too, not the
          // projection's "repeats the survey model's one-year risk".
          expect(withLab.caveat, tableOnly.caveat, reason: reason);
          expect(withLab.caveat, isNot(contains('one-year risk')), reason: reason);
          expect(withLab.medianCrossingExtrapolated, tableOnly.medianCrossingExtrapolated, reason: reason);
          expect([for (final q in withLab.annualCurve) q.age], [for (final q in tableOnly.annualCurve) q.age]);
        }
      }
    });

    test('no one-year step changes the expected age by more than 3 years, 18–85, both sexes', () {
      final golden = jsonDecode(File('test/twin/lifespan_golden.json').readAsStringSync()) as Map<String, dynamic>;
      final readme = Map<String, dynamic>.from(
        (golden['profiles'] as List).cast<Map<String, dynamic>>().firstWhere(
              (p) => p['name'] == 'male_45_readme',
            )['profile']
            as Map,
      );
      var largest = 0.0;
      for (final base in [rosa(), readme]) {
        for (final sex in [1, 2]) {
          double? last;
          for (var age = 18; age <= 85; age++) {
            final e = LifespanEstimate.forProfile(
              {...base, 'age': age, 'sex_nhanes': sex},
              currentYear: 2026,
              lab: model.projection,
            )!;
            if (last != null) {
              final step = (e.expectedAge - last).abs();
              if (step > largest) largest = step;
              expect(step, lessThanOrEqualTo(3.0), reason: 'sex $sex age ${age - 1}→$age');
            }
            last = e.expectedAge;
          }
        }
      }
      expect(largest, greaterThan(0));
    });

    test('the repository marks the life-table ages Rough guide', () async {
      final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
      await repo.saveConversationProfile({...fullProfile, 'age': 30});
      final e = repo.lifespanEstimate!;
      expect(e.status, LifespanStatus.extrapolated);
      expect(RepositoryWellness(repo).snapshot.lifespan!.roughGuide, isTrue);
    });

    test('a worse profile gives an earlier age', () {
      final p = rosa();
      final good = LifespanEstimate.forProfile(p, currentYear: 2026, lab: model.projection)!;
      final bad = LifespanEstimate.forProfile(
        {...p, 'smoking_status': 2, 'diabetes_diagnosed': 1},
        currentYear: 2026,
        lab: model.projection,
      )!;
      expect(bad.expectedAge, lessThan(good.expectedAge));
    });

    test('a fractional age gets an estimate: projection at the floor, blend weight fractional', () {
      final p = rosa();
      final half = LifespanEstimate.forProfile({...p, 'age': 64.5}, currentYear: 2026, lab: model.projection)!;
      final whole = LifespanEstimate.forProfile(p, currentYear: 2026, lab: model.projection)!;
      expect(half.expectedAge, whole.expectedAge); // pure projection, run at 64
      expect(half.expectedYear, 2026 + (whole.expectedAge - 64.5 + 0.5).floor());
      for (final age in [18.4, 34.9, 35.5, 40.25, 44.9, 70.5, 78.6, 79.5, 85.0]) {
        final e = LifespanEstimate.forProfile({...p, 'age': age}, currentYear: 2026, lab: model.projection);
        expect(e, isNotNull, reason: 'age $age');
        expect(e!.projectionWeight, lifespanProjectionWeight(age), reason: 'age $age');
        expect(e.p25Age, lessThanOrEqualTo(e.expectedAge));
        expect(e.expectedAge, lessThanOrEqualTo(e.p75Age));
      }
      final mid = LifespanEstimate.forProfile({...p, 'age': 40.25}, currentYear: 2026, lab: model.projection)!;
      final table = estimateLifespanForProfile({...p, 'age': 40.25});
      final at40 = model.projection!.assess({...p, 'age': 40}, includeExtrapolation: true)['annual'] as Map;
      final proj = (at40['median_crossing_age'] as num?)?.toDouble() ?? 110.0;
      expect(mid.expectedAge, closeTo(0.475 * table.expectedAgeAtDeath + 0.525 * proj, 1e-9));
    });

    test('unavailable under 18, over 85, or for an incomplete or unsupported profile', () {
      final p = rosa();
      for (final q in [
        {...p, 'age': 17},
        {...p, 'age': 86},
        {...p, 'age': double.nan},
        {...p}..remove('bmi'),
        {...p, 'bmi': 60, 'sedentary_min_day': 1200, 'sleep_hours': 2},
      ]) {
        expect(LifespanEstimate.forProfile(q, currentYear: 2026, lab: model.projection), isNull, reason: '$q');
      }
    });
  });

  group('weight guard', () {
    test('a higher BMI alone shows zero benefit, at every age and BMI', () {
      for (final age in [35, 55, 64, 79, 30, 85]) {
        for (final bmi in [19.0, 22.0, 25.0, 30.0, 38.0]) {
          final current = {...rosa(), 'age': age, 'bmi': bmi};
          for (final up in [0.5, 2.0, 5.0]) {
            final c = model.compare({
              'current_profile': current,
              'alternative_profile': {...current, 'bmi': bmi + up},
            });
            final d = c['modeled_difference_percentage_points'] as Map?;
            if (d == null) continue; // one side unavailable: no number shown at all
            expect(d.values, everyElement(0.0), reason: 'age $age bmi $bmi +$up');
            expect(c['weight_guard'], isTrue);
            expect(c['warnings'], contains(weightGuardWarning));
            expect(c['health_score_delta'], 0.0, reason: 'age $age bmi $bmi +$up');
            expect(c['health_score_alternative'], c['health_score_current']);
            expect(
              (c['alternative'] as Map)['survival_percent_by_year'],
              (c['current'] as Map)['survival_percent_by_year'],
            );
          }
        }
      }
    });

    test('the guard is needed: unguarded, the model would show a benefit', () {
      final current = {...rosa(), 'bmi': 21.0};
      final raw = model.engine.compare({
        'current_profile': current,
        'alternative_profile': {...current, 'bmi': 24.0},
      });
      expect(((raw['modeled_difference_percentage_points'] as Map)['5'] as num), greaterThan(0));
      final guarded = model.compare({
        'current_profile': current,
        'alternative_profile': {...current, 'bmi': 24.0},
      });
      expect(guarded['health_score_delta'], 0.0);
    });

    test('weight gain through height and weight is guarded too', () {
      final current = {...toModelProfile(rosaProfile)};
      final c = model.compare({
        'current_profile': current,
        'alternative_profile': {...current, 'weight_kg': (current['weight_kg'] as num) + 8},
      });
      expect((c['modeled_difference_percentage_points'] as Map).values, everyElement(0.0));
      expect(c['weight_guard'], isTrue);
      expect(c['health_score_delta'], 0.0);
    });

    test('other changes, and a lower BMI, are not touched', () {
      final current = {...rosa(), 'bmi': 30.0};
      final quit = {...current, 'smoking_status': 0};
      final smoker = {...current, 'smoking_status': 2};
      final c = model.compare({'current_profile': smoker, 'alternative_profile': {...quit, 'bmi': 31.0}});
      expect(c['weight_guard'], isNull);
      expect(((c['modeled_difference_percentage_points'] as Map)['5'] as num), greaterThan(0));
      // The experiment delta is the changed twin's index minus the current twin's.
      final now = model.assessModel(smoker).healthScore!, then = model.assessModel({...quit, 'bmi': 31.0}).healthScore!;
      expect(c['health_score_current'], closeTo(now, 1e-12));
      expect(c['health_score_alternative'], closeTo(then, 1e-12));
      expect(c['health_score_delta'], closeTo(then - now, 1e-12));
      expect(c['health_score_delta'] as double, greaterThan(0));
      final lower = model.compare({'current_profile': current, 'alternative_profile': {...current, 'bmi': 28.0}});
      expect(lower['weight_guard'], isNull);
      expect(model.compare({'current_profile': current, 'alternative_profile': current})['weight_guard'], isNull);
    });
  });

  group('score history engine tag', () {
    test('points carry the current Cox engine and older scales are left out', () async {
      final backend = MemoryBackend();
      final repo = TwinRepository(model: model, store: await TwinStore.open(backend));
      await repo.saveConversationProfile(Map<String, dynamic>.from(fullProfile));
      final doc = jsonDecode(backend.text!) as Map<String, dynamic>;
      final stored = (doc['health_score'] as List).cast<Map<String, dynamic>>();
      expect(stored, isNotEmpty);
      expect(stored.every((p) => p['engine'] == healthScoreEngine), isTrue);
      expect(stored.last['centered_score'], repo.healthScore);
      expect(stored.last['score'], repo.rawLogRelativeHazard);

      // A point from before the tag (old −log-hazard scale), one with the old tag, and one
      // from another engine.
      final untagged = {...stored.first, 'score': -0.5}..remove('engine')..remove('centered_score');
      final oldTag = {...untagged, 'engine': 'cox_v1', 'score': -0.6};
      final index = {...stored.first, 'engine': 'cox_index_v1', 'health_index': 1.65}..remove('centered_score');
      final other = {...stored.first, 'engine': 'neural_v1', 'centered_score': 9.0};
      doc['health_score'] = [untagged, ...stored, oldTag, index, other];
      backend.text = jsonEncode(doc);
      final reopened = TwinRepository(model: model, store: await TwinStore.open(backend));
      final points = reopened.healthScoreHistory();
      expect(points.length, stored.length);
      expect(points.every((p) => p.engine == healthScoreEngine), isTrue);
      expect(points.map((p) => p.score), [for (final p in stored) p['centered_score']]);
      expect(reopened.healthScoreHistory(engine: 'cox_index_v1'), hasLength(1));
      expect(reopened.healthScoreHistory(engine: legacyHealthScoreEngine).map((p) => p.rawLogRelativeHazard), [-0.5, -0.6]);
      expect(reopened.healthScoreHistory(engine: 'neural_v1').single.score, 9.0);
      // The sparkline reads the same filtered history.
      expect(RepositoryWellness(reopened).snapshot.history, [
        for (final p in points)
          if (p.score != null) p.score!,
      ]);
    });
  });
}
