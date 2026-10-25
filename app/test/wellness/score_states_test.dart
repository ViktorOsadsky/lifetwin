// Health score display across every state: wording says higher = better, no state renders a blank
// card, "NaN", "null" or an infinity, and "What moves it" opens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/twin_model.dart' show HealthScoreStatus;
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/wellness/home_panel.dart';
import 'package:lifesim/wellness/models.dart';

import '../support/app_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  Future<void> pump(WidgetTester t, WellnessSnapshot s, {VoidCallback? onDrivers, double scale = 1}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: HomeWellnessPanel(snapshot: s, compact: true, onEstimate: () {}, onDrivers: onDrivers),
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  String allText(WidgetTester t) => [
    for (final w in t.widgetList<Text>(find.byType(Text)))
      if (w.data != null) w.data!,
    for (final w in t.widgetList<RichText>(find.byType(RichText))) w.text.toPlainText(),
  ].join(' | ');

  void expectSane(WidgetTester t, {bool title = true}) {
    expect(t.takeException(), isNull);
    final text = allText(t);
    for (final bad in ['NaN', 'null', 'Infinity', 'Instance of', 'Exception']) {
      expect(text.contains(bad), isFalse, reason: '"$bad" in: $text');
    }
    if (title) expect(find.text('Health score'), findsOneWidget, reason: 'the card keeps its title');
  }

  for (final status in HealthScoreStatus.values) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('status ${status.name} at ${scale}x text shows copy, not a blank card', (t) async {
        final hasNumber = status.hasScore;
        await pump(
          t,
          WellnessSnapshot(
            healthScore: hasNumber ? 0.67 : null,
            status: status,
            ageGroupPercentile: hasNumber ? 41 : null,
          ),
          scale: scale,
        );
        expectSane(t, title: status != HealthScoreStatus.underAge);
        if (status == HealthScoreStatus.underAge) {
          expect(find.text(HomeWellnessPanel.underAgeLine), findsOneWidget);
          expect(find.textContaining('+'), findsNothing);
          return;
        }
        if (hasNumber) {
          expect(find.text('+0.67'), findsOneWidget, reason: 'the score, signed, two decimals');
          expect(find.textContaining('Better health'), findsOneWidget);
          expect(find.textContaining('Higher risk'), findsOneWidget);
        } else {
          // No number: a plain line, never a fabricated score or a scale.
          expect(find.text('Getting to know you'), findsOneWidget);
          expect(find.textContaining('Better health'), findsNothing);
          expect(find.textContaining(RegExp(r'\d\.\d\d')), findsNothing);
        }
      });
    }
  }

  testWidgets('a status without a number shows the model\'s own message when it has one', (t) async {
    await pump(
      t,
      const WellnessSnapshot(
        status: HealthScoreStatus.missingInputs,
        message: 'Tell me your sleep and I can work out your score.',
      ),
    );
    expectSane(t);
    expect(find.text('Tell me your sleep and I can work out your score.'), findsOneWidget);
  });

  testWidgets('a number without a status never shows (no invented score)', (t) async {
    await pump(t, const WellnessSnapshot(healthScore: 1.2));
    expectSane(t);
    expect(find.text('1.20'), findsNothing);
    expect(find.text('Getting to know you'), findsOneWidget);
  });

  testWidgets('a status that has a score but a null value does not crash or show a number', (t) async {
    await pump(t, const WellnessSnapshot(status: HealthScoreStatus.available));
    expectSane(t);
    expect(find.text('Getting to know you'), findsOneWidget);
  });

  testWidgets('higher is better: a higher score sits further along the Better health direction', (t) async {
    await pump(t, const WellnessSnapshot(healthScore: -0.5, status: HealthScoreStatus.available));
    expect(ScoreScale.position(-0.5), lessThan(ScoreScale.position(0.7)));
    expect(ScoreScale.position(0), 0.5); // 0 is the middle of the age group
    expect(find.text('−0.50'), findsOneWidget);
    await pump(t, const WellnessSnapshot(healthScore: 0.7, status: HealthScoreStatus.available));
    expect(find.text('+0.70'), findsOneWidget);
    final l = t.getRect(find.textContaining('Higher risk')), r = t.getRect(find.textContaining('Better health'));
    expect(l.left, lessThan(r.left), reason: 'risk on the left, better health on the right');
  });

  testWidgets('the number is not coloured by value (no red for low, green for high)', (t) async {
    for (final (score, text) in [(-0.4, '−0.40'), (0.9, '+0.90')]) {
      await pump(t, WellnessSnapshot(healthScore: score, status: HealthScoreStatus.available));
      final colour = t.widget<Text>(find.text(text)).style?.color;
      expect(colour == null || colour == LtColors.ink, isTrue, reason: 'score $score coloured $colour');
    }
  });

  testWidgets('scores beyond the usual range still draw and print (clamped marker, true number)', (t) async {
    await pump(t, const WellnessSnapshot(healthScore: 9.87, status: HealthScoreStatus.available));
    expectSane(t);
    expect(find.text('+9.87'), findsOneWidget);
    expect(ScoreScale.position(9.87), 1.0);
    await pump(t, const WellnessSnapshot(healthScore: -5.05, status: HealthScoreStatus.available));
    expect(find.text('−5.05'), findsOneWidget);
    expect(ScoreScale.position(-5.05), 0.0);
  });

  test('formatting edge cases: signed two decimals, a real minus, no sign at zero; the semantics say plus/minus', () {
    expect(formatHealthScore(0.994), '+0.99');
    expect(formatHealthScore(-0.006), '−0.01');
    expect(formatHealthScore(0), '0.00');
    expect(formatHealthScore(-0.004), '0.00', reason: 'never "−0.00"');
    expect(formatHealthScore(-0.4), contains('−'));
    expect(formatHealthScore(-0.4), isNot(contains('-')));
    expect(healthScoreSemantics(0.5), contains('plus 0.50'));
    expect(healthScoreSemantics(-0.4), contains('minus 0.40'));
    expect(healthScoreSemantics(0), startsWith('Health score 0.00.'));
    expect(healthScoreSemantics(1.5), contains('Above 0 is healthier'));
  });

  testWidgets('the info button ("What moves your score") opens at every state that shows a number or a line', (
    t,
  ) async {
    for (final status in [
      HealthScoreStatus.available,
      HealthScoreStatus.extrapolated,
      HealthScoreStatus.missingInputs,
    ]) {
      var opened = 0;
      await pump(
        t,
        WellnessSnapshot(healthScore: status.hasScore ? 1.5 : null, status: status),
        onDrivers: () => opened++,
      );
      await t.tap(find.byTooltip('What moves your score'));
      expect(opened, 1, reason: status.name);
    }
  });

  testWidgets('extrapolated shows the Rough guide badge; available does not', (t) async {
    await pump(t, const WellnessSnapshot(healthScore: 1.5, status: HealthScoreStatus.extrapolated));
    expect(find.text('Rough guide'), findsOneWidget);
    await pump(t, const WellnessSnapshot(healthScore: 0.5, status: HealthScoreStatus.available));
    expect(find.text('Rough guide'), findsNothing);
  });
}
