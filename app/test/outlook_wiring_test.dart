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
    await t.tap(find.byTooltip('What moves your score'));
    await t.pumpAndSettle();
    expect(find.byType(OutlookDriversScreen), findsOneWidget);
    expect(find.text('Linked with a lower modeled outlook'), findsWidgets);
    await t.scrollUntilVisible(find.text('Explore an experiment'), 300);
    await t.tap(find.text('Explore an experiment'));
    await t.pumpAndSettle();
    expect(find.byType(ExperimentScreen), findsOneWidget);
  });
}
