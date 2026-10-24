import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/forecast/forecast_client.dart';
import 'package:lifesim/forecast/fortune_ceremony_screen.dart';
import 'package:lifesim/health/health_sample.dart';
import 'package:lifesim/health/health_screen.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/room/floor_projector.dart';
import 'package:lifesim/room/room_layout_data.dart';
import 'package:lifesim/room/room_scene.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/room/room_sim.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/voice/fakes.dart';

import 'forecast_screen_test.dart' show FakeForecastClient, supportedJson;
import 'health_screen_test.dart' show FakeReader;

VoiceOnboardingController fakeController() =>
    VoiceOnboardingController(guide: FakeConversationGuide(), input: FakeSpeechInput(), output: FakeSpeechOutput());

void setPhone(WidgetTester t, [Size size = const Size(390, 844)]) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Advances fake time in 50 ms frames until [finder] matches.
Future<void> pumpUntil(WidgetTester t, Finder finder, {double seconds = 20}) async {
  for (var i = 0; i < seconds * 20; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets, reason: 'timed out after $seconds s');
}

/// Advances fake time by [seconds] in 50 ms frames (the sim takes at most 50 ms a step).
Future<void> frames(WidgetTester t, double seconds) async {
  for (var i = 0; i < seconds * 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Finder image(String asset) =>
    find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == asset);

TwinPose twinPose(WidgetTester t) => t.widget<TwinSprite>(find.byType(TwinSprite)).pose;

Future<ValueNotifier<TwinAppearance>> pumpRoom(
  WidgetTester t, {
  TwinAppearance look = const TwinAppearance(),
  bool reduced = false,
  Future<void> Function()? onFortune,
  ValueNotifier<Forecast?>? outlook,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool hasProfile = true,
  VoidCallback? onUseHealth,
}) async {
  setPhone(t, size);
  final notifier = ValueNotifier(look);
  addTearDown(notifier.dispose);
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: reduced, textScaler: TextScaler.linear(textScale)),
        child: RoomScreen(
          appearance: notifier,
          onTalk: () {},
          onCustomize: () {},
          onFortune: onFortune ?? () async {},
          outlook: outlook,
          hasProfile: hasProfile,
          onUseHealth: onUseHealth,
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(); // the room hears how much the UI covers
  return notifier;
}

/// The box (button) around a label.
Rect boxOf(WidgetTester t, String label) =>
    t.getRect(find.ancestor(of: find.text(label), matching: find.byType(GestureDetector)).first);

/// Runs [sim] for [seconds] at 60 fps, calling [each] after every step.
void run(RoomSim sim, double seconds, [void Function()? each]) {
  for (var i = 0; i < seconds * 60; i++) {
    sim.step(1 / 60);
    each?.call();
  }
}

/// The bundled fonts, so label widths are the real ones.
Future<void> loadAppFonts() async {
  for (final (family, files) in [
    (
      'Atkinson Hyperlegible',
      ['atkinson_hyperlegible/AtkinsonHyperlegible-Regular.ttf', 'atkinson_hyperlegible/AtkinsonHyperlegible-Bold.ttf'],
    ),
    ('Fredoka', ['fredoka/Fredoka-Variable.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }
}

/// A label sits on one line, inside its box, at 15 px or more.
void expectOneLine(WidgetTester t, String label, {bool checkFloor = true}) {
  final text = t.widget<Text>(find.text(label));
  expect(text.maxLines, 1, reason: label);
  expect(text.softWrap, isFalse, reason: label);
  final para = t.renderObject<RenderParagraph>(find.text(label));
  final lineH = para.text.style!.fontSize! * para.textScaler.scale(1) * para.text.style!.height!;
  expect(para.size.height, lessThan(lineH * 1.5), reason: '$label is on one line');
  final rect = t.getRect(find.text(label)), box = boxOf(t, label);
  expect(box.left <= rect.left + 0.5 && rect.right <= box.right + 0.5, isTrue, reason: '$label fits its box');
  if (checkFloor) {
    expect(rect.height / para.text.style!.height!, greaterThanOrEqualTo(15 - 0.05), reason: '$label is 15 px or more');
  }
}

void main() {
  testWidgets('the room draws the background, the twin between the layers, and the UI', (t) async {
    await pumpRoom(t);
    expect(image(roomLayout.bgAsset), findsOneWidget);
    expect(find.byType(TwinSprite), findsOneWidget);
    expect(t.widget<TwinSprite>(find.byType(TwinSprite)).appearance.sprite(), 'assets/twin/bear/pose/stand.png');
    // Standing in front of the bed and right of the table: nothing covers it (room_furniture_test
    // covers the twin behind the bed or the table).
    expect(image(roomLayout.fgTable.asset), findsNothing);
    expect(image(roomLayout.fgBed.asset), findsNothing);
    expect(image(roomLayout.fgBedFull.asset), findsNothing);
    final stack = find.descendant(of: find.byType(RoomScene), matching: find.byType(Stack)).first;
    final order = t.widget<Stack>(stack).children;
    final bgAt = order.indexWhere((w) => w is Positioned && w.child is Image);
    final twinAt = order.indexWhere((w) => w.key == const ValueKey('room-twin'));
    expect(bgAt >= 0 && bgAt < twinAt, isTrue, reason: 'bg, then the twin');
    expect(find.bySemanticsLabel('Twin name: My twin'), findsOneWidget);
    expect(find.text('Hanging out'), findsOneWidget);
    expect(find.text('Ask the ball'), findsOneWidget); // no forecast yet: no number
    expect(find.textContaining('in 100'), findsNothing);
    for (final label in ['Exercise', 'Eat', 'Sleep', 'Customize', 'Talk', 'Fortune']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in ['Exercise', 'Eat', 'Sleep']) {
      expect(
        t.getSize(find.ancestor(of: find.text(label), matching: find.byType(GestureDetector)).first).height,
        greaterThanOrEqualTo(48),
      );
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('the outlook card shows only a real forecast', (t) async {
    final outlook = ValueNotifier<Forecast?>(null);
    addTearDown(outlook.dispose);
    await pumpRoom(t, outlook: outlook);
    expect(find.text('Ask the ball'), findsOneWidget);
    outlook.value = Forecast.parse({
      'status': 'supported',
      'model_version': 'm',
      'max_horizon_years': 5,
      'survival': [
        {'years': 5, 'survival': 0.9080},
      ],
    });
    await t.pump();
    expect(find.text('about 91 in 100'), findsOneWidget);
    expect(find.text('Your 5-yr look'), findsOneWidget);
  });

  testWidgets('Exercise walks to the mat and loops stretch and jump, then finishes', (t) async {
    await pumpRoom(t);
    await t.tap(find.text('Exercise'));
    await t.pump();
    expect(find.text('Off to the mat'), findsOneWidget);
    await pumpUntil(t, find.text('Jumping jacks!'));
    final seen = <TwinPose>{};
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
      seen.add(twinPose(t));
    }
    expect(seen, containsAll([TwinPose.stretch, TwinPose.jump]));
    await pumpUntil(t, find.text('Feeling strong'));
  });

  testWidgets('Eat walks to the table and eats', (t) async {
    await pumpRoom(t);
    await t.tap(find.text('Eat'));
    await t.pump();
    expect(find.text('Snack time!'), findsOneWidget);
    await pumpUntil(t, find.text('Crunch, crunch!'));
    await t.pump(const Duration(milliseconds: 100));
    expect(twinPose(t), TwinPose.eat);
    await pumpUntil(t, find.text('Full and happy'));
  });

  testWidgets('Sleep climbs into bed under the quilt with z\'s; a tap wakes', (t) async {
    await pumpRoom(t);
    await t.tap(find.text('Sleep'));
    await t.pump();
    expect(find.text('Off to bed'), findsOneWidget);
    await pumpUntil(t, find.text('Sleeping. Tap to wake'));
    await t.pump(const Duration(milliseconds: 600));
    expect(twinPose(t), TwinPose.sleep);
    expect(image(roomLayout.fgBed.asset), findsOneWidget);
    expect(find.text('z'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('room-twin')), warnIfMissed: false);
    await t.pump();
    expect(find.text('Good morning!'), findsOneWidget);
    await frames(t, 1);
    expect(image(roomLayout.fgBed.asset), findsNothing);
  });

  testWidgets('tapping the twin hops', (t) async {
    await pumpRoom(t);
    await t.tap(find.byKey(const ValueKey('room-twin')), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Wheee!'), findsOneWidget);
    expect(twinPose(t), TwinPose.jump);
    await frames(t, 1);
    expect(twinPose(t), isNot(TwinPose.jump));
  });

  testWidgets('Fortune walks to the shelf, holds the ball, then opens the ceremony', (t) async {
    var opened = 0;
    await pumpRoom(t, onFortune: () async => opened++);
    await t.tap(find.text('Fortune'));
    await t.pump();
    expect(find.text('Off to the shelf'), findsOneWidget);
    await pumpUntil(t, find.text('The ball glows!'));
    expect(twinPose(t), TwinPose.holdBall);
    expect(image(roomLayout.shelfEmpty.asset), findsOneWidget); // the ball left the shelf
    for (var i = 0; i < 400 && opened == 0; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(opened, 1);
    await frames(t, 2);
    expect(image(roomLayout.shelfEmpty.asset), findsNothing); // the ball is back
  });

  testWidgets('Fortune or the outlook card with no finished talk: the twin asks to talk first', (t) async {
    var opened = 0;
    await pumpRoom(t, hasProfile: false, onFortune: () async => opened++);
    await t.tap(find.text('Fortune'));
    await t.pump();
    expect(find.text(RoomScreen.talkFirst), findsOneWidget);
    expect(find.text('Off to the shelf'), findsNothing);
    await t.tap(find.text('Ask the ball'));
    await frames(t, 3);
    expect(opened, 0);
  });

  for (final scale in [1.0, 3.1]) {
    testWidgets('scale $scale: "Use my Apple Health" pill: one line, at least 48 pt, opens the import', (t) async {
      var opened = 0;
      await pumpRoom(t, textScale: scale, onUseHealth: () => opened++);
      expect(t.takeException(), isNull);
      expectOneLine(t, 'Use my Apple Health', checkFloor: false);
      expect(boxOf(t, 'Use my Apple Health').height, greaterThanOrEqualTo(48));
      expect(t.widget<Text>(find.text('Use my Apple Health')).style!.fontSize, greaterThanOrEqualTo(17));
      await t.tap(find.text('Use my Apple Health'));
      expect(opened, 1);
    });
  }

  testWidgets('no Apple Health pill once Health data is confirmed (no import callback)', (t) async {
    await pumpRoom(t);
    expect(find.text('Use my Apple Health'), findsNothing);
  });

  testWidgets('the Room pill imports Apple Health, then goes; the talk adds the values when it starts', (t) async {
    setPhone(t);
    final now = DateTime.now();
    final c = fakeController();
    final reader = FakeReader([
      HealthSample(
        type: 'WEIGHT',
        start: now.subtract(const Duration(days: 2)),
        end: now.subtract(const Duration(days: 2)),
        value: 68,
      ),
    ]);
    await t.pumpWidget(LifeTwinApp(controller: c, healthReader: reader));
    await t.pump();
    await t.tap(find.text('Use my Apple Health'));
    await t.pumpAndSettle();
    expect(find.byType(HealthImportScreen), findsOneWidget);
    await t.tap(find.text('Yes, use Apple Health'));
    await t.pumpAndSettle();
    await t.tap(find.text("Yes, that's right"));
    await t.pumpAndSettle();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(find.text('Use my Apple Health'), findsNothing);
    expect(c.hasPendingHealth, isTrue);
    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    await t.tap(find.text("No, I'll type"));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 700));
    await t.ensureVisible(find.text('Not now'));
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(c.confirmedProfile, {'weight_kg': 68});
  });

  group('in the app, after a typed answer', () {
    Future<(VoiceOnboardingController, FakeForecastClient)> start(WidgetTester t) async {
      setPhone(t);
      final forecast = FakeForecastClient()..answers.add(Forecast.parse(supportedJson()));
      final c = fakeController();
      await t.pumpWidget(LifeTwinApp(controller: c, forecastClient: forecast));
      await t.tap(find.text('Talk'));
      await t.pumpAndSettle();
      await t.tap(find.text("No, I'll type"));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 700)); // the AI question ignores a second tap at first
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
      await t.tap(find.text('Ask the ball')); // the ceremony comes first
      await t.pumpAndSettle();
      return (c, forecast);
    }

    testWidgets('Continue opens the fortune; Back returns to the Room, whose card and Fortune then work', (t) async {
      final (_, forecast) = await start(t);
      expect(forecast.calls, hasLength(1));
      await t.tap(find.bySemanticsLabel('Back'));
      await t.pumpAndSettle();
      expect(find.byType(RoomScreen), findsOneWidget);
      expect(find.text('about 88 in 100'), findsOneWidget); // the real forecast on the outlook card
      forecast.answers.add(Forecast.parse(supportedJson()));
      await t.tap(find.text('Fortune'));
      await pumpUntil(t, find.byType(FortuneCeremonyScreen));
      await t.pumpAndSettle();
      await t.tap(find.text('Ask the ball'));
      await t.pumpAndSettle();
      expect(forecast.calls, hasLength(2));
      expect(forecast.calls.last, {'age': 70});
    });

    testWidgets('"Go back to my answers" opens the conversation, where Go back can change one', (t) async {
      final (c, forecast) = await start(t);
      await t.scrollUntilVisible(find.text('Go back to my answers'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Go back to my answers'));
      await t.pumpAndSettle();
      expect(find.byType(VoiceOnboardingScreen), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      await t.tap(find.text('Go back'));
      await t.pumpAndSettle();
      expect(c.phase, VoicePhase.idle);
      expect(find.text('Continue'), findsNothing);
      // Left unfinished: the Room no longer offers a forecast from the older answers.
      Navigator.of(t.element(find.byType(VoiceOnboardingScreen))).pop();
      await t.pumpAndSettle();
      await t.tap(find.text('Fortune'));
      await t.pump();
      expect(find.text(RoomScreen.talkFirst), findsOneWidget);
      await frames(t, 3);
      expect(forecast.calls, hasLength(1));
    });
  });

  testWidgets('Talk still swooshes to the conversation and Back returns', (t) async {
    setPhone(t);
    await t.pumpWidget(LifeTwinApp(controller: fakeController()));
    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    expect(find.byType(VoiceOnboardingScreen), findsOneWidget);
    expect(find.text('Talk with me?'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Home'));
    await t.pumpAndSettle();
    expect(find.byType(VoiceOnboardingScreen), findsNothing);
    expect(find.byType(RoomScreen), findsOneWidget);
  });

  testWidgets('reduced motion: long walks become a crossfade, loops are shorter, no tilt', (t) async {
    await pumpRoom(t, reduced: true);
    await t.tap(find.text('Exercise'));
    await t.pump();
    // A crossfade of about half a second instead of a walk across the room.
    await pumpUntil(t, find.text('Jumping jacks!'), seconds: 1.5);
    final transform = t.widget<Transform>(
      find.descendant(of: find.byKey(const ValueKey('room-twin')), matching: find.byType(Transform)).first,
    );
    expect(transform.transform.getRotation().entry(0, 1), closeTo(0, 1e-9));
    await pumpUntil(t, find.text('Feeling strong'), seconds: 4);
  });

  testWidgets('a human twin uses its own poses for every room action', (t) async {
    const human = TwinAppearance(type: TwinType.human);
    expect(resolveRoomPose(human, RoomPose.walk).$1, TwinPose.walkSide);
    expect(resolveRoomPose(human, RoomPose.walkFront).$1, TwinPose.walkFront);
    expect(resolveRoomPose(human, RoomPose.ball).$1, TwinPose.holdBall);
    expect(resolveRoomPose(human, RoomPose.eat).$1, TwinPose.eat);
    expect(resolveRoomPose(human, RoomPose.sleep).$1, TwinPose.sleep);
    expect(resolveRoomPose(human, RoomPose.think).$1, TwinPose.think);
    expect(resolveRoomPose(const TwinAppearance(look: TwinLook.plain), RoomPose.sleep).$1, TwinPose.sleep);
    await pumpRoom(t, look: human);
    await t.tap(find.text('Sleep'));
    await pumpUntil(t, find.text('Sleeping. Tap to wake'));
    await t.pump(const Duration(milliseconds: 300));
    final sprite = t.widget<TwinSprite>(find.byType(TwinSprite));
    expect(sprite.appearance.sprite(sprite.pose), 'assets/twin/human/pose/sleep.png');
  });

  testWidgets('a twin without the hat sleeps in its no-hat pose', (t) async {
    await pumpRoom(t, look: const TwinAppearance(look: TwinLook.plain));
    await t.tap(find.text('Sleep'));
    await pumpUntil(t, find.text('Sleeping. Tap to wake'));
    await t.pump(const Duration(milliseconds: 300));
    final sprite = t.widget<TwinSprite>(find.byType(TwinSprite));
    expect(sprite.appearance.sprite(sprite.pose), 'assets/twin/bear/pose_nohat/sleep.png');
  });

  testWidgets('no overflow on a small phone at 1.3x text', (t) async {
    setPhone(t, const Size(375, 667));
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(375, 667), textScaler: TextScaler.linear(1.3)),
          child: RoomScreen(appearance: look, onTalk: () {}, onCustomize: () {}, onFortune: () async {}),
        ),
      ),
    );
    await frames(t, 3);
    expect(t.takeException(), isNull);
  });

  testWidgets('effects: sweat and sparkles in Exercise, hop sparkles on a tap', (t) async {
    await pumpRoom(t);
    await t.tap(find.byKey(const ValueKey('room-twin')), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('room-fx')), findsOneWidget);
    await frames(t, 1.5);
    await t.tap(find.text('Exercise'));
    await pumpUntil(t, find.text('Jumping jacks!'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('room-fx')), findsOneWidget);
    await pumpUntil(t, find.text('Feeling strong'));
  });

  test('effects: each action spawns its own; none under reduced motion', () {
    for (final reduced in [false, true]) {
      final sim = RoomSim(layout: roomLayout, reduced: reduced);
      final kinds = <RoomFxKind>{};
      void seen() => kinds.addAll(sim.fx.map((p) => p.kind));
      final glows = <double>{};
      sim.tapTwin();
      run(sim, 1, seen);
      for (final a in [RoomAction.exercise, RoomAction.eat]) {
        sim.startAction(a);
        run(sim, 12, seen);
      }
      sim.startAction(RoomAction.fortune);
      run(sim, 10, () {
        seen();
        if (sim.glow > 0) glows.add((sim.glow * 100).roundToDouble());
      });
      if (reduced) {
        expect(kinds, isEmpty);
        expect(glows, {50}, reason: 'a steady glow, no pulses');
      } else {
        expect(kinds, {RoomFxKind.sparkle, RoomFxKind.drop});
        expect(glows.reduce((a, b) => a > b ? a : b), greaterThan(90), reason: 'the ball pulses');
      }
      sim.dispose();
    }
  });

  testWidgets('Eat takes the apple out of the bowl and pops it back after', (t) async {
    await pumpRoom(t);
    expect(image(roomLayout.bowlEmpty.asset), findsNothing);
    await t.tap(find.text('Eat'));
    await pumpUntil(t, find.text('Crunch, crunch!'));
    await t.pump(const Duration(milliseconds: 100));
    expect(image(roomLayout.bowlEmpty.asset), findsWidgets); // the apple is out
    await pumpUntil(t, find.text('Yum!'));
    expect(image(roomLayout.bowlEmpty.asset), findsWidgets);
    await pumpUntil(t, find.text('Full and happy'));
    expect(find.byKey(const ValueKey('room-apple-pop')), findsOneWidget); // popping back in
    await frames(t, 0.6);
    expect(image(roomLayout.bowlEmpty.asset), findsNothing);
    expect(find.byKey(const ValueKey('room-apple-pop')), findsNothing);
  });

  testWidgets('reduced motion: the apple comes back at once, with no effects', (t) async {
    await pumpRoom(t, reduced: true);
    await t.tap(find.text('Eat'));
    await pumpUntil(t, find.text('Crunch, crunch!'));
    await t.pump(const Duration(milliseconds: 100));
    expect(image(roomLayout.bowlEmpty.asset), findsWidgets);
    expect(find.byKey(const ValueKey('room-fx')), findsNothing);
    await pumpUntil(t, find.text('Full and happy'));
    await t.pump(const Duration(milliseconds: 50));
    expect(image(roomLayout.bowlEmpty.asset), findsNothing);
    expect(find.byKey(const ValueKey('room-apple-pop')), findsNothing);
  });

  testWidgets('a long press makes the twin dizzy, then all better', (t) async {
    await pumpRoom(t);
    await t.longPress(find.byKey(const ValueKey('room-twin')), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Whoa, dizzy!'), findsOneWidget);
    expect(twinPose(t), TwinPose.dizzy);
    await pumpUntil(t, find.text('All better'), seconds: 3);
    expect(twinPose(t), isNot(TwinPose.dizzy));
  });

  testWidgets('the standing bear blinks', (t) async {
    await pumpRoom(t);
    await pumpUntil(t, find.byKey(const ValueKey('room-blink')), seconds: 12);
    expect(twinPose(t), TwinPose.stand);
    await frames(t, 0.3);
    expect(find.byKey(const ValueKey('room-blink')), findsNothing);
  });

  test('idle: a sit on the rug or a wave every 8 to 12 s; the walk tilts, bobs and squashes', () {
    final sim = RoomSim(layout: roomLayout, random: math.Random(3));
    addTearDown(sim.dispose);
    final said = <String>[];
    var maxTilt = 0.0, maxBob = 0.0, minSq = 1.0;
    run(sim, 40, () {
      if (said.isEmpty || said.last != sim.status) said.add(sim.status);
      if (sim.pose == RoomPose.walk || sim.pose == RoomPose.walkFront || sim.pose == RoomPose.walkBack) {
        maxTilt = math.max(maxTilt, sim.tilt.abs());
        maxBob = math.max(maxBob, sim.bob);
        minSq = math.min(minSq, sim.sq);
      }
    });
    expect(said.where((s) => s == 'Hi there!' || s == 'Sitting on the rug').length, greaterThanOrEqualTo(2));
    expect(maxTilt, closeTo(3.5 * math.pi / 180, 0.005)); // the prototype's values
    expect(maxBob, closeTo(0.026 * roomLayout.bearHeight, 0.002));
    expect(minSq, closeTo(1 - 0.028, 0.004));
  });

  test('the room only slides on screens shorter than the render', () {
    const clear = EdgeInsets.only(top: 90, bottom: 260);
    expect(roomAlignmentY(roomLayout, const Size(390, 844), clear), 0);
    final y = roomAlignmentY(roomLayout, const Size(375, 667), clear);
    expect(y, greaterThan(0), reason: 'slides up to show more floor');
    expect(y, lessThanOrEqualTo(1));
  });

  testWidgets('button labels never break inside a word (test font, 390 wide)', (t) async {
    await pumpRoom(t);
    for (final label in ['Exercise', 'Eat', 'Sleep', 'Customize', 'Fortune']) {
      expectOneLine(t, label, checkFloor: false);
    }
  });

  group('FloorProjector', () {
    final p = roomLayout.projector;

    test('floor points round-trip through the homography', () {
      for (final pt in [Offset.zero, const Offset(1.05, 1.15), const Offset(-1.4, -1.0), const Offset(1.9, -1.9)]) {
        final back = p.screenToFloor(p.floorToScreen(pt));
        expect(back.dx, closeTo(pt.dx, 1e-6));
        expect(back.dy, closeTo(pt.dy, 1e-6));
      }
    });

    test('matches the calibration points rendered by the prototype', () {
      final json = jsonDecode(File('assets/scene/room/room_layers.json').readAsStringSync()) as Map<String, dynamic>;
      expect(json['viewProjection'], roomLayout.viewProjection);
      final fromJson = FloorProjector(
        viewProjection: [for (final v in json['viewProjection'] as List) (v as num).toDouble()],
        viewport: const Size(390, 844),
      );
      for (final c in json['calibration'] as List) {
        final w = [for (final v in c['world'] as List) (v as num).toDouble()];
        final s = [for (final v in c['screen'] as List) (v as num).toDouble()];
        final got = fromJson.project(w[0], w[1], w[2]);
        expect(got.dx, closeTo(s[0], 0.01));
        expect(got.dy, closeTo(s[1], 0.01));
      }
    });

    test('paths go around the bed', () {
      const a = Offset(-1.4, -1.0), b = Offset(1.3, -1.0);
      final path = roomLayout.planPath(a, b);
      expect(path.last, b);
      expect(path.length, greaterThan(1));
      var from = a;
      for (final p in path) {
        expect(roomLayout.clear(from, p), isTrue);
        from = p;
      }
      expect(roomLayout.planPath(const Offset(0.3, 0.1), const Offset(-1.0, 0.4)), [const Offset(-1.0, 0.4)]);
    });
  });

  test('the sim starts at rest and keeps the status short', () {
    final sim = RoomSim(layout: roomLayout);
    addTearDown(sim.dispose);
    expect(sim.resting, isTrue);
    final said = <String>{sim.status};
    sim.startAction(RoomAction.exercise);
    for (var i = 0; i < 20 * 60; i++) {
      sim.step(1 / 60);
      said.add(sim.status);
    }
    for (final s in said) {
      expect(s.split(' ').length, lessThanOrEqualTo(4), reason: s);
    }
  });

  group('with the bundled fonts', () {
    setUpAll(loadAppFonts);

    testWidgets('Exercise and Customize fit one line at 17 px on a 390 phone', (t) async {
      await pumpRoom(t);
      for (final label in ['Exercise', 'Eat', 'Sleep', 'Customize', 'Fortune']) {
        expectOneLine(t, label);
        expect(t.getRect(find.text(label)).height, closeTo(17 * 1.35, 0.5), reason: '$label is not scaled down');
      }
    });

    testWidgets('375 x 667: the twin stays clear of the activity row and dock during Exercise', (t) async {
      for (final scale in [1.0, 1.3]) {
        await pumpRoom(t, size: const Size(375, 667), textScale: scale);
        await t.tap(find.text('Exercise'));
        await pumpUntil(t, find.text('Jumping jacks!'));
        final row = boxOf(t, 'Exercise');
        for (var i = 0; i < 30; i++) {
          await t.pump(const Duration(milliseconds: 50));
          final twin = t.getRect(find.byKey(const ValueKey('room-twin')));
          expect(twin.bottom, lessThanOrEqualTo(row.top), reason: 'feet above the buttons at ${scale}x');
          expect(twin.top, greaterThanOrEqualTo(0), reason: 'head on screen at ${scale}x');
        }
        await pumpUntil(t, find.text('Feeling strong'));
        expect(t.takeException(), isNull);
      }
    });

    testWidgets('labels stay on one line at 15 px or more on 375 x 667 with 1.3x text', (t) async {
      await pumpRoom(t, size: const Size(375, 667), textScale: 1.3);
      for (final label in ['Exercise', 'Eat', 'Sleep', 'Customize', 'Fortune']) {
        expectOneLine(t, label);
      }
      expect(t.takeException(), isNull);
    });
  });
}
