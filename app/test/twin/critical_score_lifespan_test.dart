// Adversarial tests for the health score, its age-group percentile and the lifespan
// estimate, written from the product rules: higher score = better, ages 18-85 supported
// and rougher outside 35-79, no guessed sex, a rough year and range but never a date.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/lifespan.dart';
import 'package:lifesim/twin/twin_model.dart';

import 'store_and_checkin_test.dart' show fullProfile;

/// A strict expected failure (like pytest's xfail): the body must FAIL today.
void knownBug(String name, String reason, dynamic Function() body) {
  test('BUG (xfail) $name: $reason', () async {
    var failed = false;
    try {
      await body();
    } on TestFailure {
      failed = true;
    }
    if (!failed) {
      fail('XPASS: the bug looks fixed; remove knownBug for "$name"');
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  late Map<String, dynamic> readme;
  setUpAll(() async {
    model = await TwinModelService.load();
    final golden = jsonDecode(
      File('test/twin/lifespan_golden.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    readme = Map<String, dynamic>.from(
      (golden['profiles'] as List).cast<Map<String, dynamic>>().firstWhere(
            (p) => p['name'] == 'male_45_readme',
          )['profile']
          as Map,
    );
  });

  Map<String, dynamic> person({
    int age = 60,
    String? sex = 'male',
    Map<String, dynamic> change = const {},
  }) =>
      {...fullProfile, 'age': age, 'sex': sex, ...change}
        ..removeWhere((_, v) => v == null);

  group('health score status by age', () {
    test('every age from 0 to 120 gets exactly the documented status', () {
      for (var age = 0; age <= 120; age++) {
        final a = model.assess(person(age: age));
        final HealthScoreStatus want;
        if (age < 18) {
          want = HealthScoreStatus.underAge;
        } else if (age > 85) {
          want = HealthScoreStatus.unsupportedAge;
        } else if (age < 35 || age > 79) {
          want = HealthScoreStatus.extrapolated;
        } else {
          want = HealthScoreStatus.available;
        }
        expect(a.healthScoreStatus, want, reason: 'age $age');
        expect(
          a.healthScore != null,
          want.hasScore,
          reason: 'age $age has a number only when supported',
        );
        expect(
          a.extrapolated,
          want == HealthScoreStatus.extrapolated,
          reason: 'age $age',
        );
        if (!want.hasScore) {
          expect(a.ageGroupPercentile, isNull, reason: 'age $age');
          expect(a.survivalByYear, isEmpty, reason: 'age $age');
          expect(a.message, isNotEmpty);
        }
      }
    });

    test('an age that is not a whole number in range never yields a score or throws', () {
      for (final age in [
        -1,
        double.nan,
        double.infinity,
        '45',
        null,
        true,
        1e9,
      ]) {
        final a = model.assess({...fullProfile, 'age': age});
        expect(a.healthScore, isNull, reason: 'age $age');
        expect(a.healthScoreStatus.hasScore, isFalse, reason: 'age $age');
      }
    });

    test('out-of-range heights, weights and sleep are invalid or unsupported, never a number', () {
      for (final change in <Map<String, dynamic>>[
        {'height_cm': 0},
        {'height_cm': -170},
        {'weight_kg': -5},
        {'weight_kg': 0},
        {'height_cm': 1e9, 'weight_kg': 1e9},
        {'sleep_hours': 99},
        {'sleep_hours': -3},
        {'sedentary_min_day': 100000},
        {'vigorous_recreation_min_week': -60},
        {'moderate_recreation_min_week': 1e12},
      ]) {
        final a = model.assess(person(change: change));
        expect(a.healthScore, isNull, reason: '$change');
        expect(a.healthScoreStatus.hasScore, isFalse, reason: '$change');
        expect(a.message, isNotEmpty, reason: '$change');
      }
    });
  });

  group('sex is never guessed', () {
    for (final sex in [
      'intersex',
      'prefer_not_to_say',
      'prefer not to say',
      'other',
      'Male',
      'FEMALE',
      '',
      'm',
      0,
      1,
      true,
    ]) {
      test(
        'sex ${jsonEncode(sex)} is left out and the score says it is missing',
        () {
          final a = model.assess({...fullProfile, 'age': 60, 'sex': sex});
          expect(a.healthScoreStatus, HealthScoreStatus.missingInputs);
          expect(a.healthScore, isNull);
          expect(a.missingInputs, contains('sex_nhanes'));
          expect(a.profileUsed['sex_nhanes'], isNull);
          expect(a.ageGroupPercentile, isNull);
        },
      );
    }

    test('a missing sex gives no number and no age-group comparison', () {
      final a = model.assess(person(sex: null));
      expect(a.healthScore, isNull);
      expect(a.missingInputs, ['sex_nhanes']);
      expect(a.ageGroupPercentile, isNull);
      expect(a.survivalByYear, isEmpty);
    });

    test('lifespan has no estimate without a sex, and never picks one', () {
      final noSex = {...readme}..remove('sex_nhanes');
      expect(LifespanEstimate.forProfile(noSex, currentYear: 2026, lab: model.projection), isNull);
      for (final bad in [0, 3, '1', 'male', null, 1.5]) {
        expect(
          LifespanEstimate.forProfile({
            ...readme,
            'sex_nhanes': bad,
          }, currentYear: 2026, lab: model.projection),
          isNull,
          reason: 'sex_nhanes $bad',
        );
      }
    });
  });

  group('health score direction: higher is better', () {
    final worsenings = <String, Map<String, dynamic>>{
      'smoking never -> current': {'smoking_status': 'current'},
      'smoking never -> former': {'smoking_status': 'former'},
      'diabetes no -> yes': {'diabetes': true},
      'sitting 360 -> 900 min a day': {'sedentary_min_day': 900},
      'general health very good -> poor': {'general_health': 5},
      'high blood pressure diagnosed': {'hypertension_diagnosed': true},
      'no hard exercise': {'vigorous_recreation_min_week': 0},
      'no moderate exercise': {'moderate_recreation_min_week': 0},
    };
    for (final entry in worsenings.entries) {
      test('${entry.key} never raises the score or the percentile', () {
        for (final sex in ['male', 'female']) {
          for (final age in [30, 40, 55, 65, 75, 82]) {
            final base = model.assess(person(age: age, sex: sex));
            final worse = model.assess(
              person(age: age, sex: sex, change: entry.value),
            );
            expect(base.healthScore, isNotNull);
            expect(worse.healthScore, isNotNull);
            expect(
              worse.healthScore!,
              lessThanOrEqualTo(base.healthScore!),
              reason: '$sex $age ${entry.key}',
            );
            if (base.ageGroupPercentile != null &&
                worse.ageGroupPercentile != null) {
              expect(
                worse.ageGroupPercentile!,
                lessThanOrEqualTo(base.ageGroupPercentile!),
                reason: '$sex $age ${entry.key}',
              );
            }
          }
        }
      });
    }

    test(
      'current smoking is clearly worse than never smoking, not merely equal',
      () {
        for (final sex in ['male', 'female']) {
          final never = model.assess(person(age: 60, sex: sex));
          final current = model.assess(
            person(age: 60, sex: sex, change: {'smoking_status': 'current'}),
          );
          expect(current.healthScore!, lessThan(never.healthScore!));
          expect(
            current.ageGroupPercentile!,
            lessThan(never.ageGroupPercentile!),
          );
          // Survival is the other face of the same fact.
          expect(
            current.survivalByYear[5]!,
            lessThan(never.survivalByYear[5]!),
          );
        }
      },
    );

    test('the raw model value rises with age; the score (centred) is relative to the age group', () {
      for (final sex in ['male', 'female']) {
        double? last;
        for (final age in [20, 30, 40, 50, 60, 70, 80, 85]) {
          final a = model.assess(person(age: age, sex: sex));
          // The score is centred on people of the same age and sex, so it does not
          // fall with age by itself; the raw Cox value (age term included) does rise.
          expect(a.healthScore!.isFinite, isTrue);
          if (a.healthScore != 0) expect(a.healthScore! > 0, a.ageGroupPercentile! > 50);
          if (last != null) {
            expect(a.rawLogRelativeHazard!, greaterThan(last), reason: '$sex $age');
          }
          last = a.rawLogRelativeHazard;
        }
      }
    });
  });

  group('age-group percentile', () {
    test(
      'stays between 0 and 100 for every supported age, sex and habit mix',
      () {
        final mixes = <Map<String, dynamic>>[
          {},
          {
            'smoking_status': 'current',
            'diabetes': true,
            'general_health': 5,
            'sedentary_min_day': 1000,
          },
          {
            'vigorous_recreation_min_week': 600,
            'moderate_recreation_min_week': 900,
            'general_health': 1,
          },
          {'bmi_dummy': null, 'height_cm': 150, 'weight_kg': 120},
          {'sleep_hours': 4},
          {'sleep_hours': 11},
        ];
        for (var age = 18; age <= 85; age++) {
          for (final sex in ['male', 'female']) {
            for (final mix in mixes) {
              final a = model.assess(person(age: age, sex: sex, change: mix));
              final p = a.ageGroupPercentile;
              if (!a.healthScoreStatus.hasScore) continue;
              if (a.survival['status'] != 'available') continue;
              expect(p, isNotNull, reason: '$sex $age $mix');
              expect(p!, inInclusiveRange(0, 100), reason: '$sex $age $mix');
              expect(p.isFinite, isTrue);
              expect(a.ageGroupSize!, greaterThan(0), reason: '$sex $age');
            }
          }
        }
      },
    );

    test(
      'compares people of the same age band and widens only when too few',
      () {
        final a = model.assess(person(age: 60));
        expect(a.ageGroupWidth, isIn([5, 7, 10]));
        expect(
          a.ageGroupBand,
          '${60 - a.ageGroupWidth!}–${60 + a.ageGroupWidth!}',
        );
        expect(a.ageGroupNearestBand, isFalse);
        expect(
          a.ageGroupSize!,
          greaterThanOrEqualTo(AgeGroupReference.minPeople),
        );
      },
    );

    test('outside 35-79 the nearest band inside it is used and said so', () {
      for (final age in [18, 25, 34, 80, 85]) {
        final a = model.assess(person(age: age));
        if (a.ageGroupPercentile == null) continue;
        expect(a.ageGroupNearestBand, isTrue, reason: 'age $age');
        final band = a.ageGroupBand!.split('–').map(int.parse).toList();
        expect(band.first, greaterThanOrEqualTo(35));
        expect(band.last, lessThanOrEqualTo(79));
      }
    });

    test('the other sex does not change the comparison group', () {
      final male = model.assess(person(age: 55, sex: 'male'));
      final female = model.assess(person(age: 55, sex: 'female'));
      expect(male.ageGroupSize, isNot(equals(0)));
      expect(female.ageGroupSize, isNot(equals(0)));
      // Same person except sex: both are compared only with their own sex, so the
      // percentile is not forced to be the same, and each is a valid share.
      expect(male.ageGroupPercentile!, inInclusiveRange(0, 100));
      expect(female.ageGroupPercentile!, inInclusiveRange(0, 100));
    });
  });

  group('lifespan estimate', () {
    LifespanEstimate estimate(Map<String, dynamic> p, {int year = 2026}) =>
        LifespanEstimate.forProfile(p, currentYear: year, lab: model.projection)!;

    final dateLike = RegExp(
      r'\b(19|20|21)\d{2}-\d{2}-\d{2}\b|\b(january|february|march|april|may|june|july|august|september|october|november|december)\b|\b\d{1,2}/\d{1,2}/\d{2,4}\b',
      caseSensitive: false,
    );

    test('a rough year and range for every supported age and sex, ordered and sane', () {
      for (var age = 18; age <= 85; age++) {
        for (final sex in [1, 2]) {
          final e = estimate({...readme, 'age': age, 'sex_nhanes': sex});
          final reason = 'age $age sex $sex';
          expect(e.p25Age, lessThanOrEqualTo(e.expectedAge), reason: reason);
          expect(e.expectedAge, lessThanOrEqualTo(e.p75Age), reason: reason);
          expect(e.expectedAge, greaterThan(age), reason: reason);
          expect(e.p25Age, greaterThanOrEqualTo(age), reason: reason);
          expect(e.p75Age, lessThan(121), reason: reason);
          expect(e.expectedYear, greaterThan(2026), reason: reason);
          expect(e.expectedYear, lessThan(2026 + 100), reason: reason);
          // Rough guide where the life table has the larger weight in the seam blend
          // (owner ruling): ages 18-39 and 75-85.
          expect(e.extrapolated, lifespanProjectionWeight(age) < 0.5, reason: reason);
          expect(e.caveat, contains('rough'), reason: reason);
          expect(
            e.caveat.contains('even rougher'),
            e.extrapolated,
            reason: reason,
          );
        }
      }
    });

    test(
      'the wording is a rough age and range, never a date, never certain',
      () {
        for (var age = 18; age <= 85; age += 3) {
          final e = estimate({...readme, 'age': age});
          for (final text in [
            e.headline,
            e.caveat,
            lifespanRoughEstimateNote,
          ]) {
            expect(dateLike.hasMatch(text), isFalse, reason: text);
            expect(
              text,
              isNot(
                matches(
                  RegExp(
                    r'\b(will|definitely|guarantee|promise|die[sd]?|death)\b',
                    caseSensitive: false,
                  ),
                ),
              ),
            );
          }
          expect(e.headline, contains('likely'));
          expect(e.headline, contains('about'));
          expect(e.headline, contains('Most people like you'));
          // The only years in the headline are ages.
          final numbers = RegExp(r'\d+')
              .allMatches(e.headline)
              .map((m) => int.parse(m.group(0)!));
          expect(
            numbers.every((n) => n >= age && n <= 120),
            isTrue,
            reason: e.headline,
          );
        }
      },
    );

    test('the response object carries no exact date at all', () {
      final e = estimate(readme);
      final everything = [
        e.headline,
        e.caveat,
        '${e.expectedYear}',
        ...e.annualCurve.map((p) => '${p.age} ${p.survivalPercent}'),
      ];
      expect(dateLike.hasMatch(everything.join(' ')), isFalse);
      expect(e.expectedYear, isA<int>());
    });

    test('a smoker never out-lives an otherwise identical non-smoker', () {
      for (var age = 18; age <= 85; age++) {
        for (final sex in [1, 2]) {
          final never = estimate({
            ...readme,
            'age': age,
            'sex_nhanes': sex,
            'smoking_status': 0,
          });
          final former = estimate({
            ...readme,
            'age': age,
            'sex_nhanes': sex,
            'smoking_status': 1,
          });
          final current = estimate({
            ...readme,
            'age': age,
            'sex_nhanes': sex,
            'smoking_status': 2,
          });
          expect(
            current.expectedAge,
            lessThanOrEqualTo(never.expectedAge),
            reason: 'age $age sex $sex',
          );
          expect(
            current.p25Age,
            lessThanOrEqualTo(never.p25Age),
            reason: 'age $age sex $sex',
          );
          expect(
            current.expectedAge,
            lessThanOrEqualTo(former.expectedAge),
            reason: 'age $age sex $sex',
          );
        }
      }
    });

    test(
      'diabetes, poor health and heavy sitting never raise the expected age',
      () {
        for (var age = 18; age <= 85; age += 1) {
          final base = estimate({...readme, 'age': age});
          for (final change in <Map<String, dynamic>>[
            {'diabetes_diagnosed': 1},
            {'general_health': 5},
            {'sedentary_min_day': 900},
          ]) {
            final worse = estimate({...readme, 'age': age, ...change});
            expect(
              worse.expectedAge,
              lessThanOrEqualTo(base.expectedAge),
              reason: 'age $age $change',
            );
          }
        }
      },
    );

    // Owner choices "Projection with fixes" and "blend the seams": the life table below 35
    // and from 79, the yearly Cox projection at 45-70, blended linearly in between. No
    // one-year step is now over 3 years (largest 2.3), but the projection sits 12-22 years
    // above the life table, so across 35-45 the remaining years still grow (readme male:
    // 47.8 at 35, 53.1 at 40, 57.3 at 45) and across 70-79 the expected age falls
    // (103.8 at 70, 98.9 at 75). The rule this test states still does not hold.
    knownBug(
      'lifespan seams',
      'the blended projection/life-table seams (35-45, 70-79): remaining years rise, expected age falls',
      () {
      double? lastAge, lastRemaining;
      for (var age = 20; age <= 85; age += 5) {
        final e = estimate({...readme, 'age': age});
        if (lastAge != null) {
          expect(
            e.expectedAge,
            greaterThanOrEqualTo(lastAge),
            reason: 'age $age',
          );
          expect(
            e.expectedAge - age,
            lessThan(lastRemaining!),
            reason: 'age $age',
          );
        }
        lastAge = e.expectedAge;
        lastRemaining = e.expectedAge - age;
      }
    });

    test(
      'under 18, over 85, non-numbers and incomplete profiles have no estimate',
      () {
        for (final age in [0, 10, 17, 86, 100, -1, double.nan, '45', null]) {
          expect(
            LifespanEstimate.forProfile({
              ...readme,
              'age': age,
            }, currentYear: 2026, lab: model.projection),
            isNull,
            reason: 'age $age',
          );
        }
        for (final key in [
          'bmi',
          'sleep_hours',
          'smoking_status',
          'diabetes_diagnosed',
          'general_health',
          'sedentary_min_day',
        ]) {
          final missing = {...readme}..remove(key);
          expect(
            LifespanEstimate.forProfile(missing, currentYear: 2026, lab: model.projection),
            isNull,
            reason: 'missing $key',
          );
        }
      },
    );

    test('every profile the model accepts, even an extreme one, gets a finite ordered estimate', () {
      var accepted = 0;
      for (final change in <Map<String, dynamic>>[
        {'height_cm': 150, 'weight_kg': 130},
        {'height_cm': 190, 'weight_kg': 50},
        {'sleep_hours': 4},
        {'sleep_hours': 11},
        {'sedentary_min_day': 1300},
        {'sedentary_min_day': 0},
        {
          'vigorous_recreation_min_week': 1200,
          'moderate_recreation_min_week': 1200,
        },
        {
          'smoking_status': 'current',
          'diabetes': true,
          'general_health': 5,
          'hypertension_diagnosed': true,
        },
      ]) {
        for (final age in [18, 34, 35, 79, 80, 85]) {
          for (final sex in ['male', 'female']) {
            final a = model.assess(person(age: age, sex: sex, change: change));
            if (a.rawLogRelativeHazard == null) continue;
            accepted++;
            LifespanEstimate? e;
            expect(
              () => e = LifespanEstimate.forProfile(
                a.profileUsed,
                currentYear: 2026,
                lab: model.projection,
              ),
              returnsNormally,
              reason: '$sex $age $change',
            );
            expect(e, isNotNull, reason: '$sex $age $change');
            expect(
              e!.expectedAge.isFinite &&
                  e!.p25Age.isFinite &&
                  e!.p75Age.isFinite,
              isTrue,
            );
            expect(
              e!.p25Age,
              lessThanOrEqualTo(e!.expectedAge),
              reason: '$sex $age $change',
            );
            expect(
              e!.expectedAge,
              lessThanOrEqualTo(e!.p75Age),
              reason: '$sex $age $change',
            );
            expect(
              e!.expectedAge,
              greaterThan(age),
              reason: '$sex $age $change',
            );
          }
        }
      }
      expect(
        accepted,
        greaterThan(20),
        reason: 'the sweep must really exercise accepted profiles',
      );
    });
  });
}
