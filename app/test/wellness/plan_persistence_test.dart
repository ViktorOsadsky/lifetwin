// Today's plan survives a relaunch: the revision after a check-in still has its base and can say
// what changed. It is kept per local date, and Delete my data removes it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';

import '../checkin/daily_checkin_test.dart' show profile;
import '../checkin/readback_flow_test.dart' show ContractGuide;
import '../checkin/routes_wiring_test.dart' show FakeCapabilities;
import '../support/app_fonts.dart';
import 'coach_test.dart' show FakeCoach;
import 'today_card_test.dart' show fourSlots;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  late MemoryBackend backend;
  var now = DateTime(2026, 10, 24, 9);

  /// Opens the app on [backend] (a relaunch when it already holds data) and returns the after-check-in hook.
  Future<(TwinRepository, TodayPlanHook)> launch(WidgetTester t, FakeCoach coach) async {
    final repo = TwinRepository(model: model, store: await TwinStore.open(backend), clock: () => now);
    if (!repo.store.hasProfile) await repo.saveConversationProfile(profile);
    final look = ValueNotifier(const TwinAppearance(name: 'Mochi'));
    addTearDown(look.dispose);
    final voice = VoiceOnboardingController(
      guide: FakeConversationGuide(),
      input: FakeSpeechInput(),
      output: FakeSpeechOutput(),
    );
    addTearDown(voice.dispose);
    final routes = AgenticRoutes(
      look: look,
      api: ApiBase(),
      voice: () => voice,
      guide: ContractGuide(),
      coach: coach,
      capabilities: FakeCapabilities(null),
    )..attach(repo);
    await t.pumpWidget(MaterialApp(builder: routes.wrap, home: const Scaffold(body: Text('room'))));
    return (repo, t.widget<CheckInScope>(find.byType(CheckInScope)).todayPlan!);
  }

  setUp(() {
    backend = MemoryBackend();
    now = DateTime(2026, 10, 24, 9);
  });

  testWidgets('after a relaunch the revision still sends the earlier plan and says what changed', (t) async {
    final first = FakeCoach()..responses.add(fourSlots());
    final (_, hook) = await launch(t, first);
    expect((await hook.update()).changes, isNull, reason: 'nothing to compare with yet');
    expect(first.requests.single.containsKey('previous_plan'), isFalse);

    final second = FakeCoach()..responses.add(fourSlots(revision: 'r2'));
    final (repo, again) = await launch(t, second);
    expect(repo.todayPlan?['revision_id'], 'r1', reason: 'kept in the store, not only in memory');
    final update = await again.update();
    expect(update.changes, isNotNull);
    final sent = second.requests.single;
    expect((sent['previous_plan'] as Map)['revision_id'], 'r1');
    expect(sent['latest_revision_id'], 'r1');
    expect(repo.todayPlan?['revision_id'], 'r2');
  });

  testWidgets('a plan from an earlier day is not the base for today', (t) async {
    final (_, hook) = await launch(t, FakeCoach()..responses.add(fourSlots()));
    await hook.update();
    now = DateTime(2026, 10, 25, 9);
    final next = FakeCoach()..responses.add(fourSlots(revision: 'r2'));
    final (repo, again) = await launch(t, next);
    expect(repo.todayPlan, isNull);
    expect((await again.update()).changes, isNull);
    expect(next.requests.single.containsKey('previous_plan'), isFalse);
  });

  testWidgets('Delete my data removes the kept plan', (t) async {
    final (repo, hook) = await launch(t, FakeCoach()..responses.add(fourSlots()));
    await hook.update();
    expect(repo.todayPlan, isNotNull);
    await repo.deleteMyData();
    expect(repo.todayPlan, isNull);
    expect((await TwinStore.open(backend)).lastPlan, isNull);
  });
}
