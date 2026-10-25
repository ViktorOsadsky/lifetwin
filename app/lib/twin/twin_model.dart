import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipDecoder;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:lifetwin_on_device/lifetwin_on_device.dart';

import 'profile_mapping.dart';

/// Typed reading of one `LifeTwinEngine.assess()` result. The raw map is kept as it
/// came, so `profile_used` and `input_provenance` are preserved for the UI.
class TwinAssessment {
  TwinAssessment(this.raw)
    : survival = Map<String, dynamic>.from(raw['survival'] as Map? ?? const {}),
      invalidInput = null;

  /// A profile value the package refused (`FormatException`): ask the person to correct
  /// it. Never shown as a number.
  TwinAssessment.invalid(String message, {this.invalidInput})
    : raw = const {},
      survival = {'status': 'invalid_input', 'message': message};

  final Map<String, dynamic> raw;
  final Map<String, dynamic> survival;

  /// The model input the package refused, by its package name, when it could be told.
  final String? invalidInput;

  /// `available`, `missing_inputs`, `unsupported_age`, `under_age`, `unsupported_profile`, or the
  /// app's own `invalid_input`.
  String get status => survival['status'] as String? ?? 'invalid_input';
  bool get available => status == 'available';

  /// The package's status message, shown instead of a number when not [available].
  String? get message => survival['message'] as String?;

  /// Package input names (e.g. `sedentary_min_day`, `bmi`) still needed.
  List<String> get missingInputs => [for (final m in survival['missing_inputs'] as List? ?? const []) '$m'];
  List<String> get supportIssues => [for (final m in survival['support_issues'] as List? ?? const []) '$m'];

  String get modelVersion => survival['model_version'] as String? ?? '';
  String? get interpretation => survival['interpretation'] as String?;

  /// Cumulative survival 0..1 through years 1–5; empty unless [available].
  Map<int, double> get survivalByYear => yearMap(survival['survival_probabilities']);

  /// The same in percent, as the package gives it; empty unless [available].
  Map<int, double> get percentByYear => yearMap(survival['survival_percent_by_year']);

  Map<String, dynamic> get profileUsed => Map<String, dynamic>.from(raw['profile_used'] as Map? ?? const {});
  Map<String, dynamic> get inputProvenance => Map<String, dynamic>.from(raw['input_provenance'] as Map? ?? const {});

  /// `profile_snapshot`, `daily_logs` or `weekly_summaries`.
  String get source => inputProvenance['source'] as String? ?? 'profile_snapshot';

  Map<String, dynamic> get avatar => Map<String, dynamic>.from(raw['avatar'] as Map? ?? const {});
  List<String> get strengths => [for (final s in avatar['strengths'] as List? ?? const []) '$s'];
  List<String> get opportunities => [for (final s in avatar['opportunities'] as List? ?? const []) '$s'];

  /// Owner ruling (2026-10-24): 1 or 2 of the 11 inputs are missing, and the number is a ROUGH,
  /// flagged estimate marginalised over people of the same sex and age in the survey (see
  /// [TwinModelService.roughMissingMax]). [missingInputs] still lists what is missing.
  bool get roughMissing => raw['rough_missing'] == true;

  /// [missingInputs].length: the answers the estimate still needs.
  int get missingCount => missingInputs.length;

  /// The age is 18–34 or 80–85, outside the ages the model was checked on; numbers are a
  /// rough guide and carry [extrapolationCaveat].
  bool get extrapolated => raw['extrapolated'] == true;

  /// The model owner's own number, `log_relative_hazard_score`, exactly as the model
  /// gives it (for ages 18–34 and 80–85, the same extrapolated score the forecast uses).
  /// Lower is lower modelled risk, 0 is the average survey participant, and it includes
  /// the age and sex terms. Null unless the model gave a number; never filled in.
  double? get rawLogRelativeHazard {
    final s = survival['log_relative_hazard_score'];
    return available && s is num ? s.toDouble() : null;
  }

  /// The health score shown to the person, CENTRED ON 0 (owner: "i wish health score would
  /// be positive if it is good"): `median s of the age group − s`, where s is the Cox log
  /// relative hazard without the age and sex terms, over exactly the rows and band that
  /// [ageGroupPercentile] ranks (see [AgeGroup.medianScore]). 0 is the middle of people your
  /// age and sex in the survey; POSITIVE IS HEALTHIER than typical, negative less healthy;
  /// above 0 exactly when the percentile is above 50 (a tie at the median gives 0). It is
  /// the log of a ratio of modelled hazards, not a probability. Ages 18–34 and 80–85 use the
  /// percentile's extrapolation and carry its [extrapolated] ("Rough guide") flag. Null
  /// unless the model gave a number ([rawLogRelativeHazard]); never filled in.
  double? get healthScore {
    final h = (raw['age_group'] as Map?)?['health_score'];
    return rawLogRelativeHazard != null && h is double && h.isFinite ? h : null;
  }

  /// The group [healthScore] and [ageGroupPercentile] compare with, as the band actually
  /// used, e.g. `women 59–69`. Null whenever [healthScore] is null.
  String? get healthGroupLabel => healthScore == null ? null : (raw['age_group'] as Map?)?['label'] as String?;

  HealthScoreStatus get healthScoreStatus => switch (status) {
    'available' when roughMissing => HealthScoreStatus.roughMissing,
    'available' => extrapolated ? HealthScoreStatus.extrapolated : HealthScoreStatus.available,
    'missing_inputs' => HealthScoreStatus.missingInputs,
    'unsupported_age' => HealthScoreStatus.unsupportedAge,
    'under_age' => HealthScoreStatus.underAge,
    'unsupported_profile' => HealthScoreStatus.unsupportedProfile,
    _ => HealthScoreStatus.invalidInput,
  };

  /// How healthy the person is relative to people like them in the survey: the share
  /// (0–100) of the package's reference people of the same sex and age band whose score is
  /// HIGHER (worse), both scored without the age and sex terms. 70 means "healthier than 70
  /// of 100 people like you in the survey". The reference is unweighted survey
  /// participants, not a national population. Null when there is no [healthScore].
  double? get ageGroupPercentile => (raw['age_group'] as Map?)?['percentile'] as double?;

  /// The number of reference people compared.
  int? get ageGroupSize => (raw['age_group'] as Map?)?['size'] as int?;

  /// The reference ages compared, e.g. `40–50`.
  String? get ageGroupBand {
    final g = raw['age_group'] as Map?;
    return g == null ? null : '${g['band_low']}–${g['band_high']}';
  }

  /// The half-width used: 5, widened to 7 then 10 when fewer than 50 people fit.
  int? get ageGroupWidth => (raw['age_group'] as Map?)?['width'] as int?;

  /// True when the age is outside 35–79 and the nearest band inside it was used.
  bool? get ageGroupNearestBand => (raw['age_group'] as Map?)?['nearest_band'] as bool?;

  /// `steady`, `explore_changes` or `needs_input`.
  String get wellnessState => avatar['wellness_state'] as String? ?? 'needs_input';

  List<WellnessCard> get wellnessCards => [
    for (final c in raw['wellness_cards'] as List? ?? const [])
      if (c is Map) WellnessCard.fromJson(Map<String, dynamic>.from(c)),
  ];

  /// "Modeled survival of similar people" (the package's display rule).
  static const survivalTitle = 'Modeled survival of similar people';

  /// "Modeled difference between profiles".
  static const scenarioTitle = 'Modeled difference between profiles';

  /// `{'1': x, …}` → `{1: x, …}`.
  static Map<int, double> yearMap(Object? m) => {
    if (m is Map)
      for (final e in m.entries)
        if (int.tryParse('${e.key}') != null && e.value is num) int.parse('${e.key}'): (e.value as num).toDouble(),
  };
}

/// Why the health score has, or lacks, a number. `extrapolated` has a number (age 30–34
/// or 80–85, a rough guide); the others have none. `underAge` is under 18. `invalidInput` is the app's own status
/// for a value the package refused.
enum HealthScoreStatus {
  available('available'),
  extrapolated('extrapolated'),

  /// 1 or 2 inputs missing: a rough number, marginalised over similar survey people, flagged.
  roughMissing('rough_missing'),
  missingInputs('missing_inputs'),
  unsupportedAge('unsupported_age'),
  underAge('under_age'),
  unsupportedProfile('unsupported_profile'),
  invalidInput('invalid_input');

  const HealthScoreStatus(this.wire);

  /// The name stored in the score history.
  final String wire;

  bool get hasScore => this == available || this == extrapolated || this == roughMissing;

  static HealthScoreStatus fromWire(Object? v) => values.firstWhere((s) => s.wire == v, orElse: () => invalidInput);
}

/// A public-health guidance card from the package, shown beside the twin with its
/// source link. Not derived from the survival model.
class WellnessCard {
  const WellnessCard({
    required this.id,
    required this.level,
    required this.title,
    required this.message,
    required this.sourceUrl,
  });

  factory WellnessCard.fromJson(Map<String, dynamic> j) => WellnessCard(
    id: '${j['id']}',
    level: '${j['level']}',
    title: '${j['title']}',
    message: '${j['message']}',
    sourceUrl: '${j['source_url']}',
  );

  /// `smoking`, `activity`, `sleep`, `sitting`, `sitting_trend`, `bmi`, `adult_guidance_scope`.
  final String id;

  /// `strength`, `opportunity` or `info`.
  final String level;
  final String title;
  final String message;
  final String sourceUrl;
}

/// The engine (and scale) of the health score: the centred Cox score ([AgeGroup.healthScore]).
/// Stored on every score history point; readers keep only this engine's points, so scales
/// never mix (earlier `cox_index_v1` and untagged points are left out).
const healthScoreEngine = 'cox_centered_bmi35_v2';

/// The tag a history point stored before the engine tag existed reads as: the earlier
/// −(Cox log relative hazard) scale, which readers leave out.
const legacyHealthScoreEngine = 'cox_v1';

/// Shown with a compare() whose only change is a higher BMI ([TwinModelService.compare]).
const weightGuardWarning =
    'A higher weight is never shown as a benefit: the model\'s BMI link is not evidence that '
    'gaining weight helps.';

/// Owner ruling: "it is okay to extrapolate a bit below and above the age ranges".
const extrapolatedAgeRange = (low: 18, high: 85);
const checkedAgeRange = (low: 35, high: 79);
const extrapolationCaveat =
    'Your age is outside the ages this model was checked on (35–79), so treat this as a rough guide.';
const unsupportedAgeMessage = 'Annual estimates support ages 18–85 only.';
const underAgeMessage = 'LifeTwin estimates are for adults, ages 18 and over.';
const underAge = 18;

/// The checked age the package is run at for an extrapolated [age]; null when [age] needs
/// no extrapolation (inside 35–79, outside 18–85, or not a number).
num? anchorAge(Object? age) {
  if (age is! num) return null;
  if (age >= extrapolatedAgeRange.low && age < checkedAgeRange.low) return checkedAgeRange.low;
  if (age > checkedAgeRange.high && age <= extrapolatedAgeRange.high) return checkedAgeRange.high;
  return null;
}

/// The model, loaded once at startup, and the one place the app calls it.
///
/// Ages 18–34 and 80–85 (owner ruling) go through a narrow wrapper around the copied
/// package, which itself accepts only 35–79. The package runs at the nearest checked age
/// (35 or 79), so every other check (missing inputs, entry ranges, the 1st–99th percentile
/// support and the nearest-neighbour support) still applies unchanged. Then only the age
/// term is moved to the person's real age with the model's own coefficient:
/// `score += coefficient[age_decade] * (age - anchor) / 10`, `S(t) = baseline(t)^exp(score)`.
/// The age is not clamped, so an 84-year-old is not shown a 79-year-old's survival.
class TwinModelService {
  TwinModelService(this.engine, {Float64List? reference, this.projection})
    : _ageGroups = reference == null
          ? null
          : AgeGroupReference(
              reference,
              [for (final c in engine.model.spec['coefficients'] as List) (c as num).toDouble()],
              [for (final c in engine.model.spec['feature_center'] as List) (c as num).toDouble()],
            ),
      _ageCoefficient = ((engine.model.spec['coefficients'] as List).first as num).toDouble(),
      _baseline = [for (final b in engine.model.spec['baseline_survival'] as List) (b as num).toDouble()],
      _horizons = [for (final h in engine.model.spec['horizons_years'] as List) '$h'] {
    if ((engine.model.spec['encoded_features'] as List).first != 'age_decade') {
      throw const FormatException('The model no longer starts with age_decade; review the age extrapolation');
    }
  }

  final LifeTwinEngine engine;

  /// The handoff's projection lab, used only for the lifespan estimate's yearly Cox curve
  /// (lifespan.dart). Nothing in the app reads its neural output. Null: no estimate.
  final LifeTwinProjectionLab? projection;
  final AgeGroupReference? _ageGroups;
  final double _ageCoefficient;
  final List<double> _baseline;
  final List<String> _horizons;

  static Future<TwinModelService> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final engine = LifeTwinEngine(await loadLifeTwinModel(bundle: bundle));
    final projection = await loadLifeTwinProjectionLab(bundle: assets, cox: engine.model);
    final data = await assets.load('packages/lifetwin_on_device/assets/support_reference.f64.gz');
    final bytes = Uint8List.fromList(
      const GZipDecoder().decodeBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)),
    );
    final reference = Float64List(bytes.lengthInBytes ~/ 8);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < reference.length; i++) {
      reference[i] = view.getFloat64(i * 8, Endian.little);
    }
    return TwinModelService(engine, reference: reference, projection: projection);
  }

  String get modelVersion => engine.model.spec['model_version'] as String;

  /// Assesses the confirmed app profile. [window] is `{'daily_logs': [...]}` or
  /// `{'weekly_summaries': [...]}` (see twin_history.dart), or empty for a snapshot.
  TwinAssessment assess(Map<String, dynamic> appProfile, {Map<String, dynamic> window = const {}, DateTime? asOf}) =>
      assessModel(toModelProfile(appProfile), window: window, asOf: asOf);

  /// Assesses an already mapped model profile. With 1 or 2 inputs missing, a rough, flagged
  /// estimate ([_roughMissing]); with more, none.
  TwinAssessment assessModel(
    Map<String, dynamic> modelProfile, {
    Map<String, dynamic> window = const {},
    DateTime? asOf,
  }) {
    final a = _assessModel(modelProfile, window: window, asOf: asOf);
    return a.status == 'missing_inputs' ? _roughMissing(a, modelProfile, window: window, asOf: asOf) : a;
  }

  /// Owner ruling (2026-10-24): with at most this many of the 11 inputs missing, a rough estimate.
  static const roughMissingMax = 2;

  /// The fewest same-sex people of nearby ages a rough estimate averages over (the band widens
  /// ±5, ±7, ±10 years as the percentile's does; with fewer still, no estimate).
  static const roughMinPeople = 30;

  /// The 1 or 2 missing inputs are MARGINALISED over the reference people of the person's sex
  /// and age band ([AgeGroupReference.band]): for each of them only the missing inputs take that
  /// person's values, and the Cox hazards are averaged (mean of exp(score), then log). Never a
  /// single typical or healthy value. Age and sex must be known (they choose the band).
  ///
  /// Done as one ordinary assessment of the profile filled with a real reference person's
  /// values (the placeholder), then shifted by
  /// `Δ = log mean_r exp(Σ_c β_c (x_rc − x_0c))` over the missing inputs' columns c. The score
  /// is linear in the columns, so this equals the mean of the hazards: the score gets `+Δ`,
  /// survival `S^exp(Δ)`, and the percentile and centred score are re-ranked. The placeholder
  /// never shows: `profile_used` stays the person's own answers, `missing_inputs` stays the
  /// list, and `rough_fill` / `rough_shift` carry what the lifespan needs.
  TwinAssessment _roughMissing(
    TwinAssessment partial,
    Map<String, dynamic> modelProfile, {
    Map<String, dynamic> window = const {},
    DateTime? asOf,
  }) {
    final ref = _ageGroups, missing = partial.missingInputs;
    final age = modelProfile['age'], sex = modelProfile['sex_nhanes'];
    if (ref == null ||
        !_roughEncoding ||
        missing.isEmpty ||
        missing.length > roughMissingMax ||
        age is! num ||
        sex is! num ||
        age < underAge ||
        age > extrapolatedAgeRange.high ||
        missing.any((m) => !roughColumns.containsKey(m))) {
      return partial;
    }
    final rows = ref.band(age: age, female: sex == 2, minPeople: roughMinPeople);
    if (rows == null) return partial;
    final cols = [for (final m in missing) ...roughColumns[m]!];
    // Placeholders from a few real reference people, in case one is outside the model's support.
    for (final r0 in rows.take(5)) {
      final fill = {for (final m in missing) m: ref.decode(r0, m)};
      final TwinAssessment f;
      try {
        f = _assessModel({...modelProfile, ...fill}, window: window, asOf: asOf);
      } on FormatException {
        continue;
      }
      final score = f.survival['log_relative_hazard_score'];
      if (!f.available || score is! num) continue;
      var sum = 0.0;
      for (final r in rows) {
        var d = 0.0;
        for (final c in cols) {
          d += _coefficients[c] * (ref.value(r, c) - ref.value(r0, c));
        }
        sum += math.exp(d.clamp(-40, 40));
      }
      final shift = math.log(sum / rows.length);
      final moved = score + shift;
      return TwinAssessment({
        ...partial.raw,
        'survival': {..._shifted(f.survival, shift), 'missing_inputs': missing},
        if (f.extrapolated) 'extrapolated': true,
        if (f.extrapolated) 'extrapolation_caveat': extrapolationCaveat,
        'age_group': ref.compare(score: moved, age: age, female: sex == 2).toJson(),
        'rough_missing': true,
        'rough_people': rows.length,
        'rough_fill': fill,
        'rough_shift': shift,
      });
    }
    return partial;
  }

  /// An available [survival] with its hazard multiplied by exp([shift]).
  static Map<String, dynamic> _shifted(Map survival, double shift) {
    final out = Map<String, dynamic>.from(survival);
    if (survival['status'] != 'available') return out;
    final power = math.exp(shift);
    final fractions = {
      for (final e in (survival['survival_probabilities'] as Map).entries)
        '${e.key}': math.pow((e.value as num).toDouble(), power).toDouble(),
    };
    return {
      ...out,
      'log_relative_hazard_score': (survival['log_relative_hazard_score'] as num) + shift,
      'survival_probabilities': fractions,
      'survival_percent_by_year': {for (final e in fractions.entries) e.key: 100 * e.value},
      'rough_missing': true,
    };
  }

  /// The encoded columns of each model input that can be marginalised (the package's
  /// `encoded_features` order, checked by [_roughEncoding]). Age and sex choose the band.
  static const roughColumns = <String, List<int>>{
    'bmi': [1, 2],
    'sleep_hours': [3, 4],
    'vigorous_recreation_min_week': [5],
    'moderate_recreation_min_week': [6],
    'sedentary_min_day': [7],
    'smoking_status': [9, 10],
    'diabetes_diagnosed': [11],
    'hypertension_diagnosed': [12],
    'general_health': [13, 14, 15, 16],
  };
  static const _roughFeatures = [
    'age_decade', 'bmi_below23', 'bmi_above35', 'sleep_below7', 'sleep_above8', 'vigorous_log', //
    'moderate_log', 'sedentary_120', 'female', 'former_smoker', 'current_smoker', 'diabetes', //
    'hypertension', 'health_2', 'health_3', 'health_4', 'health_5', //
  ];
  late final bool _roughEncoding = () {
    final f = engine.model.spec['encoded_features'] as List;
    if (f.length != _roughFeatures.length) return false;
    for (var i = 0; i < f.length; i++) {
      if (f[i] != _roughFeatures[i]) return false;
    }
    return true;
  }();
  late final List<double> _coefficients = [
    for (final c in engine.model.spec['coefficients'] as List) (c as num).toDouble(),
  ];

  TwinAssessment _assessModel(
    Map<String, dynamic> modelProfile, {
    Map<String, dynamic> window = const {},
    DateTime? asOf,
  }) {
    final age = modelProfile['age'];
    final anchor = anchorAge(age);
    final request = <String, dynamic>{
      'profile': anchor == null ? modelProfile : {...modelProfile, 'age': anchor},
      ...window,
    };
    if (asOf != null) request['as_of_date'] = isoDate(asOf);
    try {
      final raw = engine.assess(request);
      if (anchor == null) {
        final survival = _ageMessage(raw['survival'] as Map, age);
        return TwinAssessment({...raw, 'survival': survival, ..._ageGroup(survival, modelProfile)});
      }
      // The guidance cards change only at ages 18, 61 and 65, which no anchor crosses.
      final survival = _moveAge(raw['survival'] as Map, from: anchor, to: age as num);
      return TwinAssessment({
        ...raw,
        'profile_used': {...raw['profile_used'] as Map<String, dynamic>, 'age': age},
        'survival': survival,
        'extrapolated': true,
        'extrapolation_caveat': extrapolationCaveat,
        ..._ageGroup(survival, modelProfile),
      });
    } on FormatException catch (e) {
      return invalidAssessment(e);
    }
  }

  /// `LifeTwinEngine.compare()` with the same age extrapolation. Request and result have
  /// the package's shapes, plus `extrapolated` and `extrapolation_caveat`.
  ///
  /// Weight guard (model card: BMI is flat from 23 to 35 and the positive fitted
  /// association above 35 is not a causal weight-change effect): when the only change is a higher BMI
  /// (`bmi`, or `height_cm`/`weight_kg`), the alternative's survival is the current one and
  /// the modelled difference is zero in every year, with `weight_guard: true` and
  /// [weightGuardWarning]. Every experiment, plan and recommendation goes through here.
  ///
  /// Also `health_score_current`, `health_score_alternative` (each side's
  /// [TwinAssessment.healthScore]) and `health_score_delta` = alternative − current: the
  /// experiment's score change (null when either side has no score; 0 under the guard).
  Map<String, dynamic> compare(Map<String, dynamic> request) {
    final current = Map<String, dynamic>.from(request['current_profile'] as Map);
    final missing = [
      for (final k in modelInputs)
        if (k == 'bmi' ? bmiOf(current) == null : current[k] == null) k,
    ];
    if (missing.isEmpty || missing.length > roughMissingMax) return _compareFull(request);
    return _roughCompare(current, Map<String, dynamic>.from(request['alternative_profile'] as Map), missing);
  }

  /// [compare] with 1 or 2 inputs missing: both sides get the same placeholder and shift
  /// ([_roughMissing]), so only the moved levers differ. A missing input cannot be moved: an
  /// alternative that sets one has no number.
  Map<String, dynamic> _roughCompare(
    Map<String, dynamic> current,
    Map<String, dynamic> alternative,
    List<String> missing,
  ) {
    final a = assessModel(current);
    final fill = a.raw['rough_fill'], shift = a.raw['rough_shift'];
    if (!a.roughMissing || fill is! Map || shift is! double || missing.any((m) => alternative[m] != null)) {
      final none = {
        'status': 'missing_inputs',
        'missing_inputs': missing,
        'message': 'Complete every model input to show annual survival percentages.',
      };
      return {
        'current': a.roughMissing ? a.survival : none,
        'alternative': none,
        'modeled_difference_percentage_points': null,
        'health_score_current': a.healthScore,
        'health_score_alternative': null,
        'health_score_delta': null,
        'warnings': const <String>[],
        'rough_missing': true,
      };
    }
    final r = _compareFull({
      'current_profile': {...current, ...fill},
      'alternative_profile': {...alternative, ...fill},
    });
    final cur = {..._shifted(r['current'] as Map, shift), 'missing_inputs': missing};
    final alt = {..._shifted(r['alternative'] as Map, shift), 'missing_inputs': missing};
    Map<String, double>? difference;
    if (cur['status'] == 'available' && alt['status'] == 'available') {
      final p = cur['survival_probabilities'] as Map, q = alt['survival_probabilities'] as Map;
      difference = {
        for (final y in p.keys) '$y': r['weight_guard'] == true ? 0.0 : 100 * ((q[y] as double) - (p[y] as double)),
      };
    }
    final now = _healthScore(cur, current);
    final then = r['weight_guard'] == true ? now : _healthScore(alt, alternative);
    return {
      ...r,
      'current': cur,
      'alternative': alt,
      'modeled_difference_percentage_points': difference,
      'health_score_current': now,
      'health_score_alternative': then,
      'health_score_delta': now == null || then == null ? null : then - now,
      'rough_missing': true,
    };
  }

  Map<String, dynamic> _compareFull(Map<String, dynamic> request) {
    var result = _compare(request);
    final current = request['current_profile'] as Map, alternative = request['alternative_profile'] as Map;
    final difference = result['modeled_difference_percentage_points'];
    final guarded = difference is Map && _onlyHigherBmi(current, alternative);
    if (guarded) {
      result = {
        ...result,
        'alternative': Map<String, dynamic>.from(result['current'] as Map),
        'modeled_difference_percentage_points': {for (final y in difference.keys) '$y': 0.0},
        'weight_guard': true,
        'warnings': [...result['warnings'] as List? ?? const [], weightGuardWarning],
      };
    }
    final now = _healthScore(result['current'] as Map, current);
    final then = guarded ? now : _healthScore(result['alternative'] as Map, alternative);
    return {
      ...result,
      'health_score_current': now,
      'health_score_alternative': then,
      'health_score_delta': now == null || then == null ? null : (guarded ? 0.0 : then - now),
    };
  }

  /// The centred health score for a compare() side: its moved score against [profile]'s age group.
  double? _healthScore(Map survival, Map profile) {
    final score = survival['log_relative_hazard_score'];
    final age = profile['age'], sex = profile['sex_nhanes'];
    if (survival['status'] != 'available' || score is! num || age is! num || sex is! num || _ageGroups == null) {
      return null;
    }
    final h = _ageGroups.compare(score: score.toDouble(), age: age, female: sex == 2).healthScore;
    return h.isFinite ? h : null;
  }

  /// True when [b] differs from [a] only in weight, height or BMI, and its BMI is higher.
  static bool _onlyHigherBmi(Map a, Map b) {
    const bmiKeys = {'bmi', 'height_cm', 'weight_kg'};
    final others = {...a.keys, ...b.keys}.where((k) => !bmiKeys.contains(k) && a[k] != b[k]);
    final before = bmiOf(a), after = bmiOf(b);
    return others.isEmpty && before != null && after != null && after > before;
  }

  /// `bmi`, else weight / height² from `height_cm` and `weight_kg`; null without either.
  static double? bmiOf(Map p) {
    final bmi = p['bmi'], h = p['height_cm'], w = p['weight_kg'];
    if (bmi is num) return bmi.toDouble();
    if (h is num && w is num && h > 0) return w / ((h / 100) * (h / 100));
    return null;
  }

  Map<String, dynamic> _compare(Map<String, dynamic> request) {
    final current = Map<String, dynamic>.from(request['current_profile'] as Map);
    final alternative = Map<String, dynamic>.from(request['alternative_profile'] as Map);
    final a = anchorAge(current['age']), b = anchorAge(alternative['age']);
    final c = engine.compare({
      'current_profile': a == null ? current : {...current, 'age': a},
      'alternative_profile': b == null ? alternative : {...alternative, 'age': b},
    });
    if (a == null && b == null) {
      return {
        ...c,
        'current': _ageMessage(c['current'] as Map, current['age']),
        'alternative': _ageMessage(c['alternative'] as Map, alternative['age']),
      };
    }
    final first = a == null
        ? _ageMessage(c['current'] as Map, current['age'])
        : _moveAge(c['current'] as Map, from: a, to: current['age'] as num);
    final second = b == null
        ? _ageMessage(c['alternative'] as Map, alternative['age'])
        : _moveAge(c['alternative'] as Map, from: b, to: alternative['age'] as num);
    Map<String, double>? difference;
    if (first['status'] == 'available' && second['status'] == 'available') {
      final p = first['survival_probabilities'] as Map<String, double>;
      final q = second['survival_probabilities'] as Map<String, double>;
      difference = {for (final y in p.keys) y: 100 * (q[y]! - p[y]!)};
    }
    return {
      ...c,
      'current': first,
      'alternative': second,
      'changed_features': [
        for (final k in modelInputs)
          if (current[k] != alternative[k]) k,
      ],
      'modeled_difference_percentage_points': difference,
      'extrapolated': true,
      'extrapolation_caveat': extrapolationCaveat,
    };
  }

  /// The app supports 18–85, so its own message replaces the package's "35–79 only"; under
  /// 18 the status is `under_age`.
  Map<String, dynamic> _ageMessage(Map survival, Object? age) {
    final out = Map<String, dynamic>.from(survival);
    if (survival['status'] == 'unsupported_age') {
      final under = age is num && age < underAge;
      out['status'] = under ? 'under_age' : 'unsupported_age';
      out['message'] = under ? underAgeMessage : unsupportedAgeMessage;
    }
    return out;
  }

  /// `{'age_group': …}` for an available [survival], else nothing.
  Map<String, dynamic> _ageGroup(Map survival, Map<String, dynamic> modelProfile) {
    final score = survival['log_relative_hazard_score'];
    final age = modelProfile['age'], sex = modelProfile['sex_nhanes'];
    if (survival['status'] != 'available' || score is! num || age is! num || sex is! num || _ageGroups == null) {
      return const {};
    }
    return {'age_group': _ageGroups.compare(score: score.toDouble(), age: age, female: sex == 2).toJson()};
  }

  /// The package's survival at the anchor age, moved to the real age along the age term.
  Map<String, dynamic> _moveAge(Map survival, {required num from, required num to}) {
    final out = {...Map<String, dynamic>.from(survival), 'extrapolated': true};
    if (survival['status'] != 'available') return out;
    final score = (survival['log_relative_hazard_score'] as num) + _ageCoefficient * (to - from) / 10;
    final power = math.exp(score.clamp(-40, 40));
    final fractions = <String, double>{};
    for (var i = 0; i < _horizons.length; i++) {
      final s = math.pow(_baseline[i], power).toDouble();
      if (!s.isFinite || s <= 0 || s > 1 || (i > 0 && s > fractions[_horizons[i - 1]]! + 1e-10)) {
        throw const FormatException('Invalid survival curve');
      }
      fractions[_horizons[i]] = s;
    }
    return {
      ...out,
      'log_relative_hazard_score': score,
      'survival_probabilities': fractions,
      'survival_percent_by_year': {for (final e in fractions.entries) e.key: 100 * e.value},
    };
  }
}

/// The people compared for the age-group statistic.
class AgeGroup {
  const AgeGroup({
    required this.percentile,
    required this.size,
    required this.bandLow,
    required this.bandHigh,
    required this.width,
    required this.nearestBand,
    required this.female,
    required this.ownScore,
    required this.medianScore,
  });

  /// 0–100: the share of the band whose score is higher (worse) than the person's.
  final double percentile;

  final bool female;

  /// The person's score without the age and sex terms: the quantity [percentile] ranks.
  final double ownScore;

  /// The band's median of that score: the ⌈n/2⌉-th smallest (the lower median when n is
  /// even), so that `ownScore < medianScore` exactly when [percentile] > 50.
  final double medianScore;

  /// The centred health score `medianScore − ownScore`: 0 is the middle of the band,
  /// positive is healthier, above 0 exactly when [percentile] > 50 (a tie gives 0).
  double get healthScore => medianScore - ownScore;

  /// The band actually used, e.g. `women 59–69`.
  String get label => '${female ? 'women' : 'men'} ${_age(bandLow)}–${_age(bandHigh)}';
  static String _age(num a) => a == a.roundToDouble() ? '${a.round()}' : '$a';
  final int size;
  final num bandLow;
  final num bandHigh;

  /// Half-width of the band in years: 5, 7 or 10.
  final int width;
  final bool nearestBand;

  Map<String, dynamic> toJson() => {
    'percentile': percentile,
    'size': size,
    'band_low': bandLow,
    'band_high': bandHigh,
    'width': width,
    'nearest_band': nearestBand,
    'health_score': healthScore,
    'label': label,
  };
}

/// The package's reference set (`support_reference.f64.gz`: rows of the encoded features),
/// scored without the age_decade and female terms, for "relative to people like you in the
/// survey". The rows are unweighted survey participants, not a national population.
class AgeGroupReference {
  AgeGroupReference(Float64List data, this._coef, this._centre)
    : assert(_coef.length == _centre.length && data.length % _coef.length == 0),
      _rows = data.length ~/ _coef.length,
      _data = data,
      _ages = [],
      _female = [],
      _scores = [] {
    final n = _coef.length;
    for (var r = 0; r < _rows; r++) {
      var s = 0.0;
      for (var i = 0; i < n; i++) {
        if (i == _ageColumn || i == _femaleColumn) continue;
        s += (data[r * n + i] - _centre[i]) * _coef[i];
      }
      _ages.add(data[r * n + _ageColumn] * 10 + 55);
      _female.add(data[r * n + _femaleColumn] == 1);
      _scores.add(s);
    }
  }

  static const _ageColumn = 0, _femaleColumn = 8;
  static const minPeople = 50;
  static const widths = [5, 7, 10];

  final List<double> _coef, _centre;
  final int _rows;
  final List<double> _ages, _scores;
  final List<bool> _female;

  int get length => _rows;
  final Float64List _data;

  /// Row [r]'s encoded feature [c].
  double value(int r, int c) => _data[r * _coef.length + c];

  /// The rows of one sex in the percentile's band around [age] (±5, then ±7, ±10 years; outside
  /// 35–79 the nearest band inside it), or null when even ±10 has fewer than [minPeople].
  List<int>? band({required num age, required bool female, required int minPeople}) {
    final nearest = age < checkedAgeRange.low || age > checkedAgeRange.high;
    for (final w in widths) {
      final centre = nearest ? age.clamp(checkedAgeRange.low + w, checkedAgeRange.high - w) : age;
      final low = math.max(centre - w, checkedAgeRange.low), high = math.min(centre + w, checkedAgeRange.high);
      final rows = [
        for (var r = 0; r < _rows; r++)
          if (_female[r] == female && _ages[r] >= low && _ages[r] <= high) r,
      ];
      if (rows.length >= minPeople) return rows;
    }
    return null;
  }

  /// Row [r]'s value of model [input] in the package's units, read back from its encoding so
  /// that it encodes to the same columns (in the flat parts, BMI 23–35 and sleep 7–8, any value
  /// does; 29 and 7.5 are used).
  Object decode(int r, String input) {
    double v(int c) => value(r, c);
    return switch (input) {
      'bmi' => v(1) > 0 ? 23 - 5 * v(1) : (v(2) > 0 ? 35 + 5 * v(2) : 29.0),
      'sleep_hours' => v(3) > 0 ? 7 - v(3) : (v(4) > 0 ? 8 + v(4) : 7.5),
      'vigorous_recreation_min_week' => math.max(0.0, math.pow(76, v(5)) - 1.0),
      'moderate_recreation_min_week' => math.max(0.0, math.pow(151, v(6)) - 1.0),
      'sedentary_min_day' => (360 + 120 * v(7)).clamp(0.0, 1439.0),
      'smoking_status' => v(10) == 1 ? 2 : (v(9) == 1 ? 1 : 0),
      'diabetes_diagnosed' => v(11).round(),
      'hypertension_diagnosed' => v(12).round(),
      'general_health' =>
        [
              for (var l = 2; l <= 5; l++)
                if (v(11 + l) == 1) l,
            ].firstOrNull ??
            1,
      _ => throw ArgumentError.value(input, 'input', 'not marginalised'),
    };
  }

  /// The reference people of one sex with ages in [low, high] (inclusive).
  int count({required bool female, required num low, required num high}) {
    var n = 0;
    for (var r = 0; r < _rows; r++) {
      if (_female[r] == female && _ages[r] >= low && _ages[r] <= high) n++;
    }
    return n;
  }

  /// The statistic for a person with model [score] (which includes the age and sex terms)
  /// at [age]. Band: age ±5 years, same sex; ±7 then ±10 when fewer than 50 people. Outside
  /// 35–79 the nearest ±w band inside 35–79 is used.
  AgeGroup compare({required double score, required num age, required bool female}) {
    final own =
        score -
        ((age - 55) / 10 - _centre[_ageColumn]) * _coef[_ageColumn] -
        ((female ? 1 : 0) - _centre[_femaleColumn]) * _coef[_femaleColumn];
    final nearest = age < checkedAgeRange.low || age > checkedAgeRange.high;
    late num low, high;
    var width = widths.last, size = 0;
    for (final w in widths) {
      final centre = nearest ? age.clamp(checkedAgeRange.low + w, checkedAgeRange.high - w) : age;
      low = math.max(centre - w, checkedAgeRange.low);
      high = math.min(centre + w, checkedAgeRange.high);
      width = w;
      size = count(female: female, low: low, high: high);
      if (size >= minPeople) break;
    }
    var worse = 0;
    final band = <double>[];
    for (var r = 0; r < _rows; r++) {
      if (_female[r] == female && _ages[r] >= low && _ages[r] <= high) {
        band.add(_scores[r]);
        if (_scores[r] > own) worse++;
      }
    }
    band.sort();
    return AgeGroup(
      percentile: size == 0 ? 0 : 100 * worse / size,
      size: size,
      bandLow: low,
      bandHigh: high,
      width: width,
      nearestBand: nearest,
      female: female,
      ownScore: own,
      medianScore: band.isEmpty ? double.nan : band[(band.length + 1) ~/ 2 - 1],
    );
  }
}

/// A plain "please check this answer" for a value the package refused.
TwinAssessment invalidAssessment(FormatException e) {
  final text = e.message;
  final key = modelInputs.followedBy(['height_cm', 'weight_kg']).where(text.contains).firstOrNull;
  final label = switch (key) {
    null => null,
    'height_cm' || 'weight_kg' => 'height and weight',
    _ => modelInputLabels[key],
  };
  return TwinAssessment.invalid(
    label == null
        ? 'One of your answers is outside what the model can read. Please check your answers.'
        : 'Your answer for $label is outside what the model can read. Please check it.',
    invalidInput: key == 'height_cm' || key == 'weight_kg' ? 'bmi' : key,
  );
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The calendar day of [d], as a UTC midnight (the package's date arithmetic).
DateTime dayOf(DateTime d) => DateTime.utc(d.year, d.month, d.day);
