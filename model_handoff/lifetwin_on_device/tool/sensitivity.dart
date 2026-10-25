// Brute-force sensitivity scan of the packaged LifeTwin Cox model.
//
// Run from this package directory:
//   dart tool/sensitivity.dart [output.json]
// Default output: ../../docs/model-sensitivity.json (the repository docs/).
// Markdown tables for docs/model-sensitivity.md are printed to stdout.
//
// Every number comes from LifeTwinModel.predict(), the same code the app runs,
// including its validation and input-support check. Results are observational
// model contrasts at the 5-year horizon, not causal effects.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../lib/src/model.dart';

const horizon = '5';
const seed = 20261024;

typedef Profile = Map<String, dynamic>;

late LifeTwinModel model;
late Map<String, dynamic> spec;

/// 5-year survival in percent, or null when predict() does not return a
/// supported estimate. [reason] receives 'support' or 'invalid'.
double? s5(Profile p, [List<String>? reason]) {
  try {
    final r = model.predict(p);
    if (r['status'] != 'available') {
      reason?.add('support');
      return null;
    }
    return (r['survival_percent_by_year'] as Map<String, double>)[horizon];
  } on FormatException {
    reason?.add('invalid');
    return null;
  }
}

double score(Profile p) => model.predict(p)['log_relative_hazard_score'] as double;

// ---------------------------------------------------------------------------
// Profiles: decode the model's own support reference (2,000 encoded NHANES
// training profiles) back to raw inputs.

List<Profile> decodeReference(Float64List ref) {
  final rng = math.Random(seed);
  final rows = ref.length ~/ 17;
  final out = <Profile>[];
  double r(double v, [int digits = 6]) =>
      double.parse(v.toStringAsFixed(digits));
  for (var i = 0; i < rows; i++) {
    final x = List<double>.generate(17, (c) => ref[i * 17 + c]);
    double bmi;
    if (x[1] > 0) {
      bmi = 23 - 5 * x[1];
    } else if (x[2] > 0) {
      bmi = 27 + 5 * x[2];
    } else {
      // 23–27 is flat in the model and not recoverable; impute uniformly.
      bmi = 23 + 4 * rng.nextDouble();
    }
    double sleep;
    if (x[3] > 0) {
      sleep = 7 - x[3];
    } else if (x[4] > 0) {
      sleep = 8 + x[4];
    } else {
      // 7–8 h is flat; NHANES 2007–2012 sleep is whole hours.
      sleep = rng.nextBool() ? 7 : 8;
    }
    var health = 1;
    for (var l = 2; l <= 5; l++) {
      if (x[11 + l] == 1) health = l;
    }
    out.add({
      'age': r(55 + 10 * x[0], 3),
      'sex_nhanes': x[8] == 1 ? 2 : 1,
      'bmi': r(bmi, 3),
      'sleep_hours': r(sleep, 3),
      'smoking_status': x[10] == 1 ? 2 : (x[9] == 1 ? 1 : 0),
      'diabetes_diagnosed': x[11].round(),
      'hypertension_diagnosed': x[12].round(),
      'general_health': health,
      'vigorous_recreation_min_week': r(math.pow(76, x[5]) - 1, 2),
      'moderate_recreation_min_week': r(math.pow(151, x[6]) - 1, 2),
      'sedentary_min_day': r(x[7] * 120 + 360, 2),
    });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Levers. Each returns the perturbed profile, or null when it does not apply
// to this person (e.g. quitting for a never-smoker).

class Lever {
  Lever(this.id, this.label, this.kind, this.modifiable, this.apply,
      {this.recommendable = false, this.caution});
  final String id, label, kind; // kind: 'unit' or 'realistic'
  final bool modifiable, recommendable;
  final String? caution;
  final Profile? Function(Profile) apply;
}

Profile put(Profile p, String k, num v) => {...p, k: v};

final bmiCaution =
    'BMI terms: below 23 the model assigns higher hazard to lower BMI (likely illness-related weight loss); above 27 the fitted slope is near zero and slightly inverse. Neither is evidence that changing weight helps or harms.';
final longSleepCaution =
    'The long-sleep term (>8 h) is a strong association that may reflect existing illness; it is not evidence that sleeping less helps.';
final healthCaution =
    'Self-rated health is not a direct lever. "Very good" (2) is fitted lower-hazard than "excellent" (1), so 2->1 lowers modeled survival.';

List<Lever> levers() => [
      // Unit steps (finite-difference sensitivities).
      Lever('sleep_plus_1h', '+1 h sleep', 'unit', true,
          (p) => put(p, 'sleep_hours', p['sleep_hours'] + 1),
          caution: longSleepCaution),
      Lever('moderate_plus_30', '+30 min/week moderate', 'unit', true,
          (p) => put(p, 'moderate_recreation_min_week',
              p['moderate_recreation_min_week'] + 30)),
      Lever('vigorous_plus_30', '+30 min/week vigorous', 'unit', true,
          (p) => put(p, 'vigorous_recreation_min_week',
              p['vigorous_recreation_min_week'] + 30)),
      Lever('sitting_minus_60', '-60 min/day sitting', 'unit', true,
          (p) => put(p, 'sedentary_min_day', p['sedentary_min_day'] - 60)),
      Lever('bmi_plus_1', 'BMI +1', 'unit', true,
          (p) => put(p, 'bmi', p['bmi'] + 1),
          caution: bmiCaution),
      Lever('bmi_minus_1', 'BMI -1', 'unit', true,
          (p) => put(p, 'bmi', p['bmi'] - 1),
          caution: bmiCaution),
      Lever('smoking_current_to_former', 'Smoking current -> former', 'unit',
          true, (p) => p['smoking_status'] == 2 ? put(p, 'smoking_status', 1) : null),
      Lever('smoking_former_to_never', 'Smoking former -> never', 'unit', false,
          (p) => p['smoking_status'] == 1 ? put(p, 'smoking_status', 0) : null,
          caution: 'Not a reachable change: a former smoker cannot become a never smoker.'),
      Lever('health_one_level_better', 'General health one level better',
          'unit', false,
          (p) => p['general_health'] >= 2
              ? put(p, 'general_health', p['general_health'] - 1)
              : null,
          caution: healthCaution),
      Lever('diabetes_absent_vs_present', 'No diabetes vs diabetes', 'unit',
          false, (p) => null),
      Lever('hypertension_absent_vs_present',
          'No hypertension vs hypertension', 'unit', false, (p) => null),
      Lever('age_plus_1y', 'Age +1 year', 'unit', false,
          (p) => put(p, 'age', p['age'] + 1)),
      Lever('female_vs_male', 'Female vs male (same other inputs)', 'unit',
          false, (p) => null),
      // Realistic changes over a few months.
      Lever('quit_smoking', 'Quit smoking (current -> former)', 'realistic',
          true,
          (p) => p['smoking_status'] == 2 ? put(p, 'smoking_status', 1) : null,
          recommendable: true),
      Lever('moderate_plus_90', '+90 min/week moderate (3 x 30 min walks)',
          'realistic', true,
          (p) => put(p, 'moderate_recreation_min_week',
              p['moderate_recreation_min_week'] + 90),
          recommendable: true),
      Lever('vigorous_plus_60', '+60 min/week vigorous (2 x 30 min)',
          'realistic', true,
          (p) => put(p, 'vigorous_recreation_min_week',
              p['vigorous_recreation_min_week'] + 60),
          recommendable: true),
      Lever('sitting_minus_60_realistic',
          '-60 min/day awake sitting (if sitting >= 90)', 'realistic', true,
          (p) => p['sedentary_min_day'] >= 90
              ? put(p, 'sedentary_min_day', p['sedentary_min_day'] - 60)
              : null,
          recommendable: true),
      Lever('short_sleep_plus_1h', 'Short sleepers (<7 h): +1 h, max 7 h',
          'realistic', true,
          (p) => p['sleep_hours'] < 7
              ? put(p, 'sleep_hours', math.min(p['sleep_hours'] + 1, 7))
              : null,
          recommendable: true),
      Lever('long_sleep_minus_1h', 'Long sleepers (>8 h): -1 h, min 8 h',
          'realistic', true,
          (p) => p['sleep_hours'] > 8
              ? put(p, 'sleep_hours', math.max(p['sleep_hours'] - 1, 8))
              : null,
          caution: longSleepCaution),
      Lever('weight_minus_5pct_bmi27', 'BMI >= 27: lose 5% of body weight',
          'realistic', true,
          (p) => p['bmi'] >= 27 ? put(p, 'bmi', p['bmi'] * 0.95) : null,
          caution: bmiCaution),
    ];

/// Applies the special contrasts that evaluate both sides of a flag.
/// Returns [baseline, alternative] profiles; the effect is S(alt) - S(base).
List<Profile>? pairFor(Lever l, Profile p) {
  switch (l.id) {
    case 'diabetes_absent_vs_present':
      return [put(p, 'diabetes_diagnosed', 1), put(p, 'diabetes_diagnosed', 0)];
    case 'hypertension_absent_vs_present':
      return [
        put(p, 'hypertension_diagnosed', 1),
        put(p, 'hypertension_diagnosed', 0)
      ];
    case 'female_vs_male':
      return [put(p, 'sex_nhanes', 1), put(p, 'sex_nhanes', 2)];
  }
  final alt = l.apply(p);
  return alt == null ? null : [p, alt];
}

/// All recommendable realistic levers that apply, combined and re-evaluated.
Profile combined(Profile p, List<Lever> ls) {
  var q = p;
  for (final l in ls.where((l) => l.recommendable)) {
    final next = l.apply(q);
    if (next != null) q = next;
  }
  return q;
}

// ---------------------------------------------------------------------------
// Statistics.

double quantile(List<double> sorted, double q) {
  if (sorted.isEmpty) return double.nan;
  final pos = (sorted.length - 1) * q;
  final lo = pos.floor(), hi = pos.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

double r4(double v) => v.isNaN ? v : double.parse(v.toStringAsFixed(4));

class Cell {
  final effects = <double>[];
  final dLogHazard = <double>[];
  int notApplicable = 0, droppedSupport = 0, droppedInvalid = 0;
  int groupSize = 0;

  Map<String, dynamic> summary() {
    final s = [...effects]..sort();
    final h = [...dLogHazard]..sort();
    final n = s.length;
    return {
      'n_evaluated': n,
      'n_not_applicable': notApplicable,
      'n_dropped_outside_support': droppedSupport,
      'n_dropped_invalid_input': droppedInvalid,
      'share_applicable': groupSize == 0
          ? null
          : r4((n + droppedSupport + droppedInvalid) / groupSize),
      'median_pp': n == 0 ? null : r4(quantile(s, .5)),
      'q25_pp': n == 0 ? null : r4(quantile(s, .25)),
      'q75_pp': n == 0 ? null : r4(quantile(s, .75)),
      'iqr_pp': n == 0 ? null : r4(quantile(s, .75) - quantile(s, .25)),
      'min_pp': n == 0 ? null : r4(s.first),
      'max_pp': n == 0 ? null : r4(s.last),
      'share_favorable': n == 0
          ? null
          : r4(s.where((v) => v > 1e-9).length / n),
      'share_unfavorable': n == 0
          ? null
          : r4(s.where((v) => v < -1e-9).length / n),
      'median_delta_log_hazard': h.isEmpty ? null : r4(quantile(h, .5)),
      'population_mean_pp': groupSize == 0
          ? null
          : r4(s.fold<double>(0, (a, b) => a + b) / groupSize),
    };
  }
}

String band(num age) => age < 50 ? '35-49' : (age < 65 ? '50-64' : '65-79');
String sexName(num s) => s == 2 ? 'female' : 'male';

String f(double? v, [int d = 2]) => v == null ? '–' : v.toStringAsFixed(d);

// ---------------------------------------------------------------------------

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args[0] : '../../docs/model-sensitivity.json';
  spec = jsonDecode(File('assets/model.json').readAsStringSync())
      as Map<String, dynamic>;
  final bytes = Uint8List.fromList(
      File('assets/support_reference.f64').readAsBytesSync());
  model = LifeTwinModel.fromArtifacts(spec, bytes);

  // 0. Golden check: this script runs the same code as the checker.
  final golden =
      jsonDecode(File('test/golden_vectors.json').readAsStringSync()) as List;
  var goldenMax = 0.0;
  for (final g in golden) {
    final r = model.predict(Map<String, dynamic>.from(g['profile'] as Map));
    final exp = g['survival_probabilities'] as Map<String, dynamic>;
    final act = r['survival_probabilities'] as Map<String, double>;
    for (final y in exp.keys) {
      goldenMax = math.max(goldenMax, (act[y]! - (exp[y] as num)).abs());
    }
    goldenMax = math.max(
        goldenMax,
        ((r['log_relative_hazard_score'] as double) -
                (g['log_relative_hazard_score'] as num))
            .abs());
  }
  if (goldenMax > 1e-9) throw StateError('Golden mismatch $goldenMax');

  // 1. Profiles.
  final ref = Float64List.view(bytes.buffer);
  final decoded = decodeReference(ref);
  final base = <Profile>[];
  final baseS = <double>[];
  var excludedBase = 0;
  for (final p in decoded) {
    final v = s5(p);
    if (v == null) {
      excludedBase++;
    } else {
      base.add(p);
      baseS.add(v);
    }
  }

  // 2. Analytic Jacobian versus central finite differences.
  final coef = (spec['coefficients'] as List).map((e) => (e as num).toDouble()).toList();
  double analytic(int i, String k) {
    final p = base[i];
    final s = baseS[i] / 100;
    double dx; // d score / d input
    switch (k) {
      case 'age':
        dx = coef[0] / 10;
      case 'bmi':
        final b = p['bmi'] as num;
        dx = b < 23 ? -coef[1] / 5 : (b > 27 ? coef[2] / 5 : 0.0);
      case 'sleep_hours':
        final h = p['sleep_hours'] as num;
        dx = h < 7 ? -coef[3] : (h > 8 ? coef[4] : 0.0);
      case 'vigorous_recreation_min_week':
        dx = coef[5] / ((1 + p[k]) * math.log(76));
      case 'moderate_recreation_min_week':
        dx = coef[6] / ((1 + p[k]) * math.log(151));
      default:
        dx = coef[7] / 120;
    }
    return 100 * s * math.log(s) * dx; // pp per input unit
  }

  const hStep = 1e-4;
  var jacMaxAbs = 0.0, jacChecked = 0, jacSkipped = 0;
  for (var i = 0; i < base.length; i++) {
    final p = base[i];
    for (final k in [
      'age',
      'bmi',
      'sleep_hours',
      'vigorous_recreation_min_week',
      'moderate_recreation_min_week',
      'sedentary_min_day'
    ]) {
      final v = p[k] as num;
      final nearKink = (k == 'bmi' && ((v - 23).abs() < 1e-3 || (v - 27).abs() < 1e-3)) ||
          (k == 'sleep_hours' && ((v - 7).abs() < 1e-3 || (v - 8).abs() < 1e-3));
      final up = s5(put(p, k, v + hStep)), dn = s5(put(p, k, v - hStep));
      if (nearKink || up == null || dn == null) {
        jacSkipped++;
        continue;
      }
      final fd = (up - dn) / (2 * hStep);
      jacMaxAbs = math.max(jacMaxAbs, (fd - analytic(i, k)).abs());
      jacChecked++;
    }
  }

  // 3. Per-profile, per-lever scan.
  final ls = levers();
  final groups = <String, Map<String, Cell>>{};
  Cell cell(String g, String lever) =>
      (groups[g] ??= {})[lever] ??= Cell();
  final groupSizes = <String, int>{};
  List<String> groupKeys(Profile p) => [
        'all',
        'age:${band(p['age'])}',
        'sex:${sexName(p['sex_nhanes'])}',
        '${band(p['age'])}|${sexName(p['sex_nhanes'])}',
      ];
  for (final p in base) {
    for (final g in groupKeys(p)) {
      groupSizes[g] = (groupSizes[g] ?? 0) + 1;
    }
  }
  final allLeverIds = [...ls.map((l) => l.id), 'combined_recommendable'];
  // Interaction collectors.
  final quitByBand = <String, Cell>{};
  final modByBaseline = <String, Cell>{};
  final combinedVsSum = <String, List<double>>{'combined': [], 'sum': []};
  final riskDecile = <double, List<double>>{};
  // Non-monotonic responses, bucketed by the starting value.
  final shape = <String, Map<String, Cell>>{};
  String? shapeBucket(String id, Profile p) {
    switch (id) {
      case 'bmi_minus_1':
      case 'bmi_plus_1':
        final b = p['bmi'] as num;
        return b < 24 ? '<24' : (b <= 26 ? '24-26' : (b < 28 ? '26-28' : '>=28'));
      case 'sleep_plus_1h':
        final h = p['sleep_hours'] as num;
        return h < 6.5 ? '<=6' : (h < 7.5 ? '7' : (h < 8.5 ? '8' : '>=9'));
      case 'health_one_level_better':
        final g = p['general_health'] as num;
        return '$g->${g - 1}';
    }
    return null;
  }

  // Which recommendable realistic lever is each person's largest?
  final bestLever = <String, Map<String, int>>{};

  for (var i = 0; i < base.length; i++) {
    final p = base[i];
    final keys = groupKeys(p);
    for (final g in keys) {
      for (final id in allLeverIds) {
        cell(g, id).groupSize = groupSizes[g]!;
      }
    }
    final realisticEffects = <double>[];
    String? best;
    var bestEff = 1e-9;
    for (final l in ls) {
      final pair = pairFor(l, p);
      if (pair == null) {
        for (final g in keys) cell(g, l.id).notApplicable++;
        continue;
      }
      final why = <String>[];
      final a = s5(pair[0], why), b = s5(pair[1], why);
      if (a == null || b == null) {
        for (final g in keys) {
          if (why.contains('invalid')) {
            cell(g, l.id).droppedInvalid++;
          } else {
            cell(g, l.id).droppedSupport++;
          }
        }
        continue;
      }
      final eff = b - a;
      final dh = score(pair[1]) - score(pair[0]);
      for (final g in keys) {
        cell(g, l.id).effects.add(eff);
        cell(g, l.id).dLogHazard.add(dh);
      }
      if (l.kind == 'realistic' && l.recommendable) {
        realisticEffects.add(eff);
        if (eff > bestEff) {
          bestEff = eff;
          best = l.id;
        }
      }
      final sb = shapeBucket(l.id, p);
      if (sb != null) ((shape[l.id] ??= {})[sb] ??= Cell()).effects.add(eff);
      if (l.id == 'quit_smoking') {
        (quitByBand['${band(p['age'])}|${sexName(p['sex_nhanes'])}'] ??= Cell())
            .effects
            .add(eff);
      }
      if (l.id == 'moderate_plus_90') {
        final m = p['moderate_recreation_min_week'] as num;
        final k = m == 0
            ? '0'
            : (m < 60 ? '1-59' : (m < 150 ? '60-149' : (m < 300 ? '150-299' : '300+')));
        (modByBaseline[k] ??= Cell()).effects.add(eff);
      }
      if (l.id == 'vigorous_plus_60') {
        (riskDecile[100 - baseS[i]] ??= []).add(eff);
      }
    }
    for (final g in keys) {
      final m = bestLever[g] ??= {};
      m[best ?? 'none'] = (m[best ?? 'none'] ?? 0) + 1;
    }
    // Combined realistic, re-evaluated.
    final c = combined(p, ls);
    final why = <String>[];
    final cs = identical(c, p) ? null : s5(c, why);
    if (identical(c, p)) {
      for (final g in keys) cell(g, 'combined_recommendable').notApplicable++;
    } else if (cs == null) {
      for (final g in keys) {
        if (why.contains('invalid')) {
          cell(g, 'combined_recommendable').droppedInvalid++;
        } else {
          cell(g, 'combined_recommendable').droppedSupport++;
        }
      }
    } else {
      final eff = cs - baseS[i];
      for (final g in keys) {
        cell(g, 'combined_recommendable').effects.add(eff);
        cell(g, 'combined_recommendable').dLogHazard.add(score(c) - score(p));
      }
      combinedVsSum['combined']!.add(eff);
      combinedVsSum['sum']!.add(realisticEffects.fold(0.0, (a, b) => a + b));
    }
  }

  // 4. Smoking x age on fixed archetypes (only age varies).
  final archetype = <String, dynamic>{
    'sex_nhanes': 1,
    'bmi': 26,
    'sleep_hours': 7,
    'diabetes_diagnosed': 0,
    'hypertension_diagnosed': 0,
    'general_health': 3,
    'vigorous_recreation_min_week': 0,
    'moderate_recreation_min_week': 60,
    'sedentary_min_day': 420,
  };
  final smokingAge = <Map<String, dynamic>>[];
  for (final sex in [1, 2]) {
    for (final age in [35, 45, 55, 65, 75, 79]) {
      final cur = {...archetype, 'sex_nhanes': sex, 'age': age, 'smoking_status': 2};
      final a = s5(cur), b = s5(put(cur, 'smoking_status', 1));
      final m = s5(put(cur, 'moderate_recreation_min_week', 150));
      smokingAge.add({
        'sex': sexName(sex),
        'age': age,
        'baseline_5y_survival_pct': a == null ? null : r4(a),
        'quit_smoking_pp': a == null || b == null ? null : r4(b - a),
        'moderate_60_to_150_pp': a == null || m == null ? null : r4(m - a),
      });
    }
  }

  // 5. Assemble output.
  final leverMeta = {
    for (final l in ls)
      l.id: {
        'label': l.label,
        'kind': l.kind == 'unit' ? 'unit_step' : 'realistic_change',
        'modifiable': l.modifiable,
        'recommendable': l.recommendable,
        if (l.caution != null) 'caution': l.caution,
      },
    'combined_recommendable': {
      'label': 'All applicable recommendable realistic changes together',
      'kind': 'realistic_change',
      'modifiable': true,
      'recommendable': true,
    },
  };
  Map<String, dynamic> groupOut(String g) {
    final cells = groups[g]!;
    final stats = {for (final id in allLeverIds) id: cells[id]!.summary()};
    List<Map<String, dynamic>> rank(bool Function(String) keep) {
      final ids = allLeverIds
          .where(keep)
          .where((id) => stats[id]!['median_pp'] != null)
          .toList()
        ..sort((a, b) => (stats[b]!['median_pp'] as double)
            .compareTo(stats[a]!['median_pp'] as double));
      return [
        for (final id in ids) {'lever': id, ...stats[id]!}
      ];
    }

    return {
      'n_profiles': groupSizes[g],
      'median_baseline_5y_survival_pct': () {
        final xs = [
          for (var i = 0; i < base.length; i++)
            if (groupKeys(base[i]).contains(g)) baseS[i]
        ]..sort();
        return r4(quantile(xs, .5));
      }(),
      'recommendable_levers_ranked': rank((id) =>
          id != 'combined_recommendable' &&
          leverMeta[id]!['recommendable'] == true),
      'all_modifiable_ranked': rank((id) =>
          id != 'combined_recommendable' && leverMeta[id]!['modifiable'] == true),
      'non_modifiable_ranked': rank((id) => leverMeta[id]!['modifiable'] == false),
      'combined_recommendable': {'lever': 'combined_recommendable', ...stats['combined_recommendable']!},
      'share_whose_largest_recommendable_lever_is': {
        for (final e in bestLever[g]!.entries)
          e.key: r4(e.value / groupSizes[g]!)
      },
    };
  }

  final groupOrder = [
    'all',
    'age:35-49',
    'age:50-64',
    'age:65-79',
    'sex:male',
    'sex:female',
    for (final b in ['35-49', '50-64', '65-79'])
      for (final s in ['male', 'female']) '$b|$s',
  ];
  final cvsS = [...combinedVsSum['combined']!];
  final sumS = [...combinedVsSum['sum']!];
  final out = {
    'model_version': spec['model_version'],
    'generated_by': 'model_handoff/lifetwin_on_device/tool/sensitivity.dart',
    'horizon_years': 5,
    'units':
        'percentage points of modeled 5-year survival (positive = higher modeled survival)',
    'causal_interpretation': false,
    'interpretation':
        'Observational model contrasts between profiles at the 5-year horizon. Not the benefit of changing a habit, and never years of life gained.',
    'how_to_use':
        'Order candidate levers for a person by recommendable_levers_ranked for their age band and sex, then compute their own effect with LifeTwinModel.compare() before showing a number. Skip levers that do not apply to them.',
    'checks': {
      'golden_max_abs_error': goldenMax,
      'jacobian_points_checked': jacChecked,
      'jacobian_points_skipped_kink_or_support': jacSkipped,
      'jacobian_max_abs_error_pp_per_unit': jacMaxAbs,
    },
    'profiles': {
      'source':
          'assets/support_reference.f64 decoded to raw inputs (2,000 encoded NHANES training profiles); BMI in 23-27 imputed uniform, sleep in 7-8 h imputed as 7 or 8 (seeded)',
      'seed': seed,
      'n_decoded': decoded.length,
      'n_excluded_unsupported_baseline': excludedBase,
      'n_used': base.length,
      'age_bands': ['35-49', '50-64', '65-79'],
    },
    'levers': leverMeta,
    'groups': {for (final g in groupOrder) g: groupOut(g)},
    'interactions': {
      'quit_smoking_by_age_sex_population': {
        for (final e in quitByBand.entries) e.key: e.value.summary()
      },
      'smoking_by_age_archetype': {
        'fixed_inputs': archetype,
        'rows': smokingAge,
      },
      'moderate_plus_90_by_baseline_moderate_min_week': {
        for (final k in ['0', '1-59', '60-149', '150-299', '300+'])
          if (modByBaseline[k] != null) k: modByBaseline[k]!.summary()
      },
      'non_monotonic_by_starting_value': {
        for (final e in shape.entries)
          e.key: {for (final b in e.value.entries) b.key: b.value.summary()}
      },
      'combined_vs_sum_of_individual': {
        'n': cvsS.length,
        'median_combined_pp': r4(quantile([...cvsS]..sort(), .5)),
        'median_sum_of_individual_pp': r4(quantile([...sumS]..sort(), .5)),
        'median_ratio_combined_to_sum': r4(quantile(
            [
              for (var i = 0; i < cvsS.length; i++)
                if (sumS[i] > 1e-9) cvsS[i] / sumS[i]
            ]..sort(),
            .5)),
      },
    },
  };
  Object? clean(Object? v, String path) {
    if (v is double && !v.isFinite) {
      stderr.writeln('non-finite at $path');
      return null;
    }
    if (v is Map) return {for (final e in v.entries) e.key: clean(e.value, '$path.${e.key}')};
    if (v is List) return [for (var i = 0; i < v.length; i++) clean(v[i], '$path[$i]')];
    return v;
  }

  File(outPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(clean(out, r'$'))}\n');

  // 6. Markdown tables.
  final md = StringBuffer();
  md.writeln('<!-- generated by tool/sensitivity.dart -->');
  md.writeln(
      'Profiles: ${decoded.length} decoded, $excludedBase unsupported at baseline, ${base.length} used. Golden max error ${goldenMax.toStringAsExponential(1)}. Jacobian: $jacChecked points checked, $jacSkipped skipped, max |FD - analytic| ${jacMaxAbs.toStringAsExponential(1)} pp/unit.\n');
  String pct(bool Function(Profile) t) =>
      '${(base.where(t).length * 100 / base.length).round()}%';
  md.writeln('Coverage: current smokers ${pct((p) => p['smoking_status'] == 2)}, '
      'former ${pct((p) => p['smoking_status'] == 1)}, '
      'diabetes ${pct((p) => p['diabetes_diagnosed'] == 1)}, '
      'hypertension ${pct((p) => p['hypertension_diagnosed'] == 1)}, '
      'no moderate ${pct((p) => p['moderate_recreation_min_week'] == 0)}, '
      'no vigorous ${pct((p) => p['vigorous_recreation_min_week'] == 0)}, '
      'sleep <7 h ${pct((p) => p['sleep_hours'] < 7)}, '
      'BMI >= 30 ${pct((p) => p['bmi'] >= 30)}, '
      'BMI < 23 ${pct((p) => p['bmi'] < 23)}, '
      'health fair/poor ${pct((p) => p['general_health'] >= 4)}.\n');
  void table(String g, String title) {
    final cells = groups[g]!;
    md.writeln('#### $title (n=${groupSizes[g]})\n');
    md.writeln(
        '| Lever | Modifiable | Applies | Median pp | IQR (q25 to q75) | Favourable | Dropped (support/invalid) |');
    md.writeln('|---|---|---|---|---|---|---|');
    final ids = [...allLeverIds]..sort((a, b) {
        final ma = cells[a]!.summary()['median_pp'] as double? ?? -1e9;
        final mb = cells[b]!.summary()['median_pp'] as double? ?? -1e9;
        return mb.compareTo(ma);
      });
    for (final id in ids) {
      final s = cells[id]!.summary();
      md.writeln(
          '| ${leverMeta[id]!['label']} | ${leverMeta[id]!['modifiable'] == true ? 'yes' : 'no'} | ${s['n_evaluated']} | ${f(s['median_pp'] as double?)} | ${f(s['q25_pp'] as double?)} to ${f(s['q75_pp'] as double?)} | ${s['share_favorable'] == null ? '–' : '${((s['share_favorable'] as double) * 100).round()}%'} | ${s['n_dropped_outside_support']}/${s['n_dropped_invalid_input']} |');
    }
    md.writeln();
  }

  table('all', 'All profiles');
  // Compact matrix: median [q25, q75] per lever and group.
  const matrixGroups = [
    'age:35-49',
    'age:50-64',
    'age:65-79',
    'sex:male',
    'sex:female'
  ];
  md.writeln('#### Median pp [IQR] by age band and sex\n');
  md.writeln('| Lever | ${matrixGroups.join(' | ')} |');
  md.writeln('|---|${'---|' * matrixGroups.length}');
  final allSorted = [...allLeverIds]..sort((a, b) =>
      ((groups['all']![b]!.summary()['median_pp'] as double?) ?? -1e9)
          .compareTo((groups['all']![a]!.summary()['median_pp'] as double?) ?? -1e9));
  for (final id in allSorted) {
    md.writeln('| ${leverMeta[id]!['label']} | ' +
        matrixGroups.map((g) {
          final s = groups[g]![id]!.summary();
          if (s['median_pp'] == null) return '–';
          return '${f(s['median_pp'] as double?)} [${f(s['q25_pp'] as double?)}, ${f(s['q75_pp'] as double?)}]';
        }).join(' | ') +
        ' |');
  }
  md.writeln();
  md.writeln('#### Recommendable levers ranked by median pp\n');
  md.writeln('| Group | n | Median 5-y survival | 1st | 2nd | 3rd | 4th | 5th |');
  md.writeln('|---|---|---|---|---|---|---|---|');
  for (final g in groupOrder) {
    final o = groupOut(g);
    final r = (o['recommendable_levers_ranked'] as List).cast<Map>();
    md.writeln('| $g | ${o['n_profiles']} | ${f(o['median_baseline_5y_survival_pct'] as double, 1)}% | ' +
        [
          for (final x in r.take(5))
            '${leverMeta[x['lever']]!['label']} (${f(x['median_pp'] as double)})'
        ].join(' | ') +
        ' |');
  }
  md.writeln('\n#### Smoking x age archetype\n');
  md.writeln('| Sex | Age | Baseline 5-y % | Quit (pp) | Moderate 60->150 (pp) |');
  md.writeln('|---|---|---|---|---|');
  for (final r in smokingAge) {
    md.writeln(
        '| ${r['sex']} | ${r['age']} | ${f(r['baseline_5y_survival_pct'] as double?)} | ${f(r['quit_smoking_pp'] as double?)} | ${f(r['moderate_60_to_150_pp'] as double?)} |');
  }
  md.writeln('\n#### Quit smoking by age band and sex (population current smokers)\n');
  md.writeln('| Group | n | Median pp | IQR |');
  md.writeln('|---|---|---|---|');
  for (final b in ['35-49', '50-64', '65-79']) {
    for (final s in ['male', 'female']) {
      final c = quitByBand['$b|$s'];
      if (c == null) continue;
      final x = c.summary();
      md.writeln(
          '| $b $s | ${x['n_evaluated']} | ${f(x['median_pp'] as double?)} | ${f(x['q25_pp'] as double?)} to ${f(x['q75_pp'] as double?)} |');
    }
  }
  md.writeln('\n#### +90 min/week moderate by current moderate minutes\n');
  md.writeln('| Current min/week | n | Median pp | IQR |');
  md.writeln('|---|---|---|---|');
  for (final k in ['0', '1-59', '60-149', '150-299', '300+']) {
    final c = modByBaseline[k];
    if (c == null) continue;
    final x = c.summary();
    md.writeln(
        '| $k | ${x['n_evaluated']} | ${f(x['median_pp'] as double?)} | ${f(x['q25_pp'] as double?)} to ${f(x['q75_pp'] as double?)} |');
  }
  final ivs = out['interactions'] as Map;
  final cv = ivs['combined_vs_sum_of_individual'] as Map;
  md.writeln(
      '\nCombined vs sum (n=${cv['n']}): median combined ${f(cv['median_combined_pp'])} pp, median sum ${f(cv['median_sum_of_individual_pp'])} pp, median ratio ${f(cv['median_ratio_combined_to_sum'], 3)}.');
  // Risk dependence for one lever.
  final rk = riskDecile.keys.toList()..sort();
  final dec = <List<double>>[];
  for (var d = 0; d < 5; d++) {
    final part = rk.sublist(rk.length * d ~/ 5, rk.length * (d + 1) ~/ 5);
    dec.add([for (final k in part) ...riskDecile[k]!]..sort());
  }
  md.writeln('\n+60 min/week vigorous by baseline 5-year risk quintile: ' +
      [
        for (var d = 0; d < 5; d++)
          'Q${d + 1} median ${f(quantile(dec[d], .5))} pp'
      ].join('; '));
  md.writeln('\n#### Non-monotonic responses by starting value\n');
  md.writeln('| Step | Starting value | n | Median pp | IQR | Favourable |');
  md.writeln('|---|---|---|---|---|---|');
  for (final id in ['bmi_minus_1', 'bmi_plus_1', 'sleep_plus_1h', 'health_one_level_better']) {
    final m = shape[id]!;
    final ks = m.keys.toList()..sort();
    for (final k in ks) {
      final x = m[k]!.summary();
      md.writeln(
          '| ${leverMeta[id]!['label']} | $k | ${x['n_evaluated']} | ${f(x['median_pp'] as double?)} | ${f(x['q25_pp'] as double?)} to ${f(x['q75_pp'] as double?)} | ${((x['share_favorable'] as double) * 100).round()}% |');
    }
  }
  md.writeln('\n#### Share of people whose largest recommendable lever is X\n');
  final bestIds = [
    ...ls.where((l) => l.recommendable).map((l) => l.id),
    'none'
  ];
  md.writeln('| Group | ' +
      bestIds.map((id) => id == 'none' ? 'none' : leverMeta[id]!['label']).join(' | ') +
      ' |');
  md.writeln('|---|${'---|' * bestIds.length}');
  for (final g in groupOrder) {
    final m = bestLever[g]!;
    md.writeln('| $g | ' +
        bestIds
            .map((id) => '${((m[id] ?? 0) * 100 / groupSizes[g]!).round()}%')
            .join(' | ') +
        ' |');
  }
  stdout.write(md);
}
