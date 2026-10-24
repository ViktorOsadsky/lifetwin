import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/forecast/forecast_client.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/widgets/lip_button.dart';

import 'forecast_screen_test.dart' show FakeForecastClient, supportedJson;

Future<void> pumpRoom(WidgetTester t, {bool hasProfile = false, VoidCallback? onTalk, VoidCallback? onForecast}) =>
    t.pumpWidget(
      MaterialApp(
        home: RoomScreen(hasProfile: hasProfile, onTalk: onTalk ?? () {}, onForecast: onForecast ?? () {}),
      ),
    );

void phoneTest(String name, Future<void> Function(WidgetTester t) body) {
  testWidgets(name, (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await body(t);
  });
}

void main() {
  phoneTest('first visit: greeting, twin, Pip, both buttons', (t) async {
    await pumpRoom(t);
    expect(find.text('Your room'), findsOneWidget);
    expect(find.text("Hi! I'm Pip. Shall we talk?"), findsOneWidget);
    expect(find.bySemanticsLabel('Your twin, waving'), findsOneWidget);
    expect(find.bySemanticsLabel('Pip'), findsOneWidget);
    expect(find.text('Talk with Pip'), findsOneWidget);
    expect(find.text('See my forecast'), findsOneWidget);
  });

  phoneTest('after the intake Pip says Welcome back.', (t) async {
    await pumpRoom(t, hasProfile: true);
    expect(find.text('Welcome back.'), findsOneWidget);
  });

  phoneTest('button sizes: primary at least 72, secondary at least 56', (t) async {
    await pumpRoom(t);
    expect(t.getSize(find.widgetWithText(LipButton, 'Talk with Pip')).height, greaterThanOrEqualTo(96));
    expect(t.getSize(find.widgetWithText(LipButton, 'See my forecast')).height, greaterThanOrEqualTo(72));
  });

  phoneTest('Talk calls onTalk; forecast with a profile calls onForecast', (t) async {
    var talk = 0, forecast = 0;
    await pumpRoom(t, hasProfile: true, onTalk: () => talk++, onForecast: () => forecast++);
    await t.tap(find.text('Talk with Pip'));
    await t.tap(find.text('See my forecast'));
    expect([talk, forecast], [1, 1]);
  });

  phoneTest('forecast without a profile: Pip asks to talk first, nothing opens', (t) async {
    var forecast = 0;
    await pumpRoom(t, onForecast: () => forecast++);
    await t.tap(find.text('See my forecast'));
    await t.pump();
    expect(forecast, 0);
    expect(find.text(RoomScreen.talkFirst), findsOneWidget);
    expect(find.text('Talk with Pip'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    phoneTest('no overflow at 390x844, text scale $scale', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      for (final has in [false, true]) {
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(scale)),
              child: RoomScreen(hasProfile: has, onTalk: () {}, onForecast: () {}),
            ),
          ),
        );
        await t.tap(find.text('See my forecast'), warnIfMissed: false);
        await t.pump();
        expect(t.takeException(), isNull);
      }
    });
  }

  group('in the app', () {
    Future<(VoiceOnboardingController, FakeForecastClient)> start(WidgetTester t) async {
      final forecast = FakeForecastClient()..answers.add(Forecast.parse(supportedJson()));
      final c = VoiceOnboardingController(
        guide: FakeConversationGuide(),
        input: FakeSpeechInput(),
        output: FakeSpeechOutput(),
      );
      await t.pumpWidget(LifeTwinApp(controller: c, forecastClient: forecast));
      return (c, forecast);
    }

    phoneTest('no profile: See my forecast stays on the Room and Talk opens the consent screen', (t) async {
      await start(t);
      await t.tap(find.text('See my forecast'));
      await t.pumpAndSettle();
      expect(find.text(RoomScreen.talkFirst), findsOneWidget);
      await t.tap(find.text('Talk with Pip'));
      await t.pumpAndSettle();
      expect(find.text('Talk with me?'), findsOneWidget);
    });

    phoneTest('intake Continue opens the forecast; Back returns to the Room; forecast button then works', (t) async {
      final (_, forecast) = await start(t);
      await t.tap(find.text('Talk with Pip'));
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
      expect(forecast.calls, hasLength(1));
      await t.tap(find.text('Back'));
      await t.pumpAndSettle();
      expect(find.text('Welcome back.'), findsOneWidget);
      forecast.answers.add(Forecast.parse(supportedJson()));
      await t.tap(find.text('See my forecast'));
      await t.pumpAndSettle();
      expect(forecast.calls, hasLength(2));
      expect(forecast.calls.last, {'age': 70});
    });

    phoneTest('"Go back to my answers" opens the conversation, where Go back can change one', (t) async {
      final (c, forecast) = await start(t);
      await t.tap(find.text('Talk with Pip'));
      await t.pumpAndSettle();
      await t.tap(find.text("No, I'll type"));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 700)); // the AI question ignores a second tap at first
      await t.ensureVisible(find.text('Not now'));
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '70');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      await t.tap(find.text('Yes'));
      await t.pumpAndSettle();
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
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
      await t.tap(find.text('See my forecast'));
      await t.pumpAndSettle();
      expect(find.text(RoomScreen.talkFirst), findsOneWidget);
      expect(forecast.calls, hasLength(1));
    });
  });
}
