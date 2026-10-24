// QA: impatient or shaky double taps (two taps 60 ms apart) on every button. A double
// tap may never send a turn twice, open a screen twice, or answer the next question.
//   flutter test integration_test/qa_taps_test.dart -d <sim> --dart-define=API_BASE_URL=http://127.0.0.1:8051
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/forecast/forecast_screen.dart';
import 'package:lifesim/forecast/fortune_ceremony_screen.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';

import 'support/qa_support.dart';

Future<void> expectActions(List<String> expected) async {
  final got = await qaTurnActions();
  expect(got, expected, reason: 'onboarding turns sent');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(qaReset);

  testWidgets('double tap on "Talk" and the voice consent answers only that question', (t) async {
    await qaReset();
    await t.pumpWidget(const LifeTwinApp());
    await doubleTapText(t, 'Talk');
    await pumpFor(t, const Duration(seconds: 1));
    expect(find.byType(VoiceOnboardingScreen, skipOffstage: false), findsOneWidget, reason: 'one conversation screen');
    await doubleTapText(t, "Yes, I'll talk");
    await pumpFor(t, const Duration(seconds: 1));
    // The second tap lands where "Yes, turn it on" now is; it must not agree to the AI helper.
    expect(find.text('Let an AI helper read hard answers?'), findsOneWidget);
    await expectActions([]);
  });

  testWidgets('double taps while typing: Send, Yes, quick answers, change, skip, go back, Continue', (t) async {
    // Soft checks: every second-tap effect is logged, then the test fails once at the end.
    final problems = <String>[];
    void check(bool ok, String what) {
      if (!ok) {
        problems.add(what);
        debugPrint('QA-DOUBLE-TAP PROBLEM $what');
      }
    }

    /// Back to the conversation if a second tap opened the Health screen.
    Future<void> backToTalk() async {
      if (find.text('Use Apple Health?').evaluate().isNotEmpty) {
        check(false, 'a second tap opened the Health screen');
        await tapText(t, 'Not now');
        await pumpFor(t, const Duration(seconds: 1));
      }
    }

    await qaReset();
    await t.pumpWidget(const LifeTwinApp());
    await tapText(t, 'Talk');
    await doubleTapText(t, "No, I'll type");
    await pumpFor(t, const Duration(seconds: 1));
    check(
      find.text('Let an AI helper read hard answers?').evaluate().isNotEmpty,
      'AI question answered by a double tap',
    );
    await doubleTapText(t, 'Not now');
    await pumpFor(t, const Duration(seconds: 1));
    await backToTalk();
    await waitFor(t, find.textContaining('How old are you?'));
    await settled(t);
    check((await qaTurnActions()).length == 1, 'start sent ${await qaTurnActions()}');

    await t.enterText(find.byType(TextField), '71');
    await doubleTapText(t, 'Send');
    await waitFor(t, find.textContaining('you are 71'));
    await pumpFor(t, const Duration(seconds: 1));
    await settled(t);
    check((await qaTurnActions()).where((a) => a == 'reply').length == 1, 'Send twice: ${await qaTurnActions()}');

    await doubleTapText(t, 'Yes');
    await waitFor(t, find.textContaining('What sex'));
    await pumpFor(t, const Duration(seconds: 1));
    await backToTalk();
    await settled(t);
    check((await qaTurnActions()).where((a) => a == 'confirm').length == 1, 'Yes twice: ${await qaTurnActions()}');
    check(ctl(t).caption != 'female' && ctl(t).caption != 'male', 'Yes double tap answered the sex question');

    if (!ctl(t).confirming) {
      await doubleTapText(t, 'Female');
      await waitFor(t, find.textContaining('female at birth'));
      await pumpFor(t, const Duration(seconds: 1));
      await settled(t);
    }
    check(!ctl(t).correcting && ctl(t).confirming, 'after Female: confirming=${ctl(t).confirming}');

    await doubleTapText(t, 'No, change it');
    await pumpFor(t, const Duration(milliseconds: 500));
    check(find.text('Okay. What is the right answer?').evaluate().isNotEmpty, 'No, change it double tap');
    // The second tap may have landed in the typing box; put the keyboard away first.
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpFor(t, const Duration(milliseconds: 800));
    await tapText(t, 'Never mind');
    await doubleTapText(t, 'Yes');
    await waitFor(t, find.textContaining('How tall'));
    await pumpFor(t, const Duration(seconds: 1));
    await settled(t);

    // Skip: the link stays in the same place for the next question.
    var before = (await qaTurnActions()).where((a) => a == 'skip').length;
    await doubleTapText(t, 'Skip this question');
    await pumpFor(t, const Duration(seconds: 2));
    await settled(t);
    var skips = (await qaTurnActions()).where((a) => a == 'skip').length - before;
    check(skips == 1, 'Skip double tap skipped $skips questions (now on ${ctl(t).state?['current_field']})');

    before = (await qaTurnActions()).where((a) => a == 'reply').length;
    await doubleTapText(t, 'Go back');
    await pumpFor(t, const Duration(seconds: 2));
    await settled(t);
    final backs = (await qaTurnActions()).where((a) => a == 'reply').length - before;
    check(backs == 1, 'Go back double tap went back $backs times (now on ${ctl(t).state?['current_field']})');

    for (var i = 0; i < 14 && find.text('Continue').evaluate().isEmpty; i++) {
      if (ctl(t).confirming) {
        await tapText(t, 'Yes');
      } else {
        await tapText(t, 'Skip this question');
      }
      await pumpFor(t, const Duration(milliseconds: 900));
      await settled(t);
    }
    await doubleTapText(t, 'Continue');
    await pumpFor(t, const Duration(seconds: 2));
    check(
      find.byType(FortuneCeremonyScreen, skipOffstage: false).evaluate().length == 1,
      'Continue opened two ceremonies',
    );
    await doubleTapText(t, 'Ask the ball');
    await pumpFor(t, const Duration(seconds: 4)); // the ball glows for 2.4 s first
    check(find.byType(ForecastScreen, skipOffstage: false).evaluate().length == 1, 'Continue opened two forecasts');
    check(await qaCount('/api/predict') == 1, 'Continue: ${await qaCount('/api/predict')} predictions');

    await doubleTapText(t, 'Back', finder: roundButton('Back'));
    await pumpFor(t, const Duration(seconds: 1));
    check(find.byType(RoomScreen).evaluate().isNotEmpty, 'Back double tap: not on the Room');
    await doubleTapText(t, 'Fortune');
    await waitFor(t, find.byType(FortuneCeremonyScreen), seconds: 20); // the twin walks to the shelf first
    await pumpFor(t, const Duration(seconds: 2));
    check(
      find.byType(FortuneCeremonyScreen, skipOffstage: false).evaluate().length == 1,
      'two ceremonies from the Room',
    );
    await doubleTapText(t, 'Ask the ball');
    await pumpFor(t, const Duration(seconds: 4)); // the ball glows for 2.4 s first
    check(find.byType(ForecastScreen, skipOffstage: false).evaluate().length == 1, 'two forecasts from the Room');
    check(await qaCount('/api/predict') == 2, 'Room forecast: ${await qaCount('/api/predict')} predictions');
    expect(problems, isEmpty);
  });

  testWidgets('double tap on Try again sends the failed turn once', (t) async {
    await startTyped(t);
    await qaMode('down', path: '/api/onboarding/turn', times: 1);
    await t.enterText(find.byType(TextField), '71');
    await tapText(t, 'Send');
    await waitFor(t, find.text('Try again'));
    await settled(t);
    await doubleTapText(t, 'Try again');
    await waitFor(t, find.textContaining('you are 71'));
    await pumpFor(t, const Duration(seconds: 1));
    await expectActions(['start', 'reply', 'reply']);
  });
}
