// Clean Home, and the Settings hub that holds everything that left it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/my_data_screen.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/voice/fakes.dart';

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

  Future<void> pumpApp(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = await memoryRepo(model);
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
  }

  testWidgets('Home: score card, one Check in, one Today card, the dock; the old pills are gone', (t) async {
    await pumpApp(t);
    expect(find.text('Health score'), findsOneWidget);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.textContaining('Today', findRichText: true), findsOneWidget);
    for (final gone in ['Use my Apple Health', 'Upload a document', 'My data & privacy', 'What I see', 'Hanging out']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Add band'), findsOneWidget);
    expect(find.byTooltip('My history'), findsOneWidget);
  });

  testWidgets('Settings hub rows: My data, Reminders, Change an answer, Health documents, Apple Health', (t) async {
    await pumpApp(t);
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle();
    for (final row in ['Change an answer', 'Apple Health', 'Health documents', 'Reminders', 'My data']) {
      await t.scrollUntilVisible(find.text(row), 200);
      expect(find.text(row), findsWidgets, reason: row);
    }
    await t.ensureVisible(find.text('See your data or delete it'));
    await t.pumpAndSettle();
    await t.tap(find.text('See your data or delete it'));
    await t.pumpAndSettle();
    expect(find.byType(MyDataScreen), findsOneWidget);
  });
}
