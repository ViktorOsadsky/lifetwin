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

/// Puts the keyboard away: with it up, the progress line is hidden to make room.
Future<void> hideKeyboard(WidgetTester t) async {
  FocusManager.instance.primaryFocus?.unfocus();
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester t, String label) async {
  final f = find.text(label);
  await waitFor(t, f);
  // These links ignore taps for 0.7 s after a new question, so a double tap can't act twice.
  if (const {'Skip this question', 'Go back', 'Use my Apple Health', 'Never mind'}.contains(label)) {
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first);
  // The Room's Talk swooshes the conversation in (720 ms); its buttons move until then.
  if (const {'Talk', 'Go back to my answers'}.contains(label)) {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }
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
  throw TestFailure('Timed out waiting for $finder. Screen: ${screenText()}');
}

String screenText() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText())
    .whereType<String>()
    .where((s) => s.isNotEmpty)
    .join(' | ');

/// Types an answer, sends it, and waits for LifeTwin's reply to contain [expect].
Future<void> say(WidgetTester t, String answer, Pattern expect) async {
  // The previous Yes may have hit the rate limit; waitForReply taps "Try again".
  await waitForReply(t, find.byType(TextField));
  await t.enterText(find.byType(TextField), answer);
  await tapText(t, 'Send');
  await waitForReply(t, find.textContaining(expect));
}

/// Mochi's wording varies by a per-session seed, so a question is found by the words
/// every wording shares, in any case.
RegExp words(String pattern) => RegExp(pattern, caseSensitive: false, dotAll: true);

final ageQuestion = words('how old are you');
final sexQuestion = words('female or male');
final smokingQuestion = words('do you smoke now');
final heightQuestion = words('how tall');
final weightQuestion = words('how much do you weigh');
final sleepQuestion = words('hours do you sleep');
final healthQuestion = words('excellent, very good, good, fair or poor');
final bloodPressureQuestion = words('told you that you have high blood pressure|said you have high blood pressure');
final diabetesQuestion = words('ever told you that you have diabetes');
final sittingQuestion = words('how many hours.*sit');
final lighterQuestion = words('lighter activity.*like brisk');
final harderQuestion = words('harder exercise');

/// Conversation v2 opens with the memory question, then age, sex and smoking, then offers
/// Apple Health, then asks only what is still missing.
const memoryQuestion = 'Can I remember the little things you tell me';
const healthOffer = 'Shall I fill in your height, weight, sleep and activity from Apple Health?';
final healthDeclined = words("i'll just ask you|we'll do it together");

/// A habit follow-up (up to three, only when the person let Mochi remember) ends like this.
const followUpTail = 'Or we can move on.';

/// A forecast with a number, shown once every model input is known.
final forecastNumber = RegExp(r'Out of 100 people with answers like yours, about \d+ were still living \d+ years? later\.');
const noNumber = 'Complete every model input to show annual survival percentages.';

/// Taps Yes on a read-back and waits for [next]. A habit follow-up may come first when
/// Mochi may remember: it is answered with "let's move on", as a person in a hurry would.
Future<int> yesThen(WidgetTester t, Pattern next) async {
  await tapText(t, 'Yes');
  var followUps = 0;
  final nextFinder = find.textContaining(next);
  final followUp = find.textContaining(followUpTail);
  final deadline = DateTime.now().add(const Duration(seconds: 150));
  while (DateTime.now().isBefore(deadline)) {
    await t.pump(const Duration(milliseconds: 100));
    if (nextFinder.evaluate().isNotEmpty) return followUps;
    if (followUp.evaluate().isNotEmpty) {
      followUps++;
      await say(t, "let's move on", next);
      return followUps;
    }
    // Rate limited? Tap Try again as a person would.
    final retry = find.text('Try again');
    if (retry.evaluate().isNotEmpty) {
      await Future<void>.delayed(const Duration(seconds: 12));
      await t.tap(retry.first);
    }
  }
  throw TestFailure('Timed out waiting for $next');
}

/// Opens the app, chooses typing, and waits for the memory question (the first thing
/// Mochi asks), answers it by typing, and waits for the age question.
Future<void> startTyped(WidgetTester t, {bool aiHelper = false, String memory = 'No thanks'}) async {
  await t.pumpWidget(const LifeTwinApp());
  await tapText(t, 'Talk');
  await tapText(t, "No, I'll type");
  // The AI question ignores taps for a moment, so a double tap can't answer it.
  await Future<void>.delayed(const Duration(milliseconds: 800));
  await tapText(t, aiHelper ? 'Yes, turn it on' : 'Not now');
  await waitFor(t, find.textContaining(memoryQuestion));
  expect(find.textContaining(ageQuestion), findsNothing, reason: 'the memory question comes before age');
  await say(t, memory, ageQuestion);
}

/// Declines the Apple Health offer (it comes right after smoking) and waits for height.
Future<void> declineHealth(WidgetTester t) async {
  await waitForReply(t, find.textContaining(healthOffer));
  await say(t, 'No thanks', healthDeclined);
  await waitForReply(t, find.textContaining(heightQuestion));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the memory question comes first, and its answer decides about habit follow-ups', (t) async {
    await t.pumpWidget(const LifeTwinApp());
    await tapText(t, 'Talk');
    await tapText(t, "No, I'll type");
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await tapText(t, 'Not now');
    await waitFor(t, find.textContaining(memoryQuestion));
    expect(find.textContaining(ageQuestion), findsNothing);
    await say(t, 'Sure', ageQuestion);
    expect(find.textContaining(memoryQuestion), findsNothing);
  });

  testWidgets('one reply can answer age, sex and smoking, with one read-back; Apple Health is offered next', (t) async {
    await startTyped(t);
    await say(t, "I'm 72, female, and I've never smoked", 'you have never smoked');
    expect(find.textContaining('you are 72'), findsOneWidget);
    expect(find.textContaining('female at birth'), findsOneWidget);
    await tapText(t, 'Yes');
    // Age, sex and smoking are all in: Apple Health is next, not height.
    await waitForReply(t, find.textContaining(healthOffer));
    expect(find.textContaining(heightQuestion), findsNothing);
    expect(find.textContaining(sexQuestion), findsNothing);
    await say(t, 'No thanks', healthDeclined);
    await waitForReply(t, find.textContaining(heightQuestion));
  });

  testWidgets('"No, change it" after a wrong age lets the person correct it', (t) async {
    await startTyped(t);
    await say(t, '45', 'you are 45');
    await tapText(t, 'No, change it');
    await waitFor(t, find.textContaining('What is the right answer'));
    await say(t, "no, I'm 71", 'you are 71');
    await tapText(t, 'Yes');
    await waitForReply(t, find.textContaining(sexQuestion));
  });

  testWidgets('the Skip button moves past a question, and Go back reopens it', (t) async {
    await startTyped(t);
    await hideKeyboard(t);
    expect(find.text('Question 1 of 11'), findsOneWidget);
    expect(find.text('Go back'), findsNothing);
    await tapText(t, 'Skip this question');
    await waitForReply(t, find.textContaining(sexQuestion));
    await hideKeyboard(t);
    expect(find.text('Question 2 of 11'), findsOneWidget);
    await tapText(t, 'Go back');
    await waitForReply(t, find.textContaining('go back to your age'));
    await hideKeyboard(t);
    expect(find.text('Question 1 of 11'), findsOneWidget);
  });

  testWidgets('"skip" typed moves past a question', (t) async {
    await startTyped(t);
    await waitFor(t, find.byType(TextField));
    await t.enterText(find.byType(TextField), 'skip');
    await tapText(t, 'Send');
    await waitForReply(t, find.textContaining(sexQuestion));
    expect(find.textContaining(ageQuestion), findsNothing);
  });

  testWidgets('"Skip" typed after a confirmed answer also works', (t) async {
    await startTyped(t);
    await say(t, '71', 'you are 71');
    await tapText(t, 'Yes');
    await say(t, 'skip', smokingQuestion);
  });

  testWidgets('a birth year is worked out and checked, and can be corrected', (t) async {
    await startTyped(t);
    await say(t, 'born in 1980', 'makes you 46');
    await tapText(t, 'No, change it');
    await say(t, '45', 'you are 45');
    await tapText(t, 'Yes');
  });

  testWidgets('a hard answer offers the AI helper, and the consent button is shown', (t) async {
    await startTyped(t);
    await say(t, 'somewhere around the middle of my fifties, ish', 'AI helper');
    expect(find.text('Yes, let the AI helper read it'), findsOneWidget);
    await tapText(t, 'Yes, let the AI helper read it');
    // The same answer is sent again; the offer goes away, whatever the helper makes of it.
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (find.text('Yes, let the AI helper read it').evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) throw TestFailure('offer never went away');
      await t.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets('the whole intake ends on Continue after Yes answers only', (t) async {
    await startTyped(t);
    // Age, sex and smoking, Apple Health declined, then height and weight.
    const first = [('71', 'you are 71'), ('male', 'male at birth'), ('never', 'never smoked')];
    for (final (answer, expect) in first) {
      await say(t, answer, expect);
      await tapText(t, 'Yes');
    }
    await declineHealth(t);
    const steps = [('6 foot', '6 feet'), ('180', '180 pounds')];
    for (final (answer, expect) in steps) {
      await say(t, answer, expect);
      await tapText(t, 'Yes');
    }
    // Skip everything left until the conversation is finished.
    for (var i = 0; i < 20 && find.text('Continue').evaluate().isEmpty; i++) {
      await tapText(t, 'Skip this question');
      await t.pump(const Duration(milliseconds: 1500));
    }
    await waitFor(t, find.text('Continue'));
  });

  testWidgets('the sex, smoking and diabetes buttons answer without typing', (t) async {
    await startTyped(t);
    await say(t, '71', 'you are 71');
    await tapText(t, 'Yes');
    await waitForReply(t, find.text('Female'));
    await tapText(t, 'Female');
    await waitForReply(t, find.textContaining('female at birth'));
    await tapText(t, 'Yes');
    await waitForReply(t, find.text('I used to smoke'));
    await tapText(t, 'I used to smoke');
    await waitForReply(t, find.textContaining('smoked in the past'));
    await tapText(t, 'Yes');
    await declineHealth(t);
    // Skip height, weight, sleep, general health and high blood pressure to reach diabetes.
    for (final next in [weightQuestion, sleepQuestion, healthQuestion, bloodPressureQuestion, diabetesQuestion]) {
      await waitFor(t, find.byType(TextField));
      // Tap into the box (keyboard up), type, and tap Send once: nothing may be swallowed.
      await t.tap(find.byType(TextField));
      await t.pump(const Duration(milliseconds: 600));
      await t.enterText(find.byType(TextField), 'skip');
      await t.pump(const Duration(milliseconds: 300));
      expect(t.widget<TextField>(find.byType(TextField)).controller?.text, 'skip');
      await tapText(t, 'Send');
      await t.pump(const Duration(milliseconds: 300));
      expect(t.widget<TextField>(find.byType(TextField)).controller?.text, isEmpty, reason: 'Send was swallowed');
      await waitForReply(t, find.textContaining(next));
      await t.pump(const Duration(milliseconds: 1500));
    }
    await waitForReply(t, find.text('Not sure'));
    await tapText(t, 'No');
    await waitForReply(t, find.textContaining('not told you that you have diabetes'));
    await tapText(t, 'Yes');
    await waitForReply(t, find.textContaining(sittingQuestion));
  });

  testWidgets('a whole typed intake with indirect answers ends on a forecast with a number', (t) async {
    final started = DateTime.now();
    await startTyped(t, memory: 'Sure');
    debugPrint('first question after ${DateTime.now().difference(started).inMilliseconds} ms');

    var followUps = 0;
    // (what the person says, what Mochi reads back, the question that comes next)
    final steps = <(String, Pattern, Pattern)>[
      ('I was born in 1980', 'makes you 46', sexQuestion),
      ('female', 'female at birth', smokingQuestion),
      ('quit when my daughter was born', 'smoked in the past', healthOffer),
    ];
    for (final (answer, expect, next) in steps) {
      await say(t, answer, expect);
      followUps += await yesThen(t, next);
      debugPrint('ok: "$answer" -> $expect');
    }
    await declineHealth(t);
    final rest = <(String, Pattern, Pattern)>[
      ("yea that's right", '5 feet 10 inches', weightQuestion),
      ('a buck sixty', '160 pounds', sleepQuestion),
      ('bed at 10 up at 6', '8 hours a night', healthQuestion),
      ('good', 'your health is good', bloodPressureQuestion),
      ('nope', 'not told you that you have high blood pressure', diabetesQuestion),
      ('nope', 'not told you that you have diabetes', sittingQuestion),
      ('about six hours', 'sit about 6 hours', lighterQuestion),
      ('i walk the dog twice a day for 20 minutes', '280 minutes of lighter activity', harderQuestion),
      ('none', 'no harder exercise', 'All done'),
    ];
    for (final (answer, expect, next) in rest) {
      await say(t, answer, expect);
      followUps += await yesThen(t, next);
      debugPrint('ok: "$answer" -> $expect');
    }
    // Mochi may remember, so a few optional follow-ups came up (at most three), skippable.
    expect(followUps, inInclusiveRange(1, 3), reason: 'sitting 6 hours or the dog walk should lead to a follow-up');
    await waitFor(t, find.text('Continue'));
    // Every model input is known now, so the forecast runs on the phone and shows a number.
    await tapText(t, 'Continue');
    await waitFor(t, find.text('Ask the ball'));
    await Future<void>.delayed(const Duration(milliseconds: 900)); // it ignores taps while sliding in
    await tapText(t, 'Ask the ball');
    await waitFor(t, find.textContaining(forecastNumber));
    expect(find.textContaining(noNumber), findsNothing);
  });

  testWidgets('"I don\'t know" and skipped answers still give the no-number message', (t) async {
    await startTyped(t);
    const first = [('71', 'you are 71'), ('female', 'female at birth'), ('never', 'never smoked')];
    for (final (answer, expect) in first) {
      await say(t, answer, expect);
      await tapText(t, 'Yes');
    }
    await declineHealth(t);
    // The first "I don't know" is recorded as unknown, and Mochi says what that means.
    await say(t, "I don't know", "Your twin will say it's still learning");
    await say(t, "I don't know", sleepQuestion); // weight is left out too, and never asked again
    for (var i = 0; i < 20 && find.text('Continue').evaluate().isEmpty; i++) {
      await tapText(t, 'Skip this question');
      await t.pump(const Duration(milliseconds: 1500));
    }
    await waitFor(t, find.text('Continue'));
    await tapText(t, 'Continue');
    await waitFor(t, find.text('Ask the ball'));
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await tapText(t, 'Ask the ball');
    await waitFor(t, find.textContaining(noNumber));
    expect(find.textContaining('still living'), findsNothing);
  });
}
