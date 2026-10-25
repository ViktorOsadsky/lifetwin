import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/notebook_screen.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';

import '../support/app_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  Future<TwinRepository> repoWith({required bool memory, int notes = 0}) async {
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => DateTime(2026, 10, 18),
    );
    await repo.applyMemoryConsent(memory);
    for (var i = 0; i < notes; i++) {
      await repo.addHabitNote({'topic': 't$i', 'text': 'note number $i'});
    }
    return repo;
  }

  Future<void> pump(WidgetTester t, TwinRepository repo) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: NotebookScreen(repository: repo, onBack: () {}),
      ),
    );
    await t.pump();
  }

  testWidgets('lists the saved notes with dates and the reason', (t) async {
    final repo = await repoWith(memory: true, notes: 2);
    await pump(t, repo);
    expect(find.text('Mochi’s notebook'), findsOneWidget);
    expect(find.text('2 notes'), findsOneWidget);
    expect(find.text('note number 0'), findsOneWidget);
    expect(find.text('note number 1'), findsOneWidget);
    expect(find.text('Oct 18'), findsNWidgets(2));
    expect(find.text('Mochi remembers these to make suggestions fit you.'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
  });

  testWidgets('turning memory off is two steps; Keep them changes nothing', (t) async {
    final repo = await repoWith(memory: true, notes: 3);
    await pump(t, repo);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Turn off memory?'), findsOneWidget);
    await t.tap(find.text('Turn off and forget'));
    await t.pumpAndSettle();
    expect(find.text('Forget 3 notes?'), findsOneWidget);
    expect(find.text('They’ll be gone for good.'), findsOneWidget);
    await t.tap(find.text('Keep them'));
    await t.pumpAndSettle();
    expect(repo.store.memoryConsent, isTrue);
    expect(repo.store.habitNotes, hasLength(3));

    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.tap(find.text('Turn off and forget'));
    await t.pumpAndSettle();
    await t.tap(find.text('Forget notes'));
    await t.pumpAndSettle();
    expect(repo.store.memoryConsent, isFalse);
    expect(repo.store.habitNotes, isEmpty);
    expect(find.text('Memory is off.'), findsOneWidget);
    expect(find.text('note number 0'), findsNothing);
  });

  testWidgets('Keep memory on the first step changes nothing', (t) async {
    final repo = await repoWith(memory: true, notes: 1);
    await pump(t, repo);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.tap(find.text('Keep memory'));
    await t.pumpAndSettle();
    expect(repo.store.memoryConsent, isTrue);
    expect(repo.store.habitNotes, hasLength(1));
  });

  testWidgets('memory off shows the empty state, and the switch turns it back on', (t) async {
    final repo = await repoWith(memory: false);
    await pump(t, repo);
    expect(find.text('Memory is off.'), findsOneWidget);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(repo.store.memoryConsent, isTrue);
    expect(find.text('Memory is off.'), findsNothing);
  });
}
