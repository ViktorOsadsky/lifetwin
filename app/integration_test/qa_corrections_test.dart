// QA: changing answers. "No, change it", "go back", "change my age to 71", "start over"
// against "yes, start over", skipping every question (blood pressure included), and the
// AI-helper offer, consent and Settings switch. A wrong value may never be saved.
//   flutter test integration_test/qa_corrections_test.dart -d <sim> --dart-define=API_BASE_URL=http://127.0.0.1:8051
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';

import 'support/qa_support.dart';

Future<void> typeSend(WidgetTester t, String text) async {
  await typeAndSend(t, text);
  await settled(t);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(qaReset);

  testWidgets('"No, change it", "go back" in a correction and "change my age to 71" never save a wrong age', (t) async {
    await startTyped(t);
    await say(t, '45', 'you are 45');
    await tapText(t, 'No, change it');
    await waitFor(t, find.text('Okay. What is the right answer?'));
    await say(t, '47', 'you are 47');
    expect(ctl(t).confirmedProfile['age'], isNull);
    // "go back" typed as the correction is understood, not read as a value.
    await tapText(t, 'No, change it');
    await say(t, 'go back', 'What is the right answer for your age');
    expect(find.textContaining("couldn't read"), findsNothing);
    expect(ctl(t).confirmedProfile['age'], isNull);
    await tapText(t, 'No, change it');
    await say(t, 'change my age to 71', 'you are 71');
    await yes(t, 'What sex');
    expect(ctl(t).confirmedProfile['age'], 71);
    // Later, from another question.
    await say(t, 'change my age to 72', 'you are 72');
    expect(ctl(t).confirmedProfile['age'], 71, reason: 'not saved before Yes');
    await yes(t, 'What sex');
    expect(ctl(t).confirmedProfile['age'], 72);
  });

  testWidgets('"go back" typed and the Go back link reopen; "keep it" keeps the answer', (t) async {
    await startTyped(t);
    await say(t, '71', 'you are 71');
    await yes(t, 'What sex');
    await say(t, 'go back', 'go back to your age');
    expect(ctl(t).questionNumber, 1);
    await say(t, 'keep it', 'What sex');
    expect(ctl(t).confirmedProfile['age'], 71);
    await hideKeyboard(t);
    await tapText(t, 'Go back');
    await waitFor(t, find.textContaining('go back to your age'));
    await settled(t);
    await say(t, '70', 'you are 70');
    await yes(t, 'What sex');
    expect(ctl(t).confirmedProfile['age'], 70);
  });

  testWidgets('"start over" only asks; "yes, start over" clears everything', (t) async {
    await startTyped(t);
    await say(t, '71', 'you are 71');
    await yes(t, 'What sex');
    await say(t, 'start over', 'start again');
    expect(ctl(t).confirmedProfile['age'], 71, reason: '"start over" alone must not clear');
    await say(t, 'yes, start over', 'cleared your answers');
    expect(ctl(t).confirmedProfile.values.whereType<Object>(), isEmpty);
    expect(ctl(t).questionNumber, 1);
    expect(ctl(t).canGoBack, isFalse);
    // "start over" as the correction of a read-back only asks; Yes then saves the read-back.
    await say(t, '68', 'you are 68');
    await tapText(t, 'No, change it');
    await say(t, 'start over', 'start again');
    expect(ctl(t).confirming, isTrue);
    expect(ctl(t).confirmedProfile['age'], isNull);
    await yes(t, 'What sex');
    expect(ctl(t).confirmedProfile['age'], 68);
  });

  testWidgets('every question can be skipped, blood pressure included, and Continue follows', (t) async {
    await startTyped(t);
    final seen = <String>{};
    for (var i = 0; i < 14 && find.text('Continue').evaluate().isEmpty; i++) {
      seen.add('${ctl(t).state?['current_field']}');
      await tapText(t, 'Skip this question');
      await pumpFor(t, const Duration(milliseconds: 600));
      await settled(t);
      expect(ctl(t).notice, isNull, reason: 'skip refused at ${ctl(t).state?['current_field']}');
    }
    expect(seen, containsAll(['age', 'sex', 'systolic_bp']));
    await waitFor(t, find.text('Continue'));
    expect(ctl(t).confirmedProfile.values.whereType<Object>(), isEmpty);
    await tapText(t, 'Continue');
    await askTheBall(t);
    await waitFor(t, find.textContaining("I can't make a forecast for you yet."));
    expect(find.textContaining('still living'), findsNothing);
  });

  testWidgets('typed "skip" at blood pressure, and a lone top number is not saved as both', (t) async {
    await startTyped(t);
    await answerAll(t, fullIntake.sublist(0, 9));
    await waitFor(t, find.textContaining('blood pressure'));
    await typeSend(t, '130');
    // Either a follow-up for the bottom number or a read-back; never a saved guess.
    expect(ctl(t).confirmedProfile['systolic_bp'], isNull);
    expect(ctl(t).confirmedProfile['diastolic_bp'], isNull);
    if (ctl(t).confirming) {
      await tapText(t, 'No, change it');
    }
    await typeSend(t, 'skip');
    await waitFor(t, find.text('Continue'));
    expect(ctl(t).confirmedProfile['systolic_bp'], isNull);
  });

  testWidgets('AI helper: offer after a hard answer, consent resends it; Settings switch off and on', (t) async {
    await startTyped(t);
    await typeSend(t, 'somewhere around the middle of my fifties, ish');
    await waitFor(t, find.text('Yes, let the AI helper read it'));
    expect(ctl(t).aiHelper, isFalse);
    await tapText(t, 'Yes, let the AI helper read it');
    await settled(t, seconds: 40);
    expect(ctl(t).aiHelper, isTrue);
    expect(find.text('Yes, let the AI helper read it'), findsNothing);
    // Whatever the helper made of it, nothing is saved without a Yes.
    expect(ctl(t).confirmedProfile['age'], isNull);
    if (ctl(t).confirming) await yes(t, 'What sex');
    await hideKeyboard(t);
    await tapText(t, 'Settings');
    await waitFor(t, find.text('AI helper'));
    final toggle = find.byType(SwitchListTile);
    expect(t.widget<SwitchListTile>(toggle).value, isTrue);
    await t.tap(toggle);
    await t.pump(const Duration(milliseconds: 300));
    expect(ctl(t).aiHelper, isFalse);
    expect(t.widget<SwitchListTile>(toggle).value, isFalse);
    await t.tap(toggle);
    await t.pump(const Duration(milliseconds: 300));
    expect(ctl(t).aiHelper, isTrue);
    // Type/Talk switch in Settings: Talk asks "Talk with me?" first (typing was chosen).
    await tapText(t, 'Talk');
    await waitFor(t, find.text('Talk with me?'));
    await tapText(t, 'Keep typing');
    await waitFor(t, find.byType(TextField));
    expect(ctl(t).typing, isTrue);
    expect(ctl(t).phase, isNot(VoicePhase.listening));
  });
}
