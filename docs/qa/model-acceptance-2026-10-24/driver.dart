import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final path = Platform.environment['QA107_CAPTURE_PATH'];
    if (path == null || !path.startsWith('/private/tmp/')) {
      throw StateError(
        'QA107_CAPTURE_PATH must name a /private/tmp JSON artifact',
      );
    }
    await File(path)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    stdout.writeln('Synthetic QA107 capture: $path');
  },
);
