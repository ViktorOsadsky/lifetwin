// "Delete my data" is a full reset: the app is exactly as on a fresh install, and the
// onboarding conversation can be done again from its first question.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/checkin/my_data_screen.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/fakes.dart';

import 'checkin_controller_test.dart' show FakePort;
import 'forecast_screen_test.dart' show FakeForecastClient, supportedJson;
import 'support/app_fonts.dart';
import 'support/assessments.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  late MemoryBackend backend;
  late TwinRepository repo;
  late FakePort port;
  late FakeConversationGuide guide;
  late VoiceOnboardingController controller;
  late ValueNotifier<TwinAppearance> look;

  Future<void> pumpApp(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    backend = MemoryBackend();
    port = FakePort();
    repo = TwinRepository(
      model: model,
      store: await TwinStore.open(backend),
      reminders: CheckinReminders(port),
    );
    guide = FakeConversationGuide();
    controller = VoiceOnboardingController(guide: guide, input: FakeSpeechInput(), output: FakeSpeechOutput());
    look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    final forecast = FakeForecastClient()
      ..answers.addAll([forecastFrom(supportedJson()), forecastFrom(supportedJson())]);
    await t.pumpWidget(
      LifeTwinApp(controller: controller, forecastClient: forecast, twin: Future.value(repo), appearance: look),
    );
    await t.pump();
    await t.pump();
  }

  /// What the first-run screen shows and the state behind it.
  Map<String, Object?> capture(WidgetTester t) {
    final room = t.widget<RoomScreen>(find.byType(RoomScreen));
    return {
      'roomScreens': find.byType(RoomScreen).evaluate().length,
      'hasProfile': room.hasProfile,
      'texts': [
        for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText(),
      ]..sort((a, b) => '$a'.compareTo('$b')),
      'phase': controller.phase.name,
      'turn': controller.turn,
      'typing': controller.typing,
      'voiceUsable': controller.voiceUsable,
      'aiHelper': controller.aiHelper,
      'notice': controller.notice,
      'caption': controller.caption,
      'mascotLine': controller.mascotLine,
      'correcting': controller.correcting,
      'askingVoice': controller.askingVoice,
      'look': '${look.value.type.name}/${look.value.look.slug}/${look.value.name}/${look.value.room.name}',
      'storeEmpty':
          !repo.store.hasProfile &&
          repo.store.checkins.isEmpty &&
          repo.store.dayLogs.isEmpty &&
          repo.store.historyEntries.isEmpty &&
          repo.store.habitNotes.isEmpty &&
          repo.store.twin == null &&
          !repo.store.memoryConsent &&
          !repo.store.lifespanRevealSeen &&
          !repo.store.outsideAiConsent,
      'current': repo.current,
      'backend': backend.text,
    };
  }

  /// The conversation, typed (the fake guide finishes after one answer), back to the Room.
  Future<void> talkThrough(WidgetTester t) async {
    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    await t.tap(find.text("No, I'll type"));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 700));
    await t.ensureVisible(find.text('Not now'));
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
  }

  Future<void> onboard(WidgetTester t) async {
    await talkThrough(t);
    await t.tap(find.text('Ask the ball'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Back'));
    await t.pumpAndSettle();
    await t.tap(find.text('Not now').last); // the reminder offer
    await t.pumpAndSettle();
  }

  Future<void> seedEverything() async {
    await repo.applyCheckin({
      'complete': true,
      'emergency': false,
      'daily_logs': [],
      'state': {
        'kind': 'quick',
        'confirmed': {'wellbeing': 'good'},
      },
    }, localDate: '2026-10-24');
    await repo.applyMemoryConsent(true);
    await repo.addHabitNote({'topic': 'walks', 'text': 'I walk the dog'});
    await repo.setOutsideAiConsent(true, provider: 'muse');
    await repo.saveTwinLook({'type': 'bear', 'look': 'calHat', 'name': 'Mochi', 'room': 'original'});
    await repo.saveCheckinSettings(repo.checkinSettings.copyWith(remindersOn: true, reminderHour: 7));
    await repo.markLifespanRevealSeen();
    port.scheduled.add(DateTime(2026, 10, 25, 7));
    look.value = const TwinAppearance(name: 'Biscuit');
  }

  Future<void> deleteMyData(WidgetTester t) async {
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('See your data or delete it'), 200);
    await t.ensureVisible(find.text('See your data or delete it'));
    await t.tap(find.text('See your data or delete it'));
    await t.pumpAndSettle();
    expect(find.byType(MyDataScreen), findsOneWidget);
    await t.ensureVisible(find.text('Delete my data'));
    await t.tap(find.text('Delete my data'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete everything'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes, delete'));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 700));
  }

  testWidgets('Delete my data leaves the app exactly as a fresh install', (t) async {
    await pumpApp(t);
    final fresh = capture(t);
    expect(fresh['hasProfile'], isFalse);
    expect(fresh['phase'], 'consent');
    expect(find.text('Talk'), findsOneWidget);

    await onboard(t);
    expect(repo.store.hasProfile, isTrue);
    expect(controller.phase, isNot(VoicePhase.consent), reason: 'the conversation really ran');
    await seedEverything();

    await deleteMyData(t);
    expect(capture(t), fresh);
    expect(port.scheduled, isEmpty, reason: 'the planned reminders are cancelled');
  });

  testWidgets('every persisted item is gone, and deleting twice is safe', (t) async {
    await pumpApp(t);
    await onboard(t);
    await seedEverything();
    final before = jsonDecode(backend.text!) as Map<String, dynamic>;
    expect(
      before.keys.toSet(),
      containsAll([
        'profile',
        'profile_meta',
        'checkins',
        'history',
        'habit_notes',
        'twin',
        'memory_consent',
        'lifespan_reveal_seen',
        'outside_ai_consent',
        'checkin_settings',
      ]),
    );
    await deleteMyData(t);
    expect(backend.text, isNull, reason: 'the whole store document is removed, no key is left behind');
    final reopened = await TwinStore.open(backend);
    expect(reopened.hasProfile, isFalse);
    expect(reopened.checkinSettings.remindersOn, isFalse);
    expect(reopened.twin, isNull);
    expect(reopened.outsideAiProvider, isNull);

    await repo.deleteMyData();
    await repo.deleteMyData();
    expect(backend.text, isNull);
    expect(repo.current, isNull);
  });

  testWidgets('after the reset onboarding runs again from the start, with nothing pre-filled or skipped', (t) async {
    await pumpApp(t);
    await onboard(t);
    final firstRun = guide.calls.length;
    await seedEverything();
    await deleteMyData(t);

    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    expect(find.text("No, I'll type"), findsOneWidget, reason: 'the voice question comes first, as on a fresh install');
    expect(controller.turn, isNull);
    await t.tap(find.text("No, I'll type"));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 700));
    await t.ensureVisible(find.text('Not now'));
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    final start = guide.calls.skip(firstRun).first;
    expect(start['action'], 'start');
    expect(start['state'], isNull, reason: 'no stale answers sent');
    expect(controller.confirmedProfile, isEmpty);
    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(repo.store.hasProfile, isTrue, reason: 'completed again and saved');
  });
}
