// Home, top to bottom: quiz chip, score card, Check in, Today line, the big Experiment button, the dock.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/room/room_scene.dart';
import 'package:lifesim/room/room_sim.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/wellness/widgets.dart' show WellnessCard;
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

  Future<void> pumpHome(WidgetTester t, {double width = 390, double height = 844, double scale = 1, double topInset = 0, double bottomInset = 0}) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = await memoryRepo(model);
    await repo.saveConversationProfile(_profile);
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(scale),
            padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
            viewPadding: EdgeInsets.only(top: topInset, bottom: bottomInset),
          ),
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

  /// Loads the room and the twin's real sprites, so a picture shows Mochi.
  Future<void> loadArt(WidgetTester t) async {
    await t.runAsync(() async {
      final c = t.element(find.byType(Scaffold).first);
      await precacheImage(const AssetImage('assets/scene/room/room_bg.jpg'), c);
      for (final pose in TwinPose.values) {
        final a = twinAsset(TwinType.bear, TwinLook.calHat, pose);
        try {
          await precacheImage(AssetImage(a), c);
        } catch (_) {}
      }
    });
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
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
    // Check in sits inside the Today row, on its right.
    final today = find.textContaining('Today', findRichText: true);
    expect(t.getCenter(checkIn).dx, greaterThan(t.getCenter(today).dx));
    expect((t.getCenter(checkIn).dy - t.getCenter(today).dy).abs(), lessThan(30));
    expect(top(t, experiment), lessThan(top(t, find.text('Talk'))));
    expect(find.text('Fortune'), findsOneWidget);
    for (final gone in ['Exercise', 'Eat', 'Sleep']) {
      expect(find.text(gone), findsNothing, reason: 'no $gone row on Home');
    }
    // Experiment is the biggest action after Check in: taller than Check in, far larger than the quiz chip.
    double h(Finder f) => t.getSize(find.ancestor(of: f, matching: find.byType(LipButton)).first).height;
    expect(h(experiment), greaterThanOrEqualTo(h(checkIn)));
    expect(t.getSize(find.ancestor(of: quiz, matching: find.byType(Container)).first).height, lessThan(h(experiment)));
    // Everything fits: Home does not scroll at 390 x 844.
    expect(t.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent, 0);
    // A picture for review.
    final shots = Directory('${Directory.current.path}/../../evidence_shots')..createSync(recursive: true);
    await loadArt(t);
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${shots.path}/home_order.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });

  for (final (w, h, top, bottom) in [(390.0, 844.0, 0.0, 0.0), (402.0, 874.0, 62.0, 34.0)]) {
  testWidgets('Mochi has a clear window and the quiz chip is the topmost element at $w x $h (top inset $top)', (t) async {
    await pumpHome(t, width: w, height: h, topInset: top, bottomInset: bottom);
    await loadArt(t);
    // The quiz chip is the first element, one inset (safe area + 8) from the top; gaps below are 8.
    final quizBox = t.getRect(find.ancestor(of: find.text('Quiz · play'), matching: find.byType(Semantics)).first);
    expect(quizBox.top, top + 8);
    final header = t.getRect(find.byTooltip('Settings'));
    expect(header.top, greaterThanOrEqualTo(quizBox.bottom));
    expect(t.getTopLeft(find.byType(HomeWellnessPanel)).dy - header.bottom, lessThanOrEqualTo(8.5));
    expect(top, lessThan(quizBox.top));
    final twin = t.getRect(find.byType(TwinSprite).first);
    // The sprite box has transparent margins: test against the body (the middle of the box).
    final body = Rect.fromCenter(center: twin.center, width: twin.width * 0.5, height: twin.height * 0.7);
    Rect box(Finder f, Type within) => t.getRect(find.ancestor(of: f.first, matching: find.byType(within)).first);
    final boxes = <String, Rect>{
      'quiz chip': box(find.text('Quiz · play'), Semantics),
      'score card': t.getRect(find.byType(HomeWellnessPanel)),
      'check in': box(find.text('Check in'), LipButton),
      'today row': box(find.textContaining('Today', findRichText: true), WellnessCard),
      'experiment': box(find.text('Experiment with your twin'), LipButton),
      'dock': t.getRect(find.text('Talk').first),
    };
    for (final e in boxes.entries) {
      expect(body.overlaps(e.value), isFalse, reason: '${e.key} ${e.value} covers the twin $body');
    }
    if (h == 874.0) {
      final shots = Directory('${Directory.current.path}/../../evidence_shots')..createSync(recursive: true);
      await t.runAsync(() async {
        final bnd = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await bnd.toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${shots.path}/home_top_17pro.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
  }

  testWidgets('the activity pill opens the chooser; choosing Sleep puts Mochi in bed', (t) async {
    await pumpHome(t, width: 402, height: 874, topInset: 62, bottomInset: 34);
    await loadArt(t);
    final pill = find.byKey(const ValueKey('room-activity'));
    expect(t.getSize(pill).height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel(RegExp(r'is \w+\. Change what')), findsOneWidget);
    await t.tap(pill);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('What should Mochi do?'), findsOneWidget);
    for (final label in ['Walk', 'Exercise', 'Eat', 'Sleep']) {
      final h = t.getSize(find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first).height;
      expect(h, greaterThanOrEqualTo(48), reason: label);
    }
    // The current choice carries a check, not only a colour.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final shots = Directory('${Directory.current.path}/../../evidence_shots')..createSync(recursive: true);
    await t.runAsync(() async {
      final bnd = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await bnd.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${shots.path}/home_pill_sheet.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await t.tap(find.text('Sleep'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final sim = t.widget<RoomScene>(find.byType(RoomScene)).sim;
    expect(sim.action, RoomAction.sleep);
    for (var i = 0; i < 400 && !sim.inBed; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(sim.inBed, isTrue);
  });

  for (final w in [390.0, 320.0]) {
    testWidgets('fits without overflow at $w wide, 1.0x text', (t) async {
      await pumpHome(t, width: w, height: w == 320 ? 640 : 844);
      expect(t.takeException(), isNull);
      expect(find.text('Experiment with your twin'), findsOneWidget);
    });
  }

  testWidgets('1.6x text: nothing clips; Home scrolls only if it must and Experiment is reachable', (t) async {
    await pumpHome(t, scale: 1.6);
    expect(t.takeException(), isNull);
    final s = t.state<ScrollableState>(find.byType(Scrollable).first);
    if (s.position.maxScrollExtent > 0) {
      await t.scrollUntilVisible(find.text('Experiment with your twin'), 200);
    }
    expect(find.text('Experiment with your twin'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
