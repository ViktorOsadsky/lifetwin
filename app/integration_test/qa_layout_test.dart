// QA: every screen at the simulator's current text size and appearance. Set them first:
//   xcrun simctl ui <sim> content_size accessibility-extra-extra-extra-large   (about 3x)
//   xcrun simctl ui <sim> appearance dark
// Any overflow or an unnamed control fails the test; tap targets under 44 pt are logged
// (a control partly scrolled out of view counts by its visible part). The shell watcher
// saves a screenshot of each screen (QA_LABEL-name).
//   flutter test integration_test/qa_layout_test.dart -d <sim> \
//     --dart-define=API_BASE_URL=http://127.0.0.1:8051 --dart-define=QA_LABEL=ax3
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/main.dart';

import 'support/qa_support.dart';

const label = String.fromEnvironment('QA_LABEL', defaultValue: 'default');

/// One screen: every control named, tap targets logged, a screenshot saved.
Future<void> lookAt(WidgetTester t, List<String> problems, String name) async {
  await pumpFor(t, const Duration(milliseconds: 700));
  final labels = await labeledTapTargetGuideline.evaluate(t);
  if (!labels.passed) problems.add('$name label: ${labels.reason}');
  // Advisory only: a control partly scrolled out of view (a link at the top edge of a
  // scrolled story) is measured by its visible sliver. Check these in the screenshots.
  final size = await iOSTapTargetGuideline.evaluate(t);
  if (!size.passed) debugPrint('QA-LAYOUT ADVISORY $name tap target: ${size.reason}');
  await qaAction(t, 'shot', name: '$label-$name', wait: const Duration(milliseconds: 900));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the forecast without a number fits too ($label)', (t) async {
    final semantics = t.ensureSemantics();
    final problems = <String>[];
    Future<void> look(String name) => lookAt(t, problems, name);
    await startTyped(t);
    await say(t, '71', 'you are 71');
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
    await hideKeyboard(t);
    await tapText(t, 'Continue');
    await askTheBall(t);
    // Skipped answers: the on-device model reports missing inputs and shows no number.
    await waitFor(t, find.textContaining('Complete every model input to show annual survival percentages.'));
    expect(find.textContaining('still living'), findsNothing);
    await pumpFor(t, const Duration(seconds: 2));
    await look('13d-no-number');
    for (final p in problems) {
      debugPrint('QA-LAYOUT PROBLEM $p');
    }
    semantics.dispose();
    expect(problems, isEmpty);
  });

  testWidgets('every screen fits, is reachable and labeled ($label)', (t) async {
    final semantics = t.ensureSemantics();
    final problems = <String>[];
    Future<void> look(String name) => lookAt(t, problems, name);

    await qaReset();
    debugPrint(
      'QA-LAYOUT scale=${t.platformDispatcher.textScaleFactor} '
      'brightness=${t.platformDispatcher.platformBrightness}',
    );
    await t.pumpWidget(const LifeTwinApp());
    await waitFor(t, find.text('Talk'));
    await look('01-room');
    // The bear wanders: Exercise sends it across the room to the mat. A few frames, 1.2 s apart.
    await tapText(t, 'Exercise');
    for (var i = 1; i <= 4; i++) {
      await qaAction(t, 'shot', name: '$label-01w-wander-$i', wait: const Duration(milliseconds: 1200));
    }
    await waitFor(t, find.text('Feeling strong'), seconds: 30);
    // To bed and from the bed to the table: the bear walks around the bed, never through it.
    await pumpFor(t, const Duration(seconds: 1));
    await tapText(t, 'Sleep');
    for (var i = 1; i <= 5; i++) {
      await qaAction(t, 'shot', name: '$label-01x-to-bed-$i', wait: const Duration(milliseconds: 1000));
    }
    await waitFor(t, find.text('Sleeping. Tap to wake'), seconds: 30);
    await tapText(t, 'Eat');
    for (var i = 1; i <= 6; i++) {
      await qaAction(t, 'shot', name: '$label-01y-bed-to-table-$i', wait: const Duration(milliseconds: 900));
    }
    await pumpFor(t, const Duration(seconds: 8));
    await tapText(t, 'Customize');
    await waitFor(t, find.text('Save look'));
    await look('01b-customize');
    await tapRound(t, 'Back to room');
    await waitFor(t, find.text('Talk'));
    await pumpFor(t, const Duration(milliseconds: 800)); // Customize slides away
    await tapText(t, 'Talk');
    await waitFor(t, find.text("No, I'll type"));
    await look('03-consent');
    await tapText(t, "No, I'll type");
    await readQuestion(t);
    await look('04-ai-consent');
    await tapText(t, 'Not now');
    // The memory question comes first, then age.
    await waitFor(t, find.textContaining(memoryQuestion));
    await settled(t);
    await hideKeyboard(t);
    await look('04b-memory-question');
    await say(t, 'No thanks', ageQuestion);
    await hideKeyboard(t);
    await look('05-question');
    await typeAndSend(t, '71');
    await waitFor(t, find.textContaining('you are 71'));
    await settled(t);
    await look('06-read-back');
    await tapText(t, 'No, change it');
    await hideKeyboard(t);
    await look('07-correcting');
    await tapText(t, 'Never mind');
    await yes(t, sexQuestion);
    await hideKeyboard(t);
    await look('08-quick-answers');
    await qaMode('down', path: '/api/onboarding/turn', times: 1);
    await tapText(t, 'Female');
    await waitFor(t, find.text('Try again'));
    await settled(t);
    await look('09-notice');
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining('female at birth'));
    await settled(t);
    await yes(t, smokingQuestion);
    await hideKeyboard(t);
    await tapText(t, 'Settings');
    await waitFor(t, find.text('AI helper'));
    await look('10-settings');
    await tapText(t, 'Done');
    await pumpFor(t, const Duration(milliseconds: 600));
    // Smoking, then the Apple Health offer (it fits too), then the rest.
    await answerAll(t, fullIntake.sublist(2, 3));
    await settled(t);
    await hideKeyboard(t);
    await look('10b-health-offer');
    await answerAll(t, fullIntake.sublist(3));
    await hideKeyboard(t);
    await look('11-done');
    await tapText(t, 'Use my Apple Health');
    await waitFor(t, find.text('Yes, use Apple Health'));
    await look('12-health-intro');
    await tapText(t, "No thanks, I'll answer myself");
    await waitFor(t, find.text('Continue'));
    await pumpFor(t, const Duration(seconds: 1));
    await tapText(t, 'Continue');
    await waitFor(t, find.text('Ask the ball'));
    await look('12b-ceremony');
    await askTheBall(t);
    await waitFor(t, find.textContaining(forecastNumber));
    await pumpFor(t, const Duration(seconds: 2));
    await look('13-forecast');
    await tapText(t, 'See what shaped it');
    await waitFor(t, roundButton('Back to your look ahead'));
    await look('13b-outlook');
    await t.scrollUntilVisible(find.text('Limits'), 300, scrollable: find.byType(Scrollable).first);
    await look('13c-outlook-end');
    t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0); // back to the top
    await pumpFor(t, const Duration(milliseconds: 600));
    await tapRound(t, 'Back to your look ahead');
    await waitFor(t, find.text('See what shaped it'));
    await t.scrollUntilVisible(find.text('Go back to my answers'), 300, scrollable: find.byType(Scrollable).first);
    await look('14-forecast-end');

    // Landscape (the app allows it on iPhone): the same screens must still fit.
    final portrait = t.view.physicalSize;
    t.view.physicalSize = Size(portrait.height, portrait.width);
    await pumpFor(t, const Duration(seconds: 1));
    await look('15-landscape-forecast');
    await tapText(t, 'Go back to my answers');
    await pumpFor(t, const Duration(seconds: 1));
    await look('16-landscape-done');
    await tapText(t, 'Go back');
    await waitFor(t, find.textContaining("let's go back to your"));
    await settled(t);
    await hideKeyboard(t);
    await look('17-landscape-question');
    t.view.resetPhysicalSize();
    await pumpFor(t, const Duration(seconds: 1));

    for (final p in problems) {
      debugPrint('QA-LAYOUT PROBLEM $p');
    }
    semantics.dispose();
    expect(problems, isEmpty);
  });
}
