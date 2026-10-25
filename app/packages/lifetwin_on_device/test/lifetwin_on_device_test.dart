import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifetwin_on_device/lifetwin_on_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('package assets load and inference runs offline', () async {
    final model = await loadLifeTwinModel();
    final engine = LifeTwinEngine(model);
    final request = jsonDecode(
            File('test/fixtures/snapshot_request.json').readAsStringSync())
        as Map<String, dynamic>;
    final result = engine.assess(request);
    final survival = result['survival'] as Map<String, dynamic>;
    expect(survival['status'], 'available');
    expect((survival['survival_percent_by_year'] as Map<String, double>)['5'],
        closeTo(99.3242941735678, 1e-9));
    expect(survival['death_date'], isNull);
    expect((result['wellness_cards'] as List).isNotEmpty, isTrue);
  });

  test('vendored projection lab loads and its neural part matches the golden', () async {
    final lab = await loadLifeTwinProjectionLab();
    final golden =
        jsonDecode(File('test/neural_golden.json').readAsStringSync()) as List;
    for (final g in golden) {
      expect(
        lab.neural.score(Map<String, dynamic>.from(g['profile'] as Map)),
        closeTo((g['log_relative_hazard'] as num).toDouble(), 1e-12),
      );
    }
    final result = lab.assess(golden[1]['profile'] as Map<String, dynamic>);
    expect(result['status'], 'available');
    final annual = result['annual'] as Map;
    expect((annual['points'] as List).length, greaterThan(5));
    // The yearly recurrence reproduces the trained Cox curve for year 1.
    final cox = lab.cox.predict(golden[1]['profile'] as Map<String, dynamic>);
    expect(
      ((annual['points'] as List)[1] as Map)['survival_percent'],
      closeTo((cox['survival_percent_by_year'] as Map)['1'] as double, 1e-9),
    );
  });
}
