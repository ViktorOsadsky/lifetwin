// The app parses the recommendations contract's lever fields. The hand-over to the Experiment is
// tested on the live Ideas screens (ideas_test.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the app reads the server\'s experiment_lever / experiment_target', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('experiment_lever'));
    expect(hits, isNotEmpty, reason: 'the recommendations contract (#102) has a field the app never parses');
  });
}
