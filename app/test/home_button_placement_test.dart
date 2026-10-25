// The Home button never covers a header, title, Back, quiz button, close button or content, on any deep screen.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/band/band_file_session.dart';
import 'package:lifesim/checkin/my_data_screen.dart' show MyDataScreen;
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

/// A bounded settle: the check-in's listening indicator animates forever, so pumpAndSettle would time out.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });
  tearDown(BandFileSession.disposeIfCreated);

  final shotKey = GlobalKey();
  late AgenticRoutes routes;
  late BuildContext room;
  var settingsOpened = 0;

  Future<void> pump(
    WidgetTester t, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // Joined 8 days ago, so the weekly check-in's 7-day gate is open (the gate itself is untouched).
    var clock = DateTime.now().subtract(const Duration(days: 8));
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => clock,
    );
    await repo.saveConversationProfile(profile);
    clock = DateTime.now();
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
      openSettings: () async => settingsOpened++,
    )..attach(repo);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        navigatorObservers: [HomeDepth.instance],
        builder: (c, child) => RepaintBoundary(
          key: shotKey,
          child: MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: routes.wrap(c, child),
          ),
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
    await settle(t);
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
      MaterialPageRoute<void>(
        builder: (p) => QuizScreen(onBack: () => Navigator.of(p).pop()),
      ),
    ),
  };

  final evidenceDir = Platform.environment['EVIDENCE_DIR'];
  Future<void> shot(WidgetTester t, String name) async {
    if (evidenceDir == null) return;
    await t.runAsync(() async {
      final b =
          shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$evidenceDir/$name.png');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  /// Rects of everything the Home button must not sit on: text and other tappables.
  List<(String, Rect)> neighbours(WidgetTester t) {
    final home = find.byType(HomeButton);
    final screen = t.view.physicalSize;
    final out = <(String, Rect)>[];
    bool inHome(Element e) => find
        .descendant(of: home, matching: find.byWidget(e.widget))
        .evaluate()
        .isNotEmpty;
    for (final e in find.byType(Text).evaluate()) {
      if (inHome(e)) continue;
      final w = e.widget as Text;
      final s = w.data ?? w.textSpan?.toPlainText() ?? '';
      if (s.trim().isEmpty) continue;
      final box = e.renderObject! as RenderBox;
      if (!box.attached || !box.hasSize) continue;
      // Skip text that is scrolled or clipped off screen.
      final r = t.getRect(find.byWidget(e.widget));
      if (r.bottom < 0 || r.top > screen.height) continue;
      out.add(('text "$s"', r));
    }
    for (final e
        in find
            .byWidgetPredicate(
              (w) =>
                  w is GestureDetector && w.onTap != null ||
                  w is InkResponse && w.onTap != null,
            )
            .evaluate()) {
      if (inHome(e)) continue;
      final r = t.getRect(find.byWidget(e.widget));
      // Skip a whole-screen tap target, and any tappable that contains Home.
      if (r.width * r.height > screen.width * screen.height * 0.4) {
        continue;
      }
      if (find.descendant(of: find.byWidget(e.widget), matching: home).evaluate().isNotEmpty) {
        continue;
      }
      out.add(('tappable ${e.widget.runtimeType} at $r', r));
    }
    return out;
  }

  for (final e in deep.entries) {
    for (final (w, scale) in [(390.0, 1.0), (390.0, 2.0), (320.0, 1.0), (320.0, 2.0)]) {
      testWidgets('${e.key}: Home covers nothing at ${w.toInt()} wide, ${scale}x text', (t) async {
        await pump(t, size: Size(w, w == 390 ? 844 : 640), scale: scale);
        final c = await mid(t);
        t.takeException();
        e.value(c);
        await settle(t);
        t.takeException();
        expect(find.byType(HomeButton), findsOneWidget);
        final slug = e.key.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
        await shot(t, '${slug}_${w.toInt()}_${scale.toInt()}x');
        final home = t.getRect(find.byType(HomeButton));
        expect(home.shortestSide, greaterThanOrEqualTo(52));
        expect(home.top, greaterThanOrEqualTo(MediaQuery.paddingOf(room).top));
        final hits = [
          for (final (name, r) in neighbours(t))
            if (r.overlaps(home)) name,
        ];
        expect(hits, isEmpty, reason: 'Home at $home');
      });
    }
  }
}
