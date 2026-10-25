import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/checkin/checkin_controller.dart' show emergencyCallUri;
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';

import '../support/app_fonts.dart';

import 'package:lifesim/voice/fakes.dart';

import '../checkin_controller_test.dart' show FakeCheckinGuide;
import 'readback_flow_test.dart' show ContractGuide;

const profile = {
  'age': 55,
  'sex': 'male',
  'height_cm': 175.0,
  'weight_kg': 80.0,
  'sleep_hours': 7,
  'smoking_status': 'never',
  'diabetes': false,
  'hypertension_diagnosed': false,
  'general_health': 3,
  'vigorous_recreation_min_week': 30,
  'moderate_recreation_min_week': 90,
  'sedentary_min_day': 360,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  // A Saturday morning.
  var now = DateTime(2026, 10, 24, 9);
  setUp(() => now = DateTime(2026, 10, 24, 9));

  Future<TwinRepository> repoWith(Map<String, dynamic>? p) async {
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => now);
    if (p != null) await repo.saveConversationProfile(p);
    return repo;
  }

  group('the Room entry and the quick check-in, end to end', () {
    late TwinRepository repo;
    late dynamic guide;
    final opened = <Uri>[];

    Future<void> pumpRoom(WidgetTester t) async {
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
            guide: guide,
            speechInput: FakeSpeechInput(),
            speechOutput: FakeSpeechOutput(),
            appearance: look,
            openUrl: (u) async => opened.add(u),
            now: () => now,
            child: child!,
          ),
          home: RoomScreen(
            appearance: look,
            hasProfile: true,
            onTalk: () {},
            onCustomize: () {},
            onFortune: () async {},
          ),
        ),
      );
      await t.pump();
    }

    setUp(() {
      opened.clear();
      guide = FakeCheckinGuide();
    });

    testWidgets('no saved profile: nothing is offered and openCheckIn does nothing', (t) async {
      repo = await repoWith(null);
      await pumpRoom(t);
      expect(find.text('Check in'), findsNothing);
      expect(find.text('Checked in today'), findsNothing);
      await openCheckIn(t.element(find.byType(RoomScreen)), kind: CheckInKind.quick);
      await t.pump();
      expect(find.text('Check in'), findsNothing);
      expect(guide.calls, isEmpty);
    });

    testWidgets('due: the entry is the most prominent control; the dock stays reachable', (t) async {
      repo = await repoWith(profile);
      await pumpRoom(t);
      expect(find.text('Check in'), findsOneWidget);
      expect(find.text('Checked in today'), findsNothing);
      final entry = t.getSize(find.ancestor(of: find.text('Check in'), matching: find.byType(ConstrainedBox)).first);
      expect(entry.height, greaterThanOrEqualTo(48));
      for (final dock in ['Customize', 'Talk', 'Fortune']) {
        expect(find.text(dock), findsOneWidget, reason: dock);
      }
      expect(t.getTopLeft(find.text('Check in')).dy, lessThan(t.getTopLeft(find.text('Talk')).dy));
    });

    testWidgets(
      'tapping it opens the flow; a tapped answer needs no confirm; finishing records it ONCE and marks it done',
      (t) async {
        repo = await repoWith(profile);
        guide = ContractGuide();
        await pumpRoom(t);
        await t.tap(find.text('Check in'));
        await t.pumpAndSettle();
        expect(find.textContaining('How did you sleep last night?'), findsWidgets);
        expect(find.text('Skip'), findsOneWidget);
        await t.enterText(find.byType(TextField), '7 hours');
        await t.testTextInput.receiveAction(TextInputAction.send);
        await t.pumpAndSettle();
        // One read-back at the end, not one per answer.
        expect(find.text('Yes'), findsNothing);
        expect(find.text('Not quite'), findsNothing);
        expect(repo.store.checkins, isEmpty);
        await t.tap(find.text('About 6 hours'));
        await t.pumpAndSettle();
        expect(find.text('Looks right'), findsOneWidget);
        expect(repo.store.checkins, isEmpty, reason: 'nothing is saved before the yes');
        await t.tap(find.text('Looks right'));
        await t.pumpAndSettle();
        // Finished: recorded exactly once.
        expect(repo.store.checkins, hasLength(1));
        expect(repo.store.checkins.single.kind, 'quick');
        expect(repo.history().where((e) => e.kind == HistoryKind.quick), hasLength(1));
        expect(find.text('Back to my room'), findsOneWidget);
        await t.tap(find.text('Back to my room'));
        await t.pumpAndSettle();
        // Done for today: the quiet state replaces the primary button; nothing is recorded again.
        expect(repo.store.checkins, hasLength(1));
        expect(find.text('Checked in today'), findsOneWidget);
        expect(find.text('Check in'), findsNothing);
        for (final dock in ['Customize', 'Talk', 'Fortune']) {
          expect(find.text(dock), findsOneWidget);
        }
      },
    );

    testWidgets('skip is quick, and a skipped answer is never filled in', (t) async {
      repo = await repoWith(profile);
      await pumpRoom(t);
      await t.tap(find.text('Check in'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '6 hours');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pumpAndSettle();
      await t.tap(find.text('Yes'));
      await t.pumpAndSettle();
      await t.tap(find.text('Skip'));
      await t.pumpAndSettle();
      expect(repo.store.checkins, hasLength(1));
      expect(repo.store.checkins.single.answers['sleep_hours_last_night'], 6);
      expect(repo.store.checkins.single.answers.containsKey('sedentary_min_day'), isFalse);
    });

    testWidgets('an emergency pauses calmly: Call 911 is a tapped tel: link, nothing is saved, Continue resumes', (
      t,
    ) async {
      repo = await repoWith(profile);
      await pumpRoom(t);
      await t.tap(find.text('Check in'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), "I can't breathe");
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pumpAndSettle();
      expect(find.text('If you need help right now, please call 911.'), findsOneWidget);
      expect(opened, isEmpty, reason: 'never auto-dial');
      expect(repo.store.checkins, isEmpty);
      await t.tap(find.text('Call 911'));
      expect(opened.single, emergencyCallUri);
      expect(opened.single.toString(), 'tel:911');
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text('If you need help right now, please call 911.'), findsNothing);
      expect(guide.calls.last['action'], 'resume');
    });

    testWidgets('openCheckIn when nothing is left to ask today says so, and records nothing', (t) async {
      repo = await repoWith(profile);
      await repo.applyCheckin({
        'complete': true,
        'emergency': false,
        'daily_logs': [],
        'state': {
          'kind': 'quick',
          'confirmed': {'wellbeing': 'good'},
        },
      }, localDate: '2026-10-24');
      await pumpRoom(t);
      expect(find.text('Check in'), findsNothing);
      expect(find.text('Checked in today'), findsOneWidget);
      unawaited(openCheckIn(t.element(find.byType(RoomScreen)), kind: CheckInKind.quick));
      await t.pumpAndSettle();
      expect(find.text('All set for today'), findsOneWidget);
      expect(repo.store.checkins, hasLength(1));
      expect(guide.calls, isEmpty);
    });
  });
}
