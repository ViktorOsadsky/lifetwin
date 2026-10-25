import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/voice/fakes.dart';

import 'voice_question_state_test.dart' show ThreeQuestions;

void main() {
  testWidgets('a sent answer shows "Question 1 saved" beside the next question', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = VoiceOnboardingController(guide: ThreeQuestions(), input: FakeSpeechInput(), output: FakeSpeechOutput());
    await c.answerConsent(false); // typing
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
          child: VoiceOnboardingScreen(controller: c, onDone: (_) {}),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Question 1 of 12'), findsOneWidget);
    expect(find.text('Question 1 saved'), findsNothing);
    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(find.text('Question 1 saved'), findsOneWidget);
    expect(find.text('Question 2 of 12'), findsOneWidget);
    expect(find.textContaining('female or male'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
}
