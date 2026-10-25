// HOST ONLY: imports the canonical handoff directly, never the vendored app package.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../model_handoff/lifetwin_on_device/lib/src/model.dart';
import '../../../model_handoff/lifetwin_on_device/lib/src/neural_hazard.dart';
import '../../../model_handoff/lifetwin_on_device/lib/src/projection.dart';

final handoff = Platform.script
    .resolve('../../../model_handoff/lifetwin_on_device/')
    .toFilePath();
Map<String, dynamic> object(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
void require(bool ok, String path) {
  if (!ok) throw StateError(path);
}

void close(Object? actual, Object? expected, String path) {
  if (actual == null || expected == null) {
    require(actual == expected, '$path null mask');
    return;
  }
  require(
    actual is num && expected is num && actual.isFinite && expected.isFinite,
    '$path finite numbers',
  );
  require(
    ((actual as num) - (expected as num)).abs() <= 1e-9,
    '$path: $actual vs $expected',
  );
}

double? crossing(List points, double threshold) {
  for (var i = 1; i < points.length; i++) {
    final before = points[i - 1]['survival_percent'] as num,
        after = points[i]['survival_percent'] as num;
    if (before > threshold && after <= threshold)
      return ((points[i]['age'] as num) -
              1 +
              (before - threshold) / (before - after))
          .toDouble();
  }
  return null;
}

void pointsEqual(List actual, List expected, String id) {
  require(actual.length == expected.length, '$id point count');
  for (var i = 0; i < expected.length; i++) {
    require(actual[i]['age'] == expected[i]['age'], '$id age[$i]');
    require(
      actual[i]['extrapolated'] == expected[i]['extrapolated'],
      '$id extrapolated[$i]',
    );
    close(
      actual[i]['survival_percent'],
      expected[i]['survival_percent'],
      '$id survival[$i]',
    );
  }
}

void main(List<String> args) {
  require(
    args.length == 2 || (args.length == 3 && args[2] == '--host-fixture'),
    'usage: dart canonical_oracle.dart CAPTURE.json ORACLE.json',
  );
  final capture = object(args[0]);
  final hostOnly = args.length == 3;
  final validMode = hostOnly
      ? capture['host_fixture_only'] == true &&
            capture['host_fixture_assertions_passed'] == true &&
            capture['device_assertions_passed'] == false &&
            capture['owner_approved_and_merged'] == false
      : capture['owner_approved_and_merged'] == true &&
            capture['device_assertions_passed'] == true &&
            capture['host_fixture_only'] != true;
  require(
    capture['schema'] == 'lifetwin.qa107.engine.v2' &&
        capture['score_scale'] == 'cox_centered_v1' &&
        capture['synthetic_only'] == true &&
        validMode,
    'completed approved device capture or explicitly marked host fixture required',
  );
  final spec = object('$handoff/assets/model.json');
  final referenceBytes = Uint8List.fromList(
    File('$handoff/assets/support_reference.f64').readAsBytesSync(),
  );
  final cox = LifeTwinModel.fromArtifacts(spec, referenceBytes);
  final lab = LifeTwinProjectionLab(
    cox,
    NeuralHazardModel(object('$handoff/assets/neural_model.json')),
  );
  final coef = [
    for (final x in spec['coefficients'] as List) (x as num).toDouble(),
  ];
  final centre = [
    for (final x in spec['feature_center'] as List) (x as num).toDouble(),
  ];
  final view = ByteData.sublistView(referenceBytes);
  final reference = <({double age, bool female, double score})>[];
  for (var r = 0; r < referenceBytes.length ~/ (8 * coef.length); r++) {
    final x = [
      for (var i = 0; i < coef.length; i++)
        view.getFloat64((r * coef.length + i) * 8, Endian.little),
    ];
    var s = 0.0;
    for (var i = 0; i < coef.length; i++) {
      if (i != 0 && i != 8) s += (x[i] - centre[i]) * coef[i];
    }
    reference.add((age: x[0] * 10 + 55, female: x[8] == 1, score: s));
  }
  Map<String, dynamic> index(Map<String, dynamic> p, num raw) {
    final age = p['age'] as num, female = p['sex_nhanes'] == 2;
    final own =
        raw -
        ((age - 55) / 10 - centre[0]) * coef[0] -
        ((female ? 1 : 0) - centre[8]) * coef[8];
    var band = <double>[];
    num lo = 0, hi = 0;
    for (final width in [5, 7, 10]) {
      final mid = age < 35 || age > 79
          ? age.clamp(35 + width, 79 - width)
          : age;
      lo = math.max(35, mid - width);
      hi = math.min(79, mid + width);
      band = [
        for (final row in reference)
          if (row.female == female && row.age >= lo && row.age <= hi) row.score,
      ]..sort();
      if (band.length >= 50) break;
    }
    require(band.isNotEmpty, 'reference group must exist');
    return {
      'health_score': band[(band.length + 1) ~/ 2 - 1] - own,
      'percentile': 100 * band.where((s) => s > own).length / band.length,
      'group_band': '$lo–$hi',
      'group_size': band.length,
    };
  }

  final results = <Map<String, dynamic>>[];
  final records = capture['records'] as List;
  require(
    records.length == 4,
    'four supported synthetic repository profiles required',
  );
  final edges = capture['edge_records'] as List;
  require(
    edges.map((r) => r['profile_used']['age']).toSet().containsAll([
      18,
      34,
      35,
      39,
      40,
      44,
      45,
      70,
      74,
      75,
      78,
      79,
      80,
      85,
    ]),
    'all blend boundary profiles required',
  );
  for (final record in [...records, ...edges]) {
    final id = record['id'] as String,
        p = Map<String, dynamic>.from(record['profile_used'] as Map);
    final ageForProjection = p['age'] as num;
    final projectionProfile = ageForProjection >= 35 && ageForProjection <= 79
        ? {...p, 'age': ageForProjection.floor()}
        : p;
    final canonical = lab.assess(projectionProfile, includeExtrapolation: true);
    if (canonical['status'] != 'available') {
      // Outside canonical35–79 support: do not turn missing curves into zero.
      require(
        (p['age'] as num) < 35 || (p['age'] as num) > 79,
        '$id unexpected canonical rejection',
      );
      require(canonical['annual'] == null, '$id canonical unavailable mask');
      require(
        record['projection_component'] == null &&
            record['lifespan']['method'] == 'life_table_mean' &&
            record['lifespan']['projection_weight'] == 0 &&
            record['lifespan']['extrapolated'] == true,
        '$id fallback must be flagged',
      );
      results.add({
        'id': id,
        'canonical_status': canonical['status'],
        'canonical_annual': null,
        'fallback_check': 'required: check_fallback.py',
      });
      continue;
    }
    final current = cox.predict(p), annual = canonical['annual'] as Map;
    close(
      record['raw_log_hazard'],
      current['log_relative_hazard_score'],
      '$id raw hazard',
    );
    close(
      record['five_year_probability'],
      current['survival_probabilities']['5'],
      '$id five-year probability',
    );
    close(
      record['five_year_percent'],
      current['survival_percent_by_year']['5'],
      '$id five-year percent',
    );
    final expectedIndex = index(p, current['log_relative_hazard_score'] as num);
    close(
      record['health_score'],
      expectedIndex['health_score'],
      '$id health index',
    );
    close(record['percentile'], expectedIndex['percentile'], '$id percentile');
    require(
      record['group_band'].split('–').map(double.parse).toList().toString() ==
              expectedIndex['group_band']
                  .split('–')
                  .map(double.parse)
                  .toList()
                  .toString() &&
          record['group_size'] == expectedIndex['group_size'],
      '$id group',
    );
    final e = record['lifespan'] as Map, points = annual['points'] as List;
    final component = record['projection_component'] as Map;
    pointsEqual(
      component['points'] as List,
      points,
      '$id projection component',
    );
    close(
      component['median_crossing_age'],
      annual['median_crossing_age'],
      '$id projection median',
    );
    require(
      component['median_crossing_extrapolated'] ==
          annual['median_crossing_extrapolated'],
      '$id component tail flag',
    );
    final age = p['age'] as num;
    final w = age <= 35 || age >= 79
        ? 0.0
        : (age < 45 ? (age - 35) / 10 : (age <= 70 ? 1.0 : (79 - age) / 9));
    close(e['projection_weight'], w, '$id projection weight');
    require(
      e['selected_curve_source'] ==
          (w < .5 ? 'life_table' : 'yearly_cox_projection'),
      '$id selected curve source',
    );
    if (w >= .5)
      pointsEqual(e['points'] as List, points, '$id selected projection curve');
    results.add({
      'id': id,
      'canonical_status': 'available',
      'projection_component_all_points_parity': true,
      'selected_projection_curve_parity': w >= .5 ? true : null,
      'summary_check':
          'required: check_fallback.py weighted CDC mean/projection crossings',
    });
  }
  final ref = capture['reference_person'] as Map;
  final rp = Map<String, dynamic>.from(ref['profile_used'] as Map);
  final rr = cox.predict(rp);
  final ri = index(rp, rr['log_relative_hazard_score'] as num);
  close(ref['health_score'], 0.0, 'reference person app0.0');
  close(ri['health_score'], 0.0, 'reference person canonical0.0');
  close(ref['percentile'], ri['percentile'], 'reference percentile');
  final missing = capture['missing_input'] as Map;
  final masked = capture['masked_records'] as List;
  require(masked.length == 2, 'under18/over85 masks required');
  for (final row in masked) {
    require(
      row['health_score'] == null &&
          row['raw_log_hazard'] == null &&
          row['five_year_probability'] == null &&
          row['five_year_percent'] == null &&
          row['lifespan'] == null,
      '${row['id']} unsupported is never zero',
    );
  }
  final unavailable = lab.assess(
    Map<String, dynamic>.from(missing['profile_used'] as Map),
  );
  require(
    unavailable['status'] == 'missing_inputs' &&
        unavailable['annual'] == null &&
        missing['health_score'] == null &&
        missing['five_year_probability'] == null &&
        missing['lifespan'] == null,
    'missing-input null masks',
  );
  final fractional = capture['fractional_records'] as List;
  require(
    fractional.length == 5,
    'five fractional direct-wrapper cases required',
  );
  for (final row in fractional) {
    final gate = row['repository_gate'] as Map;
    require(
      gate['status'] == 'missing_inputs' &&
          (gate['missing_inputs'] as List).contains('age') &&
          gate['health_score'] == null &&
          gate['lifespan'] == null &&
          gate['five_year_probability'] == null,
      'fractional confirmed-age repository gate',
    );
    final p = Map<String, dynamic>.from(row['profile_used'] as Map);
    final age = p['age'] as num;
    final pp = age >= 35 && age <= 79 ? {...p, 'age': age.floor()} : p;
    final canonical = lab.assess(pp, includeExtrapolation: true);
    require(
      row['lifespan_available'] == true,
      'fractional direct-wrapper availability',
    );
    if (canonical['status'] == 'available') {
      final annual = canonical['annual'] as Map;
      pointsEqual(
        row['projection_component']['points'] as List,
        annual['points'] as List,
        'fractional floor projection',
      );
      close(
        row['projection_component']['median_crossing_age'],
        annual['median_crossing_age'],
        'fractional floor median',
      );
    } else {
      require(
        row['projection_component'] == null && row['projection_weight'] == 0,
        'fractional outside canonical support',
      );
    }
  }
  final guards = capture['guards'] as List;
  require(guards.length == 4, 'four BMI guards');
  for (final g in guards) {
    final result = g['result'] as Map;
    require(result['weight_guard'] == true, 'BMI guard enabled');
    close(result['health_score_delta'], 0, 'BMI indexdelta');
    require(
      (result['modeled_difference_percentage_points'] as Map).isNotEmpty,
      'BMI comparison supported',
    );
    for (final delta
        in (result['modeled_difference_percentage_points'] as Map).values) {
      close(delta, 0, 'BMI survivaldelta');
    }
  }
  File(args[1]).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'schema': 'lifetwin.qa107.oracle.v2',
      'host_fixture_only': hostOnly,
      'proposed_sha': capture['proposed_sha'],
      'merged_sha': capture['merged_sha'],
      'source': handoff,
      'tolerance': 1e-9,
      'records': results,
      'reference_person_parity': true,
      'missing_masks_parity': true,
      'bmi_guards_checked': guards.length,
    }),
  );
  stdout.writeln(
    'PASS canonical projection components/index/masks; Python blended-summary check remains required: ${args[1]}',
  );
}
