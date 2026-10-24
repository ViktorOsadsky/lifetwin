import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/forecast/forecast_client.dart';
import 'package:lifesim/forecast/fortune_ceremony_screen.dart';
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
}) async {
  setPhone(t);
  final notifier = ValueNotifier(look);
  addTearDown(notifier.dispose);
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), disableAnimations: reduced),
        child: RoomScreen(
          appearance: notifier,
          onTalk: () {},
          onCustomize: () {},
          onFortune: onFortune ?? () async {},
          outlook: outlook,
        ),
      ),
    ),
  );
  await t.pump();
  return notifier;
}

void main() {
  testWidgets('the room draws the background, the twin between the layers, and the UI', (t) async {
    await pumpRoom(t);
    expect(image(roomLayout.bgAsset), findsOneWidget);
    expect(find.byType(TwinSprite), findsOneWidget);
    expect(t.widget<TwinSprite>(find.byType(TwinSprite)).appearance.sprite(), 'assets/twin/bear/pose/stand.png');
    // Standing in front of the bed and behind the table line: the table covers, the quilt does not.
    expect(image(roomLayout.fgTable.asset), findsOneWidget);
    expect(image(roomLayout.fgBed.asset), findsNothing);
    final stack = find.descendant(of: find.byType(RoomScene), matching: find.byType(Stack)).first;
    final order = t.widget<Stack>(stack).children;
    final bgAt = order.indexWhere((w) => w is Positioned && w.child is Image);
    final twinAt = order.indexWhere((w) => w.key == const ValueKey('room-twin'));
    final fgAt = order.lastIndexWhere((w) => w is Positioned && w.child is IgnorePointer);
    expect(bgAt < twinAt && twinAt < fgAt, isTrue, reason: 'bg, then the twin, then the foreground');
    expect(find.bySemanticsLabel('Twin name: My twin'), findsOneWidget);
    expect(find.text('Hanging out'), findsOneWidget);
    expect(find.text('Ask the ball'), findsOneWidget); // no forecast yet: no number
    expect(find.textContaining('in 100'), findsNothing);
    for (final label in ['Exercise', 'Eat', 'Sleep', 'Customize', 'Talk', 'Fortune']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in ['Exercise', 'Eat', 'Sleep']) {
      expect(t.getSize(find.ancestor(of: find.text(label), matching: find.byType(GestureDetector)).first).height,
          greaterThanOrEqualTo(48));
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
    setPhone(t);
    await t.pumpWidget(LifeTwinApp(controller: fakeController()));
    await t.tap(find.text('Fortune'));
    await t.pump();
    expect(find.text('Off to the shelf'), findsOneWidget);
    await pumpUntil(t, find.text('The ball glows!'));
    expect(twinPose(t), TwinPose.holdBall);
    expect(image(roomLayout.shelfEmpty.asset), findsOneWidget); // the ball left the shelf
    await pumpUntil(t, find.byType(FortuneCeremonyScreen));
    await t.pumpAndSettle();
    await t.tap(find.text('Back to room'));
    await t.pumpAndSettle();
    expect(find.byType(FortuneCeremonyScreen), findsNothing);
    expect(image(roomLayout.shelfEmpty.asset), findsNothing); // the ball is back
  });

  testWidgets('Talk still swooshes to the conversation and Back returns', (t) async {
    setPhone(t);
    await t.pumpWidget(LifeTwinApp(controller: fakeController()));
    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    expect(find.byType(VoiceOnboardingScreen), findsOneWidget);
    expect(find.text('Talk with me?'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Back to room'));
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

  testWidgets('a human twin uses its own poses and falls back where it has none', (t) async {
    const human = TwinAppearance(type: TwinType.human);
    expect(resolveRoomPose(human, RoomPose.walk).$1, TwinPose.walkSide);
    expect(resolveRoomPose(human, RoomPose.walkFront).$1, TwinPose.walkSide);
    expect(resolveRoomPose(human, RoomPose.ball).$1, TwinPose.holdBall);
    expect(resolveRoomPose(human, RoomPose.eat).$1, TwinPose.sit);
    expect(resolveRoomPose(human, RoomPose.sleep).$1, TwinPose.sit);
    expect(resolveRoomPose(human, RoomPose.think).$1, TwinPose.stand);
    expect(resolveRoomPose(const TwinAppearance(look: TwinLook.plain), RoomPose.sleep).$1, TwinPose.stand);
    await pumpRoom(t, look: human);
    await t.tap(find.text('Sleep'));
    await pumpUntil(t, find.text('Sleeping. Tap to wake'));
    await t.pump(const Duration(milliseconds: 300));
    final sprite = t.widget<TwinSprite>(find.byType(TwinSprite));
    expect(sprite.appearance.sprite(sprite.pose), 'assets/twin/human/pose/sit.png');
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
      final path = roomLayout.planPath(const Offset(-1.0, -0.1), const Offset(1.0, -0.1));
      expect(path.last, const Offset(1.0, -0.1));
      expect(roomLayout.planPath(const Offset(0.3, 0.1), const Offset(1.0, 1.15)), [const Offset(1.0, 1.15)]);
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
}
