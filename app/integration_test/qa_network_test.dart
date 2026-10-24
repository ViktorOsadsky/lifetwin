// QA: the server goes away, slows down, says "too busy", or sends garbage. Every case
// must end in a plain message and a way on, without losing confirmed answers.
//   python3 integration_test/support/qa_proxy.py 8051 http://127.0.0.1:8050 &
//   flutter test integration_test/qa_network_test.dart -d <sim> --dart-define=API_BASE_URL=http://127.0.0.1:8051
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/room/room_screen.dart';

import 'support/qa_support.dart';

const cantReach = "I can't reach LifeTwin right now.";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(qaReset);

  testWidgets('typed happy path: room, talk, done, forecast, back, room, forecast again', (t) async {
    await startTyped(t);
    await answerAll(t);
    await tapText(t, 'Continue');
    await waitFor(t, find.textContaining('were still living 5 years later'));
    expect(find.textContaining('date'), findsWidgets); // "not a date"
    await tapText(t, 'Back');
    await waitFor(t, find.text('Your room'));
    expect(find.text(RoomScreen.returningGreeting), findsOneWidget);
    await tapText(t, 'See my forecast');
    await waitFor(t, find.textContaining('were still living 5 years later'));
    await tapText(t, 'Back');
    await waitFor(t, find.text('Your room'));
  });

  testWidgets('server down before the first question: Try again starts the talk', (t) async {
    await qaReset();
    await qaMode('down');
    await t.pumpWidget(const LifeTwinApp());
    await tapText(t, 'Talk with Pip');
    await tapText(t, "No, I'll type");
    await readQuestion(t);
    await tapText(t, 'Not now');
    await waitFor(t, find.textContaining(cantReach));
    expect(find.text('Try again'), findsOneWidget);
    // Typing something anyway while it is still down must not strand the conversation.
    if (find.byType(TextField).evaluate().isNotEmpty) {
      await t.enterText(find.byType(TextField), '71');
      await tapText(t, 'Send');
      await waitFor(t, find.textContaining(cantReach));
    }
    await qaMode('pass');
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining('How old are you?'));
    await settled(t);
    expect(ctl(t).notice, isNull);
    await say(t, '71', 'you are 71');
  });

  testWidgets('server down mid-conversation: message, Try again, no lost answers', (t) async {
    await startTyped(t);
    await say(t, '71', 'you are 71');
    await yes(t, 'What sex');
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
    await waitFor(t, find.textContaining('How tall'));
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
    await waitFor(t, find.textContaining('What sex'));
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
      await waitFor(t, find.textContaining('What sex'));
      await settled(t);
      await tapText(t, 'Go back');
      await waitFor(t, find.textContaining('go back to your age'));
      await settled(t);
    }
  });

  testWidgets('forecast: 500, garbage and slow answers recover with Try again', (t) async {
    await startTyped(t);
    await answerAll(t);
    await qaMode('500', path: '/api/predict', times: 1);
    await tapText(t, 'Continue');
    await waitFor(t, find.text("I couldn't get your forecast just now."));
    expect(find.textContaining('Something went wrong on our side'), findsOneWidget);
    await qaMode('html', path: '/api/predict', times: 1);
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining('check the connection'));
    await qaMode('down', path: '/api/predict', times: 1);
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining('check the connection'));
    await qaMode('429', path: '/api/predict', times: 1);
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining('Too many tries'));
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining('were still living 5 years later'));
    await tapText(t, 'Back');
    await waitFor(t, find.text('Your room'));
  });

  testWidgets('unsupported forecast (age 85, sex skipped): plain reason and a way to add the answer', (t) async {
    await startTyped(t);
    await say(t, '85', 'you are 85');
    await yes(t, 'What sex');
    await tapText(t, 'Skip this question');
    await waitFor(t, find.textContaining('How tall'));
    await settled(t);
    for (var i = 0; i < 12 && find.text('Continue').evaluate().isEmpty; i++) {
      await tapText(t, 'Skip this question');
      await pumpFor(t, const Duration(milliseconds: 800));
      await settled(t);
    }
    await tapText(t, 'Continue');
    await waitFor(t, find.textContaining("I can't make a forecast for you yet."));
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
    // Still unsupported for age 85, with its own plain reason.
    await waitFor(t, find.textContaining('above 80'));
  });
}
