import 'dart:math' as math;

/// Frozen dense DeepSurv network. Its scalar output is a Cox log hazard score.
class NeuralHazardModel {
  NeuralHazardModel(this.spec)
      : _numeric = (spec['numeric_features'] as List).cast<String>(),
        _categorical = (spec['categorical_features'] as List).cast<String>(),
        _means = (spec['numeric_means'] as List)
            .map((value) => (value as num).toDouble())
            .toList(),
        _scales = (spec['numeric_scales'] as List)
            .map((value) => (value as num).toDouble())
            .toList(),
        _levels = (spec['categorical_levels'] as List)
            .map(
              (values) =>
                  (values as List).map((v) => (v as num).toDouble()).toList(),
            )
            .toList(),
        _layers = (spec['layers'] as List).cast<Map>();

  final Map<String, dynamic> spec;
  final List<String> _numeric;
  final List<String> _categorical;
  final List<double> _means;
  final List<double> _scales;
  final List<List<double>> _levels;
  final List<Map> _layers;

  double score(Map<String, dynamic> profile) {
    final values = <double>[];
    for (final key in _numeric) {
      final value = profile[key];
      if (value is! num || !value.isFinite) {
        throw FormatException('$key is required for neural hazard');
      }
      values.add(value.toDouble());
    }
    final ageRange = spec['age_range'] as List;
    if (values.first < (ageRange[0] as num) ||
        values.first > (ageRange[1] as num)) {
      throw const FormatException('Neural hazard supports ages 35–79');
    }
    final bounds = spec['numeric_bounds'] as Map;
    for (var i = 1; i < values.length; i++) {
      final pair = bounds[_numeric[i]] as List;
      if (values[i] < (pair[0] as num) || values[i] > (pair[1] as num)) {
        throw FormatException('${_numeric[i]} is outside its valid range');
      }
    }
    if (values[3] + values[4] > 10080 ||
        values[2] * 60 + values[5] + (values[3] + values[4]) / 7 > 1440) {
      throw const FormatException('Reported time exceeds 24 hours per day');
    }
    final encoded = <double>[];
    for (var i = 0; i < values.length; i++) {
      encoded.add((values[i] - _means[i]) / _scales[i]);
    }
    // Every supplied profile is complete, so the training missingness flags are zero.
    for (var i = values.length; i < _means.length; i++) {
      encoded.add(-_means[i] / _scales[i]);
    }
    for (var i = 0; i < _categorical.length; i++) {
      final raw = profile[_categorical[i]];
      if (raw is! num || !_levels[i].contains(raw.toDouble())) {
        throw FormatException('${_categorical[i]} has an unsupported category');
      }
      for (final level in _levels[i]) {
        encoded.add(raw.toDouble() == level ? 1.0 : 0.0);
      }
    }
    var activations = encoded;
    for (var layerIndex = 0; layerIndex < _layers.length; layerIndex++) {
      final kernel = _layers[layerIndex]['kernel'] as List;
      final bias = _layers[layerIndex]['bias'] as List;
      if (kernel.length != activations.length) {
        throw const FormatException('Neural model dimension mismatch');
      }
      final next = List<double>.generate(bias.length, (out) {
        var sum = (bias[out] as num).toDouble();
        for (var input = 0; input < activations.length; input++) {
          sum += activations[input] *
              ((kernel[input] as List)[out] as num).toDouble();
        }
        return layerIndex == _layers.length - 1 ? sum : math.max(0, sum);
      });
      activations = next;
    }
    return activations.single;
  }

  Map<String, dynamic> predict(Map<String, dynamic> profile) {
    final logHazard = score(profile);
    final reference = (spec['reference_log_hazard'] as num).toDouble();
    return {
      'model_version': spec['model_version'],
      'log_relative_hazard': logHazard,
      'relative_hazard_vs_reference': math.exp(logHazard - reference),
      'reference_profile': spec['reference_profile'],
      'interpretation': spec['interpretation'],
      'is_probability': false,
    };
  }
}
