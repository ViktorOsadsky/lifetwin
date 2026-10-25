// Expected lifespan: a rough, proof-of-concept estimate for the one-time lifespan reveal
// (owner override 2026-10-24; TwinRepository.lifespanEstimate).
//
// The reveal ([LifespanEstimate]) now uses the model owner's yearly Cox projection
// (model_handoff/SURVIVAL_PROJECTION_HANDOFF.md, commit 9ac602e); see [LifespanEstimate].
//
// The life-table calculation below ([estimateLifespan], [LifespanCurve]) is no longer read
// by the app. It is kept, with its server parity test, for comparison
// (docs/lifespan-estimate.md). Its method: relative-risk-adjusted period life table.
//   * Population: CDC/NCHS United States Life Tables, 2024, by sex ([lifeTableSource]).
//     Deaths are uniform within each year of age (the table's own a = 0.5); above 100 the
//     hazard is constant at 1 / e(100). With HR = 1 this reproduces the table exactly.
//   * Personal hazard ratio: the LifeTwin Cox model's terms except age and sex (both are
//     already in the sex-specific table), relative to the log-mean hazard of NHANES
//     training profiles of the same sex and similar age. HR = 1 is the average hazard.
//   * Age-band calibration: one multiplicative hazard factor k per sex and age band (35–44,
//     45–54, 55–64, 65–74, 75–79) so the life-table 5-year survival of the NHANES training
//     profiles matches the Cox model's within each band. Ages 18–34 and 80–85 use the
//     nearest band's k, held constant ([bandLogAdjustment]).
//   * Proportional hazards: in the year starting at age y, survival from y + u to y + v is
//     ((1 - v q) / (1 - u q)) ^ HR.
//   * Attenuation: log HR holds for the model's validated 5 years, then halves every
//     [defaultHalfLifeYears] years; pass `halfLifeYears: null` to turn it off.
//
// Presentation (owner ruling): an expected YEAR and age, with the 25th–75th percentile ages
// as the range; see [LifespanEstimate]. Never a day or date.
//
// The same operations, in the same order, are in server/tools/lifespan_reference.py;
// test/twin/lifespan_test.dart checks the two agree to 1e-9.
//
// Callers must only use a profile the packaged model itself accepts (status 'available'
// or the app's 18–85 age extension). This file does not repeat the model's support check.

import 'dart:math' as math;

import 'package:lifetwin_on_device/lifetwin_on_device.dart' show LifeTwinProjectionLab;

import 'lifespan_data.dart';
import 'twin_model.dart' show checkedAgeRange, extrapolatedAgeRange;

const defaultHalfLifeYears = 20.0;
const validatedYears = 5.0;
const daysPerYear = 365.2425;

/// The health score's ages (owner ruling); under 18 gives no estimate.
const lifespanProfileAges = extrapolatedAgeRange;
const _checkedAges = checkedAgeRange;

/// Upper ages of the calibration bands 35–44, 45–54, 55–64, 65–74, 75–79.
const _bandHighAges = [44, 54, 64, 74, 79];
const _milestones = [80, 90, 100];
const _curveEndAge = 110;

enum LifespanSex { male, female }

/// The full calculation (survival curve, moments, percentiles). The app reads the
/// summary [LifespanEstimate]; this is for the "How?" view and the tests.
class LifespanCurve {
  const LifespanCurve({
    required this.age,
    required this.logHazardRatio,
    required this.halfLifeYears,
    required this.lifeExpectancyYears,
    required this.sdYears,
    required this.age25thPercentile,
    required this.medianAge,
    required this.age75thPercentile,
    required this.probabilityReach,
    required this.survivalCurve,
  });

  /// Exact age at assessment, years.
  final double age;
  final double logHazardRatio;

  /// Null when attenuation is off.
  final double? halfLifeYears;

  /// Remaining life expectancy: the integral of the survival curve from [age].
  final double lifeExpectancyYears;

  /// Standard deviation of the age at death. Shown next to any single number.
  final double sdYears;

  /// Age by which 25% / 50% / 75% of people like this have died.
  final double age25thPercentile;
  final double medianAge;
  final double age75thPercentile;

  /// Probability of reaching 80, 90 and 100; null for a milestone already passed.
  final Map<int, double?> probabilityReach;

  /// (age, survival) from [age] through 110: the start, then every whole age.
  final List<(double, double)> survivalCurve;

  double get hazardRatio => math.exp(logHazardRatio);
  double get expectedAgeAtDeath => age + lifeExpectancyYears;

  /// Owner ruling (option 1): the headline is this expected age, rounded to a whole year.
  int get headlineAge => _roundHalfUp(expectedAgeAtDeath);

  /// The range shown with it: 25th–75th percentile ages, whole years.
  int get rangeLowAge => _roundHalfUp(age25thPercentile);
  int get rangeHighAge => _roundHalfUp(age75thPercentile);

  /// "You're likely to live to about 85. Most people like you live to between 79 and 92."
  /// Show with [lifespanRoughEstimateNote]; put the model caveats behind a "How?" tap.
  /// Never deterministic wording, and never a day or date.
  String get headline =>
      "You're likely to live to about $headlineAge. "
      'Most people like you live to between $rangeLowAge and $rangeHighAge.';

  /// [currentYear] + the remaining life expectancy, rounded to a whole year. A year, not
  /// a day: the SD is [sdYears] years, so a date would be false precision.
  int expectedYear(int currentYear) =>
      currentYear + _roundHalfUp(lifeExpectancyYears);
}

const lifespanRoughEstimateNote =
    'A rough estimate from people with a similar profile, not a prediction for you.';

/// Shown with every [LifespanEstimate] (owner ruling: a proof of concept).
const lifespanCaveat =
    'Proof of concept: a rough estimate, not a prediction for you. It repeats the survey '
    "model's one-year risk at each later age with your answers held fixed, so it can never "
    'be truly accurate. LifeTwin then focuses on your relative health score.';

/// Added to [lifespanCaveat] when the middle of the curve lies past age 79.
const lifespanBeyondCheckedAgesCaveat =
    'The model was only checked up to age 79, so the ages past that are even rougher.';

/// Kept for the status; the projection gives no estimate outside 35–79 (see [LifespanEstimate]).
const lifespanExtrapolationCaveat =
    'Your age is outside the ages the model was checked on (35–79), so this is even rougher.';

enum LifespanStatus {
  /// The person's age is 35–79, where the model was checked.
  available,

  /// The person's age is outside 35–79. The projection lab refuses those ages, so
  /// [LifespanEstimate.forProfile] never produces this today; kept for the reveal's flag.
  extrapolated,
}

/// One point of the yearly curve: cumulative survival (0–100) at a whole [age].
typedef LifespanPoint = ({int age, double survivalPercent, bool extrapolated});

/// What the app shows once (the lifespan reveal): an age and YEAR with a range. No day or
/// date.
///
/// Method (model_handoff/SURVIVAL_PROJECTION_HANDOFF.md, commit 9ac602e): the yearly curve
/// of `LifeTwinProjectionLab.assess(profile, includeExtrapolation: true)['annual']`, i.e.
/// `∏ S(1 | age = a + k, other inputs fixed)` from the Cox model, continued past 79 to 110.
/// [expectedAge] is where it crosses 50% (the lab's `median_crossing_age`), [p25Age] and
/// [p75Age] where it crosses 75% and 25%, each by linear interpolation between whole ages
/// (the lab's own rule). The handoff calls the 50% crossing a projected median threshold,
/// not life expectancy.
class LifespanEstimate {
  const LifespanEstimate({
    required this.expectedAge,
    required this.p25Age,
    required this.p75Age,
    required this.expectedYear,
    required this.status,
    required this.caveat,
    required this.medianCrossingExtrapolated,
    required this.annualCurve,
  });

  /// From a model profile (package codes; the profile the model accepted) in [currentYear].
  /// Null (unavailable) when the lab gives no curve: an incomplete or unsupported profile,
  /// an age outside 35–79 or not in whole years, or a curve that does not cross 25% by 110.
  static LifespanEstimate? forProfile(
    Map<String, dynamic> profile, {
    required int currentYear,
    required LifeTwinProjectionLab? lab,
  }) {
    final age = profile['age'];
    if (lab == null || age is! num) return null;
    final Map<String, dynamic> result;
    try {
      result = lab.assess(profile, includeExtrapolation: true);
    } on FormatException {
      return null;
    }
    final annual = result['annual'];
    if (result['status'] != 'available' || annual is! Map) return null;
    final points = <LifespanPoint>[
      for (final p in annual['points'] as List)
        (
          age: (p as Map)['age'] as int,
          survivalPercent: (p['survival_percent'] as num).toDouble(),
          extrapolated: p['extrapolated'] == true,
        ),
    ];
    final median = annual['median_crossing_age'];
    final p25 = crossingAge(points, 75), p75 = crossingAge(points, 25);
    if (median is! num || p25 == null || p75 == null) return null;
    final extrapolatedAge = age < _checkedAges.low || age > _checkedAges.high;
    final beyond = annual['median_crossing_extrapolated'] == true;
    return LifespanEstimate(
      expectedAge: median.toDouble(),
      p25Age: p25,
      p75Age: p75,
      expectedYear: currentYear + _roundHalfUp((median - age).toDouble()),
      status: extrapolatedAge ? LifespanStatus.extrapolated : LifespanStatus.available,
      caveat: [
        lifespanCaveat,
        if (extrapolatedAge) lifespanExtrapolationCaveat,
        if (beyond) lifespanBeyondCheckedAgesCaveat,
      ].join(' '),
      medianCrossingExtrapolated: beyond,
      annualCurve: points,
    );
  }

  /// The age where [points] first fall to [percent] or below, interpolated linearly
  /// between whole ages exactly as `LifeTwinProjectionLab` does for 50%; null if never.
  static double? crossingAge(List<LifespanPoint> points, double percent) {
    for (var i = 1; i < points.length; i++) {
      final before = points[i - 1].survivalPercent, after = points[i].survivalPercent;
      if (before > percent && after <= percent) {
        return points[i].age - 1 + (before - percent) / (before - after);
      }
    }
    return null;
  }

  /// Age where the yearly curve crosses 50% (unrounded; show it rounded, see [headline]).
  final double expectedAge;

  /// Ages where the curve crosses 75% and 25%.
  final double p25Age;
  final double p75Age;

  /// Current year + (expectedAge − current age), rounded to a year.
  final int expectedYear;
  final LifespanStatus status;

  /// "Proof of concept / rough estimate" text; show it with the number.
  final String caveat;

  /// The 50% crossing is past age 79, in the extrapolated part of the curve.
  final bool medianCrossingExtrapolated;

  /// The yearly curve from the current age to 110, for a "How?" view.
  final List<LifespanPoint> annualCurve;

  bool get extrapolated => status == LifespanStatus.extrapolated;

  /// "You're likely to live to about 85. Most people like you live to between 79 and 92."
  /// Never deterministic wording, and never a day or date.
  String get headline =>
      "You're likely to live to about ${_roundHalfUp(expectedAge)}. "
      'Most people like you live to between ${_roundHalfUp(p25Age)} and ${_roundHalfUp(p75Age)}.';
}

int _roundHalfUp(double x) => (x + 0.5).floor();

double exactAgeYears(DateTime birth, DateTime asOf) {
  final b = DateTime.utc(birth.year, birth.month, birth.day);
  final a = DateTime.utc(asOf.year, asOf.month, asOf.day);
  return a.difference(b).inDays / daysPerYear;
}

double _attenuation(double yearsFromNow, double? halfLife) {
  if (halfLife == null || yearsFromNow <= validatedYears) return 1.0;
  return math.pow(0.5, (yearsFromNow - validatedYears) / halfLife).toDouble();
}

double _pow(double x, double y) => math.pow(x, y).toDouble();

/// Survival from exact [age] under hazard HR(t) × population hazard(age + t).
LifespanCurve estimateLifespan({
  required LifespanSex sex,
  required double age,
  required double logHazardRatio,
  double? halfLifeYears = defaultHalfLifeYears,
}) {
  final female = sex == LifespanSex.female;
  return estimateFromTable(
    qx: female ? qxFemale : qxMale,
    e100: female ? e100Female : e100Male,
    age: age,
    logHazardRatio: logHazardRatio,
    halfLifeYears: halfLifeYears,
  );
}

LifespanCurve estimateFromTable({
  required List<double> qx,
  required double e100,
  required double age,
  required double logHazardRatio,
  double? halfLifeYears = defaultHalfLifeYears,
}) {
  final logHr = logHazardRatio;
  if (!(age >= 1.0 && age < 100.0) || !logHr.isFinite) {
    throw ArgumentError('age must be in [1, 100) and logHazardRatio finite');
  }
  if (halfLifeYears != null && !(halfLifeYears > 0)) {
    throw ArgumentError('halfLifeYears must be positive or null');
  }
  final first = age.floor();
  var survival = 1.0;
  var mean = 0.0;
  var second = 0.0;
  final curve = <(double, double)>[(age, 1.0)];
  const targets = [0.75, 0.5, 0.25];
  final quantiles = <double>[];
  final milestones = <int, double?>{for (final m in _milestones) m: null};
  for (var y = first; y < 100; y++) {
    final q = qx[y];
    final u = y == first ? age - y : 0.0;
    final tMid = 0.5 * ((y + u) + (y + 1)) - age;
    final hr = math.exp(logHr * _attenuation(tMid, halfLifeYears));
    final a = 1 - u * q;
    final b = 1 - q;
    final ratio = b / a;
    final end = survival * _pow(ratio, hr);
    final i0 = (a - b * _pow(ratio, hr)) / (q * (hr + 1));
    final i1 =
        ((_pow(a, hr + 1) - _pow(b, hr + 1)) / (hr + 1) -
            (_pow(a, hr + 2) - _pow(b, hr + 2)) / (hr + 2)) /
        (q * q * _pow(a, hr));
    final t0 = y - age;
    mean += survival * i0;
    second += survival * (t0 * i0 + i1);
    while (quantiles.length < targets.length &&
        end <= targets[quantiles.length]) {
      final target = targets[quantiles.length];
      final v = (1 - a * _pow(target / survival, 1 / hr)) / q;
      quantiles.add(y + v);
    }
    survival = end;
    curve.add(((y + 1).toDouble(), survival));
    if (milestones.containsKey(y + 1)) milestones[y + 1] = survival;
  }
  final t100 = 100 - age;
  final hr = math.exp(logHr * _attenuation(t100, halfLifeYears));
  final rate = hr / e100;
  mean += survival / rate;
  second += survival * (t100 / rate + 1 / (rate * rate));
  while (quantiles.length < targets.length) {
    final target = targets[quantiles.length];
    quantiles.add(100 + math.log(survival / target) / rate);
  }
  for (var end = 101; end <= _curveEndAge; end++) {
    curve.add((end.toDouble(), survival * math.exp(-rate * (end - 100))));
  }
  final variance = 2 * second - mean * mean;
  return LifespanCurve(
    age: age,
    logHazardRatio: logHr,
    halfLifeYears: halfLifeYears,
    lifeExpectancyYears: mean,
    sdYears: math.sqrt(variance),
    age25thPercentile: quantiles[0],
    medianAge: quantiles[1],
    age75thPercentile: quantiles[2],
    probabilityReach: milestones,
    survivalCurve: curve,
  );
}

const _required = [
  'age',
  'sex_nhanes',
  'bmi',
  'sleep_hours',
  'vigorous_recreation_min_week',
  'moderate_recreation_min_week',
  'sedentary_min_day',
  'smoking_status',
  'diabetes_diagnosed',
  'hypertension_diagnosed',
  'general_health',
];

double _num(Map<String, dynamic> p, String key) {
  final v = p[key];
  if (v is! num || !v.isFinite) {
    throw FormatException('$key must be a finite number');
  }
  return v.toDouble();
}

void _checkProfile(Map<String, dynamic> p) {
  final missing = [
    for (final k in _required)
      if (p[k] == null) k,
  ];
  if (missing.isNotEmpty) throw FormatException('missing inputs: $missing');
  for (final k in _required) {
    _num(p, k);
  }
  bool oneOf(String k, List<num> allowed) => allowed.contains(p[k]);
  if (!oneOf('sex_nhanes', [1, 2]) ||
      !oneOf('smoking_status', [0, 1, 2]) ||
      !oneOf('general_health', [1, 2, 3, 4, 5]) ||
      !oneOf('diabetes_diagnosed', [0, 1]) ||
      !oneOf('hypertension_diagnosed', [0, 1])) {
    throw const FormatException('unsupported category');
  }
  final age = _num(p, 'age');
  if (age < lifespanProfileAges.low || age > lifespanProfileAges.high) {
    throw FormatException(
      'age must be ${lifespanProfileAges.low}-${lifespanProfileAges.high}',
    );
  }
}

/// The Cox model's encoding (model.dart `_encode`) without age_decade and female, in the
/// order of [riskFeatureNames].
List<double> encodeRisk(Map<String, dynamic> p) {
  final bmi = _num(p, 'bmi');
  final sleep = _num(p, 'sleep_hours');
  final smoking = p['smoking_status'];
  final health = p['general_health'];
  return [
    math.max(23 - bmi, 0) / 5,
    math.max(bmi - 27, 0) / 5,
    math.max(7 - sleep, 0).toDouble(),
    math.max(sleep - 8, 0).toDouble(),
    math.log(1 + _num(p, 'vigorous_recreation_min_week')) / math.log(76),
    math.log(1 + _num(p, 'moderate_recreation_min_week')) / math.log(151),
    (_num(p, 'sedentary_min_day') - 360) / 120,
    smoking == 1 ? 1.0 : 0.0,
    smoking == 2 ? 1.0 : 0.0,
    _num(p, 'diabetes_diagnosed'),
    _num(p, 'hypertension_diagnosed'),
    for (final level in [2, 3, 4, 5]) health == level ? 1.0 : 0.0,
  ];
}

/// Linear interpolation over integer ages 35..79, held flat outside (18–34, 80–85).
double referenceScore(LifespanSex sex, double age) {
  final table = sex == LifespanSex.female
      ? referenceScoreFemale
      : referenceScoreMale;
  if (age <= _checkedAges.low) return table.first;
  if (age >= _checkedAges.high) return table.last;
  final i = age.floor();
  final frac = age - i;
  final lo = _checkedAges.low;
  return table[i - lo] + frac * (table[i + 1 - lo] - table[i - lo]);
}

/// The calibration band's log k for an assessment [age]; the nearest band outside 35–79.
double bandLogAdjustment(LifespanSex sex, double age) {
  final table = sex == LifespanSex.female
      ? bandLogAdjustmentFemale
      : bandLogAdjustmentMale;
  for (var i = 0; i < _bandHighAges.length; i++) {
    if (age < _bandHighAges[i] + 1) return table[i];
  }
  return table.last;
}

/// log HR versus the average hazard of people of the same sex and age, plus the band's
/// calibration factor log k when [adjusted].
double lifespanLogHazardRatio(
  Map<String, dynamic> profile, {
  bool adjusted = true,
}) {
  _checkProfile(profile);
  final x = encodeRisk(profile);
  var score = 0.0;
  for (var i = 0; i < x.length; i++) {
    score += riskCoefficients[i] * x[i];
  }
  final sex = profile['sex_nhanes'] == 2
      ? LifespanSex.female
      : LifespanSex.male;
  final age = _num(profile, 'age');
  return score -
      referenceScore(sex, age) +
      (adjusted ? bandLogAdjustment(sex, age) : 0.0);
}

LifespanCurve estimateLifespanForProfile(
  Map<String, dynamic> profile, {
  double? halfLifeYears = defaultHalfLifeYears,
}) {
  final logHr = lifespanLogHazardRatio(profile);
  return estimateLifespan(
    sex: profile['sex_nhanes'] == 2 ? LifespanSex.female : LifespanSex.male,
    age: _num(profile, 'age'),
    logHazardRatio: logHr,
    halfLifeYears: halfLifeYears,
  );
}
