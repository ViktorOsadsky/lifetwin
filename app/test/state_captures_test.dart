// Response-frame captures through the real app entrypoint: the fortune
// reveal and a quiz wrong answer (the twin's sniffle plus recovery path),
// at 390x844 with the bundled fonts. Regenerate with --update-goldens.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetwin/app/app.dart';
import 'package:lifetwin/app/router.dart';
import 'package:lifetwin/widgets/lt_twin.dart';

const _appKey = ValueKey('app-root');

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

Future<void> _open(WidgetTester tester, String route) async {
  const dpr = 2.0;
  tester.view.physicalSize = const Size(390 * dpr, 844 * dpr);
  tester.view.devicePixelRatio = dpr;
  tester.view.padding = const FakeViewPadding(top: 47 * dpr, bottom: 34 * dpr);
  tester.view.viewPadding = const FakeViewPadding(
    top: 47 * dpr,
    bottom: 34 * dpr,
  );
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _appKey,
      child: ProviderScope(
        child: LifeTwinApp(router: buildRouter(initialLocation: route)),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('capture fortune revealed', (tester) async {
    await _open(tester, '/fortune');
    await tester.tap(find.text('Reveal my outlook'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('[xx.x %]'), findsOneWidget);
    expect(find.text('Modeled association, not cause'), findsOneWidget);
    await expectLater(
      find.byKey(_appKey),
      matchesGoldenFile('captures/state_fortune_revealed_390x844.png'),
    );
  });

  testWidgets('capture quiz wrong answer', (tester) async {
    await _open(tester, '/quiz');
    await tester.tap(find.text('75 minutes'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(tester.widget<Twin>(find.byType(Twin)).pose, TwinPose.huddle);
    expect(find.text('Help it recover'), findsOneWidget);
    await expectLater(
      find.byKey(_appKey),
      matchesGoldenFile('captures/state_quiz_wrong_390x844.png'),
    );
  });
}
