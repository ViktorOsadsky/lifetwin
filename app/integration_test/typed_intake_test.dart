// Runs on the iPhone against the real server, typing instead of talking:
//   flutter test integration_test/typed_intake_test.dart -d <device> \
//     --dart-define-from-file=<file with API_BASE_URL>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/main.dart';

/// Pumps frames until [finder] shows up. The mascot animates forever, so
/// pumpAndSettle would never return.
Future<void> waitFor(WidgetTester t, Finder finder, {int seconds = 20}) async {
  for (var i = 0; i < seconds * 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

Future<void> tapText(WidgetTester t, String label) async {
  final f = find.text(label);
  await waitFor(t, f);
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first);
}

/// Like [waitFor], but if the server says "too many tries" (60 requests a
/// minute per address, shared with every other client) it waits and taps
/// "Try again", as a person would.
Future<void> waitForReply(WidgetTester t, Finder finder, {int seconds = 150}) async {
  final retry = find.text('Try again');
  var lastRetry = DateTime.now();
  for (var i = 0; i < seconds * 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
    if (retry.evaluate().isNotEmpty && DateTime.now().difference(lastRetry).inSeconds >= 12) {
      lastRetry = DateTime.now();
      await t.ensureVisible(retry.first);
      await t.tap(retry.first);
    }
  }
  throw TestFailure('Timed out waiting for $finder');
}

/// Types an answer, sends it, and waits for LifeTwin's reply to contain [expect].
Future<void> say(WidgetTester t, String answer, String expect) async {
  await waitFor(t, find.byType(TextField));
  await t.enterText(find.byType(TextField), answer);
  await tapText(t, 'Send');
  await waitForReply(t, find.textContaining(expect));
}

/// Opens the app, chooses typing, and waits for the first question.
Future<void> startTyped(WidgetTester t, {bool aiHelper = false}) async {
  await t.pumpWidget(const LifeTwinApp());
  await tapText(t, 'Type instead');
  await tapText(t, aiHelper ? 'Yes, turn it on' : 'Not now');
  await waitFor(t, find.textContaining('How old are you?'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('"Change" after a wrong age lets the person correct it', (t) async {
    await startTyped(t);
    await say(t, '45', 'Age: 45');
    await tapText(t, 'Change');
    await waitFor(t, find.text('Okay. What is the right answer?'));
    await say(t, "no, I'm 71", 'Age: 71');
    await tapText(t, 'Yes');
    await waitForReply(t, find.textContaining('What sex were you'));
  });

  testWidgets('"skip" moves past a question', (t) async {
    await startTyped(t);
    await waitFor(t, find.byType(TextField));
    await t.enterText(find.byType(TextField), 'skip');
    await tapText(t, 'Send');
    await waitForReply(t, find.textContaining('What sex were you'));
    expect(find.textContaining('How old are you?'), findsNothing);
  });

  testWidgets('"Skip" typed after a confirmed answer also works', (t) async {
    await startTyped(t);
    await say(t, '71', 'Age: 71');
    await tapText(t, 'Yes');
    await say(t, 'skip', 'How tall');
  });

  testWidgets('a birth year is worked out and checked, and can be corrected', (t) async {
    await startTyped(t);
    await say(t, 'born in 1980', 'makes you 46');
    await say(t, '45', 'Age: 45');
    await tapText(t, 'Yes');
  });

  testWidgets('a hard answer offers the AI helper, and the consent button is shown', (t) async {
    await startTyped(t);
    await say(t, 'somewhere around the middle of my fifties, ish', 'AI helper');
    expect(find.text('Yes, let the AI helper read it'), findsOneWidget);
    await tapText(t, 'Yes, let the AI helper read it');
    // The same answer is sent again; the offer goes away, whatever the helper makes of it.
    await waitFor(t, find.text('Turn off AI helper'));
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (find.text('Yes, let the AI helper read it').evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) throw TestFailure('offer never went away');
      await t.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets('the whole intake ends on Continue after Yes answers only', (t) async {
    await startTyped(t);
    const steps = [('71', 'Age: 71'), ('male', 'male at birth'), ('6 foot', '6 feet'), ('180', '180 pounds')];
    for (final (answer, expect) in steps) {
      await say(t, answer, expect);
      await tapText(t, 'Yes');
    }
    // Skip everything left until the conversation is finished.
    for (var i = 0; i < 20 && find.text('Continue').evaluate().isEmpty; i++) {
      await waitFor(t, find.byType(TextField));
      await t.enterText(find.byType(TextField), 'skip');
      await tapText(t, 'Send');
      await t.pump(const Duration(milliseconds: 1500));
    }
    await waitFor(t, find.text('Continue'));
  });

  testWidgets('the sex and smoking buttons answer without typing', (t) async {
    await startTyped(t);
    await say(t, '71', 'Age: 71');
    await tapText(t, 'Yes');
    await waitForReply(t, find.text('Female'));
    await tapText(t, 'Female');
    await waitForReply(t, find.textContaining('female at birth'));
    await tapText(t, 'Yes');
    // Skip height, weight, sleep and exercise to reach the smoking question.
    await waitForReply(t, find.textContaining('How tall'));
    for (final next in ['How much do you weigh', 'How many hours', 'How many minutes', 'Do you smoke now']) {
      await waitFor(t, find.byType(TextField));
      // The keyboard can swallow the text or a tap; try again until a tap sends it.
      for (var i = 0; i < 5; i++) {
        await t.tap(find.byType(TextField));
        await t.pump(const Duration(milliseconds: 300));
        await t.enterText(find.byType(TextField), 'skip');
        await t.pump(const Duration(milliseconds: 600));
        if (t.widget<TextField>(find.byType(TextField)).controller?.text != 'skip') continue;
        await tapText(t, 'Send');
        await t.pump(const Duration(milliseconds: 300));
        if (t.widget<TextField>(find.byType(TextField)).controller?.text.isEmpty ?? true) break;
      }
      await waitForReply(t, find.textContaining(next));
      await t.pump(const Duration(milliseconds: 1500));
    }
    await waitForReply(t, find.text('I used to smoke'));
    await tapText(t, 'I used to smoke');
    await waitForReply(t, find.textContaining('smoked in the past'));
    await tapText(t, 'Yes');
  });

  testWidgets('a whole typed intake with indirect answers', (t) async {
    final started = DateTime.now();
    await t.pumpWidget(const LifeTwinApp());
    await tapText(t, 'Type instead');
    await tapText(t, 'Not now');
    await waitFor(t, find.textContaining('How old are you?'));
    debugPrint('first question after ${DateTime.now().difference(started).inMilliseconds} ms');

    const steps = [
      ('I was born in 1980', 'makes you 46'),
      ('female', 'female at birth'),
      ("yea that's right", '5 feet 10 inches'),
      ('a buck sixty', '160 pounds'),
      ('bed at 10 up at 6', '8 hours a night'),
      ('i walk the dog twice a day for 20 minutes', '280 minutes a week'),
      ('quit when my daughter was born', 'smoked in the past'),
      ('a bottle of wine a week', '5 drinks a week'),
      ('nope', 'Diabetes: no'),
      ('130 slash 85', '130 over 85'),
    ];
    for (final (answer, expect) in steps) {
      await say(t, answer, expect);
      await tapText(t, 'Yes');
      debugPrint('ok: "$answer" -> $expect');
    }
    await waitFor(t, find.text('Continue'));
  });
}
