// Home, top to bottom: quiz chip, score card, Check in, Today line, the big Experiment button, the dock.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/wellness/home_panel.dart';

import 'support/app_fonts.dart';
import 'support/settings_hub.dart';

const _profile = {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  final key = GlobalKey();

  Future<void> pumpHome(WidgetTester t, {double width = 390, double height = 844, double scale = 1}) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = await memoryRepo(model);
    await repo.saveConversationProfile(_profile);
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(scale)),
          child: LifeTwinApp(
            controller: VoiceOnboardingController(
              guide: FakeConversationGuide(),
              input: FakeSpeechInput(),
              output: FakeSpeechOutput(),
            ),
            twin: Future.value(repo),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
  }

  double top(WidgetTester t, Finder f) => t.getTopLeft(f.first).dy;

  testWidgets('order: quiz above the score card; Experiment below Check in and the largest button', (t) async {
    await pumpHome(t);
    final quiz = find.text('Quiz · play');
    final card = find.byType(HomeWellnessPanel);
    final checkIn = find.text('Check in');
    final experiment = find.text('Experiment with your twin');
    expect(quiz, findsOneWidget);
    expect(experiment, findsOneWidget);
    expect(top(t, quiz), lessThan(top(t, card)));
    expect(top(t, card), lessThan(top(t, checkIn)));
    expect(top(t, checkIn), lessThan(top(t, experiment)));
    expect(top(t, experiment), lessThan(top(t, find.text('Talk'))));
    expect(find.text('Fortune'), findsOneWidget);
    // Experiment is the biggest action after Check in: taller than Check in, far larger than the quiz chip.
    double h(Finder f) => t.getSize(find.ancestor(of: f, matching: find.byType(LipButton)).first).height;
    expect(h(experiment), greaterThanOrEqualTo(h(checkIn)));
    expect(t.getSize(find.ancestor(of: quiz, matching: find.byType(Container)).first).height, lessThan(h(experiment)));
    // Everything fits: Home does not scroll at 390 x 844.
    expect(t.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent, 0);
    // A picture for review.
    final shots = Directory('${Directory.current.path}/../../evidence_shots')..createSync(recursive: true);
    await t.runAsync(() async {
      final c = t.element(find.byType(Scaffold).first);
      await precacheImage(const AssetImage('assets/scene/room/room_bg.jpg'), c);
    });
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${shots.path}/home_order.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });

  for (final w in [390.0, 320.0]) {
    testWidgets('fits without overflow at $w wide, 1.0x text', (t) async {
      await pumpHome(t, width: w, height: w == 320 ? 640 : 844);
      expect(t.takeException(), isNull);
      expect(find.text('Experiment with your twin'), findsOneWidget);
    });
  }

  testWidgets('1.6x text: Home scrolls and nothing clips', (t) async {
    await pumpHome(t, scale: 1.6);
    expect(t.takeException(), isNull);
    final s = t.state<ScrollableState>(find.byType(Scrollable).first);
    expect(s.position.maxScrollExtent, greaterThan(0));
    await t.scrollUntilVisible(find.text('Experiment with your twin'), 200);
    expect(t.takeException(), isNull);
  });
}
