// Regression: once a baseline exists, the "Confirmed: ..." source chip sits
// in a Row. Without Flexible it overflowed on narrow phones and large text.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetwin/app/app.dart';
import 'package:lifetwin/app/router.dart';
import 'package:lifetwin/features/activity/activity_models.dart';
import 'package:lifetwin/state/confirmed_baseline.dart';

Future<void> _loadFonts() async {
  for (final (family, file) in const [
    ('Bricolage', 'assets/fonts/BricolageGrotesque-Variable.ttf'),
    ('DMSans', 'assets/fonts/DMSans-Variable.ttf'),
  ]) {
    final bytes = File(file).readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final scale in [1.0, 1.6]) {
    testWidgets('confirmed source chip fits at 320 wide, text x$scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 1386);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(confirmedBaselineProvider.notifier)
          .confirmActivity(
            minutesPerWeek: 1234,
            source: ActivitySource.appleHealth,
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LifeTwinApp(
            router: buildRouter(initialLocation: '/record-measurements'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text('Confirmed: 1234 min/week (Apple Health)'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
