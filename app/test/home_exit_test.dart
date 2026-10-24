import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/voice/fakes.dart';

const _guard = Duration(milliseconds: 700);

Future<VoiceOnboardingController> _open(
  WidgetTester t, {
  required FakeSpeechInput input,
  FakeSpeechOutput? output,
}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final c = VoiceOnboardingController(
    guide: FakeConversationGuide(),
    input: input,
    output: output ?? FakeSpeechOutput(),
  );
  await t.pumpWidget(LifeTwinApp(controller: c));
  await t.tap(find.text('Talk with Pip'));
  await t.pumpAndSettle();
  return c;
}

Future<void> _consent(WidgetTester t, String voice) async {
  await t.tap(find.text(voice));
  await t.pumpAndSettle();
  await t.pump(_guard);
  await t.tap(find.text('Not now'));
  await t.pumpAndSettle();
  await t.pump(_guard);
}

void main() {
  testWidgets('Home is visible, named for screen readers, at least 48 px, on every conversation screen', (t) async {
    final h = t.ensureSemantics();
    await _open(t, input: FakeSpeechInput());
    for (var step = 0; step < 3; step++) {
      expect(find.bySemanticsLabel('Home'), findsOneWidget, reason: 'step $step');
      final box = t.getRect(find.text('Home'));
      expect(
        t.getSize(find.ancestor(of: find.text('Home'), matching: find.byType(ConstrainedBox)).first).height,
        greaterThanOrEqualTo(48),
      );
      expect(box.top, lessThan(120));
      if (step == 0) {
        await t.tap(find.text("No, I'll type"));
        await t.pumpAndSettle();
        await t.pump(_guard);
      } else if (step == 1) {
        await t.tap(find.text('Not now'));
        await t.pumpAndSettle();
      }
    }
    h.dispose();
  });

  testWidgets('Home returns to the Room, keeps confirmed answers, and Talk resumes the conversation', (t) async {
    final c = await _open(t, input: FakeSpeechInput());
    await _consent(t, "No, I'll type");
    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    expect(c.confirmedProfile, {'age': 70});

    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    expect(find.text('Your room'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(c.confirmedProfile, {'age': 70});

    await t.tap(find.text('Talk with Pip'));
    await t.pumpAndSettle();
    expect(find.text('Talk with me?'), findsNothing); // resumes, not restarts
    expect(c.confirmedProfile, {'age': 70});
  });

  testWidgets('a double tap on Home leaves once and never closes the Room', (t) async {
    await _open(t, input: FakeSpeechInput());
    final at = t.getCenter(find.text('Home'));
    await t.tapAt(at);
    await t.pump(const Duration(milliseconds: 60));
    await t.tapAt(at);
    await t.pumpAndSettle();
    expect(find.text('Your room'), findsOneWidget);
  });

  testWidgets('Home closes the microphone', (t) async {
    final input = FakeSpeechInput()..captions = ['I am 70'];
    final c = await _open(t, input: input);
    await _consent(t, "Yes, I'll talk");
    await t.tap(find.text('Tap to talk'));
    await t.pump(const Duration(milliseconds: 100)); // not settled: the listening clock would time out
    expect(c.phase, VoicePhase.listening);

    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    expect(find.text('Your room'), findsOneWidget);
    expect(input.cancels, 1);
    expect(input.finishes, 0); // heard words are dropped, not sent
    expect(c.phase, isNot(VoicePhase.listening));
  });

  testWidgets('Home stops Pip mid-sentence', (t) async {
    final output = FakeSpeechOutput()..holdSpeech = true;
    final c = await _open(t, input: FakeSpeechInput(), output: output);
    await _consent(t, "Yes, I'll talk");
    expect(c.phase, VoicePhase.speaking);

    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    expect(find.text('Your room'), findsOneWidget);
    expect(output.stops, greaterThan(0));
    expect(c.phase, isNot(VoicePhase.speaking));
  });
}
