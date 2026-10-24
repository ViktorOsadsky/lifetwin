import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/forecast/forecast_client.dart';
import 'package:lifesim/health/health_sample.dart';
import 'package:lifesim/health/health_screen.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/room/room_screen.dart';
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

Future<void> pumpRoom(
  WidgetTester t, {
  bool hasProfile = false,
  VoidCallback? onTalk,
  VoidCallback? onFortune,
  VoidCallback? onUseHealth,
  double scale = 1,
}) async {
  final look = ValueNotifier(const TwinAppearance());
  addTearDown(look.dispose);
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: RoomScreen(
            appearance: look,
            hasProfile: hasProfile,
            onTalk: onTalk ?? () {},
            onCustomize: () {},
            onFortune: onFortune ?? () {},
            onUseHealth: onUseHealth,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Room renders the twin on the plate, the bubble, the mood chip and the dock', (t) async {
    setPhone(t);
    await pumpRoom(t);
    final sprite = t.widget<TwinSprite>(find.byType(TwinSprite));
    expect(sprite.appearance.sprite(), 'assets/twin/bear/pose/stand.png');
    expect(find.bySemanticsLabel('Your bear twin in the Cal hat'), findsOneWidget);
    expect(find.text(RoomScreen.firstGreeting), findsOneWidget);
    expect(find.bySemanticsLabel('Feeling cozy'), findsOneWidget);
    expect(find.bySemanticsLabel('Twin name: My twin'), findsOneWidget);
    for (final label in ['Customize', 'Talk', 'Fortune']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(t.getSize(find.byType(LipButton)).height, greaterThanOrEqualTo(56));
    expect(t.takeException(), isNull);
  });

  testWidgets('after the intake the bubble says Welcome back.', (t) async {
    setPhone(t);
    await pumpRoom(t, hasProfile: true);
    expect(find.text(RoomScreen.returningGreeting), findsOneWidget);
  });

  testWidgets('Talk calls onTalk; Fortune with a profile calls onFortune', (t) async {
    setPhone(t);
    var talk = 0, fortune = 0;
    await pumpRoom(t, hasProfile: true, onTalk: () => talk++, onFortune: () => fortune++);
    await t.tap(find.text('Talk'));
    await t.tap(find.text('Fortune'));
    expect([talk, fortune], [1, 1]);
  });

  testWidgets('Fortune without a profile: the twin asks to talk first, nothing opens', (t) async {
    setPhone(t);
    var fortune = 0;
    await pumpRoom(t, onFortune: () => fortune++);
    await t.tap(find.text('Fortune'));
    await t.pump();
    expect(fortune, 0);
    expect(find.text(RoomScreen.talkFirst), findsOneWidget);
    expect(find.text('Talk'), findsOneWidget);
  });

  for (final scale in [1.0, 3.1]) {
    testWidgets('scale $scale: "Use my Apple Health" pill: one line, at least 48 pt, opens the import', (t) async {
      setPhone(t);
      var opened = 0;
      await pumpRoom(t, scale: scale, onUseHealth: () => opened++);
      expect(t.takeException(), isNull);
      final pill = find.ancestor(of: find.text('Use my Apple Health'), matching: find.byType(GestureDetector)).first;
      expect(t.getSize(pill).height, greaterThanOrEqualTo(48));
      expect(t.widget<Text>(find.text('Use my Apple Health')).style!.fontSize, greaterThanOrEqualTo(17));
      // One line: shrunk to fit rather than wrapped.
      expect(
        t.getSize(find.ancestor(of: find.text('Use my Apple Health'), matching: find.byType(FittedBox))).height,
        lessThan(t.getSize(pill).height),
      );
      await t.ensureVisible(pill);
      await t.tap(pill);
      expect(opened, 1);
    });
  }

  testWidgets('no pill once Health data is confirmed (no import callback)', (t) async {
    setPhone(t);
    await pumpRoom(t);
    expect(find.text('Use my Apple Health'), findsNothing);
  });

  testWidgets('Room swaps to the human twin when the look changes', (t) async {
    setPhone(t);
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: RoomScreen(appearance: look, onTalk: () {}, onCustomize: () {}, onFortune: () {}),
      ),
    );
    look.value = look.value.copyWith(type: TwinType.human);
    await t.pumpAndSettle();
    expect(t.widget<TwinSprite>(find.byType(TwinSprite)).appearance.sprite(), 'assets/twin/human/base/cal_hat.png');
  });

  for (final scale in [1.0, 1.3, 2.0, 3.0]) {
    testWidgets('no overflow and dock labels on one line at text scale $scale', (t) async {
      setPhone(t);
      for (final has in [false, true]) {
        await pumpRoom(t, hasProfile: has, scale: scale);
        await t.tap(find.text('Fortune'), warnIfMissed: false);
        await t.pump();
        expect(t.takeException(), isNull);
        for (final label in ['Customize', 'Fortune']) {
          // One line: the label is no taller than one line of its own (scaled) text.
          final text = t.widget<Text>(find.text(label));
          final painter = TextPainter(
            text: TextSpan(text: label, style: text.style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
          )..layout();
          expect(
            t.getSize(find.ancestor(of: find.text(label), matching: find.byType(FittedBox))).height,
            lessThanOrEqualTo(painter.height + 0.5),
          );
          painter.dispose();
        }
      }
    });
  }

  testWidgets('Room does not overflow on a small phone at 1.3x text', (t) async {
    setPhone(t, const Size(375, 667));
    await pumpRoom(t, scale: 1.3);
    expect(t.takeException(), isNull);
  });

  group('in the app', () {
    Future<(VoiceOnboardingController, FakeForecastClient)> start(WidgetTester t) async {
      setPhone(t);
      final forecast = FakeForecastClient()..answers.add(Forecast.parse(supportedJson()));
      final c = fakeController();
      await t.pumpWidget(LifeTwinApp(controller: c, forecastClient: forecast));
      return (c, forecast);
    }

    Future<void> typeOneAnswer(WidgetTester t) async {
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
    }

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

    testWidgets('Talk swooshes to the conversation and Home returns to the Room', (t) async {
      await start(t);
      expect(find.byType(RoomScreen), findsOneWidget);
      await t.tap(find.text('Talk'));
      await t.pumpAndSettle();
      expect(find.byType(VoiceOnboardingScreen), findsOneWidget);
      expect(find.text('Talk with me?'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Home'));
      await t.pumpAndSettle();
      expect(find.byType(VoiceOnboardingScreen), findsNothing);
      expect(find.text(RoomScreen.firstGreeting), findsOneWidget);
    });

    testWidgets('reduced motion: Talk still opens the conversation, with no running animation after', (t) async {
      setPhone(t);
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
          child: LifeTwinApp(controller: fakeController()),
        ),
      );
      await t.tap(find.text('Talk'));
      await t.pumpAndSettle();
      expect(find.text('Talk with me?'), findsOneWidget);
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('no profile: Fortune stays on the Room and Talk opens the consent screen', (t) async {
      await start(t);
      await t.tap(find.text('Fortune'));
      await t.pumpAndSettle();
      expect(find.text(RoomScreen.talkFirst), findsOneWidget);
      await t.tap(find.text('Talk'));
      await t.pumpAndSettle();
      expect(find.text('Talk with me?'), findsOneWidget);
    });

    testWidgets('intake Continue opens the fortune; Back returns to the Room; Fortune then works', (t) async {
      final (_, forecast) = await start(t);
      await typeOneAnswer(t);
      expect(forecast.calls, hasLength(1));
      await t.tap(find.bySemanticsLabel('Back'));
      await t.pumpAndSettle();
      expect(find.text(RoomScreen.returningGreeting), findsOneWidget);
      forecast.answers.add(Forecast.parse(supportedJson()));
      await t.tap(find.text('Fortune'));
      await t.pumpAndSettle();
      await t.tap(find.text('Ask the ball'));
      await t.pumpAndSettle();
      expect(forecast.calls, hasLength(2));
      expect(forecast.calls.last, {'age': 70});
    });

    testWidgets('"Go back to my answers" opens the conversation, where Go back can change one', (t) async {
      final (c, forecast) = await start(t);
      await typeOneAnswer(t);
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
      await t.pumpAndSettle();
      expect(find.text(RoomScreen.talkFirst), findsOneWidget);
      expect(forecast.calls, hasLength(1));
    });
  });
}
