import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/voice_indicator.dart';

import 'checkin_controller_test.dart' show FakeCheckinGuide;
import 'voice_onboarding_screen_test.dart' show choose;

/// "I should be able to close my microphone after answering": the person's own mic-off.
void main() {
  group('onboarding, mic off', () {
    late FakeConversationGuide guide;
    late FakeSpeechOutput output;
    late FakeSpeechInput input;
    late VoiceOnboardingController c;

    setUp(() {
      guide = FakeConversationGuide();
      output = FakeSpeechOutput();
      input = FakeSpeechInput();
      c = VoiceOnboardingController(guide: guide, input: input, output: output, handsFree: true);
    });

    void begin(FakeAsync fa) {
      c.answerConsent(true);
      fa.flushMicrotasks();
      expect(c.phase, VoicePhase.listening);
    }

    test('off with words heard sends them once, and the mic stays closed after Mochi speaks', () {
      fakeAsync((fa) {
        begin(fa);
        input.transcript = 'I am 72';
        input.onCaption!('I am 72');
        final sent = guide.calls.length;
        c.turnMicOff();
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 5)); // the end-of-turn timer must not send it again
        fa.flushMicrotasks();
        expect(c.micOff, isTrue);
        expect(guide.calls, hasLength(sent + 1));
        expect(guide.calls.last, containsPair('text', 'I am 72'));
        expect(input.listening, isFalse);
        expect(c.phase, VoicePhase.idle);
        expect(output.spoken.length, greaterThan(1)); // Mochi answered
      });
    });

    test('off with nothing heard closes the mic and sends nothing', () {
      fakeAsync((fa) {
        begin(fa);
        final sent = guide.calls.length;
        c.turnMicOff();
        fa.flushMicrotasks();
        expect(guide.calls, hasLength(sent));
        expect(input.listening, isFalse);
        expect(input.finishes, 0);
        expect(c.phase, VoicePhase.idle);
        expect(c.micOff, isTrue);
      });
    });

    test('no "Take your time" nudge and no restarts while off', () {
      fakeAsync((fa) {
        begin(fa);
        c.turnMicOff();
        fa.flushMicrotasks();
        final starts = input.starts;
        fa.elapse(const Duration(minutes: 2));
        fa.flushMicrotasks();
        expect(output.spoken.where((l) => l == listeningNudge), isEmpty);
        expect(input.starts, starts);
        expect(input.listening, isFalse);
      });
    });

    test('leaving the screen and coming back keeps it off; turning on listens again', () {
      fakeAsync((fa) {
        begin(fa);
        c.turnMicOff();
        fa.flushMicrotasks();
        c.pauseVoice();
        fa.flushMicrotasks();
        c.resumeVoice();
        fa.flushMicrotasks();
        expect(input.listening, isFalse);
        expect(c.micOff, isTrue);
        c.turnMicOn();
        fa.flushMicrotasks();
        expect(c.micOff, isFalse);
        expect(input.listening, isTrue);
        expect(c.phase, VoicePhase.listening);
      });
    });

    test('a new conversation clears it', () {
      fakeAsync((fa) {
        begin(fa);
        c.turnMicOff();
        fa.flushMicrotasks();
        c.resetConversation();
        fa.flushMicrotasks();
        expect(c.micOff, isFalse);
      });
    });
  });

  group('check-in, mic off', () {
    final now = DateTime(2026, 10, 24, 10);
    late FakeSpeechOutput output;
    late FakeSpeechInput input;

    CheckinController make(FakeCheckinGuide guide) => CheckinController(
      guide: guide,
      input: input,
      output: output,
      store: InMemoryCheckinStore(
        checkins: [const CheckinEntry(kind: 'quick', date: '2026-10-23', answers: {})],
      ),
      clock: () => now,
      voiceUsable: true,
      handsFree: true,
    );

    setUp(() {
      output = FakeSpeechOutput();
      input = FakeSpeechInput();
    });

    test('off with words heard sends them once, and the mic stays closed after Mochi speaks', () {
      fakeAsync((fa) {
        final guide = FakeCheckinGuide();
        final c = make(guide);
        c.start();
        fa.flushMicrotasks();
        expect(c.phase, CheckinPhase.listening);
        input.transcript = '7';
        input.onCaption!('7');
        final sent = guide.calls.length;
        c.turnMicOff();
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 5));
        fa.flushMicrotasks();
        expect(guide.calls, hasLength(sent + 1));
        expect(guide.calls.last, containsPair('text', '7'));
        expect(input.listening, isFalse);
        expect(c.micOff, isTrue);
        c.dispose();
      });
    });

    test('off with nothing heard closes the mic and sends nothing', () {
      fakeAsync((fa) {
        final guide = FakeCheckinGuide();
        final c = make(guide);
        c.start();
        fa.flushMicrotasks();
        final sent = guide.calls.length;
        c.turnMicOff();
        fa.flushMicrotasks();
        expect(guide.calls, hasLength(sent));
        expect(input.listening, isFalse);
        expect(c.phase, CheckinPhase.idle);
        c.dispose();
      });
    });

    test('no nudge while off; pause and resume keep it off; on listens again', () {
      fakeAsync((fa) {
        final c = make(FakeCheckinGuide());
        c.start();
        fa.flushMicrotasks();
        c.turnMicOff();
        fa.flushMicrotasks();
        fa.elapse(const Duration(minutes: 2));
        fa.flushMicrotasks();
        expect(output.spoken.where((l) => l == listeningNudge), isEmpty);
        c.pauseVoice();
        fa.flushMicrotasks();
        c.resumeVoice();
        fa.flushMicrotasks();
        expect(input.listening, isFalse);
        c.turnMicOn();
        fa.flushMicrotasks();
        expect(input.listening, isTrue);
        expect(c.micOff, isFalse);
        c.dispose();
      });
    });

    test('a new check-in clears it', () {
      fakeAsync((fa) {
        final c = make(FakeCheckinGuide());
        c.start();
        fa.flushMicrotasks();
        c.turnMicOff();
        fa.flushMicrotasks();
        expect(c.micOff, isTrue);
        c.dispose();
        final next = make(FakeCheckinGuide());
        next.start();
        fa.flushMicrotasks();
        expect(next.micOff, isFalse);
        next.dispose();
      });
    });
  });

  group('screen', () {
    testWidgets('the pill says Mic off, with a mic-off glyph', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: VoicePill(look: VoiceLook.micOff)),
          ),
        ),
      );
      expect(find.text('Mic off'), findsOneWidget);
      expect(find.text('Not listening'), findsNothing);
      expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-live-dot')), findsNothing);
    });

    for (final voiceOver in [false, true]) {
      testWidgets('onboarding: the button swaps (VoiceOver: $voiceOver)', (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final output = FakeSpeechOutput();
        final input = FakeSpeechInput();
        final c = VoiceOnboardingController(
          guide: FakeConversationGuide(),
          input: input,
          output: output,
          handsFree: true,
        );
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 844),
                disableAnimations: true,
                accessibleNavigation: voiceOver,
              ),
              child: VoiceOnboardingScreen(controller: c, onDone: (_) {}, onUseHealth: () {}),
            ),
          ),
        );
        await choose(t, "Yes, I'll talk");
        await t.pump(const Duration(milliseconds: 100));
        final toggle = find.byKey(const ValueKey('mic-toggle'));
        if (voiceOver) {
          expect(toggle, findsNothing);
          return;
        }
        expect(c.phase, VoicePhase.listening);
        expect(find.text('Turn off mic'), findsOneWidget);
        expect(find.byIcon(Icons.mic_off_rounded), findsWidgets);
        expect(t.getSize(toggle).height, greaterThanOrEqualTo(56));
        await t.tap(toggle);
        await t.pump(const Duration(seconds: 1));
        expect(c.micOff, isTrue);
        expect(find.text('Turn on mic'), findsOneWidget);
        expect(find.text('Turn off mic'), findsNothing);
        expect(find.text('Mic off'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('mic-toggle')));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        expect(c.micOff, isFalse);
        expect(find.text('Turn off mic'), findsOneWidget);
        expect(find.text('Mic off'), findsNothing);
      });
    }
  });
}
