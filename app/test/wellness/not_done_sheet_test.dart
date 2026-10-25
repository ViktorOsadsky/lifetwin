import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/widgets/widgets.dart' show LipButton;
import 'package:lifesim/wellness/coach_client.dart';
import 'package:lifesim/wellness/daily_plan_screen.dart';

import 'coach_test.dart' show FakeCoach, planJson;

/// The sheet lives in the Navigator overlay, so the text scale and keyboard inset are applied
/// through MaterialApp.builder (above the Navigator), not around `home`.
Future<FakeCoach> _open(WidgetTester t, {required double scale, required double keyboard, Size size = const Size(390, 844)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.view.viewInsets = FakeViewPadding(bottom: keyboard);
  t.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(t.view.reset);
  final client = FakeCoach()..responses.add(DailyPlan.fromJson(planJson(revision: 'r2')));
  await t.pumpWidget(
    MaterialApp(
      theme: lifeTwinTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: child!,
      ),
      home: DailyPlanScreen(
        client: client,
        confirmedContext: () => {'local_date': '2026-10-24'},
        initialPlan: DailyPlan.fromJson(planJson()),
        onBack: () {},
        onTalk: () {},
      ),
    ),
  );
  await t.pump();
  await t.scrollUntilVisible(find.text('Not done'), 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
  return client;
}

void main() {
  for (final (scale, keyboard) in [(1.0, 0.0), (1.0, 300.0), (1.6, 0.0), (1.6, 300.0)]) {
    testWidgets('Tell Mochi is tappable and sends the reason (scale $scale, keyboard $keyboard)', (t) async {
      final client = await _open(t, scale: scale, keyboard: keyboard);
      await t.tap(find.text('Not done'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('No time')); // with 1.6x text and the keyboard the reasons scroll
      await t.pumpAndSettle();
      await t.tap(find.text('No time'));
      await t.pump();
      // Pinned above the keyboard / home indicator, whole and at least 48 pt tall.
      final button = find.ancestor(of: find.text('Tell Mochi'), matching: find.byType(LipButton));
      final r = t.getRect(button);
      expect(r.bottom, lessThanOrEqualTo(844 - (keyboard > 0 ? keyboard : 34)), reason: 'clear of the keyboard or home indicator');
      expect(r.top, greaterThanOrEqualTo(47));
      expect(r.height, greaterThanOrEqualTo(48));
      await t.tap(find.text('Tell Mochi'));
      await t.pumpAndSettle();
      expect(client.requests, hasLength(1));
      expect(client.requests.single['feedback'], {
        'revision_id': 'r1',
        'items': [
          {'item_id': 'move', 'status': 'not_done', 'reason': 'No time'},
        ],
      });
      expect(find.text('Tell Mochi'), findsNothing);
      expect(find.text('Anything you’d like Mochi to know?'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
