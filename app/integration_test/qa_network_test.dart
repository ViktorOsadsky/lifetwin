// QA: the server goes away, slows down, says "too busy", or sends garbage. Every case
// must end in a plain message and a way on, without losing confirmed answers.
//   python3 integration_test/support/qa_proxy.py 8051 http://127.0.0.1:8050 &
//   flutter test integration_test/qa_network_test.dart -d <sim> --dart-define=API_BASE_URL=http://127.0.0.1:8051
// The forecast runs on the phone (lib/twin/), so it never touches the server.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/room/room_screen.dart';

import 'support/qa_support.dart';

const cantReach = "I can't reach LifeTwin right now.";

/// A complete intake gives the on-device model every input, so it shows a number
/// ([forecastNumber]). An intake with skipped or unknown answers still reports missing
/// inputs and shows no number.
const missingInputs =
    "I can't make a forecast for you yet. Complete every model input to show annual survival percentages.";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(qaReset);

  testWidgets('typed happy path: room, talk, done, forecast on the phone, back to the room', (t) async {
    await startTyped(t);
    await answerAll(t);
    await tapText(t, 'Continue');
    await askTheBall(t);
    await waitFor(t, find.textContaining(forecastNumber));
    expect(find.textContaining(missingInputs), findsNothing);
    await tapRound(t, 'Back');
    await waitFor(t, find.byType(RoomScreen));
    expect(await qaCount('/api/predict'), 0);
  });

  testWidgets('server down before the first question: Try again starts the talk', (t) async {
    await qaReset();
    await qaMode('down');
    await t.pumpWidget(const LifeTwinApp());
    await tapText(t, 'Talk');
    await tapText(t, "No, I'll type");
    await readQuestion(t);
    await tapText(t, 'Not now');
    await waitFor(t, find.textContaining(cantReach));
    expect(find.text('Try again'), findsOneWidget);
    // Typing something anyway while it is still down must not strand the conversation.
    if (find.byType(TextField).evaluate().isNotEmpty) {
      await t.enterText(find.byType(TextField), 'No thanks');
      await tapText(t, 'Send');
      await waitFor(t, find.textContaining(cantReach));
    }
    await qaMode('pass');
    await tapText(t, 'Try again');
    // The first thing Mochi asks is whether it may remember the little things.
    await waitFor(t, find.textContaining(memoryQuestion));
    await settled(t);
    expect(ctl(t).notice, isNull);
    await say(t, 'No thanks', ageQuestion);
    await say(t, '71', 'you are 71');
  });

  testWidgets('server down mid-conversation: message, Try again, no lost answers', (t) async {
    await startTyped(t);
    await say(t, '71', 'you are 71');
    await yes(t, sexQuestion);
    await qaMode('down');
    await t.enterText(find.byType(TextField), 'female');
    await tapText(t, 'Send');
    await waitFor(t, find.textContaining(cantReach));
    await settled(t);
    expect(ctl(t).confirmedProfile['age'], 71);
    // Still down: Try again fails the same plain way.
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining(cantReach));
    await settled(t);
    await qaMode('pass');
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining('female at birth'));
    await settled(t);
    // Yes while down, then again once it is back.
    await qaMode('down');
    await tapText(t, 'Yes');
    await waitFor(t, find.textContaining(cantReach));
    await settled(t);
    expect(ctl(t).confirming, isTrue, reason: 'the read-back must still be waiting for Yes');
    await qaMode('pass');
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining(smokingQuestion));
    await settled(t);
    expect(ctl(t).confirmedProfile['age'], 71);
    expect(ctl(t).confirmedProfile['sex'], 'female');
  });

  testWidgets('slow server: 15 s answers, 23 s times out and Try again recovers', (t) async {
    await startTyped(t);
    await qaMode('slow', path: '/api/onboarding/turn', times: 1, delay: 15);
    await t.enterText(find.byType(TextField), '71');
    await tapText(t, 'Send');
    await pumpFor(t, const Duration(seconds: 2));
    expect(ctl(t).phase, VoicePhase.interpreting);
    expect(find.text('One moment…'), findsWidgets);
    // The screen is not frozen: Settings opens and closes while waiting.
    await tapText(t, 'Settings');
    await waitFor(t, find.text('AI helper'));
    await tapText(t, 'Done');
    await waitFor(t, find.textContaining('you are 71'), seconds: 25);
    await settled(t);
    expect(ctl(t).notice, isNull);

    await qaMode('slow', path: '/api/onboarding/turn', times: 1, delay: 23);
    await tapText(t, 'Yes');
    await waitFor(t, find.text('Try again'), seconds: 40);
    await settled(t);
    expect(ctl(t).notice, isNotNull);
    expect(ctl(t).confirming, isTrue);
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining(sexQuestion));
  });

  testWidgets('rate limit (429): the wait message, then Try again works', (t) async {
    await startTyped(t);
    await qaMode('429', path: '/api/onboarding/turn', times: 1);
    await t.enterText(find.byType(TextField), '71');
    await tapText(t, 'Send');
    await waitFor(t, find.textContaining('Too many tries'));
    await settled(t);
    expect(find.text('Try again'), findsOneWidget);
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining('you are 71'));
  });

  testWidgets('garbage (HTML) answers: plain message with Try again, both 200 and 403', (t) async {
    await startTyped(t);
    for (final mode in ['html', 'html403']) {
      await qaMode(mode, path: '/api/onboarding/turn', times: 1);
      await t.enterText(find.byType(TextField), '71');
      await tapText(t, 'Send');
      await waitFor(t, find.text('Try again'));
      await settled(t);
      expect(find.textContaining('Welcome to Hotel'), findsNothing);
      await tapText(t, 'Try again');
      await waitFor(t, find.textContaining('you are 71'));
      await settled(t);
      await tapText(t, 'No, change it');
      await tapText(t, 'Never mind');
      await tapText(t, 'Yes');
      await waitFor(t, find.textContaining(sexQuestion));
      await settled(t);
      await tapText(t, 'Go back');
      await waitFor(t, find.textContaining('go back to your age'));
      await settled(t);
    }
  });

  testWidgets('forecast: the server down, slow or broken changes nothing, it runs on the phone', (t) async {
    await startTyped(t);
    await answerAll(t);
    await qaMode('down');
    await tapText(t, 'Continue');
    await askTheBall(t);
    await waitFor(t, find.textContaining(forecastNumber));
    expect(find.text("I couldn't get your forecast just now."), findsNothing);
    expect(find.text('Try again'), findsNothing);
    await qaMode('pass');
    await tapRound(t, 'Back');
    await waitFor(t, find.byType(RoomScreen));
    expect(await qaCount('/api/predict'), 0);
  });

  testWidgets('no forecast (age 85, sex skipped): the status message, what is needed, and a way to add it', (t) async {
    await startTyped(t);
    await say(t, '85', 'you are 85');
    await yes(t, sexQuestion);
    await tapText(t, 'Skip this question');
    await waitFor(t, find.textContaining(smokingQuestion));
    await settled(t);
    await tapText(t, 'Skip this question');
    await declineHealth(t);
    for (var i = 0; i < 12 && find.text('Continue').evaluate().isEmpty; i++) {
      await tapText(t, 'Skip this question');
      await pumpFor(t, const Duration(milliseconds: 800));
      await settled(t);
    }
    await tapText(t, 'Continue');
    await askTheBall(t);
    await waitFor(t, find.textContaining(missingInputs));
    expect(find.textContaining('sex at birth'), findsOneWidget);
    expect(find.textContaining('still living'), findsNothing);
    // The way back must lead somewhere the missing answer can be added.
    await tapText(t, 'Go back to my answers');
    await waitFor(t, find.text('Go back'));
    await tapText(t, 'Go back');
    await waitFor(t, find.textContaining("let's go back to your"));
    await settled(t);
    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), 'change my sex');
    await tapText(t, 'Send');
    await waitFor(t, find.textContaining('go back to your sex'));
    await settled(t);
    await tapText(t, 'Female');
    await waitFor(t, find.textContaining('female at birth'));
    await yes(t, 'Continue');
    await tapText(t, 'Continue');
    await askTheBall(t);
    // Still no number: the other inputs are skipped (and 85 is outside 35–79).
    await waitFor(t, find.textContaining(missingInputs));
    expect(find.textContaining('sex at birth'), findsNothing);
    expect(find.textContaining('still living'), findsNothing);
  });
}
