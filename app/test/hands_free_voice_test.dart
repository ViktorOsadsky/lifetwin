import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_client.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';

import 'checkin/readback_flow_test.dart' show ContractGuide;
import 'checkin_controller_test.dart' show FakeCheckinGuide;
import 'voice_onboarding_screen_test.dart' show choose;

/// A microphone that notes whether Mochi was speaking each time it was opened.
class WatchedInput extends FakeSpeechInput {
  WatchedInput(this.output);
  final FakeSpeechOutput output;
  int startsWhileSpeaking = 0;

  @override
  Future<void> start(void Function(String text) onCaption, {void Function(Object error)? onDropped}) {
    if (output.speaking) startsWhileSpeaking++;
    return super.start(onCaption, onDropped: onDropped);
  }
}

/// Product rule (owner): voice is one continuous session, like a phone call. Mochi speaks
/// first with no tap; whenever Mochi is not speaking the microphone listens; quiet never
/// closes it; typing, leaving the screen or the background pause it.
void main() {
  group('onboarding, hands-free', () {
    late FakeConversationGuide guide;
    late FakeSpeechOutput output;
    late WatchedInput input;
    late VoiceOnboardingController c;

    setUp(() {
      guide = FakeConversationGuide();
      output = FakeSpeechOutput();
      input = WatchedInput(output);
      c = VoiceOnboardingController(guide: guide, input: input, output: output, handsFree: true);
    });

    void begin(FakeAsync fa) {
      c.prepareVoice(); // "Yes, I'll talk"
      c.answerConsent(true);
      fa.flushMicrotasks();
    }

    void say(FakeAsync fa, String words) {
      input.transcript = words;
      input.onCaption!(words);
      fa.elapse(voiceEndOfTurn);
      fa.flushMicrotasks();
    }

    test('the first prompt plays with no tap, then the microphone opens by itself', () {
      fakeAsync((fa) {
        begin(fa);
        expect(input.warmUps, greaterThanOrEqualTo(1));
        expect(output.spoken, ['How old are you?']);
        expect(output.audioStarts, 1);
        expect(c.phase, VoicePhase.listening);
        expect(input.listening, isTrue);
        expect(input.startsWhileSpeaking, 0);
      });
    });

    test('the microphone opens only after the speech has finished', () {
      fakeAsync((fa) {
        output.holdSpeech = true;
        begin(fa);
        expect(c.phase, VoicePhase.speaking);
        fa.elapse(const Duration(seconds: 5)); // audio started, so no early opening
        expect(input.starts, 0);
        output.finishSpeaking();
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.listening);
        expect(input.starts, 1);
        expect(input.startsWhileSpeaking, 0);
      });
    });

    test('no audio within 1.5 s: the words stay on screen, speech stops and it listens', () {
      fakeAsync((fa) {
        output
          ..holdSpeech = true
          ..holdAudio = true;
        begin(fa);
        fa.elapse(const Duration(milliseconds: 1400));
        expect(c.phase, VoicePhase.speaking);
        expect(input.starts, 0);
        fa.elapse(const Duration(milliseconds: 200));
        fa.flushMicrotasks();
        expect(output.stops, greaterThanOrEqualTo(1));
        expect(c.mascotLine, 'How old are you?');
        expect(c.phase, VoicePhase.listening);
        expect(input.startsWhileSpeaking, 0);
      });
    });

    test('auto-send, reply, auto-listen runs twice with no tap', () {
      fakeAsync((fa) {
        begin(fa);
        say(fa, 'I am 70');
        expect(guide.calls.last, containsPair('text', 'I am 70'));
        expect(guide.calls.last, containsPair('fromTranscript', true));
        expect(output.spoken.last, 'I heard you are 70. Is that right?');
        expect(c.phase, VoicePhase.listening);
        expect(input.starts, 2);
        say(fa, 'no');
        expect(guide.calls.last, containsPair('text', 'no'));
        expect(output.spoken.last, startsWith('Okay, nothing has changed.'));
        expect(c.phase, VoicePhase.listening);
        expect(input.starts, 3);
        expect(input.startsWhileSpeaking, 0);
      });
    });

    test('never listens while Mochi speaks, the nudge included', () {
      fakeAsync((fa) {
        output.holdSpeech = true;
        begin(fa);
        output.finishSpeaking();
        fa.flushMicrotasks();
        input.transcript = 'I am 70';
        input.onCaption!('I am 70');
        fa.elapse(voiceEndOfTurn);
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.speaking); // the read-back
        expect(input.listening, isFalse);
        output.finishSpeaking();
        fa.flushMicrotasks();
        fa.elapse(voiceNudgeAfter);
        fa.flushMicrotasks();
        expect(output.spoken.last, listeningNudge);
        expect(c.phase, VoicePhase.speaking);
        expect(input.listening, isFalse);
        output.finishSpeaking();
        fa.flushMicrotasks();
        expect(input.listening, isTrue);
        expect(input.startsWhileSpeaking, 0);
      });
    });

    test('quiet never closes it: one nudge, then listening across three silent windows', () {
      fakeAsync((fa) {
        begin(fa);
        fa.elapse(const Duration(seconds: 19));
        expect(c.phase, VoicePhase.listening);
        expect(output.spoken, ['How old are you?']);
        fa.elapse(const Duration(seconds: 1));
        fa.flushMicrotasks();
        expect(output.spoken, ['How old are you?', listeningNudge]);
        expect(c.phase, VoicePhase.listening);
        final phases = <VoicePhase>[];
        c.addListener(() => phases.add(c.phase));
        // Two more windows of quiet: the recognizer is restarted out of sight, no more nudges.
        fa.elapse(voiceSessionRestart * 2 + const Duration(seconds: 1));
        fa.flushMicrotasks();
        expect(output.spoken, ['How old are you?', listeningNudge]);
        expect(c.phase, VoicePhase.listening);
        expect(input.listening, isTrue);
        expect(input.starts, 4); // first listen, after the nudge, two restarts
        expect(phases.where((p) => p != VoicePhase.listening), isEmpty);
        expect(c.notice, isNull);
        expect(c.listenSecondsLeft, isNull);
      });
    });

    test('a recognizer session that ends by itself is restarted, unseen', () {
      fakeAsync((fa) {
        begin(fa);
        input.drop();
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.listening);
        expect(input.listening, isTrue);
        expect(input.starts, 2);
        expect(c.notice, isNull);
      });
    });

    test('typing pauses auto-listen; back to voice listens again', () {
      fakeAsync((fa) {
        begin(fa);
        c.setTyping(true);
        fa.flushMicrotasks();
        expect(input.listening, isFalse);
        c.submitTyped('70');
        fa.flushMicrotasks();
        expect(c.confirming, isTrue);
        fa.elapse(const Duration(minutes: 2));
        expect(input.starts, 1);
        c.setTyping(false);
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.listening);
        expect(input.starts, 2);
      });
    });

    test('out of sight (background, left) the mic closes; back in sight it listens, if on top', () {
      fakeAsync((fa) {
        var onTop = true;
        c.mayListen = () => onTop;
        begin(fa);
        c.pauseVoice();
        fa.flushMicrotasks();
        expect(input.listening, isFalse);
        expect(c.phase, VoicePhase.idle);
        fa.elapse(const Duration(minutes: 2));
        expect(input.starts, 1);
        c.resumeVoice();
        fa.flushMicrotasks();
        expect(input.listening, isTrue);
        // Another screen on top: back in front, it stays closed.
        c.pauseVoice();
        fa.flushMicrotasks();
        onTop = false;
        c.resumeVoice();
        fa.flushMicrotasks();
        expect(input.listening, isFalse);
      });
    });

    test('a reply that arrives while out of sight is not spoken', () {
      fakeAsync((fa) {
        begin(fa);
        guide.gate = Completer<void>();
        input.transcript = 'I am 70';
        input.onCaption!('I am 70');
        fa.elapse(voiceEndOfTurn);
        fa.flushMicrotasks();
        c.pauseVoice();
        guide.gate!.complete();
        fa.flushMicrotasks();
        expect(output.spoken, ['How old are you?']);
        expect(input.listening, isFalse);
      });
    });

    test('dispose closes the microphone and leaves no timer running', () {
      fakeAsync((fa) {
        begin(fa);
        c.dispose();
        fa.flushMicrotasks();
        expect(input.disposals, 1);
        expect(fa.periodicTimerCount, 0);
      });
    });

    test('microphone not allowed: typing, with the gentle words, and no loop', () {
      fakeAsync((fa) {
        input.permission = Completer<bool>()..complete(false);
        begin(fa);
        expect(c.typing, isTrue);
        expect(c.notice, micDeniedNotice);
        fa.elapse(const Duration(minutes: 2));
        expect(input.starts, 0);
      });
    });

    test('the mic never opens before the phone allows it, nor without the voice consent', () {
      fakeAsync((fa) {
        final asked = input.permission = Completer<bool>();
        begin(fa);
        expect(output.spoken, ['How old are you?']); // the first prompt may play
        fa.elapse(const Duration(minutes: 1));
        expect(input.starts, 0);
        asked.complete(true);
        fa.flushMicrotasks();
        expect(input.listening, isTrue);
      });
      fakeAsync((fa) {
        input = WatchedInput(output);
        final typed = VoiceOnboardingController(guide: guide, input: input, output: output, handsFree: true);
        typed.answerConsent(false);
        fa.flushMicrotasks();
        fa.elapse(const Duration(minutes: 1));
        expect(input.listening, isFalse);
        expect(typed.phase, VoicePhase.idle);
      });
    });

    test('VoiceOver on: nothing opens by itself; one tap listens', () {
      fakeAsync((fa) {
        c.screenReader = true;
        begin(fa);
        expect(c.continuous, isFalse);
        expect(input.starts, 0);
        c.startTalk();
        fa.flushMicrotasks();
        say(fa, 'I am 70');
        expect(c.confirming, isTrue);
        fa.elapse(const Duration(minutes: 1));
        expect(input.starts, 1);
      });
    });

    test('an emergency speaks as before and does not listen; Continue resumes the loop', () {
      fakeAsync((fa) {
        begin(fa);
        say(fa, 'I have chest pain');
        expect(c.emergency, isTrue);
        expect(output.spoken.last, contains('call 911'));
        expect(input.listening, isFalse);
        fa.elapse(const Duration(minutes: 1));
        expect(input.starts, 1);
        c.continueAfterEmergency();
        fa.flushMicrotasks();
        expect(output.spoken.last, 'How old are you?');
        expect(input.listening, isTrue);
      });
    });

    test('a failed request keeps Try again and the mic closed; a good retry listens again', () {
      fakeAsync((fa) {
        begin(fa);
        guide.failNext = true;
        say(fa, 'I am 70');
        expect(c.notice, noNetworkNotice);
        expect(c.canRetry, isTrue);
        expect(input.listening, isFalse);
        c.retry();
        fa.flushMicrotasks();
        expect(c.confirming, isTrue);
        expect(input.listening, isTrue);
      });
    });

    test('"No, change it" while listening works, then it listens for the right answer', () {
      fakeAsync((fa) {
        begin(fa);
        say(fa, 'I am 70');
        expect(c.phase, VoicePhase.listening);
        c.change();
        fa.flushMicrotasks();
        expect(c.correcting, isTrue);
        expect(c.phase, VoicePhase.listening);
        expect(input.cancels, 1);
      });
    });
  });

  group('check-in, hands-free', () {
    final now = DateTime(2026, 10, 24, 10);
    late FakeSpeechOutput output;
    late WatchedInput input;

    CheckinController make(CheckinGuide guide, {bool ownsSpeech = true}) => CheckinController(
      guide: guide,
      input: input,
      output: output,
      ownsSpeech: ownsSpeech,
      store: InMemoryCheckinStore(checkins: [const CheckinEntry(kind: 'quick', date: '2026-10-23', answers: {})]),
      clock: () => now,
      voiceUsable: true,
      handsFree: true,
    );

    setUp(() {
      output = FakeSpeechOutput();
      input = WatchedInput(output);
    });

    void say(FakeAsync fa, String words) {
      input.transcript = words;
      input.onCaption!(words);
      fa.elapse(voiceEndOfTurn);
      fa.flushMicrotasks();
    }

    test('Mochi asks first with no tap, then listens; the loop runs twice', () {
      fakeAsync((fa) {
        final guide = FakeCheckinGuide();
        final c = make(guide);
        c.start();
        fa.flushMicrotasks();
        expect(output.spoken, ['How did you sleep last night?']);
        expect(c.phase, CheckinPhase.listening);
        say(fa, '7');
        expect(output.spoken.last, 'I heard 7. Is that right?');
        expect(c.phase, CheckinPhase.listening);
        say(fa, 'yes');
        expect(guide.calls.last, containsPair('text', 'yes'));
        expect(c.phase, CheckinPhase.listening);
        expect(input.starts, 3);
        expect(input.startsWhileSpeaking, 0);
        c.dispose();
      });
    });

    test('quiet: one nudge, then listening on, with the recognizer restarted', () {
      fakeAsync((fa) {
        final c = make(FakeCheckinGuide());
        c.start();
        fa.flushMicrotasks();
        fa.elapse(voiceNudgeAfter + voiceSessionRestart * 2 + const Duration(seconds: 2));
        fa.flushMicrotasks();
        expect(output.spoken.where((l) => l == listeningNudge), hasLength(1));
        expect(c.phase, CheckinPhase.listening);
        expect(c.notice, isNull);
        expect(input.starts, 4);
        c.dispose();
      });
    });

    test('the care question waits for its buttons; after it, listening resumes', () {
      fakeAsync((fa) {
        final c = make(ContractGuide());
        c.start();
        fa.flushMicrotasks();
        say(fa, 'awful');
        expect(c.careQuestionOpen, isTrue);
        expect(output.spoken.last, contains('call 911'));
        expect(input.listening, isFalse);
        fa.elapse(const Duration(minutes: 1));
        c.submitQuick('keep going');
        fa.flushMicrotasks();
        expect(c.careQuestionOpen, isFalse);
        expect(input.listening, isTrue);
        c.dispose();
      });
    });

    test('finished: the mic is closed and stays closed after background and foreground', () {
      fakeAsync((fa) {
        final c = make(FakeCheckinGuide());
        c.start();
        fa.flushMicrotasks();
        c.skip();
        fa.flushMicrotasks();
        c.skip();
        fa.flushMicrotasks();
        expect(c.phase, CheckinPhase.done);
        expect(input.listening, isFalse);
        final starts = input.starts;
        c.pauseVoice();
        fa.flushMicrotasks();
        c.resumeVoice();
        fa.flushMicrotasks();
        fa.elapse(const Duration(minutes: 1));
        expect(input.listening, isFalse);
        expect(input.starts, starts);
        c.dispose();
      });
    });

    test('background closes the mic; foreground listens again; leaving cancels the shared mic', () {
      fakeAsync((fa) {
        final c = make(FakeCheckinGuide(), ownsSpeech: false);
        c.start();
        fa.flushMicrotasks();
        c.pauseVoice();
        fa.flushMicrotasks();
        expect(input.listening, isFalse);
        c.resumeVoice();
        fa.flushMicrotasks();
        expect(input.listening, isTrue);
        c.dispose();
        fa.flushMicrotasks();
        expect(input.listening, isFalse);
        expect(fa.periodicTimerCount, 0);
      });
    });

    test('typing pauses it, back to voice listens; microphone not allowed types with no loop', () {
      fakeAsync((fa) {
        final c = make(FakeCheckinGuide());
        c.start();
        fa.flushMicrotasks();
        c.setTyping(true);
        fa.flushMicrotasks();
        expect(input.listening, isFalse);
        c.setTyping(false);
        fa.flushMicrotasks();
        expect(input.listening, isTrue);
        c.dispose();
      });
      fakeAsync((fa) {
        input = WatchedInput(output)..permission = (Completer<bool>()..complete(false));
        final c = make(FakeCheckinGuide());
        c.start();
        fa.flushMicrotasks();
        expect(c.typing, isTrue);
        expect(c.notice, micDeniedNotice);
        fa.elapse(const Duration(minutes: 1));
        expect(input.starts, 0);
        c.dispose();
      });
    });
  });

  group('onboarding screen, hands-free', () {
    late FakeSpeechOutput output;
    late WatchedInput input;
    late VoiceOnboardingController c;
    final nav = GlobalKey<NavigatorState>();

    Future<void> pump(WidgetTester t, {bool voiceOver = false}) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      output = FakeSpeechOutput();
      input = WatchedInput(output);
      c = VoiceOnboardingController(guide: FakeConversationGuide(), input: input, output: output, handsFree: true);
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
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
    }

    Future<void> lifecycle(WidgetTester t, List<AppLifecycleState> states) async {
      for (final s in states) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await t.pump();
    }

    Future<void> end(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      c.dispose();
    }

    testWidgets('Mochi speaks first and listens with no tap; a listening state, no "tap when done"', (t) async {
      await pump(t);
      expect(output.spoken, ['How old are you?']);
      expect(input.listening, isTrue);
      expect(find.text('Listening'), findsOneWidget); // disableAnimations: the still look drops the ellipsis
      expect(find.textContaining('tap when done'), findsNothing);
      expect(find.text('Tap to talk'), findsNothing);
      expect(find.text('Type instead'), findsOneWidget);
      await end(t);
    });

    testWidgets('background closes the mic; foreground listens again, only while on top', (t) async {
      await pump(t);
      await lifecycle(t, [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
      expect(input.listening, isFalse);
      await lifecycle(t, [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
      expect(input.listening, isTrue);
      // Another screen on top of the conversation: back in front, nothing opens.
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Other'))));
      await t.pumpAndSettle();
      await lifecycle(t, [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
      await lifecycle(t, [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
      expect(input.listening, isFalse);
      await end(t);
    });

    testWidgets('the import control stays reachable while listening; a tap closes the mic first', (t) async {
      await pump(t);
      expect(input.listening, isTrue);
      expect(find.bySemanticsLabel(ImportControl.label), findsOneWidget);
      await t.tap(find.byType(ImportControl));
      await t.pumpAndSettle();
      expect(input.listening, isFalse);
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      expect(input.listening, isTrue);
      await end(t);
    });

    testWidgets('Type instead pauses listening; Talk instead listens again', (t) async {
      await pump(t);
      await t.tap(find.text('Type instead'));
      await t.pumpAndSettle();
      expect(input.listening, isFalse);
      expect(find.text('Talk instead'), findsOneWidget);
      await t.tap(find.text('Talk instead'));
      await t.pumpAndSettle();
      expect(input.listening, isTrue);
      await end(t);
    });

    testWidgets('VoiceOver on: nothing opens by itself, one tap target to talk', (t) async {
      await pump(t, voiceOver: true);
      expect(input.starts, 0);
      expect(find.bySemanticsLabel('Tap to talk to Mochi'), findsOneWidget);
      expect(find.byType(TalkButton), findsNothing);
      await end(t);
    });

    testWidgets('leaving the screen closes the mic and nothing reopens it', (t) async {
      await pump(t);
      expect(input.listening, isTrue);
      await t.pumpWidget(const SizedBox());
      c.resumeVoice();
      await t.pump();
      expect(input.listening, isFalse);
      c.dispose();
    });
  });
}
