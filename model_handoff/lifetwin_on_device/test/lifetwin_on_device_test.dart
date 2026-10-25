import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifetwin_on_device/lifetwin_on_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled models load and both projections run offline', () async {
    final lab = await loadLifeTwinProjectionLab();
    final request =
        jsonDecode(File('test/neural_golden.json').readAsStringSync()) as List;
    final result = lab.assess(request[1]['profile'] as Map<String, dynamic>);
    expect(result['status'], 'available');
    expect((result['neural_hazard'] as Map)['is_probability'], false);
    expect(
      ((result['annual'] as Map)['points'] as List).length,
      greaterThan(5),
    );
    expect(
      ((result['five_year'] as Map)['points'] as List).length,
      greaterThan(5),
    );
  });
}
