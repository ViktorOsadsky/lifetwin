// Recommendation -> Experiment: "Try it with my twin" opens the idea's lever; an idea with no
// lever (or no target) never opens anything or pre-fills 0.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/experiment/ideas_screen.dart';
import 'package:lifesim/experiment/recommendations.dart';
import 'package:lifesim/twin/twin_experiment.dart' show LeverId;
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';

import '../support/app_fonts.dart';
import 'experiment_screen_test.dart' show older;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  Future<TwinRepository> repo() async {
    final r = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => DateTime(2026, 10, 26),
    );
    await r.saveConversationProfile(older);
    return r;
  }

  Future<void> pump(WidgetTester t, TwinRepository r, List<Recommendation> ideas, void Function(Recommendation) onTry) async {
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: IdeasScreen(
          appearance: const TwinAppearance(),
          ideas: ideas,
          cards: r.wellnessCards,
          memoryOn: false,
          onBack: () {},
          onTry: onTry,
        ),
      ),
    );
    await t.pump();
  }

  testWidgets('"Try it with my twin" hands over the tapped idea\'s own lever', (t) async {
    final r = await repo();
    final ideas = await StubRecommendations(r).load();
    final withLever = ideas.where((i) => i.leverId != null).take(2).toList();
    expect(withLever, isNotEmpty);
    final tried = <Recommendation>[];
    await pump(t, r, ideas, tried.add);
    final buttons = find.text('Try it with my twin');
    expect(buttons, findsWidgets);
    for (var i = 0; i < buttons.evaluate().length; i++) {
      await t.ensureVisible(buttons.at(i));
      await t.pump();
      await t.tap(buttons.at(i));
      await t.pump();
    }
    expect(tried.map((i) => i.id), ideas.take(2).where((i) => i.leverId != null).map((i) => i.id).toList());
    for (final i in tried) {
      expect(i.leverId, isNotNull);
    }
  });

  testWidgets('an idea with no lever cannot open the Experiment, and nothing is pre-filled', (t) async {
    final r = await repo();
    var tried = 0;
    const idea = Recommendation(
      id: 'x',
      title: 'Walk after dinner',
      tip: 'A short walk helps.',
      wellnessCardId: 'activity',
    );
    expect(idea.leverId, isNull);
    expect(idea.leverValue, isNull, reason: 'a missing target stays null, never 0');
    await pump(t, r, [idea], (_) => tried++);
    await t.ensureVisible(find.text('Try it with my twin'));
    await t.tap(find.text('Try it with my twin'), warnIfMissed: false);
    await t.pump();
    expect(tried, 0);
  });

  testWidgets('a lever with no target is handed over with a null value, not 0', (t) async {
    final r = await repo();
    Recommendation? got;
    const idea = Recommendation(
      id: 'sleep',
      title: 'More sleep',
      tip: 'Aim for a steadier night.',
      wellnessCardId: 'sleep',
      leverId: LeverId.sleepHours,
    );
    await pump(t, r, [idea], (i) => got = i);
    await t.ensureVisible(find.text('Try it with my twin'));
    await t.tap(find.text('Try it with my twin'));
    await t.pump();
    expect(got?.leverId, LeverId.sleepHours);
    expect(got?.leverValue, isNull);
  });

  test('the app reads the server\'s experiment_lever / experiment_target', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('experiment_lever'));
    expect(hits, isNotEmpty, reason: 'the recommendations contract (#102) has a field the app never parses');
  });
}
