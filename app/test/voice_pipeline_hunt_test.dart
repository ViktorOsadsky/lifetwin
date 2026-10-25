import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';

import 'checkin_controller_test.dart' show FakeCheckinGuide;

/// Bug hunt B: the hands-free voice pipeline under demo conditions, with fake STT, TTS and
/// clocks. Each test failed before its fix.
void main() {
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

  group('onboarding', () {
    test('mic off then on again while the mic is still opening: it listens', () {
      fakeAsync((fa) {
        final permission = input.permission = Completer<bool>();
        c.answerConsent(true);
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.listening);
        expect(c.micStarting, isTrue); // still opening
        c.turnMicOff();
        fa.flushMicrotasks();
        c.turnMicOn(); // a quick second tap
        fa.flushMicrotasks();
        permission.complete(true);
        fa.flushMicrotasks();
        expect(c.micOff, isFalse);
        expect(c.phase, VoicePhase.listening, reason: 'the mic is on, so hands-free listens');
        expect(input.listening, isTrue);
      });
    });

    test('the 30 s cap counts from the first word, not from when the mic opened', () {
      fakeAsync((fa) {
        begin(fa);
        fa.elapse(const Duration(seconds: 19)); // thinking (before the 20 s nudge)
        var words = 'I walk';
        input.onCaption!(words);
        for (var i = 0; i < 6; i++) {
          // a long answer, still going at 31 s since the mic opened
          fa.elapse(const Duration(seconds: 2));
          words = '$words and walk';
          input.onCaption!(words);
        }
        fa.flushMicrotasks();
        expect(input.finishes, 0, reason: 'cut off 12 s into the answer');
        expect(c.phase, VoicePhase.listening);
        input.transcript = words;
        fa.elapse(const Duration(seconds: 3)); // the person stops: sent after the end-of-turn wait
        fa.flushMicrotasks();
        expect(input.finishes, 1);
        expect(guide.calls.last, containsPair('text', words));
      });
    });

    test('the 30 s cap still ends an answer that never stops', () {
      fakeAsync((fa) {
        begin(fa);
        input.onCaption!('one');
        for (var i = 0; i < 16; i++) {
          fa.elapse(const Duration(seconds: 2));
          input.onCaption!('one ${'more ' * i}');
        }
        fa.flushMicrotasks();
        expect(input.finishes, 1);
      });
    });

    test('a later line whose audio never starts leaves its words and listens, without dead air', () {
      fakeAsync((fa) {
        begin(fa);
        output
          ..holdAudio = true
          ..holdSpeech = true; // TTS socket up, no audio (Cartesia slow or broken)
        input.onCaption!('I am 70');
        fa.elapse(const Duration(seconds: 3)); // end of turn, reply arrives, Mochi starts the line
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.speaking);
        fa.elapse(const Duration(seconds: 3, milliseconds: 100));
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.listening, reason: 'no audio 3 s after the line came: listen instead');
        expect(input.listening, isTrue);
        expect(c.mascotLine, contains('70')); // the words stay on screen
      });
    });

    test('a later line whose audio starts late but within the limit is said to the end', () {
      fakeAsync((fa) {
        begin(fa);
        output
          ..holdAudio = true
          ..holdSpeech = true;
        input.onCaption!('I am 70');
        fa.elapse(const Duration(milliseconds: 2600)); // the line starts at 2.5 s
        fa.flushMicrotasks();
        fa.elapse(const Duration(milliseconds: 2000)); // audio 2.1 s into the line
        output.startAudio();
        fa.elapse(const Duration(seconds: 5)); // a long line keeps playing
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.speaking);
        output.finishSpeaking();
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.listening);
      });
    });

    test('Hear it again replays without being cut by the no-audio limit', () {
      fakeAsync((fa) {
        begin(fa);
        final replays = output.replays;
        c.hearAgain();
        fa.elapse(const Duration(seconds: 5));
        fa.flushMicrotasks();
        expect(output.replays, replays + 1);
        expect(output.stops, lessThanOrEqualTo(1)); // only the stop before it, none cutting it
      });
    });

    test('after the nudge, back from the background, the question already said is not read again', () {
      fakeAsync((fa) {
        begin(fa);
        fa.elapse(const Duration(seconds: 21)); // the nudge is said, then it listens again
        fa.flushMicrotasks();
        expect(output.spoken.last, listeningNudge);
        expect(c.phase, VoicePhase.listening);
        final spoken = output.spoken.length;
        final replays = output.replays;
        c.pauseVoice(); // the app goes to the background
        fa.flushMicrotasks();
        c.resumeVoice();
        fa.flushMicrotasks();
        expect(output.spoken.length, spoken, reason: 'the question was said to the end already');
        expect(output.replays, replays);
        expect(c.phase, VoicePhase.listening);
      });
    });

    test('Hear it again after the nudge says the question, not the nudge', () {
      fakeAsync((fa) {
        begin(fa);
        fa.elapse(const Duration(seconds: 21));
        fa.flushMicrotasks();
        final replays = output.replays;
        c.hearAgain();
        fa.flushMicrotasks();
        expect(output.replays, replays, reason: "the speaker's last audio is the nudge");
        expect(output.spoken.last, 'How old are you?');
      });
    });

    test('a failed request while the screen is out of sight is not said out loud', () {
      fakeAsync((fa) {
        begin(fa);
        guide
          ..failNext = true
          ..gate = Completer<void>();
        input.onCaption!('I am 70');
        fa.elapse(const Duration(seconds: 3)); // sent; the server is slow
        fa.flushMicrotasks();
        c.pauseVoice(); // a sheet covers the conversation, or the app goes to the background
        fa.flushMicrotasks();
        final spoken = output.spoken.length;
        guide.gate!.complete();
        fa.flushMicrotasks();
        expect(c.notice, noNetworkNotice);
        expect(output.spoken.length, spoken);
      });
    });
  });

  group('check-in', () {
    final now = DateTime(2026, 10, 24, 10);

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

    test('a failed request is said out loud, never silent', () {
      fakeAsync((fa) {
        final g = FakeCheckinGuide();
        final k = make(g);
        k.start();
        fa.flushMicrotasks();
        expect(k.phase, CheckinPhase.listening);
        g.failNext = true;
        input.onCaption!('7 hours');
        fa.elapse(const Duration(seconds: 3));
        fa.flushMicrotasks();
        expect(k.notice, noNetworkNotice);
        expect(output.spoken.last, noNetworkNotice);
        expect(k.canRetry, isTrue);
        k.dispose();
      });
    });

    test('a start that fails is said out loud and can be tried again', () {
      fakeAsync((fa) {
        final g = FakeCheckinGuide()..failNext = true;
        final k = make(g);
        k.start();
        fa.flushMicrotasks();
        expect(output.spoken.last, noNetworkNotice);
        expect(k.phase, CheckinPhase.notStarted);
        k.retry();
        fa.flushMicrotasks();
        expect(k.phase, CheckinPhase.listening);
        k.dispose();
      });
    });

    test('mic off then on again while the mic is still opening: it listens', () {
      fakeAsync((fa) {
        final k = make(FakeCheckinGuide());
        final permission = input.permission = Completer<bool>();
        k.start();
        fa.flushMicrotasks();
        expect(k.phase, CheckinPhase.listening);
        k.turnMicOff();
        fa.flushMicrotasks();
        k.turnMicOn();
        fa.flushMicrotasks();
        permission.complete(true);
        fa.flushMicrotasks();
        expect(k.phase, CheckinPhase.listening);
        expect(input.listening, isTrue);
        k.dispose();
      });
    });

    test('the 30 s cap counts from the first word', () {
      fakeAsync((fa) {
        final k = make(FakeCheckinGuide());
        k.start();
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 19));
        var words = 'I slept';
        input.onCaption!(words);
        for (var i = 0; i < 6; i++) {
          fa.elapse(const Duration(seconds: 2));
          words = '$words and slept';
          input.onCaption!(words);
        }
        fa.flushMicrotasks();
        expect(input.finishes, 0);
        k.dispose();
      });
    });

    test('a later line whose audio never starts listens after 3 s', () {
      fakeAsync((fa) {
        final k = make(FakeCheckinGuide());
        k.start();
        fa.flushMicrotasks();
        output
          ..holdAudio = true
          ..holdSpeech = true;
        input.onCaption!('7 hours');
        fa.elapse(const Duration(seconds: 3));
        fa.flushMicrotasks();
        expect(k.phase, CheckinPhase.speaking);
        fa.elapse(const Duration(seconds: 3, milliseconds: 100));
        fa.flushMicrotasks();
        expect(k.phase, CheckinPhase.listening);
        k.dispose();
      });
    });

    test('after the nudge, back from the background, the question is not read again', () {
      fakeAsync((fa) {
        final k = make(FakeCheckinGuide());
        k.start();
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 21));
        fa.flushMicrotasks();
        expect(output.spoken.last, listeningNudge);
        final spoken = output.spoken.length;
        k.pauseVoice();
        fa.flushMicrotasks();
        k.resumeVoice();
        fa.flushMicrotasks();
        expect(output.spoken.length, spoken);
        expect(k.phase, CheckinPhase.listening);
        k.dispose();
      });
    });
  });

  test('the no-audio limit for later lines is 3 s', () {
    expect(voiceLaterAudioLimit, const Duration(seconds: 3));
  });
}
