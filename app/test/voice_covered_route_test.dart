import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/voice/fakes.dart';

const _guard = Duration(milliseconds: 700);

// Hands-free must not keep listening under another screen: words said there would be
// sent as an answer to the question hidden below.
void main() {
  testWidgets('a screen pushed over the conversation closes the mic; back on top it listens again', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final input = FakeSpeechInput();
    final c = VoiceOnboardingController(guide: FakeConversationGuide(), input: input, output: FakeSpeechOutput(), handsFree: true);
    await t.pumpWidget(LifeTwinApp(controller: c));
    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    await t.tap(find.text("Yes, I'll talk"));
    await t.pumpAndSettle();
    await t.pump(_guard);
    await t.tap(find.text('Not now'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(c.phase, VoicePhase.listening);
    expect(input.listening, isTrue);

    final nav = Navigator.of(t.element(find.byType(VoiceOnboardingScreen)));
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('On top'))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('On top'), findsOneWidget);
    expect(input.listening, isFalse);
    expect(input.finishes, 0); // nothing heard under the other screen is sent
    expect(c.phase, isNot(VoicePhase.listening));

    nav.pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(input.listening, isTrue);
  });
}
