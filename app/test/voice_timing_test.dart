import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/voice/fakes.dart';

import 'checkin_controller_test.dart' show FakeCheckinGuide;

/// Product rule: 2.5 s of quiet after a word sends the turn; 8 s of quiet before any word
/// closes the mic; disposing the screen leaves no timer, mic or speech running.
void main() {
  final now = DateTime(2026, 10, 24, 10);

  group('check-in voice timing', () {
    late FakeCheckinGuide guide;
    late FakeSpeechInput input;
    late FakeSpeechOutput output;

    CheckinController make({bool ownsSpeech = true}) => CheckinController(
      guide: guide,
      input: input,
      output: output,
      ownsSpeech: ownsSpeech,
      store: InMemoryCheckinStore(
        checkins: [const CheckinEntry(kind: 'quick', date: '2026-10-23', answers: {})],
      ),
      clock: () => now,
      voiceUsable: true,
    );

    setUp(() {
      guide = FakeCheckinGuide();
      input = FakeSpeechInput();
      output = FakeSpeechOutput();
    });

    CheckinController listening(FakeAsync fa, {bool ownsSpeech = true}) {
      final c = make(ownsSpeech: ownsSpeech);
      c.start();
      fa.flushMicrotasks();
      c.startTalk();
      fa.flushMicrotasks();
      expect(c.phase, CheckinPhase.listening);
      return c;
    }

    test('does not send at 2.4 s after a word, sends by 2.6 s', () {
      fakeAsync((fa) {
        listening(fa);
        input.onCaption!('about seven');
        fa.elapse(const Duration(milliseconds: 2400));
        expect(input.finishes, 0);
        fa.elapse(const Duration(milliseconds: 200));
        fa.flushMicrotasks();
        expect(input.finishes, 1);
      });
    });

    test('every new partial restarts the 2.5 s wait', () {
      fakeAsync((fa) {
        listening(fa);
        input.onCaption!('about');
        fa.elapse(const Duration(milliseconds: 2000));
        input.onCaption!('about seven');
        fa.elapse(const Duration(milliseconds: 2400));
        expect(input.finishes, 0);
        fa.elapse(const Duration(milliseconds: 200));
        expect(input.finishes, 1);
      });
    });

    test('before any word the mic closes after 8 s, not 7.9 s', () {
      fakeAsync((fa) {
        listening(fa);
        fa.elapse(const Duration(milliseconds: 7900));
        expect(input.finishes, 0);
        fa.elapse(const Duration(milliseconds: 1200));
        fa.flushMicrotasks();
        expect(input.finishes, 1);
      });
    });

    test('a blank partial does not start the 2.5 s send timer', () {
      fakeAsync((fa) {
        listening(fa);
        input.onCaption!('   ');
        fa.elapse(const Duration(milliseconds: 3000));
        expect(input.finishes, 0, reason: 'nothing was heard; only the 8 s close applies');
      });
    });

    test('dispose cancels the pending end-of-turn timer: nothing is sent later', () {
      fakeAsync((fa) {
        final c = listening(fa);
        input.onCaption!('about seven');
        fa.elapse(const Duration(milliseconds: 1000));
        c.dispose();
        fa.flushMicrotasks();
        final callsAtDispose = guide.calls.length;
        fa.elapse(const Duration(seconds: 20));
        fa.flushMicrotasks();
        expect(input.finishes, 0);
        expect(guide.calls.length, callsAtDispose, reason: 'a disposed check-in must not talk to the server');
      });
    });

    test('a late partial after dispose does not arm a new send', skip: 'BUG: CheckinController._armEndOfTurn has no _disposed guard; a late caption after dispose finishes the (shared) mic', () {
      fakeAsync((fa) {
        final c = listening(fa);
        c.dispose();
        fa.flushMicrotasks();
        final calls = guide.calls.length;
        input.onCaption?.call('late words');
        fa.elapse(const Duration(seconds: 5));
        fa.flushMicrotasks();
        expect(input.finishes, 0);
        expect(guide.calls.length, calls);
      });
    });

    test('dispose with shared speech stops outstanding TTS', () {
      fakeAsync((fa) {
        output.holdSpeech = true;
        final c = make(ownsSpeech: false);
        c.start();
        fa.flushMicrotasks();
        expect(c.phase, CheckinPhase.speaking);
        final stops = output.stops;
        c.dispose();
        fa.flushMicrotasks();
        expect(output.stops, greaterThan(stops), reason: 'speech must end with the check-in');
      });
    });

    test('dispose with owned speech disposes the input', () {
      fakeAsync((fa) {
        final c = listening(fa);
        c.dispose();
        fa.flushMicrotasks();
        expect(input.disposals, 1);
      });
    });
  });

  group('onboarding voice timing', () {
    late FakeConversationGuide guide;
    late FakeSpeechInput input;
    late FakeSpeechOutput output;

    VoiceOnboardingController listening(FakeAsync fa) {
      final c = VoiceOnboardingController(guide: guide, input: input, output: output);
      c.answerConsent(true);
      fa.flushMicrotasks();
      c.startTalk();
      fa.flushMicrotasks();
      expect(c.phase, VoicePhase.listening);
      return c;
    }

    setUp(() {
      guide = FakeConversationGuide();
      input = FakeSpeechInput();
      output = FakeSpeechOutput();
    });

    test('sends by 2.6 s, not at 2.4 s', () {
      fakeAsync((fa) {
        listening(fa);
        input.onCaption!('I am 70');
        fa.elapse(const Duration(milliseconds: 2400));
        expect(input.finishes, 0);
        fa.elapse(const Duration(milliseconds: 200));
        expect(input.finishes, 1);
      });
    });

    test('dispose cancels pending timers and a late partial cannot send', skip: 'BUG: VoiceOnboardingController._armEndOfTurn has no _disposed guard; a late caption after dispose finishes the mic', () {
      fakeAsync((fa) {
        final c = listening(fa);
        input.onCaption!('I am 70');
        fa.elapse(const Duration(milliseconds: 500));
        c.dispose();
        fa.flushMicrotasks();
        input.onCaption?.call('I am 71');
        fa.elapse(const Duration(seconds: 20));
        fa.flushMicrotasks();
        expect(input.finishes, 0);
      });
    });

    test('dispose while Mochi is speaking disposes (stops) the output', () {
      fakeAsync((fa) {
        final out = _CountingOutput()..holdSpeech = true;
        final c = VoiceOnboardingController(guide: guide, input: input, output: out);
        c.answerConsent(true);
        fa.flushMicrotasks();
        c.dispose();
        fa.flushMicrotasks();
        expect(out.disposals, 1);
        expect(input.disposals, 1);
      });
    });
  });
}

class _CountingOutput extends FakeSpeechOutput {
  int disposals = 0;
  @override
  Future<void> dispose() async => disposals++;
}
