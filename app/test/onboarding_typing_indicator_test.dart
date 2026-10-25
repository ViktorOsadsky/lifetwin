import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/voice/fakes.dart';

import 'support/app_fonts.dart';

/// Onboarding's typing state: no voice pill or ring (less on screen), "Talk instead" as the way back,
/// however the person came to be typing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  late VoiceOnboardingController c;
  late FakeSpeechInput input;

  Future<void> open(WidgetTester t, {bool handsFree = true, double scale = 1, Size size = const Size(390, 844)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    input = FakeSpeechInput();
    c = VoiceOnboardingController(
      guide: FakeConversationGuide(),
      input: input,
      output: FakeSpeechOutput(),
      handsFree: handsFree,
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: size, disableAnimations: true, textScaler: TextScaler.linear(scale)),
          child: VoiceOnboardingScreen(
            controller: c,
            onDone: (_) {},
            onUseHealth: () {},
            appearance: const TwinAppearance(name: 'Mochi', look: TwinLook.calHat),
          ),
        ),
      ),
    );
    await t.pump();
  }

  Future<void> chooseTyping(WidgetTester t) async {
    await t.tap(find.text("No, I'll type"));
    await t.pump(const Duration(milliseconds: 800)); // the second question's double-tap guard
    // The second consent question (AI helper), when asked.
    if (find.text('Not now').evaluate().isNotEmpty) {
      await t.tap(find.text('Not now'));
      await t.pump();
    }
    await t.pump(const Duration(milliseconds: 400));
  }

  for (final handsFree in [true, false]) {
    testWidgets('after "No, I\'ll type" onboarding shows no voice pill, and Talk instead (handsFree $handsFree)', (t) async {
      await open(t, handsFree: handsFree);
      await chooseTyping(t);
      expect(c.typing, isTrue);
      expect(input.listening, isFalse);
      expect(find.text('Not listening'), findsNothing);
      expect(find.text('Talk instead'), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-ring-typing')), findsNothing, reason: 'hollow ring has no live ring');
      expect(find.byKey(const ValueKey('voice-live-dot')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('declined voice: Talk instead asks consent first and never opens the mic (handsFree $handsFree)', (t) async {
      await open(t, handsFree: handsFree);
      await chooseTyping(t);
      await t.tap(find.text('Talk instead'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(c.askingVoice, isTrue);
      expect(input.listening, isFalse);
      expect(find.text('Talk with me?'), findsOneWidget);
      await t.tap(find.text('Keep typing'));
      await t.pump();
      expect(input.listening, isFalse);
      expect(find.text('Not listening'), findsNothing);
    });
  }

  testWidgets('with consent, typing via Type instead hides the pill and Talk instead goes to Speaking', (t) async {
    await open(t);
    unawaited(c.answerConsent(true));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('Type instead'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Not listening'), findsNothing);
    await t.tap(find.text('Talk instead'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(c.askingVoice, isFalse);
    expect(c.typing, isFalse);
    expect(c.phase, anyOf(VoicePhase.speaking, VoicePhase.listening), reason: 'back to voice, as in the check-in');
    expect(find.text('Not listening'), findsNothing);
  });

  testWidgets('chose typing at the consent, then says yes to talking: consent is asked, then Speaking', (t) async {
    await open(t);
    await chooseTyping(t);
    await t.tap(find.text('Talk instead'));
    await t.pump();
    await t.tap(find.text("Yes, I'll talk"));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(c.typing, isFalse);
    expect(c.voiceUsable, isTrue);
  });

  for (final size in [const Size(320, 693), const Size(390, 844)]) {
    testWidgets('typing state does not overflow at 1.6x on ${size.width.toInt()} wide', (t) async {
      await open(t, scale: 1.6, size: size);
      await chooseTyping(t);
      expect(find.text('Not listening'), findsNothing);
      expect(find.text('Talk instead'), findsOneWidget);
      expect(t.getSize(find.ancestor(of: find.text('Talk instead'), matching: find.byType(TextButton)).first).height,
          greaterThanOrEqualTo(48));
      expect(t.takeException(), isNull);
    });
  }
}
