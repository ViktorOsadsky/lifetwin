import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/lifespan.dart';
import 'package:lifesim/twin/lifespan_data.dart';

const tol = 1e-9;

Map<String, dynamic> loadGolden() =>
    jsonDecode(File('test/twin/lifespan_golden.json').readAsStringSync())
        as Map<String, dynamic>;

double? _halfLife(Object? v) => v == null ? null : (v as num).toDouble();

void expectMatches(LifespanCurve r, Map<String, dynamic> g) {
  expect(
    r.lifeExpectancyYears,
    closeTo((g['life_expectancy_years'] as num).toDouble(), tol),
  );
  expect(
    r.expectedAgeAtDeath,
    closeTo((g['expected_age_at_death'] as num).toDouble(), tol),
  );
  expect(r.sdYears, closeTo((g['sd_years'] as num).toDouble(), tol));
  expect(
    r.age25thPercentile,
    closeTo((g['age_25th_percentile'] as num).toDouble(), tol),
  );
  expect(r.medianAge, closeTo((g['median_age'] as num).toDouble(), tol));
  expect(
    r.age75thPercentile,
    closeTo((g['age_75th_percentile'] as num).toDouble(), tol),
  );
  expect(r.headlineAge, g['headline_age']);
  expect(r.rangeLowAge, g['range_low_age']);
  expect(r.rangeHighAge, g['range_high_age']);
  final reach = g['probability_reach'] as Map<String, dynamic>;
  for (final m in [80, 90, 100]) {
    final want = reach['$m'];
    if (want == null) {
      expect(r.probabilityReach[m], isNull);
    } else {
      expect(r.probabilityReach[m], closeTo((want as num).toDouble(), tol));
    }
  }
  final curve = g['survival_curve'] as List;
  expect(r.survivalCurve.length, curve.length);
  for (var i = 0; i < curve.length; i++) {
    final point = curve[i] as List;
    expect(r.survivalCurve[i].$1, closeTo((point[0] as num).toDouble(), tol));
    expect(r.survivalCurve[i].$2, closeTo((point[1] as num).toDouble(), tol));
  }
}

void main() {
  final golden = loadGolden();

  test(
    'generated data matches the model version used for the golden vectors',
    () {
      expect(golden['model_version'], lifespanModelVersion);
      expect(riskCoefficients.length, riskFeatureNames.length);
      expect(qxMale.length, 100);
      expect(qxFemale.length, 100);
    },
  );

  test('raw life-table cases agree with the Python reference to 1e-9', () {
    for (final g in golden['raw'] as List) {
      final m = g as Map<String, dynamic>;
      final r = estimateLifespan(
        sex: m['sex'] == 'female' ? LifespanSex.female : LifespanSex.male,
        age: (m['age'] as num).toDouble(),
        logHazardRatio: (m['log_hazard_ratio'] as num).toDouble(),
        halfLifeYears: _halfLife(m['half_life_years']),
      );
      expectMatches(r, m);
    }
  });

  test('profile cases agree with the Python reference to 1e-9', () {
    for (final g in golden['profiles'] as List) {
      final m = g as Map<String, dynamic>;
      final profile = Map<String, dynamic>.from(m['profile'] as Map);
      expect(
        lifespanLogHazardRatio(profile),
        closeTo((m['log_hazard_ratio'] as num).toDouble(), tol),
      );
      final r = estimateLifespanForProfile(
        profile,
        halfLifeYears: _halfLife(m['half_life_years']),
      );
      expectMatches(r, m);
    }
  });

  test('calendar year and headline agree with the Python reference', () {
    final c = golden['calendar_example'] as Map<String, dynamic>;
    final asOf = DateTime.parse(c['as_of'] as String);
    final birth = DateTime.parse(c['birth'] as String);
    final age = exactAgeYears(birth, asOf);
    expect(age, closeTo((c['exact_age'] as num).toDouble(), tol));
    final profile = <String, dynamic>{
      ...(golden['profiles'] as List).cast<Map<String, dynamic>>().firstWhere(
            (p) => p['name'] == 'male_45_readme',
          )['profile']
          as Map<String, dynamic>,
      'age': age,
    };
    final r = estimateLifespanForProfile(profile);
    expect(
      r.lifeExpectancyYears,
      closeTo((c['life_expectancy_years'] as num).toDouble(), tol),
    );
    expect(r.expectedYear(asOf.year), c['expected_calendar_year']);
    expect(r.headline, c['headline']);
    expect(r.headline, isNot(contains('die')));
  });

  test('HR = 1 without attenuation reproduces the published life table', () {
    for (final (sex, ex) in [
      (LifespanSex.male, publishedExMale),
      (LifespanSex.female, publishedExFemale),
    ]) {
      for (var age = 1; age < 100; age++) {
        final r = estimateLifespan(
          sex: sex,
          age: age.toDouble(),
          logHazardRatio: 0,
          halfLifeYears: null,
        );
        // The NCHS spreadsheet stores values in single precision.
        expect(
          r.lifeExpectancyYears,
          closeTo(ex[age], 2e-5),
          reason: '$sex age $age',
        );
      }
    }
    // Table A, NVSR 75-5: e65 = 18.4 (males), 20.8 (females).
    expect(
      estimateLifespan(
        sex: LifespanSex.male,
        age: 65,
        logHazardRatio: 0,
      ).lifeExpectancyYears,
      closeTo(18.4, 0.05),
    );
    expect(
      estimateLifespan(
        sex: LifespanSex.female,
        age: 65,
        logHazardRatio: 0,
      ).lifeExpectancyYears,
      closeTo(20.8, 0.05),
    );
  });

  test('HR = 1 is unaffected by attenuation', () {
    final a = estimateLifespan(
      sex: LifespanSex.female,
      age: 50,
      logHazardRatio: 0,
      halfLifeYears: null,
    );
    final b = estimateLifespan(
      sex: LifespanSex.female,
      age: 50,
      logHazardRatio: 0,
      halfLifeYears: 10,
    );
    expect(a.lifeExpectancyYears, closeTo(b.lifeExpectancyYears, 1e-12));
  });

  test('a higher HR gives a lower life expectancy, and attenuation pulls toward the table', () {
    for (final sex in LifespanSex.values) {
      for (final age in [30.0, 47.5, 65.0, 85.0]) {
        double le(double lhr, double? hl) => estimateLifespan(
          sex: sex,
          age: age,
          logHazardRatio: lhr,
          halfLifeYears: hl,
        ).lifeExpectancyYears;
        for (final hl in [null, 20.0, 10.0]) {
          var previous = double.infinity;
          for (final lhr in [-1.5, -0.5, 0.0, 0.5, 1.5]) {
            final value = le(lhr, hl);
            expect(value, lessThan(previous));
            previous = value;
          }
        }
        final avg = le(0, null);
        expect((le(-1, 20) - avg).abs(), lessThan((le(-1, null) - avg).abs()));
        expect((le(1, 20) - avg).abs(), lessThan((le(1, null) - avg).abs()));
      }
    }
  });

  test('percentiles are ordered and never below the current age', () {
    for (final sex in LifespanSex.values) {
      for (final age in [30.0, 34.5, 60.0, 79.9, 85.0]) {
        for (final lhr in [-2.0, 0.0, 2.5]) {
          final r = estimateLifespan(sex: sex, age: age, logHazardRatio: lhr);
          expect(r.age25thPercentile, greaterThanOrEqualTo(age));
          expect(r.medianAge, greaterThan(r.age25thPercentile));
          expect(r.age75thPercentile, greaterThan(r.medianAge));
          expect(r.rangeLowAge, lessThanOrEqualTo(r.headlineAge));
          expect(r.rangeHighAge, greaterThanOrEqualTo(r.headlineAge));
          expect(r.sdYears, greaterThan(0));
          var previous = 1.0;
          for (final (_, s) in r.survivalCurve) {
            expect(s, lessThanOrEqualTo(previous));
            previous = s;
          }
          expect(r.survivalCurve.last.$1, 110);
        }
      }
    }
  });

  test('profiles outside 18-85 or incomplete are refused', () {
    final p = Map<String, dynamic>.from(
      (golden['profiles'] as List).cast<Map<String, dynamic>>().first['profile']
          as Map,
    );
    expect(
      () => lifespanLogHazardRatio({...p, 'age': 17}),
      throwsFormatException,
    );
    expect(
      () => lifespanLogHazardRatio({...p, 'age': 86}),
      throwsFormatException,
    );
    expect(
      () => lifespanLogHazardRatio({...p, 'bmi': null}),
      throwsFormatException,
    );
    expect(
      () => lifespanLogHazardRatio({...p, 'smoking_status': 3}),
      throwsFormatException,
    );
    expect(math.exp(lifespanLogHazardRatio(p)), greaterThan(0));
  });

  test('after the band adjustment, 5-year survival matches the Cox model within 0.5 points per band', () {
    final model = jsonDecode(
      File('packages/lifetwin_on_device/assets/model.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final beta = (model['coefficients'] as List).cast<num>();
    final center = (model['feature_center'] as List).cast<num>();
    final s0 = ((model['baseline_survival'] as List)[4] as num).toDouble();
    final bytes = gzip.decode(
      File('packages/lifetwin_on_device/assets/support_reference.f64.gz')
          .readAsBytesSync(),
    );
    final values = Uint8List.fromList(bytes).buffer.asFloat64List();
    final riskCols = [
      for (var j = 0; j < 17; j++)
        if (j != 0 && j != 8) j,
    ];
    const bands = [(35, 44), (45, 54), (55, 64), (65, 74), (75, 79)];
    for (final sex in LifespanSex.values) {
      for (final (lo, hi) in bands) {
        var cox = 0.0, table = 0.0, n = 0;
        for (var i = 0; i < values.length; i += 17) {
          final r = values.sublist(i, i + 17);
          if ((r[8] == 1.0) != (sex == LifespanSex.female)) continue;
          final age = (55 + 10 * r[0]).roundToDouble();
          if (age < lo || age > hi) continue;
          var full = 0.0, risk = 0.0;
          for (var j = 0; j < 17; j++) {
            full += beta[j] * (r[j] - center[j]);
          }
          for (var k = 0; k < riskCols.length; k++) {
            risk += riskCoefficients[k] * r[riskCols[k]];
          }
          final logHr =
              risk - referenceScore(sex, age) + bandLogAdjustment(sex, age);
          final curve = estimateLifespan(
            sex: sex,
            age: age,
            logHazardRatio: logHr,
            halfLifeYears: null,
          ).survivalCurve;
          cox += math.pow(s0, math.exp(full)).toDouble();
          table += curve.firstWhere((p) => (p.$1 - (age + 5)).abs() < 1e-9).$2;
          n++;
        }
        expect(n, greaterThan(50));
        expect(
          100 * (table - cox) / n,
          closeTo(0, 0.5),
          reason: '$sex $lo-$hi',
        );
      }
    }
  });

  // The LifespanEstimate (the reveal) now comes from the yearly Cox projection; its tests
  // are in projection_lifespan_test.dart. The life-table calculation above is kept.

  test('the band factor outside 35–79 is the nearest band\'s', () {
    expect(
      bandLogAdjustment(LifespanSex.male, 18),
      bandLogAdjustmentMale.first,
    );
    expect(
      bandLogAdjustment(LifespanSex.male, 44.9),
      bandLogAdjustmentMale.first,
    );
    expect(bandLogAdjustment(LifespanSex.male, 45), bandLogAdjustmentMale[1]);
    expect(
      bandLogAdjustment(LifespanSex.female, 85),
      bandLogAdjustmentFemale.last,
    );
  });
}
