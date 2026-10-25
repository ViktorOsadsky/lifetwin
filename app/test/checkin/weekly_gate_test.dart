// Check-in cadence: dailies every day; the weekly opens 7 full days after first joining.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/checkin/check_in_entry.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/checkin/consents.dart';
import 'package:lifesim/checkin/my_data_screen.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';

import '../checkin_reminders_test.dart' show FakePort;
import '../support/app_fonts.dart';
import '../support/fake_change_client.dart';
import 'daily_checkin_test.dart' show profile;
import 'readback_flow_test.dart' show ContractGuide;

class _NoProvider implements CapabilitiesClient {
  @override
  Future<AiProvider?> personalize() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  const joined = '2026-10-01'; // a Thursday
  const on = CheckinSettings(remindersOn: true, reminderOffered: true);
  String day(int n) => shiftDay(joined, n);
  DateTime morning(int n) {
    final d = parseDay(day(n));
    return DateTime(d.year, d.month, d.day, 9);
  }

  group('reminders', () {
    late FakePort port;
    late CheckinReminders reminders;
    setUp(() {
      port = FakePort();
      reminders = CheckinReminders(port);
    });

    test('daily: all 7 days by default', () async {
      final planned = await reminders.reschedule(on, localNow: morning(0), history: const [], firstJoined: joined);
      expect(planned.map((t) => t.day).toSet(), hasLength(7));
      expect(planned.first, DateTime(2026, 10, 1, 10));
      expect(planned.last, DateTime(2026, 10, 7, 10));
    });

    test('a day already done gets no reminder', () async {
      final done = [const CheckinEntry(kind: 'quick', date: joined, answers: {})];
      final planned = await reminders.reschedule(on, localNow: morning(0), history: done, firstJoined: joined);
      expect(planned.first, DateTime(2026, 10, 2, 10));
    });

    test('no weekly reminder on days 0-6; day 7 has one, combined with the daily', () async {
      for (var d = 0; d < 7; d++) {
        // The planned window starting at day d reaches day d+6 at most; day 7 is in it from day 1.
        await reminders.reschedule(on, localNow: morning(d), history: const [], firstJoined: joined);
        for (final s in port.scheduled) {
          final planned = s.$2;
          final isDay7 = isoDay(dayOf(planned)) == day(7);
          expect(s.$3.contains('weekly'), isDay7, reason: 'from day $d: ${isoDay(dayOf(planned))}');
        }
      }
      await reminders.reschedule(on, localNow: morning(3), history: const [], firstJoined: joined);
      final day7 = port.scheduled.where((s) => isoDay(dayOf(s.$2)) == day(7)).toList();
      expect(day7, hasLength(1), reason: 'one notification on the shared day');
      expect(day7.single.$3, dailyAndWeeklyLine);
    });

    test('the weekly repeats every 7 days, and not when one was done this week', () async {
      await reminders.reschedule(on, localNow: morning(10), history: const [], firstJoined: joined);
      expect(port.scheduled.where((s) => s.$3 == dailyAndWeeklyLine).map((s) => isoDay(dayOf(s.$2))), [day(14)]);
      final done = [CheckinEntry(kind: 'weekly', date: day(12), answers: const {})];
      await reminders.reschedule(on, localNow: morning(10), history: done, firstJoined: joined);
      expect(port.scheduled.any((s) => s.$3 == dailyAndWeeklyLine), isFalse);
    });

    test('daily done on the weekly day: the weekly reminder goes alone', () async {
      final done = [CheckinEntry(kind: 'quick', date: day(7), answers: const {})];
      await reminders.reschedule(on, localNow: morning(7), history: done, firstJoined: joined);
      expect(port.scheduled.first.$3, weeklyOnlyLine);
    });

    test('without a join date there is no weekly reminder', () async {
      await reminders.reschedule(on, localNow: morning(0), history: const [], firstJoined: null);
      expect(port.scheduled.any((s) => s.$3.contains('weekly')), isFalse);
      expect(port.scheduled, hasLength(7));
    });
  });

  group('first_joined', () {
    late DateTime clock;
    setUp(() => clock = DateTime(2026, 10, 1, 9));

    Future<TwinRepository> repoWith(MemoryBackend backend, {CheckinReminders? reminders}) async => TwinRepository(
      model: model,
      store: await TwinStore.open(backend),
      clock: () => clock,
      reminders: reminders,
    );

    test('is stored once when onboarding first saves, and not moved by later saves', () async {
      final repo = await repoWith(MemoryBackend());
      expect(repo.firstJoined, isNull);
      await repo.saveConversationProfile(profile);
      expect(repo.store.firstJoined, joined);
      clock = DateTime(2026, 10, 20, 9);
      await repo.saveConversationProfile({...profile, 'age': 56}, kind: 'mochi_change');
      expect(repo.store.firstJoined, joined);
    });

    test('the weekly is gated on days 0-6 and open on day 7', () async {
      final repo = await repoWith(MemoryBackend());
      await repo.saveConversationProfile(profile);
      for (var d = 0; d < 7; d++) {
        clock = morning(d);
        expect(repo.weeklyAvailable, isFalse, reason: 'day $d');
        expect(repo.weeklyGateLine, 'Your first weekly check-in opens on Thursday, October 8');
      }
      clock = morning(7);
      expect(repo.weeklyAvailable, isTrue);
      expect(repo.weeklyGateLine, isNull);
    });

    test('an existing profile is backfilled from its earliest history, else today', () async {
      final seededBackend = MemoryBackend();
      await (await repoWith(seededBackend)).saveConversationProfile(profile);
      final doc = jsonDecode(seededBackend.text!) as Map<String, dynamic>..remove('first_joined');

      clock = DateTime(2026, 10, 20, 9);
      final withHistory = MemoryBackend()..text = jsonEncode(doc);
      final repo = await repoWith(withHistory);
      expect(repo.store.firstJoined, isNull);
      expect(repo.firstJoined, joined, reason: 'earliest history entry');
      expect(repo.weeklyAvailable, isTrue);

      doc.remove('history');
      final bare = await repoWith(MemoryBackend()..text = jsonEncode(doc));
      expect(bare.firstJoined, '2026-10-20', reason: 'no history: today');
    });

    test('Delete my data clears it, and re-onboarding sets it anew', () async {
      final backend = MemoryBackend();
      final repo = await repoWith(backend, reminders: CheckinReminders(FakePort()));
      await repo.saveConversationProfile(profile);
      expect(backend.text, contains('first_joined'));
      await repo.deleteMyData();
      expect(repo.store.firstJoined, isNull);
      expect(repo.firstJoined, isNull);
      expect(backend.text, isNull, reason: 'identical to a fresh install');
      clock = DateTime(2026, 11, 5, 9);
      await repo.saveConversationProfile(profile);
      expect(repo.store.firstJoined, '2026-11-05');
    });
  });

  group('entry points', () {
    late TwinRepository repo;
    late AgenticRoutes routes;
    late BuildContext home;

    /// A person who joined [daysAgo] days ago, on the real clock the entry widgets read.
    Future<void> pump(WidgetTester t, int daysAgo, Widget Function(BuildContext) body) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var clock = DateTime.now().subtract(Duration(days: daysAgo));
      repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => clock);
      await repo.saveConversationProfile(profile);
      clock = DateTime.now();
      final voice = VoiceOnboardingController(
        guide: FakeConversationGuide(),
        input: FakeSpeechInput(),
        output: FakeSpeechOutput(),
      );
      addTearDown(voice.dispose);
      routes = AgenticRoutes(
        look: ValueNotifier(const TwinAppearance(name: 'Mochi')),
        api: ApiBase(),
        voice: () => voice,
        guide: ContractGuide(),
        changeClient: FakeChangeClient(),
        capabilities: _NoProvider(),
        onDeleted: () {},
      )..attach(repo);
      await t.pumpWidget(
        MaterialApp(
          theme: lifeTwinTheme(),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true),
            child: routes.wrap(c, child),
          ),
          home: Builder(
            builder: (c) {
              home = c;
              return Scaffold(body: body(c));
            },
          ),
        ),
      );
      await t.pump();
    }

    for (final (daysAgo, open) in [(0, false), (6, false), (7, true), (9, true)]) {
      testWidgets('Home entry: the weekly button is ${open ? 'shown' : 'hidden'} $daysAgo days after joining', (t) async {
        await pump(t, daysAgo, (_) => const CheckInEntry());
        expect(find.text('Check in'), findsOneWidget, reason: 'the daily one is always there');
        expect(find.text('Weekly check-in'), open ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('Home entry: long-press opens the weekly only once it is open', (t) async {
      await pump(t, 3, (_) => const CheckInEntry());
      await t.longPress(find.byType(CheckInEntry));
      await t.pumpAndSettle();
      expect(find.text('Weekly check-in'), findsNothing);
    });

    testWidgets('My data row: before day 7 it says when it opens and does nothing', (t) async {
      await pump(t, 2, (_) => const Text('room'));
      final expected = repo.weeklyGateLine!;
      expect(expected, startsWith('Your first weekly check-in opens on '));
      routes.myData(home);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('Weekly check-in'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text(expected), findsOneWidget);
      await t.tap(find.text('Weekly check-in'));
      await t.pumpAndSettle();
      expect(find.byType(MyDataScreen), findsOneWidget, reason: 'still on My data');
    });

    testWidgets('routes.weeklyCheckIn does nothing before day 7', (t) async {
      await pump(t, 1, (_) => const Text('room'));
      await routes.weeklyCheckIn(home);
      await t.pumpAndSettle();
      expect(find.text('room'), findsOneWidget);
    });
  });
}
