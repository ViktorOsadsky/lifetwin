// The Room keeps #58's hooks: the check-in entry, the agentic pills and the twin's mood.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/experiment/room_pills.dart';
import 'package:lifesim/room/room_scene.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/fakes.dart';

import 'checkin_controller_test.dart' show FakeCheckinGuide;
import 'support/app_fonts.dart';

const _smoker = {
  'age': 55,
  'sex': 'male',
  'height_cm': 175.0,
  'weight_kg': 80.0,
  'sleep_hours': 5,
  'smoking_status': 'current',
  'diabetes': false,
  'hypertension_diagnosed': false,
  'general_health': 3,
  'vigorous_recreation_min_week': 0,
  'moderate_recreation_min_week': 20,
  'sedentary_min_day': 600,
};

final _steady = {
  ..._smoker,
  'sleep_hours': 7,
  'smoking_status': 'never',
  'vigorous_recreation_min_week': 60,
  'moderate_recreation_min_week': 200,
  'sedentary_min_day': 300,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  final now = DateTime(2026, 10, 24, 9);

  Future<TwinRepository> repoWith(Map<String, dynamic>? p) async {
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => now);
    if (p != null) await repo.saveConversationProfile(p);
    return repo;
  }

  Future<void> pumpRoom(WidgetTester t, TwinRepository repo, ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final look = ValueNotifier(const TwinAppearance(name: 'Mochi'));
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: (context, child) => CheckInScope(
          repository: repo,
          guide: FakeCheckinGuide(),
          speechInput: FakeSpeechInput(),
          speechOutput: FakeSpeechOutput(),
          appearance: look,
          now: () => now,
          child: child!,
        ),
        home: RoomScreen(
          appearance: look,
          hasProfile: repo.store.hasProfile,
          onTalk: () {},
          onCustomize: () {},
          onFortune: () async {},
          extraPills: roomPills(
            repository: repo,
            onExperiment: () {},
            onStillLearning: () {},
            onWellness: () {},
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
  }

  testWidgets('with a profile and a check-in due, the Room shows the check-in entry', (t) async {
    await pumpRoom(t, await repoWith(_smoker));
    expect(find.text('Check in'), findsOneWidget);
  });

  testWidgets('without a profile there is no check-in entry', (t) async {
    await pumpRoom(t, await repoWith(null));
    expect(find.text('Check in'), findsNothing);
  });

  testWidgets('the Room shows the agentic pills', (t) async {
    await pumpRoom(t, await repoWith(_smoker));
    expect(find.text('What I see'), findsOneWidget);
    expect(find.text('Try a change'), findsOneWidget);
  });

  testWidgets("the twin's mood follows the repository", (t) async {
    final repo = await repoWith(_smoker);
    await pumpRoom(t, repo);
    moodOf() => t.widget<RoomScene>(find.byType(RoomScene)).twinState!.mood;
    final before = moodOf();
    expect(before, repo.twinState().mood);
    await repo.saveConversationProfile(_steady);
    await t.pump();
    final after = moodOf();
    expect(after, repo.twinState().mood);
    expect(after, isNot(before));
  });
}
