// Tapping a check-in reminder opens that check-in (not just the Room), through the same path as the
// Room's entry: the weekly only while the 7-day gate is open, nothing without a profile, and the same
// check-in for every age. A tap that launched the app opens it once the Room is up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/checkin/checkin_screen.dart' show CheckInScreen;
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';

import '../support/app_fonts.dart';
import 'daily_checkin_test.dart' show profile;
import 'readback_flow_test.dart' show ContractGuide;
import 'routes_wiring_test.dart' show FakeCapabilities;

/// The phone's notifications, faked: [tap] is a tap while the app runs, [launch] the tap that started it.
class FakeTapPort implements NotificationPort, ReminderTapPort {
  String? launch;
  void Function(String? payload)? _onTap;
  void tap(String? payload) => _onTap!(payload);

  @override
  Future<String?> listenForTaps(void Function(String? payload) onTap) async {
    _onTap = onTap;
    return launch;
  }

  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime localWallTime,
    required String title,
    required String body,
    String? payload,
  }) async {}
  @override
  Future<void> cancelAll() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  late FakeTapPort port;
  setUp(() => port = FakeTapPort());

  /// The app with a repository that joined [joinedDaysAgo] days ago (no profile when [age] is null).
  Future<void> pump(WidgetTester t, {int joinedDaysAgo = 8, int? age = 40}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var clock = DateTime.now().subtract(Duration(days: joinedDaysAgo));
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => clock,
      reminders: CheckinReminders(port),
    );
    if (age != null) await repo.saveConversationProfile({...profile, 'age': age});
    clock = DateTime.now();
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
      capabilities: FakeCapabilities(null),
    )..attach(repo);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        navigatorKey: routes.navigatorKey,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true),
          child: routes.wrap(c, child),
        ),
        home: const Scaffold(body: Text('room')),
      ),
    );
    await t.pumpAndSettle();
  }

  CheckInKind? opened(WidgetTester t) {
    final screens = t.widgetList<CheckInScreen>(find.byType(CheckInScreen));
    return screens.isEmpty ? null : screens.single.kind;
  }

  Future<void> tap(WidgetTester t, String? payload) async {
    port.tap(payload);
    await t.pumpAndSettle();
  }

  testWidgets('a daily reminder opens the daily check-in', (t) async {
    await pump(t);
    expect(opened(t), isNull);
    await tap(t, reminderPayload(ReminderCheckin.daily));
    expect(opened(t), CheckInKind.quick);
  });

  testWidgets('a weekly reminder opens the weekly check-in while the weekly is open', (t) async {
    await pump(t);
    await tap(t, reminderPayload(ReminderCheckin.weekly));
    expect(opened(t), CheckInKind.weekly);
  });

  testWidgets('before the weekly opens (7 days after joining) a weekly payload opens the daily', (t) async {
    await pump(t, joinedDaysAgo: 2);
    await tap(t, reminderPayload(ReminderCheckin.weekly));
    expect(opened(t), CheckInKind.quick);
  });

  testWidgets('a reminder tapped while a check-in is open does not stack a second one', (t) async {
    await pump(t);
    await tap(t, reminderPayload(ReminderCheckin.daily));
    await tap(t, reminderPayload(ReminderCheckin.weekly));
    expect(find.byType(CheckInScreen, skipOffstage: false), findsOneWidget);
    expect(opened(t), CheckInKind.quick);
  });

  testWidgets('Remind me later and other notifications just open the app', (t) async {
    await pump(t);
    await tap(t, null);
    expect(opened(t), isNull);
    expect(find.text('room'), findsOneWidget);
  });

  testWidgets('without a saved profile nothing opens', (t) async {
    await pump(t, age: null);
    await tap(t, reminderPayload(ReminderCheckin.daily));
    expect(opened(t), isNull);
  });

  testWidgets('under 18 the tap opens the same daily check-in as the Room, and the weekly gate still holds', (
    t,
  ) async {
    await pump(t, age: 16, joinedDaysAgo: 2);
    await tap(t, reminderPayload(ReminderCheckin.weekly));
    expect(opened(t), CheckInKind.quick);
  });

  testWidgets('a tap that launched the app opens its check-in once the Room is up', (t) async {
    port.launch = reminderPayload(ReminderCheckin.weekly);
    await pump(t);
    expect(opened(t), CheckInKind.weekly);
  });
}
