import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/forecast/forecast_client.dart';
import 'package:lifesim/forecast/forecast_screen.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/voice/fakes.dart';

import 'support/assessments.dart';

/// An on-device result for a 70-year-old man.
Map<String, dynamic> supportedJson() =>
    availableAssessment(const {1: 0.9805, 2: 0.958, 3: 0.9324, 4: 0.907, 5: 0.8802});

Map<String, dynamic> unsupportedJson() => unavailableAssessment();

class FakeForecastClient implements ForecastClient {
  final calls = <Map<String, dynamic>>[];
  final answers = <Object>[]; // Forecast or ForecastFailure, in order
  Completer<void>? gate;

  @override
  Future<Forecast> predict(Map<String, dynamic> confirmedProfile) async {
    calls.add(confirmedProfile);
    if (gate != null) await gate!.future;
    final next = answers.removeAt(0);
    if (next is ForecastFailure) throw next;
    return next as Forecast;
  }
}

class Rig {
  final client = FakeForecastClient();
  final speech = FakeSpeechOutput();
  int backs = 0;

  Future<void> pump(WidgetTester t, {double scale = 1, bool reduceMotion = false, bool voice = true}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            size: const Size(390, 844),
            disableAnimations: reduceMotion,
          ),
          child: ForecastScreen(
            client: client,
            profile: const {'age': 70, 'sex': 'male'},
            speech: voice ? speech : null,
            onBack: () => backs++,
          ),
        ),
      ),
    );
  }
}

const sentence = 'Out of 100 people with answers like yours, about 88 were still living 5 years later.';

/// Painted-card buttons are at least 56pt; text links at least 48pt.
void expectBigButtons(WidgetTester t) {
  final buttons = find.byType(LipButton);
  expect(buttons, findsWidgets);
  for (final e in buttons.evaluate()) {
    expect(t.getSize(find.byWidget(e.widget)).height, greaterThanOrEqualTo(56));
  }
  for (final e in find.byWidgetPredicate((w) => w is ButtonStyleButton).evaluate()) {
    expect(t.getSize(find.byWidget(e.widget)).height, greaterThanOrEqualTo(48));
  }
}

void main() {
  testWidgets('reveals the 5-year result in one sentence, the number, bear heads and what it means', (t) async {
    final r = Rig()..client.answers.add(forecastFrom(supportedJson()));
    r.client.gate = Completer<void>();
    await r.pump(t);
    expect(find.text('Looking into the magic ball…'), findsOneWidget);
    r.client.gate!.complete();
    await t.pumpAndSettle();

    expect(find.text(sentence), findsOneWidget);
    expect(find.text('Your look ahead'), findsOneWidget);
    expect(find.textContaining('About 88 in 100', findRichText: true), findsOneWidget);
    expect(find.text('chance you\u2019re still here in 5 years'), findsOneWidget);
    expect(t.widget<BearHeadArray>(find.byType(BearHeadArray)).filled, 88);
    expect(find.bySemanticsLabel('About 88 of 100 bear heads are filled.'), findsOneWidget);
    expect(find.text('Linked, not proven.'), findsOneWidget);
    // Why? opens what it means, with the server's limitations.
    await t.ensureVisible(find.text('Why?'));
    await t.pumpAndSettle();
    await t.tap(find.text('Why?'));
    await t.pumpAndSettle();
    expect(find.text('What this means'), findsOneWidget);
    expect(find.textContaining('not a promise, and they are not a date'), findsOneWidget);
    expect(find.textContaining('links, not causes'), findsOneWidget);
    expect(find.textContaining('Nothing is filled in for you.'), findsOneWidget);
    expect(find.textContaining('not an individual death date or medical prognosis'), findsOneWidget);
    await t.ensureVisible(find.text('Got it'));
    await t.pumpAndSettle();
    await t.tap(find.text('Got it'));
    await t.pumpAndSettle();
    // Survival is labelled on the forecast itself, not only on the detail screen.
    expect(find.text('Modeled survival of similar people'), findsOneWidget);
    // The 1- and 3-year values live on the detail curve.
    await t.ensureVisible(find.text('See what shaped it'));
    await t.pumpAndSettle();
    await t.tap(find.text('See what shaped it'));
    await t.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Modeled survival of similar people. Out of 100 people with answers like yours: about 98 after 1 year, about 96 after 2 years, '
        'about 93 after 3 years, about 91 after 4 years, about 88 after 5 years.',
      ),
      findsOneWidget,
    );
    expect(find.text('Modeled survival of similar people'), findsOneWidget);
    expect(find.text('We assumed'), findsNothing);
    await t.tap(find.bySemanticsLabel('Back to your look ahead'));
    await t.pumpAndSettle();
    expect(r.speech.spoken, [sentence]);
    for (final banned in ['life expectancy', 'death', 'countdown', 'you will die']) {
      expect(find.textContaining(RegExp(banned, caseSensitive: false)), findsNothing);
    }
    expect(r.client.calls.single, {'age': 70, 'sex': 'male'});
  });

  testWidgets('reduced motion shows the result at once, with no reveal animation', (t) async {
    final r = Rig()..client.answers.add(forecastFrom(supportedJson()));
    await r.pump(t, reduceMotion: true);
    await t.pump(); // the answer arrives
    await t.pump();
    expect(find.text(sentence), findsOneWidget);
    final fade = t.widget<FadeTransition>(
      find.ancestor(of: find.text(sentence), matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, 1);
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('Back calls onBack', (t) async {
    final r = Rig()..client.answers.add(forecastFrom(supportedJson()));
    await r.pump(t);
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Back'));
    expect(r.backs, 1);
  });

  testWidgets('voice off: nothing is spoken', (t) async {
    final r = Rig()..client.answers.add(forecastFrom(supportedJson()));
    await r.pump(t, voice: false);
    await t.pumpAndSettle();
    expect(find.text(sentence), findsOneWidget);
    expect(r.speech.spoken, isEmpty);
    expect(find.text('Say it again'), findsNothing);
  });

  testWidgets('unsupported: the mascot explains why and offers to go back to the answers', (t) async {
    final r = Rig()..client.answers.add(forecastFrom(unsupportedJson()));
    await r.pump(t);
    await t.pumpAndSettle();
    const line = "I can't make a forecast for you yet. Annual estimates support ages 35–79 only.";
    expect(find.text(line), findsOneWidget);
    expect(r.speech.spoken, [line]);
    expect(find.byType(BearHeadArray), findsNothing);
    expect(find.textContaining('in 100', findRichText: true), findsNothing);
    expect(find.bySemanticsLabel(RegExp('in 100 still living')), findsNothing);
    await t.ensureVisible(find.text('Go back to my answers'));
    await t.pumpAndSettle();
    await t.tap(find.text('Go back to my answers'));
    expect(r.backs, 1);
  });

  testWidgets('an error offers Try again, which asks again', (t) async {
    final r = Rig()..client.answers.addAll([const ForecastFailure('offline'), forecastFrom(supportedJson())]);
    await r.pump(t);
    await t.pumpAndSettle();
    expect(find.text(couldNotReach), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text(sentence), findsOneWidget);
    expect(r.client.calls, hasLength(2));
  });

  for (final kind in ['supported', 'unsupported', 'error']) {
    testWidgets('no overflow at text scale 2.0 on 390x844 ($kind), buttons at least 56 pt', (t) async {
      final r = Rig();
      r.client.answers.add(switch (kind) {
        'supported' => forecastFrom(supportedJson()),
        'unsupported' => forecastFrom(unsupportedJson()),
        _ => const ForecastFailure('offline'),
      });
      await r.pump(t, scale: 2);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final scrollable = find.byType(Scrollable).first;
      for (final label in ['Go back to my answers', 'Try again', 'Say it again', 'See what shaped it', 'Go back']) {
        final f = find.text(label);
        if (f.evaluate().isEmpty) continue;
        await t.scrollUntilVisible(f, 200, scrollable: scrollable);
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull);
      expectBigButtons(t);
    });
  }

  testWidgets('Continue after the intake opens the forecast with the confirmed answers', (t) async {
    final forecast = FakeForecastClient()..answers.add(forecastFrom(supportedJson()));
    final c = VoiceOnboardingController(
      guide: FakeConversationGuide(),
      input: FakeSpeechInput(),
      output: FakeSpeechOutput(),
    );
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
    expect(forecast.calls.single, {'age': 70});
    expect(find.text(sentence), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Back'));
    await t.pumpAndSettle();
    // Back lands on wellness-first Home; the estimate is secondary.
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(find.text('Getting to know you'), findsOneWidget);
    expect(find.text('about 88 in 100'), findsNothing);
    expect(find.text('Your estimate'), findsOneWidget);
  });
}
