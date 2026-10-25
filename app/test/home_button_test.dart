// One Home button on every deep screen: present two levels below the Room, absent on Home and one level
// down, lands on the Room, asks before cutting a conversation short, and fits at 320 wide and 1.6x text.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/band/band_file_session.dart';
import 'package:lifesim/checkin/checkin_screen.dart' show CheckInScreen;
import 'package:lifesim/checkin/my_data_screen.dart' show MyDataScreen;
import 'package:lifesim/experiment/experiment_screen.dart' show ExperimentScreen;
import 'package:lifesim/quiz/quiz_screen.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/widgets/home_button.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/wellness/history_screen.dart';

import 'checkin/daily_checkin_test.dart' show profile;
import 'checkin/readback_flow_test.dart' show ContractGuide;
import 'support/app_fonts.dart';
import 'support/fake_change_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });
  tearDown(BandFileSession.disposeIfCreated);

  late AgenticRoutes routes;
  late BuildContext room;

  Future<void> pump(WidgetTester t, {Size size = const Size(390, 844), double scale = 1}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
    await repo.saveConversationProfile(profile);
    final look = ValueNotifier(const TwinAppearance(name: 'Mochi'));
    addTearDown(look.dispose);
    final voice = VoiceOnboardingController(
      guide: FakeConversationGuide(),
      input: FakeSpeechInput(),
      output: FakeSpeechOutput(),
    );
    addTearDown(voice.dispose);
    routes = AgenticRoutes(
      look: look,
      api: ApiBase(),
      voice: () => voice,
      guide: ContractGuide(),
      changeClient: FakeChangeClient(),
    )..attach(repo);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        navigatorObservers: [HomeDepth.instance],
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: routes.wrap(c, child),
        ),
        home: Builder(
          builder: (c) {
            room = c;
            return const Scaffold(body: Text('room'));
          },
        ),
      ),
    );
  }

  /// One level below the Room (Back already lands there), as My data is.
  Future<BuildContext> mid(WidgetTester t) async {
    routes.myData(room);
    await t.pumpAndSettle();
    return t.element(find.byType(MyDataScreen));
  }

  final deep = <String, void Function(BuildContext)>{
    'Experiment': (c) => routes.experiment(c),
    'Ideas list': (c) => routes.ideas(c, origin: 'Settings'),
    'Still learning': (c) => routes.stillLearning(c),
    'What I see': (c) => routes.wellness(c),
    'What moves it': (c) => routes.drivers(c),
    'Notebook': (c) => routes.notebook(c),
    'Reminders': (c) => routes.reminders(c),
    'AI and privacy': (c) => routes.aiPrivacy(c),
    'Weekly check-in': (c) => routes.weeklyCheckIn(c),
    'Change with Mochi': (c) => routes.changeAnswer(c),
    'Health documents': (c) => routes.healthDocuments(c),
    'Band pairing': (c) => routes.bandFlow(c),
    'Today plan': (c) => routes.todayPlan(c),
    'History': (c) => Navigator.of(c).push(
      MaterialPageRoute<void>(
        builder: (p) => HistoryScreen(
          days: const [],
          goodWeeks: 0,
          now: DateTime(2026, 10, 24),
          onBack: () => Navigator.of(p).pop(),
          onTalk: () {},
        ),
      ),
    ),
    'Quiz': (c) => Navigator.of(c).push(
      MaterialPageRoute<void>(builder: (p) => QuizScreen(onBack: () => Navigator.of(p).pop())),
    ),
  };

  for (final e in deep.entries) {
    testWidgets('${e.key}: Home is there, named, 48pt, and lands on the Room', (t) async {
      final h = t.ensureSemantics();
      await pump(t);
      e.value(await mid(t));
      await t.pumpAndSettle();
      expect(find.byType(HomeButton), findsOneWidget);
      final box = t.getRect(find.bySemanticsLabel('Go to Home'));
      expect(box.width, greaterThanOrEqualTo(48));
      expect(box.height, greaterThanOrEqualTo(48));
      await t.tap(find.byType(HomeButton));
      await t.pumpAndSettle();
      // A conversation asks first; the others go straight home.
      if (find.text('Leave this conversation?').evaluate().isNotEmpty) {
        await t.tap(find.text('Leave'));
        await t.pumpAndSettle();
      }
      expect(find.text('room'), findsOneWidget);
      expect(find.byType(HomeButton), findsNothing);
      h.dispose();
    });
  }

  testWidgets('Home is absent on the Room and one level below it', (t) async {
    await pump(t);
    expect(find.byType(HomeButton), findsNothing);
    routes.myData(room);
    await t.pumpAndSettle();
    expect(find.byType(HomeButton), findsNothing);
    Navigator.of(room).pop();
    await t.pumpAndSettle();
    routes.experiment(room);
    await t.pumpAndSettle();
    expect(find.byType(ExperimentScreen), findsOneWidget);
    expect(find.byType(HomeButton), findsNothing);
  });

  testWidgets('Home is absent on the onboarding conversation, which opens one level down', (t) async {
    await pump(t);
    routes.weeklyCheckIn(room);
    await t.pumpAndSettle();
    expect(find.byType(CheckInScreen), findsOneWidget);
    expect(find.byType(HomeButton), findsNothing);
  });

  testWidgets('mid-conversation, Home asks first: Keep going stays, Leave goes home', (t) async {
    await pump(t);
    routes.weeklyCheckIn(await mid(t));
    await t.pumpAndSettle();
    expect(find.byType(CheckInScreen), findsOneWidget);
    await t.tap(find.byType(HomeButton));
    await t.pumpAndSettle();
    expect(find.text('Leave this conversation?'), findsOneWidget);
    await t.tap(find.text('Keep going'));
    await t.pumpAndSettle();
    expect(find.byType(CheckInScreen), findsOneWidget);
    expect(find.text('Leave this conversation?'), findsNothing);
    await t.tap(find.byType(HomeButton));
    await t.pumpAndSettle();
    await t.tap(find.text('Leave'));
    await t.pumpAndSettle();
    expect(find.text('room'), findsOneWidget);
  });

  for (final (name, size, scale) in [
    ('320 wide', const Size(320, 640), 1.0),
    ('1.6x text', const Size(390, 844), 1.6),
    ('320 wide at 1.6x', const Size(320, 640), 1.6),
  ]) {
    testWidgets('no overflow at $name, and the 48pt target stays', (t) async {
      final h = t.ensureSemantics();
      await pump(t, size: size, scale: scale);
      final c = await mid(t);
      // My data itself (no Home on it) overflows by 53px at 320 wide and 1.6x text on main; not this change.
      t.takeException();
      for (final key in ['Experiment', 'Notebook', 'History', 'Reminders', 'Change with Mochi', 'Quiz']) {
        deep[key]!(c);
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        expect(find.byType(HomeButton), findsOneWidget);
        expect(t.takeException(), isNull, reason: key);
        final box = t.getRect(find.bySemanticsLabel('Go to Home'));
        expect(box.height, greaterThanOrEqualTo(48));
        expect(box.width, greaterThanOrEqualTo(48));
        if (scale >= 1.6) expect(find.text('Home'), findsNothing, reason: 'icon only');
        Navigator.of(t.element(find.byType(HomeButton))).pop();
        await t.pumpAndSettle();
      }
      h.dispose();
    });
  }
}
