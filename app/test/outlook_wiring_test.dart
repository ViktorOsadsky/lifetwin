// Outlook drivers and the quiz are reachable from the forecast and from Home.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/experiment/experiment_screen.dart';
import 'package:lifesim/forecast/forecast_screen.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/wellness/outlook_drivers_screen.dart';

import 'forecast_screen_test.dart' show FakeForecastClient, supportedJson;
import 'support/assessments.dart';
import 'support/app_fonts.dart';

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

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('the forecast offers "What moves it" and the quiz', (t) async {
    phone(t);
    var drivers = 0, quiz = 0;
    final client = FakeForecastClient()..answers.add(forecastFrom(supportedJson()));
    await t.pumpWidget(
      MaterialApp(
        home: ForecastScreen(
          client: client,
          profile: const {'age': 70},
          onBack: () {},
          onDrivers: () => drivers++,
          onPlayQuiz: () => quiz++,
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final label in ['What moves it', 'Play the quiz']) {
      await t.ensureVisible(find.text(label));
      await t.pump();
      await t.tap(find.text(label));
    }
    expect((drivers, quiz), (1, 1));
  });

  testWidgets('Home "What moves it" opens the drivers; its experiment button opens Experiment', (t) async {
    phone(t);
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
    await repo.saveConversationProfile(_profile);
    await t.pumpWidget(
      LifeTwinApp(
        controller: VoiceOnboardingController(
          guide: FakeConversationGuide(),
          input: FakeSpeechInput(),
          output: FakeSpeechOutput(),
        ),
        twin: Future.value(repo),
      ),
    );
    await t.pump();
    await t.pump();
    await t.tap(find.text('What moves it'));
    await t.pumpAndSettle();
    expect(find.byType(OutlookDriversScreen), findsOneWidget);
    expect(find.text('Linked with a lower modeled outlook'), findsWidgets);
    await t.scrollUntilVisible(find.text('Explore an experiment'), 300);
    await t.tap(find.text('Explore an experiment'));
    await t.pumpAndSettle();
    expect(find.byType(ExperimentScreen), findsOneWidget);
  });

  testWidgets('after a change through Mochi the reveal shows the saved answers, not the old intake', (t) async {
    phone(t);
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
    final forecast = FakeForecastClient()
      ..answers.addAll([forecastFrom(supportedJson()), forecastFrom(supportedJson())]);
    final c = VoiceOnboardingController(
      guide: FakeConversationGuide(),
      input: FakeSpeechInput(),
      output: FakeSpeechOutput(),
    );
    await t.pumpWidget(LifeTwinApp(controller: c, forecastClient: forecast, twin: Future.value(repo)));
    await t.pump();
    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    await t.tap(find.text("No, I'll type"));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 700));
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
    await t.tap(find.text('Ask the ball'));
    await t.pumpAndSettle();
    expect(forecast.calls.last['age'], 70);
    await t.tap(find.bySemanticsLabel('Back'));
    await t.pumpAndSettle();

    // A change saved through Mochi (or a weekly check-in).
    await repo.saveConversationProfile({'age': 71});
    await t.pumpAndSettle();
    await t.tap(find.text('See your estimate'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ask the ball'));
    await t.pumpAndSettle();
    expect(forecast.calls.last['age'], 71);
  });
}
