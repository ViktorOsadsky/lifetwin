// Weekly check-in through the real screen: the confirmed answer updates the forecast AND the health
// score history, shows up in History on the phone; leaving early changes none of it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/fakes.dart';

import '../support/app_fonts.dart';
import '../support/fake_weekly_guide.dart';
import 'daily_checkin_test.dart' show profile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  final now = DateTime(2026, 11, 1, 18);

  Future<TwinRepository> start(WidgetTester t) async {
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => now);
    await repo.saveConversationProfile(profile);
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: (c, child) => CheckInScope(
          repository: repo,
          guide: FakeWeeklyGuide(),
          speechInput: FakeSpeechInput(),
          speechOutput: FakeSpeechOutput(),
          appearance: look,
          now: () => now,
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openCheckIn(context, kind: CheckInKind.weekly),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '3 hours');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    return repo;
  }

  testWidgets('Yes: the forecast, the score history and History all get the weekly answer, once', (t) async {
    final repo = await start(t);
    final scoreBefore = repo.healthScore;
    final pointsBefore = repo.healthScoreHistory().length;
    final forecastBefore = repo.current!.percentByYear[5];
    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    expect(repo.store.checkins.where((c) => c.kind == 'weekly'), hasLength(1));
    expect(repo.current!.percentByYear[5], isNot(forecastBefore), reason: 'the forecast moved');
    expect(repo.healthScore, isNot(scoreBefore), reason: 'the health score moved');
    final points = repo.healthScoreHistory();
    expect(points, hasLength(pointsBefore + 1), reason: 'one new health score point, not two');
    expect(points.last.score, repo.healthScore);
    expect(points.last.date, '2026-11-01');
    expect(repo.history().where((e) => e.kind == HistoryKind.weekly), hasLength(1), reason: 'saved to History on the phone');
  });

  testWidgets('leaving before Yes changes nothing: no forecast, score, profile or History change', (t) async {
    final repo = await start(t);
    final forecastBefore = repo.current!.percentByYear[5];
    final points = repo.healthScoreHistory().length;
    expect(find.text('Yes'), findsOneWidget);
    // Close the flow without confirming.
    Navigator.of(t.element(find.byType(Scaffold).last)).pop();
    await t.pumpAndSettle();
    expect(repo.store.checkins, isEmpty);
    expect(repo.profile['sedentary_min_day'], 360);
    expect(repo.current!.percentByYear[5], forecastBefore);
    expect(repo.healthScoreHistory(), hasLength(points));
    expect(repo.history().where((e) => e.kind == HistoryKind.weekly), isEmpty);
  });
}
