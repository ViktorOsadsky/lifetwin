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
        closeTo(99.31850509406549, 1e-9));
    expect(survival['death_date'], isNull);
    expect((result['wellness_cards'] as List).isNotEmpty, isTrue);
  });
}
