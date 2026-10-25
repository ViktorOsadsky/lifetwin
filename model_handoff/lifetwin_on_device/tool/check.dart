import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/src/model.dart';
import '../lib/src/neural_hazard.dart';
import '../lib/src/projection.dart';

Map<String, dynamic> readObject(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void close(double actual, double expected, [double tolerance = 1e-8]) {
  if ((actual - expected).abs() > tolerance) {
    throw StateError('Numerical mismatch: $actual versus $expected');
  }
}

void main() {
  final cox = LifeTwinModel.fromArtifacts(
    readObject('assets/model.json'),
    Uint8List.fromList(File('assets/support_reference.f64').readAsBytesSync()),
  );
  final neural = NeuralHazardModel(readObject('assets/neural_model.json'));
  final lab = LifeTwinProjectionLab(cox, neural);
  final coxGolden =
      jsonDecode(File('test/golden_vectors.json').readAsStringSync()) as List;
  for (final item in coxGolden.cast<Map>()) {
    final actual = cox.predict(
      Map<String, dynamic>.from(item['profile'] as Map),
    );
    if (actual['status'] != 'available')
      throw StateError('Cox golden unsupported');
    close(
      actual['log_relative_hazard_score'] as double,
      (item['log_relative_hazard_score'] as num).toDouble(),
      1e-10,
    );
    final predicted = actual['survival_probabilities'] as Map;
    for (final entry in (item['survival_probabilities'] as Map).entries) {
      close(
        (predicted[entry.key] as num).toDouble(),
        (entry.value as num).toDouble(),
        1e-10,
      );
    }
  }
  final neuralGolden =
      jsonDecode(File('test/neural_golden.json').readAsStringSync()) as List;
  for (final item in neuralGolden.cast<Map>()) {
    close(
      neural.score(Map<String, dynamic>.from(item['profile'] as Map)),
      (item['log_relative_hazard'] as num).toDouble(),
      1e-5,
    );
  }
  final profile = Map<String, dynamic>.from(neuralGolden[1]['profile'] as Map);
  final result = lab.assess(profile);
  if (result['status'] != 'available') {
    throw StateError('Lab assessment failed');
  }
  final current = result['current_cox'] as Map;
  final annual = result['annual'] as Map;
  final fiveYear = result['five_year'] as Map;
  final annualPoints = (annual['points'] as List).cast<Map>();
  final blockPoints = (fiveYear['points'] as List).cast<Map>();
  close(
    (annualPoints[1]['survival_percent'] as num).toDouble(),
    (current['survival_percent_by_year'] as Map)['1'] as double,
  );
  close(
    (blockPoints[5]['survival_percent'] as num).toDouble(),
    (current['survival_percent_by_year'] as Map)['5'] as double,
  );
  if (((annualPoints[5]['survival_percent'] as num) -
              (blockPoints[5]['survival_percent'] as num))
          .abs() <
      1e-5) {
    throw StateError('The two recurrences unexpectedly coincide');
  }
  if (annual['median_crossing_age'] == null ||
      annual['median_crossing_extrapolated'] != true ||
      fiveYear['median_crossing_age'] == null ||
      fiveYear['median_crossing_extrapolated'] != true) {
    throw StateError('Experimental 50% crossing must be labeled');
  }
  for (final points in [annualPoints, blockPoints]) {
    for (var i = 1; i < points.length; i++) {
      if ((points[i]['survival_percent'] as num) >
          (points[i - 1]['survival_percent'] as num)) {
        throw StateError('Projected survival must be non-increasing');
      }
    }
    if (!points.any((point) => point['extrapolated'] == true)) {
      throw StateError('Age extrapolation was not labeled');
    }
  }
  final supportedOnly = lab.assess(profile, includeExtrapolation: false);
  if (((supportedOnly['annual'] as Map)['points'] as List).last['age'] != 80) {
    throw StateError('Supported-only annual curve should stop at age 80');
  }
  final missing = {...profile}..remove('general_health');
  if (lab.assess(missing)['status'] != 'missing_inputs') {
    throw StateError('Missing inputs should not be defaulted');
  }
  try {
    neural.predict({...profile, 'sleep_hours': 30});
    throw StateError('Impossible neural input was accepted');
  } on FormatException {
    // Expected: no silent clipping or defaulting.
  }
  close(
    (neural.predict(
      Map<String, dynamic>.from(
        neural.spec['reference_profile'] as Map,
      ),
    )['relative_hazard_vs_reference'] as num)
        .toDouble(),
    1.0,
  );
  print(
    'PASS: Cox golden, neural golden, both projections, bounds and missing inputs',
  );
  print('Example age ${profile['age']}: annual 50% crossing '
      '${annual['median_crossing_age']}; five-year 50% crossing '
      '${fiveYear['median_crossing_age']}');
}
