// The health score index and the lifespan range in the UI (design KN-HZ, K-HZ-1..4).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/experiment/result_display.dart';
import 'package:lifesim/experiment/widgets/result_card.dart';
import 'package:lifesim/twin/twin_experiment.dart';
import 'package:lifesim/twin/twin_model.dart' show HealthScoreStatus;
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/wellness/home_panel.dart';
import 'package:lifesim/wellness/lifespan_block.dart';
import 'package:lifesim/wellness/models.dart';

import '../support/app_fonts.dart';

const _rosa = WellnessSnapshot(
  healthScore: 0.504,
  status: HealthScoreStatus.available,
  ageGroupPercentile: 78.6,
  groupLabel: 'women 59–69',
  lifespanRevealSeen: true,
  lifespan: LifespanReveal(
    expectedAge: 99,
    p25Age: 87,
    p75Age: 109,
    expectedYear: 2061,
    caveat: 'If inputs stay fixed.',
  ),
);

Future<void> pump(WidgetTester t, Widget child, {double width = 390, double scale = 1}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: lifeTwinTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 844), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
  await t.pump();
}

ExperimentResult _result({double? current = 0.504, double? delta = 0.0436}) => ExperimentResult(
  status: 'available',
  differenceByYear: {1: 0.5, 2: 1, 3: 2, 4: 3, 5: 4.15},
  currentPercentByYear: {1: 98, 2: 96, 3: 94, 4: 92, 5: 89.46},
  alternativePercentByYear: {5: 93.6},
  currentScore: current,
  scoreDelta: delta,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  test('one formatter: values to two decimals, deltas signed with a real minus, "No change" at zero', () {
    expect(formatHealthScore(0.504), '+0.50');
    expect(formatHealthScore(-0.396), '−0.40');
    expect(formatHealthScore(0), '0.00');
    expect(formatScoreDelta(0.05), '+0.05');
    expect(formatScoreDelta(0.0436), '+0.04');
    expect(formatScoreDelta(-0.03), '−0.03');
    expect(formatScoreDelta(-0.03).codeUnitAt(0), 0x2212);
    expect(formatScoreDelta(0), 'No change');
    expect(formatScoreDelta(0.004), 'No change');
    expect(formatScoreDelta(-0.004), 'No change');
    expect(scoreChangeLine(0.5, 0.05), 'Health score +0.50 → +0.55 (+0.05)');
    expect(scoreChangeSemantics(0.5, 0.05), 'Health score would go from plus 0.50 to plus 0.55, up 0.05.');
    expect(scoreChangeSemantics(0.02, -0.05), 'Health score would go from plus 0.02 to minus 0.03, down 0.05.');
  });

  group('the Home card', () {
    testWidgets('one number, the percentile line, the scale and a 48pt circled i', (t) async {
      await pump(t, HomeWellnessPanel(snapshot: _rosa, compact: true, onEstimate: () {}, onDrivers: () {}));
      expect(find.text('+0.50'), findsOneWidget);
      expect(find.text('Health score'), findsOneWidget);
      expect(find.text('Healthier than 79 of 100 people your age'), findsOneWidget);
      expect(find.text('‹ Higher risk'), findsOneWidget);
      expect(find.text('Average'), findsOneWidget);
      expect(find.text('Better health ›'), findsOneWidget);
      expect(find.text(HomeWellnessPanel.tagline), findsOneWidget);
      expect(find.textContaining('×'), findsNothing);
      expect(find.textContaining('0.504'), findsNothing);
      final i = t.getSize(find.byTooltip('About the health score'));
      expect(i.width >= 48 && i.height >= 48, isTrue);
      expect(
        find.bySemanticsLabel(
          'Health score plus 0.50. Above 0 is healthier; 0 is the middle of people your age. '
          'Healthier than 79 of 100 people your age.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the marker sits at the percentile, not at the raw index', (t) async {
      await pump(t, HomeWellnessPanel(snapshot: _rosa, compact: true, onEstimate: () {}));
      final track = t.getRect(find.byKey(const ValueKey('score-marker')));
      final scale = t.getRect(find.byType(ScoreScale));
      final along = (track.center.dx - scale.left - 8) / (scale.width - 16);
      expect(along, closeTo(0.786, 0.02));
      expect(ScoreScale.position(0.504), isNot(closeTo(0.786, 0.05)), reason: 'the score position would differ');
    });

    testWidgets('the circled i opens the sheet with the group, the note, "Linked, not proven." and Got it', (t) async {
      await pump(t, HomeWellnessPanel(snapshot: _rosa, compact: true, onEstimate: () {}));
      await t.tap(find.byTooltip('About the health score'));
      await t.pumpAndSettle();
      expect(find.text('Health score +0.50'), findsOneWidget);
      expect(
        find.text(
          '0 is the middle of women 59–69 in the study. Above 0 is healthier, below 0 is less healthy. '
          'It compares risk; it is not a chance of living or dying.',
        ),
        findsOneWidget,
      );
      expect(find.text('Habit ticks and check-ins don’t change it; your confirmed answers do.'), findsOneWidget);
      expect(find.text('Linked, not proven.'), findsOneWidget);
      expect(find.text('Rough guide'), findsNothing);
      await t.tap(find.text('Got it'));
      await t.pumpAndSettle();
      expect(find.text('Linked, not proven.'), findsNothing);
    });

    testWidgets('a rough score shows the Rough guide badge on the card and in the sheet', (t) async {
      const rough = WellnessSnapshot(
        healthScore: 0.22,
        status: HealthScoreStatus.extrapolated,
        ageGroupPercentile: 64,
        groupLabel: 'women 22–32',
      );
      await pump(t, HomeWellnessPanel(snapshot: rough, compact: true, onEstimate: () {}));
      expect(find.text('Rough guide'), findsOneWidget);
      await t.tap(find.byTooltip('About the health score'));
      await t.pumpAndSettle();
      expect(find.text('Rough guide'), findsNWidgets(2));
      expect(find.textContaining('women 22–32 in the study'), findsOneWidget);
    });

    testWidgets('a negative score and exactly zero: a real minus, "Healthier than 30 of 100", no sign at 0', (t) async {
      const neg = WellnessSnapshot(
        healthScore: -0.396,
        status: HealthScoreStatus.available,
        ageGroupPercentile: 30,
        groupLabel: 'men 40–50',
      );
      await pump(t, HomeWellnessPanel(snapshot: neg, compact: true, onEstimate: () {}));
      expect(find.text('−0.40'), findsOneWidget);
      expect(find.text('Healthier than 30 of 100 people your age'), findsOneWidget);
      final track = t.getRect(find.byKey(const ValueKey('score-marker')));
      final scale = t.getRect(find.byType(ScoreScale));
      expect((track.center.dx - scale.left - 8) / (scale.width - 16), closeTo(0.30, 0.02));
      await t.tap(find.byTooltip('About the health score'));
      await t.pumpAndSettle();
      expect(find.text('Health score −0.40'), findsOneWidget);
      expect(find.textContaining('0 is the middle of men 40–50 in the study'), findsOneWidget);
      await t.tap(find.text('Got it'));
      await t.pumpAndSettle();
      const zero = WellnessSnapshot(healthScore: 0, status: HealthScoreStatus.available, ageGroupPercentile: 50);
      await pump(t, HomeWellnessPanel(snapshot: zero, compact: true, onEstimate: () {}));
      expect(find.text('0.00'), findsOneWidget);
      expect(find.text('+0.00'), findsNothing);
      expect(find.text('−0.00'), findsNothing);
    });

    testWidgets('no card under 18 and no number when null', (t) async {
      await pump(
        t,
        HomeWellnessPanel(
          snapshot: const WellnessSnapshot(healthScore: 0.2, status: HealthScoreStatus.underAge),
          onEstimate: () {},
        ),
      );
      expect(find.text('+0.20'), findsNothing);
      expect(find.text('Health score'), findsNothing);
      expect(find.text(HomeWellnessPanel.underAgeLine), findsOneWidget);
      await pump(t, HomeWellnessPanel(snapshot: const WellnessSnapshot(), onEstimate: () {}));
      expect(find.byTooltip('About the health score'), findsNothing);
      expect(find.textContaining(RegExp(r'\d\.\d\d')), findsNothing);
    });

    for (final w in [390.0, 320.0]) {
      testWidgets('1.6x text at $w wide: no overflow, tagline dropped, targets stay 48', (t) async {
        await pump(
          t,
          HomeWellnessPanel(snapshot: _rosa, compact: true, onEstimate: () {}, onDrivers: () {}),
          width: w,
          scale: 1.6,
        );
        expect(t.takeException(), isNull);
        expect(find.text(HomeWellnessPanel.tagline), findsNothing);
        expect(find.text('+0.50'), findsOneWidget);
        expect(t.getSize(find.byTooltip('About the health score')).shortestSide, greaterThanOrEqualTo(48));
      });
    }
  });

  group('lifespan', () {
    testWidgets('the chip: "Around {year}" with the caption, flag off, and its spoken form says rough guide', (
      t,
    ) async {
      await pump(t, HomeWellnessPanel(snapshot: _rosa, compact: true, onEstimate: () {}));
      expect(find.text('Around 2061'), findsOneWidget);
      expect(find.text('Estimate, rough guide'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('rough guide', caseSensitive: false)), findsWidgets);
    });

    testWidgets('the reveal: range, caption always, caveat behind the i, never "life expectancy"', (t) async {
      await pump(t, LifespanBlock(lifespan: _rosa.lifespan));
      expect(find.text('Around 2061'), findsOneWidget);
      expect(find.text('age 87–109'), findsOneWidget);
      expect(find.text('Estimate, rough guide'), findsOneWidget);
      expect(find.textContaining('xpectancy'), findsNothing);
      await t.tap(find.byIcon(Icons.info_outline_rounded));
      await t.pumpAndSettle();
      expect(find.text('If inputs stay fixed.'), findsOneWidget);
    });

    testWidgets('an open top end reads 110+', (t) async {
      const l = LifespanReveal(
        expectedAge: 106,
        p25Age: 89,
        p75Age: 110,
        expectedYear: 2070,
        p75OpenEnded: true,
        caveat: 'x',
      );
      expect(l.rangeText, 'age 89–110+');
      await pump(t, const LifespanBlock(lifespan: l));
      expect(find.text('age 89–110+'), findsOneWidget);
      expect(
        const LifespanReveal(
          expectedAge: 111,
          p25Age: 110,
          p75Age: 110,
          expectedYear: 2080,
          p25OpenEnded: true,
          p75OpenEnded: true,
        ).rangeText,
        'age 110+',
      );
    });
  });

  group('the Experiment line', () {
    Widget card({double? current = 0.504, double? delta = 0.0436}) => ResultCard(
      display: ResultDisplay.of(_result(current: current, delta: delta)),
      leverName: (id) => id,
      currentScore: current,
      scoreDelta: delta,
    );

    testWidgets('shows from → to (delta) above the survival rows, with a spoken form', (t) async {
      await pump(t, card(current: 0.5, delta: 0.05));
      expect(find.text('Health score +0.50 → +0.55 (+0.05)'), findsOneWidget);
      final sem = t.ensureSemantics();
      await t.pump();
      expect(
        t.getSemantics(find.text('Health score +0.50 → +0.55 (+0.05)')).label,
        contains('Health score would go from plus 0.50 to plus 0.55, up 0.05.'),
      );
      sem.dispose();
      expect(find.text('About 4 more in 100'), findsOneWidget, reason: 'the survival rows stay');
      expect(
        t.getTopLeft(find.text('Health score +0.50 → +0.55 (+0.05)')).dy,
        lessThan(t.getTopLeft(find.text('About 4 more in 100')).dy),
      );
    });

    testWidgets('a drop uses a real minus', (t) async {
      await pump(t, card(current: 0.5, delta: -0.03));
      expect(find.text('Health score +0.50 → +0.47 (−0.03)'), findsOneWidget);
    });

    testWidgets('hidden when scoreDelta or the current score is null', (t) async {
      await pump(t, card(delta: null));
      expect(find.textContaining('Health score'), findsNothing);
      await pump(t, card(current: null));
      expect(find.textContaining('Health score'), findsNothing);
      expect(find.text('About 4 more in 100'), findsOneWidget);
    });
  });
}
