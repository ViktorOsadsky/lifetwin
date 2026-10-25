import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';

import 'checkin_controller_test.dart' show FakeCheckinGuide;

/// A microphone whose next [failStarts] opens fail (a socket that does not open, a token
/// that cannot be fetched), and whose finish can fail once.
class FlakyInput extends FakeSpeechInput {
  int failStarts = 0;

  @override
  Future<void> start(void Function(String text) onCaption, {void Function(Object error)? onDropped}) async {
    if (failStarts > 0) {
      failStarts--;
      starts++;
      throw const VoiceFailure('stt connect: timeout');
    }
    return super.start(onCaption, onDropped: onDropped);
  }
}

/// Hands-free continuity on a real phone (owner: "it is not continuous on my phone"). Each
/// test is one way the session stopped listening and needed a tap.
void main() {
  group('onboarding, hands-free continuity', () {
    late FakeConversationGuide guide;
    late FakeSpeechOutput output;
    late FlakyInput input;
    late VoiceOnboardingController c;

    setUp(() {
      guide = FakeConversationGuide();
      output = FakeSpeechOutput();
      input = FlakyInput();
      c = VoiceOnboardingController(guide: guide, input: input, output: output, handsFree: true);
    });

    void begin(FakeAsync fa) {
      c.answerConsent(true);
      fa.flushMicrotasks();
      expect(c.phase, VoicePhase.listening);
    }

    test('a recognizer that ends now and then during a long quiet is always restarted', () {
      fakeAsync((fa) {
        begin(fa);
        // Five losses, each after the listen was up a while: before, the fourth gave up.
        for (var i = 0; i < 5; i++) {
          fa.elapse(const Duration(seconds: 12));
          input.drop();
          fa.flushMicrotasks();
          expect(c.phase, VoicePhase.listening, reason: 'drop ${i + 1}');
          expect(input.listening, isTrue, reason: 'drop ${i + 1}');
        }
        expect(c.notice, isNull);
      });
    });

    test('losses right after opening, over and over, still end in the trouble notice', () {
      fakeAsync((fa) {
        begin(fa);
        for (var i = 0; i < 4; i++) {
          input.drop();
          fa.flushMicrotasks();
        }
        expect(c.phase, VoicePhase.idle);
        expect(c.notice, voiceTroubleNotice);
      });
    });

    test('a microphone that fails to open is tried again out of sight, and listens', () {
      fakeAsync((fa) {
        input.failStarts = 2;
        c.answerConsent(true);
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.listening); // still "Listening", no notice
        expect(c.notice, isNull);
        fa.elapse(const Duration(seconds: 1));
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 2));
        fa.flushMicrotasks();
        expect(input.listening, isTrue);
        expect(c.phase, VoicePhase.listening);
        expect(c.notice, isNull);
        expect(input.starts, 3);
      });
    });

    test('a microphone that keeps failing shows the trouble notice after three tries', () {
      fakeAsync((fa) {
        input.failStarts = 10;
        c.answerConsent(true);
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 10));
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.idle);
        expect(c.notice, voiceTroubleNotice);
        expect(input.starts, 4);
      });
    });

    test('words heard before the connection went are sent, then it listens again', () {
      fakeAsync((fa) {
        begin(fa);
        input.onCaption!('I am 72');
        input.drop();
        fa.flushMicrotasks();
        expect(guide.calls.last, containsPair('text', 'I am 72'));
        expect(guide.calls.last, containsPair('fromTranscript', true));
        expect(c.notice, isNull);
        expect(c.phase, VoicePhase.listening);
      });
    });

    test('a finish that fails with nothing heard just listens on; with words, sends them', () {
      fakeAsync((fa) {
        begin(fa);
        input.finishError = const VoiceFailure('stt: closed');
        input.onCaption!('');
        c.stopTalk();
        fa.flushMicrotasks();
        expect(c.notice, isNull);
        expect(c.phase, VoicePhase.listening);
        final sent = guide.calls.length;
        input.onCaption!('I am 72');
        fa.elapse(voiceEndOfTurn);
        fa.flushMicrotasks();
        expect(guide.calls, hasLength(sent + 1));
        expect(guide.calls.last, containsPair('text', 'I am 72'));
        expect(c.notice, isNull);
      });
    });

    test('a pause while the retry waits leaves the microphone closed', () {
      fakeAsync((fa) {
        input.failStarts = 1;
        c.answerConsent(true);
        fa.flushMicrotasks();
        c.pauseVoice();
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 5));
        fa.flushMicrotasks();
        expect(input.listening, isFalse);
        expect(input.starts, 1);
      });
    });
  });

  group('check-in, hands-free continuity', () {
    final now = DateTime(2026, 10, 24, 10);
    late FakeSpeechOutput output;
    late FlakyInput input;

    CheckinController make(FakeCheckinGuide guide) => CheckinController(
      guide: guide,
      input: input,
      output: output,
      store: InMemoryCheckinStore(checkins: [const CheckinEntry(kind: 'quick', date: '2026-10-23', answers: {})]),
      clock: () => now,
      voiceUsable: true,
      handsFree: true,
    );

    setUp(() {
      output = FakeSpeechOutput();
      input = FlakyInput();
    });

    test('a recognizer that ends now and then during a long quiet is always restarted', () {
      fakeAsync((fa) {
        final c = make(FakeCheckinGuide());
        c.start();
        fa.flushMicrotasks();
        for (var i = 0; i < 5; i++) {
          fa.elapse(const Duration(seconds: 12));
          input.drop();
          fa.flushMicrotasks();
          expect(c.phase, CheckinPhase.listening, reason: 'drop ${i + 1}');
        }
        expect(c.notice, isNull);
        c.dispose();
      });
    });

    test('a microphone that fails to open is tried again out of sight, and listens', () {
      fakeAsync((fa) {
        input.failStarts = 2;
        final c = make(FakeCheckinGuide());
        c.start();
        fa.flushMicrotasks();
        expect(c.phase, CheckinPhase.listening);
        fa.elapse(const Duration(seconds: 4));
        fa.flushMicrotasks();
        expect(input.listening, isTrue);
        expect(c.notice, isNull);
        c.dispose();
      });
    });

    test('words heard before the connection went are sent, then it listens again', () {
      fakeAsync((fa) {
        final guide = FakeCheckinGuide();
        final c = make(guide);
        c.start();
        fa.flushMicrotasks();
        input.onCaption!('7');
        input.drop();
        fa.flushMicrotasks();
        expect(guide.calls.last, containsPair('text', '7'));
        expect(c.notice, isNull);
        expect(c.phase, CheckinPhase.listening);
        c.dispose();
      });
    });

    test('a finish that fails with nothing heard just listens on', () {
      fakeAsync((fa) {
        final c = make(FakeCheckinGuide());
        c.start();
        fa.flushMicrotasks();
        input.finishError = const VoiceFailure('stt: closed');
        c.stopTalk();
        fa.flushMicrotasks();
        expect(c.notice, isNull);
        expect(c.phase, CheckinPhase.listening);
        c.dispose();
      });
    });
  });
}
