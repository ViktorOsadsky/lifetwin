// Stress matrix: nine screens at three phone sizes and two text scales,
// rendered through the real app entrypoint and theme with the bundled
// fonts loaded. Asserts no layout overflow and that each screen's primary
// action is fully inside the first viewport, then saves a golden capture
// under test/captures/ (regenerate with --update-goldens).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetwin/app/app.dart';
import 'package:lifetwin/app/router.dart';
import 'package:lifetwin/widgets/lt_pressable.dart';
import 'package:lifetwin/widgets/lt_stepper.dart';

const _appKey = ValueKey('app-root');

typedef _Phone = ({String name, double w, double h, double top, double bottom});

const List<_Phone> _phones = [
  (name: '320x693', w: 320, h: 693, top: 20, bottom: 0),
  (name: '390x844', w: 390, h: 844, top: 47, bottom: 34),
  (name: '430x932', w: 430, h: 932, top: 47, bottom: 34),
];

const _scales = [1.0, 1.6];

/// Screen name, route, and a finder for the primary action.
final _screens = <(String, String, Finder Function())>[
  ('room', '/room', () => find.text('Fortune')),
  ('intake', '/intake', () => find.byType(TextField)),
  ('experiment', '/experiment', () => find.byType(LtStepper).first),
  ('activity', '/activity', () => find.text('Add your first workout')),
  ('studio', '/studio', () => find.byType(LtPressable).first),
  ('fortune', '/fortune', () => find.text('Reveal my outlook')),
  ('quiz', '/quiz', () => find.text('75 minutes')),
  ('plan', '/plan', () => find.text('Add 150 active minutes a week')),
  ('levers', '/levers', () => find.text('Research a plan')),
];

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

  for (final (name, route, primary) in _screens) {
    for (final phone in _phones) {
      for (final scale in _scales) {
        final id = '${name}_${phone.name}_x$scale';
        testWidgets('stress $id', (tester) async {
          const dpr = 2.0;
          tester.view.physicalSize = Size(phone.w * dpr, phone.h * dpr);
          tester.view.devicePixelRatio = dpr;
          tester.view.padding = FakeViewPadding(
            top: phone.top * dpr,
            bottom: phone.bottom * dpr,
          );
          tester.view.viewPadding = FakeViewPadding(
            top: phone.top * dpr,
            bottom: phone.bottom * dpr,
          );
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearAllTestValues);

          await tester.pumpWidget(
            RepaintBoundary(
              key: _appKey,
              child: ProviderScope(
                child: LifeTwinApp(router: buildRouter(initialLocation: route)),
              ),
            ),
          );
          // Let SVG icons decode off the fake clock, then settle by time.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pump(const Duration(milliseconds: 100));

          expect(tester.takeException(), isNull, reason: 'overflow in $id');

          final f = primary();
          expect(f, findsOneWidget, reason: 'primary action on $id');
          final r = tester.getRect(f);
          expect(r.top, greaterThanOrEqualTo(0), reason: '$id: $r');
          expect(
            r.bottom,
            lessThanOrEqualTo(phone.h),
            reason: '$id primary action below the first viewport: $r',
          );

          await expectLater(
            find.byKey(_appKey),
            matchesGoldenFile('captures/$id.png'),
          );
        });
      }
    }
  }
}
