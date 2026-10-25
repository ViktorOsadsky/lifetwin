// "Users can't edit their things without going through the agent": no screen offers an inline
// editor for a saved profile value; the one route is Settings > Change an answer (Mochi), and a
// change made there is labelled "Changed with Mochi".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
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
  late TwinRepository repo;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  Future<void> pumpApp(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    repo = await memoryRepo(model);
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

  Future<void> back(WidgetTester t) async {
    Navigator.of(t.element(find.byType(Scaffold).last)).pop();
    await t.pumpAndSettle();
  }

  void expectNoInlineEditor(WidgetTester t, String where) {
    expect(find.byType(TextField), findsNothing, reason: '$where has a text field');
    expect(find.byType(TextFormField), findsNothing, reason: '$where has a form field');
    expect(find.byType(Slider), findsNothing, reason: '$where has a slider');
    expect(find.byType(DropdownButton), findsNothing, reason: '$where has a dropdown');
    expect(find.byIcon(Icons.edit), findsNothing, reason: where);
    expect(find.byIcon(Icons.edit_outlined), findsNothing, reason: where);
    expect(find.byIcon(Icons.edit_rounded), findsNothing, reason: where);
  }

  testWidgets('History lists answers but offers no inline edit, even when a row is tapped', (t) async {
    await pumpApp(t);
    await t.tap(find.byTooltip('My history'));
    await t.pumpAndSettle();
    expect(find.text('Your history'), findsOneWidget);
    expectNoInlineEditor(t, 'History');
    // Tapping each visible entry never opens an editor.
    final rows = find.byType(InkWell);
    for (var i = 0; i < rows.evaluate().length && i < 8; i++) {
      final row = rows.at(i);
      if (!t.any(row)) continue;
      await t.ensureVisible(row);
      await t.tap(row, warnIfMissed: false);
      await t.pumpAndSettle();
      expectNoInlineEditor(t, 'History row $i');
      if (find.text('Your history').evaluate().isEmpty) {
        await back(t);
        await t.pumpAndSettle();
      }
    }
    expect(repo.profile['sleep_hours'], 5, reason: 'nothing changed by browsing');
  });

  testWidgets('My data and the Settings hub have no inline editor; Change an answer opens Mochi', (t) async {
    await pumpApp(t);
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle();
    expectNoInlineEditor(t, 'Settings hub');
    await t.scrollUntilVisible(find.text('My data'), 200);
    await t.tap(find.text('My data'));
    await t.pumpAndSettle();
    expectNoInlineEditor(t, 'My data');
    await back(t);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Change an answer'));
    await t.pumpAndSettle();
    await t.tap(find.text('Change an answer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Mochi'), findsWidgets, reason: 'the change goes through Mochi');
    expect(repo.profile['sleep_hours'], 5, reason: 'opening the chat changes nothing');
  });

  test('writing into the profile map the repository hands out does not change the stored profile', () async {
    repo = await memoryRepo(model);
    await repo.saveConversationProfile(_profile);
    repo.profile['sleep_hours'] = 9;
    repo.store.profile['sleep_hours'] = 9;
    expect(repo.profile['sleep_hours'], 5);
  });
}
