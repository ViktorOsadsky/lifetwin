import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/src/assessment.dart';
import '../lib/src/model.dart';

Map<String, dynamic> readObject(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void close(double actual, double expected, [double tolerance = 1e-11]) {
  if ((actual - expected).abs() > tolerance) {
    throw StateError('Numerical mismatch: $actual versus $expected');
  }
}

void main() {
  final spec = readObject('assets/model.json');
  final reference = Uint8List.fromList(
      gzip.decode(File('assets/support_reference.f64.gz').readAsBytesSync()));
  final model = LifeTwinModel.fromArtifacts(spec, reference);
  final engine = LifeTwinEngine(model);
  final golden =
      jsonDecode(File('test/golden_vectors.json').readAsStringSync()) as List;
  for (final row in golden) {
    final item = row as Map<String, dynamic>;
    final actual =
        model.predict(Map<String, dynamic>.from(item['profile'] as Map));
    if (actual['status'] != 'available')
      throw StateError('Golden profile unavailable');
    close(actual['log_relative_hazard_score'] as double,
        (item['log_relative_hazard_score'] as num).toDouble());
    final expected = item['survival_probabilities'] as Map<String, dynamic>;
    final probabilities =
        actual['survival_probabilities'] as Map<String, double>;
    for (final year in expected.keys) {
      close(probabilities[year]!, (expected[year] as num).toDouble());
    }
  }
  final bmiProfile = Map<String, dynamic>.from(golden.first['profile'] as Map);
  final at35 = model.experimentalConditionalSurvival({...bmiProfile, 'bmi': 35}, 5);
  final at50 = model.experimentalConditionalSurvival({...bmiProfile, 'bmi': 50}, 5);
  if (!(at50 < at35)) {
    throw StateError('Cox high-BMI direction regressed');
  }
  final fixture = 'test/fixtures/';
  final snapshot = engine.assess(readObject('${fixture}snapshot_request.json'));
  final expectedSnapshot = readObject('${fixture}snapshot_response.json');
  if (jsonEncode(snapshot['wellness_cards']) !=
          jsonEncode(expectedSnapshot['wellness_cards']) ||
      jsonEncode(snapshot['avatar']) !=
          jsonEncode(expectedSnapshot['avatar'])) {
    throw StateError('Snapshot guidance or avatar mismatch');
  }
  final actualSurvival = snapshot['survival'] as Map<String, dynamic>;
  final expectedSurvival = expectedSnapshot['survival'] as Map<String, dynamic>;
  for (final year in (expectedSurvival['survival_probabilities'] as Map).keys) {
    close(
        (actualSurvival['survival_probabilities'] as Map)[year] as double,
        ((expectedSurvival['survival_probabilities'] as Map)[year] as num)
            .toDouble());
  }
  for (final name in ['daily', 'weekly']) {
    final result = engine.assess(readObject('$fixture${name}_request.json'));
    if ((result['survival'] as Map)['status'] != 'available' ||
        (result['input_provenance'] as Map)['complete_weeks'] != 1) {
      throw StateError('$name assessment failed');
    }
    final used = result['profile_used'] as Map;
    close((used['sleep_hours'] as num).toDouble(), 7);
    close((used['vigorous_recreation_min_week'] as num).toDouble(), 60);
    close((used['moderate_recreation_min_week'] as num).toDouble(), 165);
  }
  final pair = engine.compare(readObject('${fixture}compare_request.json'));
  if (pair['causal_interpretation'] != false ||
      (pair['modeled_difference_percentage_points'] as Map)['5'] >= 0) {
    throw StateError('Comparison semantics failed');
  }
  final profile = Map<String, dynamic>.from(
      readObject('${fixture}compare_request.json')['current_profile'] as Map);
  if (model.predict({...profile, 'age': 85})['status'] != 'unsupported_age' ||
      model.predict({...profile, 'bmi': 60})['status'] !=
          'unsupported_profile') {
    throw StateError('Support checks failed');
  }
  profile.remove('sleep_hours');
  if (model.predict(profile)['status'] != 'missing_inputs') {
    throw StateError('Missing value check failed');
  }
  print(
      'PASS: 3 golden profiles, snapshot parity, daily/weekly mapping, comparison and support checks');
}
