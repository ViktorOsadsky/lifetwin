import 'dart:math' as math;
import 'dart:typed_data';

/// Frozen Cox model exported from the validated LifeTwin Python model.
class LifeTwinModel {
  LifeTwinModel._(this.spec, this._reference)
      : _coefficients = (spec['coefficients'] as List)
            .map((e) => (e as num).toDouble())
            .toList(),
        _center = (spec['feature_center'] as List)
            .map((e) => (e as num).toDouble())
            .toList(),
        _baseline = (spec['baseline_survival'] as List)
            .map((e) => (e as num).toDouble())
            .toList();

  final Map<String, dynamic> spec;
  final Float64List _reference;
  final List<double> _coefficients;
  final List<double> _center;
  final List<double> _baseline;

  factory LifeTwinModel.fromArtifacts(
    Map<String, dynamic> spec,
    Uint8List referenceBytes,
  ) {
    final columns = (spec['encoded_features'] as List).length;
    final coefficients = spec['coefficients'] as List;
    final center = spec['feature_center'] as List;
    final baseline = spec['baseline_survival'] as List;
    final horizons = spec['horizons_years'] as List;
    final neighborCount = spec['neighbor_count'] as int;
    final neighborCutoff = spec['neighbor_distance_cutoff'] as num;
    if (columns != 17 ||
        coefficients.length != columns ||
        center.length != columns ||
        baseline.length != horizons.length ||
        referenceBytes.lengthInBytes % (8 * columns) != 0 ||
        referenceBytes.isEmpty ||
        neighborCount < 1 ||
        neighborCount > referenceBytes.lengthInBytes ~/ (8 * columns) ||
        !neighborCutoff.isFinite ||
        neighborCutoff <= 0) {
      throw const FormatException('Malformed LifeTwin model assets');
    }
    final bytes = ByteData.sublistView(referenceBytes);
    final reference = Float64List(referenceBytes.lengthInBytes ~/ 8);
    for (var i = 0; i < reference.length; i++) {
      reference[i] = bytes.getFloat64(i * 8, Endian.little);
      if (!reference[i].isFinite)
        throw const FormatException('Invalid support reference');
    }
    final model = LifeTwinModel._(spec, reference);
    if (model._coefficients.any((v) => !v.isFinite) ||
        model._center.any((v) => !v.isFinite) ||
        model._baseline.any((v) => !v.isFinite || v <= 0 || v > 1)) {
      throw const FormatException('Invalid LifeTwin coefficients or baseline');
    }
    for (var i = 1; i < model._baseline.length; i++) {
      if (model._baseline[i] > model._baseline[i - 1]) {
        throw const FormatException('Invalid LifeTwin baseline survival');
      }
    }
    return model;
  }

  double _number(Map<String, dynamic> profile, String key) {
    final value = profile[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('$key must be a finite number');
    }
    return value.toDouble();
  }

  Map<String, double>? _validate(
    Map<String, dynamic> profile,
    List<String> missing,
  ) {
    final inputs = List<String>.from(spec['input_features'] as List);
    final extra = profile.keys.where((name) => !inputs.contains(name)).toList();
    if (extra.isNotEmpty)
      throw FormatException('Unknown profile inputs: $extra');
    final clean = <String, double>{};
    final bounds = spec['numeric_bounds'] as Map<String, dynamic>;
    final categories = spec['categorical_allowed'] as Map<String, dynamic>;
    for (final key in inputs) {
      if (profile[key] == null) {
        missing.add(key);
        continue;
      }
      final value = _number(profile, key);
      clean[key] = value;
      if (key == 'age') {
        if (value < 0 || value > 120)
          throw const FormatException('age must be between 0 and 120');
        continue;
      }
      if (bounds.containsKey(key)) {
        final pair = bounds[key] as List;
        if (value < (pair[0] as num) || value > (pair[1] as num)) {
          throw FormatException('$key is outside its valid entry range');
        }
      }
      if (categories.containsKey(key) &&
          !(categories[key] as List).contains(value)) {
        throw FormatException('$key has an unsupported category');
      }
    }
    if (missing.isNotEmpty) return null;
    if (clean['sleep_hours']! * 60 + clean['sedentary_min_day']! > 1440) {
      throw const FormatException(
        'Sleep and awake sitting cannot exceed 24 hours per day',
      );
    }
    final activity = clean['vigorous_recreation_min_week']! +
        clean['moderate_recreation_min_week']!;
    if (activity > 10080 ||
        clean['sleep_hours']! * 60 +
                clean['sedentary_min_day']! +
                activity / 7 >
            1440) {
      throw const FormatException('Recreation exceeds available time');
    }
    return clean;
  }

  List<double> _encode(Map<String, double> p) {
    final age = p['age']!, bmi = p['bmi']!, sleep = p['sleep_hours']!;
    return [
      (age - 55) / 10,
      math.max(23 - bmi, 0) / 5,
      math.max(bmi - 27, 0) / 5,
      math.max(7 - sleep, 0).toDouble(),
      math.max(sleep - 8, 0).toDouble(),
      math.log(1 + p['vigorous_recreation_min_week']!) / math.log(76),
      math.log(1 + p['moderate_recreation_min_week']!) / math.log(151),
      (p['sedentary_min_day']! - 360) / 120,
      p['sex_nhanes'] == 2 ? 1 : 0,
      p['smoking_status'] == 1 ? 1 : 0,
      p['smoking_status'] == 2 ? 1 : 0,
      p['diabetes_diagnosed']!,
      p['hypertension_diagnosed']!,
      for (var level = 2; level <= 5; level++)
        p['general_health'] == level ? 1 : 0,
    ];
  }

  Map<String, dynamic> predict(Map<String, dynamic> profile) {
    final missing = <String>[];
    final clean = _validate(profile, missing);
    final common = <String, dynamic>{
      'model_version': spec['model_version'],
      'causal_interpretation': false,
      'horizons_years': spec['horizons_years'],
      'survival_probabilities': null,
      'survival_percent_by_year': null,
      'death_date': null,
      'estimated_age_at_death': null,
    };
    if (clean == null) {
      return {
        ...common,
        'status': 'missing_inputs',
        'missing_inputs': missing,
        'message':
            'Complete every model input to show annual survival percentages.',
      };
    }
    final ageRange = spec['age_range'] as List;
    if (clean['age']! < (ageRange[0] as num) ||
        clean['age']! > (ageRange[1] as num)) {
      return {
        ...common,
        'status': 'unsupported_age',
        'message': 'Annual estimates support ages 35–79 only.',
      };
    }
    final x = _encode(clean);
    var score = 0.0;
    for (var i = 0; i < x.length; i++) {
      score += (x[i] - _center[i]) * _coefficients[i];
    }
    final issues = <String>[];
    final support = spec['numeric_support_1_99pct'] as Map<String, dynamic>;
    for (final entry in support.entries) {
      final pair = entry.value as List;
      if (clean[entry.key]! < (pair[0] as num) ||
          clean[entry.key]! > (pair[1] as num)) {
        issues.add(
          '${entry.key} is outside the training 1st–99th percentile range',
        );
      }
    }
    final columns = x.length;
    final rows = _reference.length ~/ columns;
    final distances = List<double>.filled(rows, 0);
    for (var row = 0; row < rows; row++) {
      var squared = 0.0;
      for (var col = 0; col < columns; col++) {
        final delta = _reference[row * columns + col] - x[col];
        squared += delta * delta;
      }
      distances[row] = math.sqrt(squared);
    }
    distances.sort();
    final neighborCount = spec['neighbor_count'] as int;
    if (distances[neighborCount - 1] >
        (spec['neighbor_distance_cutoff'] as num)) {
      issues.add('The input combination has few nearby training profiles');
    }
    if (issues.isNotEmpty) {
      return {
        ...common,
        'status': 'unsupported_profile',
        'message': 'Annual estimates are withheld for this profile.',
        'support_issues': issues,
      };
    }
    final power = math.exp(score.clamp(-40, 40));
    final survival = _baseline
        .map((baseline) => math.pow(baseline, power).toDouble())
        .toList();
    for (var i = 0; i < survival.length; i++) {
      if (!survival[i].isFinite ||
          survival[i] <= 0 ||
          survival[i] > 1 ||
          (i > 0 && survival[i] > survival[i - 1] + 1e-10)) {
        throw const FormatException('Invalid survival curve');
      }
    }
    final fractions = <String, double>{};
    final percentages = <String, double>{};
    final horizons = spec['horizons_years'] as List;
    for (var i = 0; i < horizons.length; i++) {
      final key = horizons[i].toString();
      fractions[key] = survival[i];
      percentages[key] = 100 * survival[i];
    }
    return {
      ...common,
      'status': 'available',
      'log_relative_hazard_score': score,
      'survival_probabilities': fractions,
      'survival_percent_by_year': percentages,
      'interpretation':
          'Estimated cumulative survival among similar survey profiles, not an individual death date or medical prognosis.',
    };
  }

  /// Mathematical Cox recurrence for the projection lab only. This deliberately
  /// bypasses the trained-age and neighbor-support gates; callers must label it
  /// as unvalidated when the assessment age is outside 35–79.
  double experimentalConditionalSurvival(
    Map<String, dynamic> profile,
    int years,
  ) {
    final missing = <String>[];
    final clean = _validate(profile, missing);
    if (clean == null) {
      throw FormatException('Missing model inputs: $missing');
    }
    if (years < 1 || years > _baseline.length) {
      throw const FormatException('Only years 1–5 are in the Cox artifact');
    }
    final encoded = _encode(clean);
    var score = 0.0;
    for (var i = 0; i < encoded.length; i++) {
      score += (encoded[i] - _center[i]) * _coefficients[i];
    }
    return math
        .pow(_baseline[years - 1], math.exp(score.clamp(-40, 40)))
        .toDouble();
  }

  Map<String, dynamic> compare(
    Map<String, dynamic> current,
    Map<String, dynamic> alternative,
  ) {
    final first = predict(current);
    final second = predict(alternative);
    final changes = (spec['input_features'] as List)
        .cast<String>()
        .where((key) => current[key] != alternative[key])
        .toList();
    Map<String, double>? difference;
    if (first['status'] == 'available' && second['status'] == 'available') {
      difference = <String, double>{};
      final a = first['survival_probabilities'] as Map<String, double>;
      final b = second['survival_probabilities'] as Map<String, double>;
      for (final year in a.keys) {
        difference[year] = 100 * (b[year]! - a[year]!);
      }
    }
    final warnings = <String>[];
    if (changes.any({'bmi', 'sleep_hours', 'sedentary_min_day'}.contains)) {
      warnings.add(
        'BMI, sleep and sitting profile contrasts do not estimate intervention effects; the high-BMI fitted slope is near zero and slightly inverse.',
      );
    }
    return {
      'current': first,
      'alternative': second,
      'changed_features': changes,
      'modeled_difference_percentage_points': difference,
      'causal_interpretation': false,
      'interpretation':
          'Difference between two model profiles, not the benefit of changing a habit.',
      'warnings': warnings,
    };
  }
}
