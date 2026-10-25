import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/forecast/forecast_client.dart';
import 'package:lifesim/forecast/forecast_screen.dart' show unsupportedSentence;
import 'package:lifesim/twin/profile_mapping.dart';
import 'package:lifesim/twin/twin_model.dart';

/// The app profile (app field names) that should map to a golden model profile.
Map<String, dynamic> appProfileFor(Map<String, dynamic> g, {bool healthAsWord = false}) {
  const height = 175.0;
  return {
    'age': g['age'],
    'sex': g['sex_nhanes'] == 1 ? 'male' : 'female',
    'height_cm': height,
    'weight_kg': (g['bmi'] as num) * math.pow(height / 100, 2),
    'sleep_hours': g['sleep_hours'],
    'smoking_status': const ['never', 'former', 'current'][g['smoking_status'] as int],
    'diabetes': g['diabetes_diagnosed'] == 1,
    'hypertension_diagnosed': g['hypertension_diagnosed'] == 1,
    'general_health': healthAsWord
        ? const ['excellent', 'very_good', 'good', 'fair', 'poor'][(g['general_health'] as int) - 1]
        : g['general_health'],
    'vigorous_recreation_min_week': g['vigorous_recreation_min_week'],
    'moderate_recreation_min_week': g['moderate_recreation_min_week'],
    'sedentary_min_day': g['sedentary_min_day'],
    // Not model inputs: kept in the profile, never sent to the model.
    'alcohol_drinks_weekly': 3,
    'systolic_bp': 120,
    'diastolic_bp': 80,
    'exercise_minutes_weekly': 999,
  };
}

/// What the current onboarding collects (no sitting, high blood pressure, general health,
/// or hard/moderate split).
const onboardingToday = {
  'age': 45,
  'sex': 'female',
  'height_cm': 165,
  'weight_kg': 68,
  'sleep_hours': 7,
  'exercise_minutes_weekly': 150,
  'smoking_status': 'never',
  'alcohol_drinks_weekly': 2,
  'diabetes': false,
  'systolic_bp': 120,
  'diastolic_bp': 80,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());

  test('the model loads once from the package assets', () {
    expect(model.modelVersion, 'personal-cox-bmi35-v3-20261024');
  });

  test('exact codes: sex_nhanes, smoking, diabetes, hypertension, general health', () {
    final p = toModelProfile({
      'age': 50,
      'sex': 'female',
      'smoking_status': 'former',
      'diabetes': true,
      'hypertension_diagnosed': false,
      'general_health': 'very good',
    });
    expect(p, {
      'age': 50,
      'sex_nhanes': 2,
      'smoking_status': 1,
      'diabetes_diagnosed': 1,
      'hypertension_diagnosed': 0,
      'general_health': 2,
    });
    expect(toModelProfile({'sex': 'male', 'smoking_status': 'current'}), {'sex_nhanes': 1, 'smoking_status': 2});
    expect(toModelProfile({'smoking_status': 'never', 'general_health': 5}), {
      'smoking_status': 0,
      'general_health': 5,
    });
  });

  test('the golden vectors come out exactly through the app mapping', () {
    final golden = jsonDecode(File('packages/lifetwin_on_device/test/golden_vectors.json').readAsStringSync()) as List;
    for (final (i, row) in golden.indexed) {
      final g = Map<String, dynamic>.from(row['profile'] as Map);
      final a = model.assess(appProfileFor(g, healthAsWord: i.isOdd));
      expect(a.status, 'available');
      final expected = row['survival_probabilities'] as Map<String, dynamic>;
      for (final e in expected.entries) {
        expect(a.survivalByYear[int.parse(e.key)], closeTo((e.value as num).toDouble(), 1e-9));
      }
      expect(a.profileUsed.keys.toSet(), modelInputs.toSet());
      expect((a.profileUsed['bmi'] as num).toDouble(), closeTo((g['bmi'] as num).toDouble(), 1e-9));
    }
  });

  test('today\'s onboarding answers: missing_inputs, no number, nothing filled in', () {
    final a = model.assess(onboardingToday);
    expect(a.status, 'missing_inputs');
    expect(a.missingInputs, [
      'vigorous_recreation_min_week',
      'moderate_recreation_min_week',
      'sedentary_min_day',
      'hypertension_diagnosed',
      'general_health',
    ]);
    expect(a.percentByYear, isEmpty);
    expect(a.message, 'Complete every model input to show annual survival percentages.');
    expect(a.wellnessState, 'needs_input');
    // The single exercise answer is not split into hard and moderate minutes.
    expect(a.profileUsed.containsKey('moderate_recreation_min_week'), isFalse);
    final f = Forecast.fromAssessment(a);
    expect(f.supported, isFalse);
    expect(f.survival, isEmpty);
    expect(f.curve, isEmpty);
    expect(
      unsupportedSentence(f),
      "I can't make a forecast for you yet. Complete every model input to show annual survival percentages. "
      'Still needed: hard exercise each week, moderate exercise each week, time spent sitting each day, '
      'being told you have high blood pressure and how you rate your health.',
    );
  });

  test('"not sure", a lone height, or an unknown word is left out, never guessed', () {
    final p = toModelProfile({
      'smoking_status': 'unknown',
      'height_cm': 170,
      'general_health': 'meh',
      'diabetes': null,
    });
    expect(p, isEmpty);
    final a = model.assess({...appProfileFor(_golden0()), 'smoking_status': 'unknown', 'weight_kg': null});
    expect(a.missingInputs, ['bmi', 'smoking_status']);
  });

  test('exactly one model input missing: missing_inputs naming it, and no number', () {
    final complete = appProfileFor(_golden0());
    // Each package input and the app field(s) that carry it.
    const carriers = {
      'age': ['age'],
      'bmi': ['weight_kg'],
      'sleep_hours': ['sleep_hours'],
      'vigorous_recreation_min_week': ['vigorous_recreation_min_week'],
      'moderate_recreation_min_week': ['moderate_recreation_min_week'],
      'sedentary_min_day': ['sedentary_min_day'],
      'sex_nhanes': ['sex'],
      'smoking_status': ['smoking_status'],
      'diabetes_diagnosed': ['diabetes'],
      'hypertension_diagnosed': ['hypertension_diagnosed'],
      'general_health': ['general_health'],
    };
    expect(carriers.keys.toSet(), modelInputs.toSet());
    for (final MapEntry(key: input, value: fields) in carriers.entries) {
      final p = {...complete}..removeWhere((k, _) => fields.contains(k));
      final a = model.assess(p);
      expect(a.status, 'missing_inputs', reason: input);
      expect(a.missingInputs, [input], reason: input);
      expect(a.percentByYear, isEmpty, reason: input);
      expect(Forecast.fromAssessment(a).supported, isFalse, reason: input);
    }
  });

  test('hypertension_diagnosed wins over the hypertension alias', () {
    expect(toModelProfile({'hypertension_diagnosed': false, 'hypertension': true})['hypertension_diagnosed'], 0);
    expect(toModelProfile({'hypertension_diagnosed': true, 'hypertension': false})['hypertension_diagnosed'], 1);
    expect(toModelProfile({'hypertension': true})['hypertension_diagnosed'], 1);
  });

  test('a fractional general health or a numeric string is left out, not guessed', () {
    expect(toModelProfile({'general_health': 2.6}), isEmpty);
    expect(toModelProfile({'general_health': '2'}), isEmpty);
    expect(toModelProfile({'age': '70'}), isEmpty);
    expect(toModelProfile({'sleep_hours': '7', 'height_cm': '175', 'weight_kg': 70}), isEmpty);
    expect(toModelProfile({'diabetes': 'no', 'hypertension_diagnosed': 2}), isEmpty);
  });

  test('a value the package refuses asks for a correction, with no number', () {
    final a = model.assess({...appProfileFor(_golden0()), 'height_cm': 60});
    expect(a.status, 'invalid_input');
    expect(a.invalidInput, 'bmi');
    expect(a.message, 'Your answer for height and weight is outside what the model can read. Please check it.');
    expect(a.percentByYear, isEmpty);
  });

  test('over 85: no number', () {
    for (final age in [86]) {
      final a = model.assess({...appProfileFor(_golden0()), 'age': age});
      expect(a.status, 'unsupported_age');
      expect(a.message, 'Annual estimates support ages 18–85 only.');
      expect(a.percentByYear, isEmpty);
    }
  });

  test('under 18: under_age, no number', () {
    final a = model.assess({...appProfileFor(_golden0()), 'age': 17});
    expect(a.status, 'under_age');
    expect(a.message, underAgeMessage);
    expect(a.percentByYear, isEmpty);
    expect(a.healthScoreStatus, HealthScoreStatus.underAge);
  });

  test('18–34 and 80–85 give a number flagged extrapolated, with the caveat', () {
    for (final age in [18, 25, 30, 34, 80, 85]) {
      final a = model.assess({...appProfileFor(_golden0()), 'age': age});
      expect(a.status, 'available', reason: 'age $age');
      expect(a.extrapolated, isTrue);
      expect(a.raw['extrapolation_caveat'], extrapolationCaveat);
      expect(a.profileUsed['age'], age); // the real age, not the anchor
      final f = Forecast.fromAssessment(a);
      expect(f.supported && f.extrapolated, isTrue);
    }
    expect(
      extrapolationCaveat,
      'Your age is outside the ages this model was checked on (35–79), so treat this as a rough guide.',
    );
    final inside = model.assess(appProfileFor(_golden0()));
    expect(inside.extrapolated, isFalse);
    expect(inside.raw.containsKey('extrapolation_caveat'), isFalse);
  });

  test('an 84-year-old is not clamped to 79: lower survival, along the model\'s own age term', () {
    final p = appProfileFor(_golden0());
    final at79 = model.assess({...p, 'age': 79}), at84 = model.assess({...p, 'age': 84});
    for (var y = 1; y <= 5; y++) {
      expect(at84.survivalByYear[y]!, lessThan(at79.survivalByYear[y]!));
    }
    // Moving the age term inside the checked range matches the package itself (79 -> 70).
    final spec = model.engine.model.spec;
    final coefficient = ((spec['coefficients'] as List).first as num).toDouble();
    final at70 = model.assess({...p, 'age': 70});
    final score70 = (at79.survival['log_relative_hazard_score'] as num) + coefficient * (70 - 79) / 10;
    expect(at70.survival['log_relative_hazard_score'], closeTo(score70, 1e-12));
    final score84 = (at79.survival['log_relative_hazard_score'] as num) + coefficient * (84 - 79) / 10;
    final base5 = ((spec['baseline_survival'] as List).last as num).toDouble();
    expect(at84.survivalByYear[5], closeTo(math.pow(base5, math.exp(score84)).toDouble(), 1e-12));
  });

  test('outside the age range, the other support checks still apply', () {
    // The package's entry ranges still reject a bad value at 84.
    expect(model.assess({...appProfileFor(_golden0()), 'age': 84, 'sleep_hours': 1}).status, 'invalid_input');
    // Missing inputs still come first.
    expect(model.assess({'age': 84, 'sex': 'male'}).status, 'missing_inputs');
  });

  test('the forecast never carries a death date or years gained', () {
    final a = model.assess(appProfileFor(_golden0()));
    expect(a.survival['death_date'], isNull);
    expect(a.survival['estimated_age_at_death'], isNull);
    final f = Forecast.fromAssessment(a);
    expect(f.curve.first, (years: 0.0, survival: 1.0));
    expect(f.curve.map((p) => p.years), [0, 1, 2, 3, 4, 5]);
    expect(f.outOf100(5), 99);
    expect(a.wellnessCards.every((c) => c.sourceUrl.startsWith('https://www.cdc.gov/')), isTrue);
  });
}

Map<String, dynamic> _golden0() => {
  'age': 45,
  'sex_nhanes': 1,
  'bmi': 25,
  'sleep_hours': 7,
  'smoking_status': 0,
  'diabetes_diagnosed': 0,
  'hypertension_diagnosed': 0,
  'general_health': 2,
  'vigorous_recreation_min_week': 60,
  'moderate_recreation_min_week': 120,
  'sedentary_min_day': 360,
};
