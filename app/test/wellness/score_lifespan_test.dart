import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/twin_model.dart' show HealthScoreStatus, TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/wellness/repository_adapter.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/wellness/home_panel.dart';
import 'package:lifesim/wellness/lifespan_block.dart';
import 'package:lifesim/wellness/models.dart';

Future<void> pump(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: lifeTwinTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('health score: higher is better', () {
    test('sign, two decimals and the accessible name come from the value', () {
      expect(formatHealthScore(0.04), '+0.04');
      expect(formatHealthScore(-1.5), '−1.50');
      expect(formatHealthScore(0.001), '0.00');
      expect(healthScoreSemantics(0.04), 'Health score plus 0.04. Higher is better. 0 is the middle of people your age.');
      expect(healthScoreSemantics(-0.5), 'Health score minus 0.50. Higher is better. 0 is the middle of people your age.');
    });

    test('the marker sits by the public value: better health is to the right', () {
      expect(ScoreScale.position(0), 0.5);
      expect(ScoreScale.position(1.5), greaterThan(0.5));
      expect(ScoreScale.position(-1.5), lessThan(0.5));
      expect(ScoreScale.position(99), 1);
    });

    testWidgets('the card reads Higher risk, Average, Better health and names the score', (t) async {
      for (final score in [0.04, -1.2]) {
        await pump(
          t,
          HealthScoreSummary(
            snapshot: WellnessSnapshot(healthScore: score, status: HealthScoreStatus.available),
          ),
        );
        expect(find.text('‹ Higher risk'), findsOneWidget);
        expect(find.text('Average'), findsOneWidget);
        expect(find.text('Better health ›'), findsOneWidget);
        expect(find.text(formatHealthScore(score)), findsOneWidget);
        expect(find.bySemanticsLabel(healthScoreSemantics(score)), findsOneWidget);
        // The marker is on the side the value says.
        final marker = t.getCenter(find.byKey(const ValueKey('score-marker'))).dx;
        final bar = t.getCenter(find.text('Average')).dx;
        expect(score > 0 ? marker > bar - 40 : marker < bar, isTrue);
      }
    });
  });

  group('the lifespan block', () {
    const l = LifespanReveal(
      expectedAge: 87,
      p25Age: 80,
      p75Age: 93,
      expectedYear: 2051,
      caveat: 'A rough estimate from people with a similar profile.',
    );

    testWidgets('hidden when the engine has no estimate', (t) async {
      await pump(t, const LifespanBlock(lifespan: null));
      expect(find.textContaining('Around'), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('a year and ages, the caveat behind (i), never a day', (t) async {
      await pump(t, const LifespanBlock(lifespan: l));
      expect(find.text('Around 2051'), findsOneWidget);
      expect(find.text('about age 87, most likely 80–93'), findsOneWidget);
      expect(find.text('Rough guide'), findsNothing);
      for (final s in t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '')) {
        expect(
          RegExp(
            r'January|February|March|April|May |June|July|August|September|October|November|December|\d{1,2}/\d{1,2}',
          ).hasMatch(s),
          isFalse,
          reason: s,
        );
      }
      await t.tap(find.byIcon(Icons.info_outline_rounded));
      await t.pumpAndSettle();
      expect(find.text(l.caveat!), findsOneWidget);
    });

    testWidgets('outside ages 35-79 the Rough guide badge shows', (t) async {
      await pump(
        t,
        const LifespanBlock(
          lifespan: LifespanReveal(expectedAge: 90, p25Age: 84, p75Age: 95, expectedYear: 2040, roughGuide: true),
        ),
      );
      expect(find.text('Rough guide'), findsOneWidget);
    });
  });

  test('the reveal is marked seen once, and the block stays hidden while the engine has no estimate', () async {
    final repo = TwinRepository(model: await TwinModelService.load(), store: await TwinStore.open(MemoryBackend()));
    final w = RepositoryWellness(repo);
    expect(w.snapshot.lifespanRevealSeen, isFalse);
    expect(w.snapshot.lifespan, isNull);
    w.markLifespanRevealSeen();
    expect(w.snapshot.lifespanRevealSeen, isTrue);
  });
}
