import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/checkin/checkin_scheduler.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';

import '../support/app_fonts.dart';
import '../support/fake_checkin_client.dart';

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

  // A Wednesday.
  var now = DateTime(2026, 10, 28, 9);
  setUp(() => now = DateTime(2026, 10, 28, 9));

  Future<TwinRepository> repoWith(Map<String, dynamic>? p) async {
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => now);
    if (p != null) await repo.saveConversationProfile(p);
    return repo;
  }

  group('CheckinScheduler.due', () {
    testWidgets('nothing is due before there is a profile', (t) async {
      final s = CheckinScheduler(await repoWith(null), now: () => now);
      expect(s.due(), isNull);
      expect(s.dueKinds(), isEmpty);
    });

    testWidgets('daily is due until one is finished today; weekly is due on Sundays', (t) async {
      final repo = await repoWith(profile);
      final s = CheckinScheduler(repo, now: () => now);
      expect(s.due(), CheckInKind.daily);
      expect(s.dueKinds(), [CheckInKind.daily]);
      expect(s.doneToday(CheckInKind.daily), isFalse);
      await repo.applyCheckin({
        'complete': true,
        'emergency': false,
        'state': {
          'kind': 'daily',
          'confirmed': {'wellbeing': 'good'},
        },
      });
      expect(s.due(), isNull);
      expect(s.doneToday(CheckInKind.daily), isTrue);
      // Tomorrow it is due again.
      now = DateTime(2026, 10, 29, 9);
      expect(s.due(), CheckInKind.daily);
      // Sunday: daily first, weekly after.
      now = DateTime(2026, 11, 1, 9);
      expect(s.dueKinds(), [CheckInKind.daily, CheckInKind.weekly]);
      await repo.applyCheckin({
        'complete': true,
        'emergency': false,
        'state': {'kind': 'weekly', 'confirmed': <String, dynamic>{}},
      });
      expect(s.dueKinds(), [CheckInKind.daily]);
    });
  });

  group('the Room entry and the daily flow, end to end', () {
    late TwinRepository repo;
    late FakeCheckinClient client;
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
            client: client,
            appearance: look,
            openUrl: (u) async => opened.add(u),
            child: child!,
          ),
          home: Builder(
            builder: (context) => RoomScreen(
              appearance: look,
              hasProfile: true,
              twin: repo,
              checkins: CheckinScheduler(repo, now: () => now),
              onCheckIn: (kind) => openCheckIn(context, kind: kind),
              onTalk: () {},
              onCustomize: () {},
              onFortune: () async {},
            ),
          ),
        ),
      );
      await t.pump();
    }

    setUp(() => opened.clear());

    Future<void> answer(WidgetTester t, String label) async {
      await t.tap(find.text(label));
      await t.pumpAndSettle();
    }

    testWidgets('due: the entry is the most prominent control; the dock stays reachable', (t) async {
      repo = await repoWith(profile);
      client = FakeCheckinClient();
      await pumpRoom(t);
      expect(find.text('Daily check-in'), findsOneWidget);
      expect(find.text('Checked in today'), findsNothing);
      final entry = t.getSize(
        find.ancestor(of: find.text('Daily check-in'), matching: find.byType(ConstrainedBox)).first,
      );
      expect(entry.height, greaterThanOrEqualTo(48));
      for (final dock in ['Customize', 'Talk', 'Fortune']) {
        expect(find.text(dock), findsOneWidget, reason: dock);
      }
      // It sits above the dock: first on the page of controls.
      expect(t.getTopLeft(find.text('Daily check-in')).dy, lessThan(t.getTopLeft(find.text('Talk')).dy));
    });

    testWidgets('tapping it opens the flow; no per-answer confirmations; ONE read-back; completing marks it done', (
      t,
    ) async {
      repo = await repoWith(profile);
      client = FakeCheckinClient();
      await pumpRoom(t);
      await t.tap(find.text('Daily check-in'));
      await t.pumpAndSettle();
      // The chat is open: Mochi's first question, quick replies, Tap to talk.
      expect(find.textContaining('How many hours did you sleep?'), findsOneWidget);
      expect(find.text('Tap to talk'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      void noPerAnswerConfirm() {
        expect(find.text('Not quite'), findsNothing);
        expect(find.text('Yes'), findsNothing);
        expect(find.text('Looks right'), findsNothing);
      }

      noPerAnswerConfirm();
      await answer(t, '7 hours');
      // The server asked "Is that right?" and the app answered for the person: the person sees the next question.
      expect(find.textContaining('minutes did you move'), findsOneWidget);
      expect(find.textContaining('Is that right?'), findsNothing);
      noPerAnswerConfirm();
      await answer(t, '30 minutes');
      noPerAnswerConfirm();
      expect(find.textContaining('good, okay, or not great'), findsOneWidget);
      // Nothing is recorded yet.
      expect(repo.store.checkins, isEmpty);
      await answer(t, 'Good');
      // ONE read-back, listing every answer.
      expect(find.text('Here’s what I heard.'), findsOneWidget);
      expect(find.text('7 hours'), findsOneWidget);
      expect(find.text('30 minutes'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Looks right'), findsOneWidget);
      expect(find.text('Change with Mochi'), findsOneWidget);
      expect(find.text('Not quite'), findsNothing);
      expect(repo.store.checkins, isEmpty, reason: 'nothing is recorded until Looks right');
      // The silent confirm turns were the app's, one per answer; the person tapped three chips.
      expect(client.turns.where((x) => x.action == 'confirm').length, 3);
      expect(client.turns.where((x) => x.action == 'reply').length, 3);

      await t.tap(find.text('Looks right'));
      await t.pumpAndSettle();
      expect(repo.store.checkins.single.kind, 'daily');
      expect(repo.store.checkins.single.answers, {
        'sleep_hours_last_night': 7,
        'exercise_minutes_today': 30,
        'wellbeing': 'good',
      });
      expect(find.text('Back to my room'), findsOneWidget);
      await t.tap(find.text('Back to my room'));
      await t.pumpAndSettle();
      // Done for today: the quiet state replaces the primary button.
      expect(CheckinScheduler(repo, now: () => now).due(), isNull);
      expect(find.text('Checked in today'), findsOneWidget);
      expect(find.text('Daily check-in'), findsNothing);
      for (final dock in ['Customize', 'Talk', 'Fortune']) {
        expect(find.text(dock), findsOneWidget);
      }
    });

    testWidgets('skip is quick: a skipped answer is listed as skipped and nothing is invented', (t) async {
      repo = await repoWith(profile);
      client = FakeCheckinClient();
      await pumpRoom(t);
      await t.tap(find.text('Daily check-in'));
      await t.pumpAndSettle();
      await answer(t, 'Skip');
      await answer(t, 'Skip');
      await answer(t, 'Okay');
      expect(find.textContaining('Skipped'), findsNWidgets(2));
      expect(find.text('Okay'), findsOneWidget);
      await t.tap(find.text('Looks right'));
      await t.pumpAndSettle();
      expect(repo.store.checkins.single.answers, {'wellbeing': 'okay'});
    });

    testWidgets('Change with Mochi starts over and records nothing', (t) async {
      repo = await repoWith(profile);
      client = FakeCheckinClient();
      await pumpRoom(t);
      await t.tap(find.text('Daily check-in'));
      await t.pumpAndSettle();
      await answer(t, 'Skip');
      await answer(t, 'Skip');
      await answer(t, 'Good');
      await t.tap(find.text('Change with Mochi'));
      await t.pumpAndSettle();
      expect(repo.store.checkins, isEmpty);
      expect(client.starts, 2);
      expect(find.textContaining('How many hours did you sleep?'), findsOneWidget);
    });

    testWidgets('typing works too, and large text does not break it', (t) async {
      repo = await repoWith(profile);
      client = FakeCheckinClient();
      await pumpRoom(t);
      await t.tap(find.text('Daily check-in'));
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Type instead'), warnIfMissed: false);
      await t.tap(find.byIcon(Icons.keyboard_alt_outlined));
      await t.pump();
      await t.enterText(find.byType(TextField), '6.5 hours');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pumpAndSettle();
      expect(find.textContaining('minutes did you move'), findsOneWidget);
      expect(client.turns.first.text, '6.5 hours');
    });

    testWidgets('an emergency pauses calmly: Call 911 is a tapped tel: link, nothing is saved, Continue resumes', (
      t,
    ) async {
      repo = await repoWith(profile);
      client = FakeCheckinClient();
      await pumpRoom(t);
      await t.tap(find.text('Daily check-in'));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.keyboard_alt_outlined));
      await t.pump();
      await t.enterText(find.byType(TextField), 'I have chest pain');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pumpAndSettle();
      expect(find.text('If you need help right now, please call 911.'), findsOneWidget);
      expect(find.text('We can carry on whenever you’re ready.'), findsOneWidget);
      expect(opened, isEmpty, reason: 'never auto-dial');
      expect(repo.store.checkins, isEmpty);
      expect(repo.twinState().emergency, isTrue);
      await t.tap(find.text('Call 911'));
      expect(opened.single.toString(), 'tel:911');
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.textContaining('hours did you sleep'), findsWidgets);
      expect(repo.twinState().emergency, isFalse);
      expect(client.turns.last.action, 'resume');
    });
  });
}
