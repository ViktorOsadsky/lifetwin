// Home layout against the product rules (current Home; codex/c-home-order is not merged):
// the health score is the focus, Add band is a top-right header icon, no stray clutter pills,
// no death date, the twin's activity row exists.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/voice/fakes.dart';

import 'support/app_fonts.dart';
import 'support/settings_hub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  Future<void> pumpHome(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = await memoryRepo(model);
    await repo.saveConversationProfile({
      'age': 55,
      'sex': 'male',
      'height_cm': 175.0,
      'weight_kg': 80.0,
      'sleep_hours': 7,
      'smoking_status': 'never',
      'diabetes': false,
      'hypertension_diagnosed': false,
      'general_health': 3,
      'vigorous_recreation_min_week': 30,
      'moderate_recreation_min_week': 60,
      'sedentary_min_day': 360,
    });
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

  testWidgets('Add band is a header icon in the top-right, not a pill in the body', (t) async {
    await pumpHome(t);
    expect(find.text('Add band'), findsNothing, reason: 'no "Add band" text pill in the body');
    final band = t.getRect(find.byTooltip('Add band'));
    expect(band.center.dx, greaterThan(390 / 2), reason: 'top-right half');
    expect(band.top, lessThan(120), reason: 'in the header');
    expect(band.width >= 48 && band.height >= 48, isTrue, reason: '48 pt target');
    // The header icons share one row with Settings, to its left.
    final settings = t.getRect(find.byTooltip('Settings'));
    expect(settings.center.dx, greaterThan(band.center.dx));
    expect((settings.center.dy - band.center.dy).abs(), lessThan(4));
  });

  testWidgets('no stray clutter pills on Home', (t) async {
    await pumpHome(t);
    for (final gone in [
      'What I see',
      'Try a change',
      'Hanging out',
      'Use my Apple Health',
      'Upload a document',
      'My data & privacy',
      'Add band',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
  });

  testWidgets('Exercise, Eat and Sleep live in Mochi\'s activity pill chooser; no separate row above the dock', (t) async {
    await pumpHome(t);
    for (final label in ['Exercise', 'Eat', 'Sleep']) {
      expect(find.text(label), findsNothing, reason: '$label is not a row on Home');
    }
    // The pill sits near the twin (above the dock) and opens the four options.
    final pill = find.byKey(const ValueKey('room-activity'));
    expect(pill, findsOneWidget);
    final dock = t.getRect(find.text('Talk'));
    expect(t.getRect(pill).bottom, lessThan(dock.top));
    final twin = t.getRect(find.byKey(const ValueKey('room-twin')));
    expect((t.getRect(pill).center.dx - twin.center.dx).abs(), lessThan(40));
    expect(t.getRect(pill).height, greaterThanOrEqualTo(48));
    await t.tap(pill);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('What should Mochi do?'), findsOneWidget);
    for (final label in ['Walk', 'Exercise', 'Eat', 'Sleep']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the health score is the focus: titled, above Check in, no death date or exact date', (t) async {
    await pumpHome(t);
    expect(find.text('Health score'), findsOneWidget);
    expect(t.getRect(find.text('Health score')).top, lessThan(t.getRect(find.text('Check in')).top));
    // Before the one-time reveal the chip invites; it never names a year.
    expect(find.text('Your estimate'), findsOneWidget);
    final texts = [
      for (final w in t.widgetList<Text>(find.byType(Text)))
        if (w.data != null) w.data!,
    ];
    final dates = RegExp(r'\b(19|20)\d{2}[-/.]\d{1,2}[-/.]\d{1,2}\b|\b\d{1,2}[-/.]\d{1,2}[-/.](19|20)\d{2}\b');
    for (final s in texts) {
      expect(dates.hasMatch(s), isFalse, reason: 'an exact date on Home: $s');
      expect(RegExp(r'\b(die|death|dead|dying|expire)', caseSensitive: false).hasMatch(s), isFalse, reason: s);
      expect(RegExp(r'\b20[3-9]\d\b').hasMatch(s), isFalse, reason: 'a future year before the reveal: $s');
    }
  });
}
