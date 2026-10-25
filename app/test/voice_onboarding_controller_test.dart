import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';

class Rig {
  Rig() {
    c = VoiceOnboardingController(guide: guide, input: input, output: output);
  }
  final guide = FakeConversationGuide();
  final input = FakeSpeechInput();
  final output = FakeSpeechOutput();
  late final VoiceOnboardingController c;
}

class HeldFinishInput extends FakeSpeechInput {
  final finished = Completer<String>();

  @override
  Future<String> finish() {
    finishes++;
    listening = false;
    return finished.future;
  }
}

class HeldCancelInput extends FakeSpeechInput {
  final cancellations = <Completer<void>>[];

  @override
  Future<void> cancel() async {
    cancels++;
    final gate = Completer<void>();
    cancellations.add(gate);
    await gate.future;
    listening = false;
  }
}

void main() {
  group('end of turn', () {
    /// Consent given and listening, inside [fa].
    Rig listening(FakeAsync fa) {
      final r = Rig();
      r.c.answerConsent(true);
      fa.flushMicrotasks();
      r.c.startTalk();
      fa.flushMicrotasks();
      expect(r.c.phase, VoicePhase.listening);
      return r;
    }

    test('the limits live in one place', () {
      expect(voiceEndOfTurn, const Duration(milliseconds: 2500));
      expect(voiceQuietClose, const Duration(seconds: 8));
      expect(VoiceOnboardingController.endOfTurn, voiceEndOfTurn);
      expect(VoiceOnboardingController.silenceLimit, voiceQuietClose);
    });

    test('after words: no send at 2.4 s of quiet, sent at 2.5 s', () {
      fakeAsync((fa) {
        final r = listening(fa);
        r.input.onCaption!('I am 70');
        fa.elapse(const Duration(milliseconds: 2400));
        expect(r.input.finishes, 0);
        expect(r.c.phase, VoicePhase.listening);
        fa.elapse(const Duration(milliseconds: 100));
        expect(r.input.finishes, 1);
        expect(r.guide.calls.last['fromTranscript'], true);
      });
    });

    test('a new partial restarts the wait, even with the same words', () {
      fakeAsync((fa) {
        final r = listening(fa);
        r.input.onCaption!('I am');
        fa.elapse(const Duration(seconds: 2));
        r.input.onCaption!('I am');
        fa.elapse(const Duration(milliseconds: 2400));
        expect(r.input.finishes, 0);
        fa.elapse(const Duration(milliseconds: 100));
        expect(r.input.finishes, 1);
      });
    });

    test('before the first word only the 8 s close applies', () {
      fakeAsync((fa) {
        final r = listening(fa);
        r.input.onCaption!(''); // nothing heard yet
        fa.elapse(const Duration(milliseconds: 7900));
        expect(r.input.finishes, 0);
        expect(r.c.phase, VoicePhase.listening);
        fa.elapse(const Duration(milliseconds: 100));
        expect(r.input.finishes, 1);
      });
    });

    test('a tap still sends at once', () {
      fakeAsync((fa) {
        final r = listening(fa);
        r.input.onCaption!('I am 70');
        r.c.stopTalk();
        fa.flushMicrotasks();
        expect(r.input.finishes, 1);
        fa.elapse(const Duration(seconds: 5));
        expect(r.input.finishes, 1, reason: 'the end-of-turn wait was dropped');
      });
    });
  });

  test('happy path: consent, ask, talk, confirm, done', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    expect(r.c.mascotLine, 'How old are you?');
    expect(r.output.spoken, ['How old are you?']);
    expect(r.c.phase, VoicePhase.idle);

    r.input.captions = ['I am', 'I am 70'];
    await r.c.startTalk();
    expect(r.c.phase, VoicePhase.listening);
    expect(r.c.caption, 'I am 70');
    await r.c.stopTalk();
    expect(r.guide.calls.last['fromTranscript'], true);
    expect(r.guide.calls.last['text'], 'I am 70');
    expect(r.c.confirming, true);
    expect(r.output.spoken.last, contains('70'));

    await r.c.confirm();
    expect(r.c.phase, VoicePhase.done);
    expect(r.c.confirmedProfile, {'age': 70});
  });

  test('state is sent back to the server unchanged each turn', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    final first = r.c.state;
    await r.c.submitTyped('70');
    expect(r.guide.calls.last['state'], first);
    expect(r.guide.calls.last['fromTranscript'], false);
  });

  test('pressing Talk while the mascot speaks stops playback first', () async {
    final r = Rig();
    r.output.holdSpeech = true;
    final starting = r.c.answerConsent(true);
    await Future<void>.delayed(Duration.zero);
    expect(r.c.phase, VoicePhase.speaking);
    await r.c.startTalk();
    expect(r.output.stops, 1);
    expect(r.c.phase, VoicePhase.listening);
    await starting;
    expect(r.c.phase, VoicePhase.listening); // the old speech ending must not undo listening
  });

  test('mic denied switches to typing and keeps the conversation state', () async {
    final r2 = Rig();
    await r2.c.answerConsent(true);
    final state = r2.c.state;
    r2.input.startError = const MicDeniedException();
    await r2.c.startTalk();
    expect(r2.c.typing, true);
    expect(r2.c.phase, VoicePhase.idle);
    await r2.c.submitTyped('70'); // typing continues the same conversation
    expect(r2.guide.calls.last['state'], state);
    expect(r2.c.confirming, true);
  });

  test('a connection lost while listening ends listening with the voice trouble notice', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    await r.c.startTalk();
    expect(r.c.phase, VoicePhase.listening);
    r.input.drop();
    expect(r.c.phase, VoicePhase.idle);
    expect(r.c.notice, voiceTroubleNotice);
    expect(r.c.typing, false, reason: 'voice stays on; Talk can be tried again');
  });

  test('voice_unavailable on the microphone path falls back to typing', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    r.input.startError = const VoiceUnavailableException();
    await r.c.startTalk();
    expect(r.c.typing, true);
    expect(r.c.voiceUsable, false);
    expect(r.c.notice, voiceOffNotice);
    await r.c.setTyping(false); // cannot switch back to voice
    expect(r.c.typing, true);
  });

  test('after a 503, a token is retried in the background and voice is back on the next turn', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    r.input.startError = const VoiceUnavailableException();
    r.input.warmUpError = const VoiceUnavailableException(); // still down
    final warmUps = r.input.warmUps;
    await r.c.startTalk();
    expect(r.c.notice, voiceOffNotice);
    expect(r.c.voiceUsable, false);
    expect(r.input.warmUps, warmUps + 1, reason: 'retried in the background at once');
    await r.c.submitTyped('70');
    expect(r.c.typing, true, reason: 'the retry failed: still typing');
    expect(r.c.voiceUsable, false);

    r.input.startError = null;
    r.input.warmUpError = null; // the provider is back
    final spoken = r.output.spoken.length;
    await r.c.submitTyped('no');
    expect(r.c.voiceUsable, true);
    expect(r.c.typing, false);
    expect(r.output.spoken.length, spoken + 1, reason: 'the next question is spoken again');
    await r.c.startTalk();
    expect(r.c.phase, VoicePhase.listening);
    await r.c.cancelTalk();
  });

  test('voice_unavailable while speaking falls back to typing and keeps the line', () async {
    final r = Rig();
    r.output.speakError = const VoiceUnavailableException();
    await r.c.answerConsent(true);
    expect(r.c.typing, true);
    expect(r.c.mascotLine, 'How old are you?');
    expect(r.c.notice, voiceOffNotice);
    expect(r.c.phase, VoicePhase.idle);
  });

  test('a speaking error keeps voice on and shows the words', () async {
    final r = Rig();
    r.output.speakError = const VoiceFailure('socket');
    await r.c.answerConsent(true);
    expect(r.c.typing, false);
    expect(r.c.notice, speakTroubleNotice);
    expect(r.c.phase, VoicePhase.idle);
  });

  test('empty transcript asks again and sends nothing', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    r.input.transcript = '   ';
    await r.c.startTalk();
    await r.c.stopTalk();
    expect(r.c.notice, emptyTranscriptNotice);
    expect(r.c.phase, VoicePhase.idle);
    expect(r.guide.calls.length, 1); // only "start"
  });

  test('duplicate taps: second Talk press and double Yes do nothing extra', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    await Future.wait([r.c.startTalk(), r.c.startTalk()]);
    expect(r.input.starts, 1);
    await r.c.stopTalk();
    await r.c.stopTalk();
    expect(r.input.finishes, 1);

    expect(r.c.confirming, true);
    final calls = r.guide.calls.length;
    await Future.wait([r.c.confirm(), r.c.confirm()]);
    expect(r.guide.calls.length, calls + 1);
  });

  test('no network keeps state and offers a retry', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    final state = r.c.state;
    r.guide.failNext = true;
    await r.c.submitTyped('70');
    expect(r.c.notice, noNetworkNotice);
    expect(r.c.canRetry, true);
    expect(r.c.state, state);
    expect(r.c.phase, VoicePhase.idle);
    await r.c.retry();
    expect(r.c.confirming, true);
    expect(r.c.notice, isNull);
  });

  test('first turn failing can be retried', () async {
    final r = Rig();
    r.guide.failNext = true;
    await r.c.answerConsent(true);
    expect(r.c.turn, isNull);
    expect(r.c.canRetry, true);
    await r.c.retry();
    expect(r.c.mascotLine, 'How old are you?');
  });

  test('first turn failing: an answer typed meanwhile starts the talk instead of being refused', () async {
    final r = Rig();
    r.guide.failNext = true;
    await r.c.answerConsent(false);
    expect(r.c.turn, isNull);
    r.guide.failNext = true;
    await r.c.submitTyped('71');
    expect(r.guide.calls.map((c) => c['action']), ['start', 'start']);
    expect(r.c.notice, noNetworkNotice);
    await r.c.retry();
    expect(r.guide.calls.last['action'], 'start');
    expect(r.c.mascotLine, 'How old are you?');
    await r.c.skip();
    expect(r.guide.calls.last['action'], 'skip');
  });

  test('a network notice that cannot be said aloud stays on screen with Try again', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    r.guide.failNext = true;
    r.output.speakError = const VoiceFailure('token: connection refused');
    await r.c.submitTyped('70');
    expect(r.c.notice, noNetworkNotice);
    expect(r.c.canRetry, isTrue);
    r.output.speakError = const VoiceUnavailableException();
    r.guide.failNext = true;
    await r.c.retry();
    expect(r.c.notice, noNetworkNotice);
    expect(r.c.canRetry, isTrue);
  });

  test('once done, Go back reopens the last answer so it can be changed', () async {
    final r = Rig();
    await r.c.answerConsent(false);
    await r.c.submitTyped('70');
    await r.c.confirm();
    expect(r.c.phase, VoicePhase.done);
    expect(r.c.canGoBack, isTrue);
    await r.c.goBack();
    expect(r.guide.calls.last['text'], 'go back');
    expect(r.c.phase, VoicePhase.idle);
  });

  test('Type instead keeps the conversation; voice declined starts in typing', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    await r.c.submitTyped('70');
    await r.c.setTyping(true);
    expect(r.c.confirming, true);
    expect(r.c.canHearAgain, false);
    await r.c.setTyping(false);
    expect(r.c.typing, false);

    final r2 = Rig();
    await r2.c.answerConsent(false);
    expect(r2.c.typing, true);
    expect(r2.output.spoken, isEmpty);
  });

  test('Type instead while listening closes the microphone', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    await r.c.startTalk();
    await r.c.setTyping(true);
    expect(r.input.cancels, 1);
    expect(r.c.phase, VoicePhase.idle);
  });

  test('Hear it again replays from memory', () async {
    final r = Rig();
    await r.c.answerConsent(true);
    await r.c.hearAgain();
    expect(r.output.replays, 1);
    expect(r.output.spoken.length, 1);
    expect(r.c.phase, VoicePhase.idle);
  });

  test('Apple Health answers are sent as an import and the conversation moves on', () async {
    final r = Rig();
    await r.c.answerConsent(false);
    expect(await r.c.importHealth({'weight_kg': 68.0, 'sleep_hours': 7.5}), isTrue);
    final call = r.guide.calls.last;
    expect(call['action'], 'import');
    expect(call['values'], {'weight_kg': 68.0, 'sleep_hours': 7.5});
    expect(r.c.confirmedProfile, {'weight_kg': 68.0, 'sleep_hours': 7.5});
    expect(r.c.mascotLine, contains('Health answers'));
    expect(r.c.phase, VoicePhase.idle);
  });

  test('Apple Health answers checked before the talk are added when it starts', () async {
    final r = Rig();
    expect(await r.c.importHealth({'weight_kg': 68.0}), isTrue); // from the Room: queued
    expect(r.guide.calls, isEmpty);
    expect(r.c.hasPendingHealth, isTrue);
    await r.c.answerConsent(false);
    expect(r.guide.calls.map((c) => c['action']), ['start', 'import']);
    expect(r.guide.calls.last['values'], {'weight_kg': 68.0});
    expect(r.c.confirmedProfile, {'weight_kg': 68.0});
    expect(r.c.hasPendingHealth, isFalse);
  });

  test('Health import waits while an answer is being confirmed, and says why', () async {
    final r = Rig();
    await r.c.answerConsent(false);
    await r.c.submitTyped('70');
    expect(r.c.confirming, isTrue);
    final before = r.guide.calls.length;
    expect(await r.c.importHealth({'weight_kg': 68.0}), isFalse, reason: 'nothing was taken');
    expect(r.guide.calls.length, before);
    expect(r.c.notice, healthWaitNotice);
  });

  test('an empty Health result sends nothing but says so', () async {
    final r = Rig();
    await r.c.answerConsent(false);
    final before = r.guide.calls.length;
    await r.c.importHealth({});
    expect(r.guide.calls.length, before);
    expect(r.c.notice, healthNoneNotice);
  });

  test('an empty Health result after the last question adds no "keep asking" notice', () async {
    final r = Rig();
    await r.c.answerConsent(false);
    await r.c.submitTyped('70');
    await r.c.confirm();
    expect(r.c.phase, VoicePhase.done);
    final before = r.guide.calls.length;
    expect(await r.c.importHealth({}), isFalse);
    expect(r.guide.calls.length, before);
    expect(r.c.notice, isNull);
    expect(r.c.phase, VoicePhase.done);
  });

  test('a rejected Health import shows the server reason and keeps the conversation', () async {
    final r = Rig();
    await r.c.answerConsent(false);
    final line = r.c.mascotLine;
    r.guide.rejectNext = 'Please check these answers: height. Then try again.';
    await r.c.importHealth({'height_cm': 17300});
    expect(r.c.notice, "I couldn't add your Apple Health answers. Please check these answers: height. Then try again.");
    expect(r.c.canRetry, isFalse);
    expect(r.c.mascotLine, line);
    expect(r.c.phase, VoicePhase.idle);
  });

  test('AI helper consent is sent with every turn and can be turned off', () async {
    final r = Rig();
    await r.c.answerConsent(false, aiHelper: true);
    expect(r.guide.calls.last['aiHelper'], isTrue);
    await r.c.setAiHelper(false);
    await r.c.submitTyped('70');
    expect(r.guide.calls.last['aiHelper'], isFalse);
  });

  group('Delete my data resets the conversation boundary', () {
    for (final source in ['apple_health', 'document']) {
      test('queued $source values cannot survive reset and a new consent/start', () async {
        final r = Rig();
        addTearDown(r.c.dispose);
        if (source == 'apple_health') {
          await r.c.importHealth({'moderate_recreation_min_week': 30});
        } else {
          await r.c.importDocument({'height_cm': 170});
        }
        expect(r.c.hasPendingHealth, isTrue);
        expect(r.c.lastImport, isNotNull);
        r.c.resetConversation();
        expect(r.c.hasPendingHealth, isFalse);
        expect(r.c.lastImport, isNull);
        expect(r.c.phase, VoicePhase.consent);
        await r.c.answerConsent(false);
        expect(r.guide.calls.map((call) => call['action']), ['start']);
        expect(r.c.confirmedProfile, isEmpty);
      });
    }

    test('a completed session restarts at consent without profile or prior helper choice', () async {
      final r = Rig();
      addTearDown(r.c.dispose);
      await r.c.answerConsent(false, aiHelper: true);
      await r.c.submitTyped('70');
      await r.c.confirm();
      expect(r.c.phase, VoicePhase.done);
      r.c.resetConversation();
      expect(r.c.phase, VoicePhase.consent);
      expect(r.c.aiHelper, isFalse);
      expect(r.c.confirmedProfile, isEmpty);
      await r.c.answerConsent(false);
      expect(r.guide.calls.last['action'], 'start');
      expect(r.guide.calls.last['state'], isNull);
      expect(r.guide.calls.last['aiHelper'], isFalse);
    });

    for (final outcome in ['success', 'failure', 'rejection']) {
      test('an in-flight import $outcome cannot restore deleted state or affect a new request', () async {
        final r = Rig();
        addTearDown(r.c.dispose);
        await r.c.answerConsent(false);
        final gate = r.guide.gate = Completer<void>();
        final oldImport = r.c.importHealth({'moderate_recreation_min_week': 30});
        await Future<void>.delayed(Duration.zero);
        expect(r.c.phase, VoicePhase.interpreting);
        r.c.resetConversation();
        r.guide.gate = null;
        await r.c.answerConsent(false);
        final fresh = r.c.turn;
        expect(fresh, isNotNull);
        if (outcome == 'failure') r.guide.failNext = true;
        if (outcome == 'rejection') r.guide.rejectNext = 'old rejected value';
        gate.complete();
        expect(await oldImport, isFalse);
        expect(identical(r.c.turn, fresh), isTrue);
        expect(r.c.confirmedProfile, isEmpty);
        expect(r.c.notice, isNull);
        expect(r.c.lastImport, isNull);
        expect(r.c.canRetry, isFalse);
        expect(r.c.phase, VoicePhase.idle);
      });
    }

    for (final failure in [false, true]) {
      test('a pending microphone finish after reset cannot submit old text (failure=$failure)', () async {
        final guide = FakeConversationGuide();
        final input = HeldFinishInput();
        final c = VoiceOnboardingController(guide: guide, input: input, output: FakeSpeechOutput());
        addTearDown(c.dispose);
        await c.answerConsent(true);
        await c.startTalk();
        final oldFinish = c.stopTalk();
        await Future<void>.delayed(Duration.zero);
        expect(input.finishes, 1);
        c.resetConversation();
        await c.answerConsent(false);
        final count = guide.calls.length;
        if (failure) {
          input.finished.completeError(const VoiceUnavailableException());
        } else {
          input.finished.complete('I am 70');
        }
        await oldFinish;
        expect(guide.calls.length, count);
        expect(c.confirmedProfile, isEmpty);
        expect(c.caption, isEmpty);
        expect(c.notice, isNull);
        expect(c.phase, VoicePhase.idle);
      });
    }

    test('old microphone callbacks and held speech cannot leave consent or restart listening', () async {
      final r = Rig();
      addTearDown(r.c.dispose);
      await r.c.answerConsent(true);
      await r.c.startTalk();
      final oldCaption = r.input.onCaption!;
      final oldDrop = r.input.onDropped!;
      r.c.resetConversation();
      await Future<void>.delayed(Duration.zero);
      oldCaption('deleted words');
      oldDrop(const VoiceFailure('old connection'));
      expect(r.input.listening, isFalse);
      expect(r.c.caption, isEmpty);
      expect(r.c.phase, VoicePhase.consent);
      expect(r.c.notice, isNull);
      r.output.holdSpeech = true;
      final speaking = r.c.answerConsent(true);
      await Future<void>.delayed(Duration.zero);
      expect(r.c.phase, VoicePhase.speaking);
      r.c.resetConversation();
      await speaking;
      expect(r.output.speaking, isFalse);
      expect(r.c.phase, VoicePhase.consent);
      expect(r.c.turn, isNull);
    });

    test('reset drops a failed-request retry instead of resending deleted answers', () async {
      final r = Rig();
      addTearDown(r.c.dispose);
      await r.c.answerConsent(false);
      r.guide.failNext = true;
      await r.c.submitTyped('70');
      expect(r.c.canRetry, isTrue);
      r.c.resetConversation();
      expect(r.c.canRetry, isFalse);
      final count = r.guide.calls.length;
      await r.c.retry();
      expect(r.guide.calls.length, count);
      expect(r.c.phase, VoicePhase.consent);
    });

    for (final granted in [false, true]) {
      test('an old microphone permission answer cannot change the new session (granted=$granted)', () async {
        final r = Rig();
        addTearDown(r.c.dispose);
        await r.c.answerConsent(true);
        final permission = r.input.permission = Completer<bool>();
        final oldStart = r.c.startTalk();
        await Future<void>.delayed(Duration.zero);
        r.c.resetConversation();
        await r.c.answerConsent(false);
        permission.complete(granted);
        await oldStart;
        expect(r.input.starts, 0);
        expect(r.input.listening, isFalse);
        expect(r.c.phase, VoicePhase.idle);
        expect(r.c.typing, isTrue);
        expect(r.c.voiceUsable, isFalse);
        expect(r.c.notice, isNull);
      });
    }

    test('an old response cannot clear a fresh pending request or accept an extra reply', () async {
      final r = Rig();
      addTearDown(r.c.dispose);
      await r.c.answerConsent(false);
      final oldGate = r.guide.gate = Completer<void>();
      final oldReply = r.c.submitTyped('70');
      await Future<void>.delayed(Duration.zero);
      r.c.resetConversation();
      final freshGate = r.guide.gate = Completer<void>();
      final freshStart = r.c.answerConsent(false);
      await Future<void>.delayed(Duration.zero);
      oldGate.complete();
      await oldReply;
      expect(r.c.phase, VoicePhase.interpreting);
      expect(r.c.turn, isNull);
      final count = r.guide.calls.length;
      await r.c.submitTyped('deleted reply');
      expect(r.guide.calls.length, count);
      freshGate.complete();
      await freshStart;
      expect(r.c.phase, VoicePhase.idle);
      expect(r.c.confirmedProfile, isEmpty);
    });

    test('repeated resets wait for earlier audio cleanup before starting fresh voice', () async {
      final guide = FakeConversationGuide();
      final input = HeldCancelInput();
      final output = FakeSpeechOutput();
      final c = VoiceOnboardingController(guide: guide, input: input, output: output);
      addTearDown(c.dispose);
      c.resetConversation();
      c.resetConversation();
      expect(input.cancellations, hasLength(2));
      final freshStart = c.answerConsent(true);
      input.cancellations[1].complete();
      await Future<void>.delayed(Duration.zero);
      expect(guide.calls, isEmpty);
      expect(output.spoken, isEmpty);
      expect(c.phase, VoicePhase.consent);
      input.cancellations[0].complete();
      await freshStart;
      expect(guide.calls.single['action'], 'start');
      expect(output.spoken, ['How old are you?']);
      await c.startTalk();
      expect(input.listening, isTrue);
    });
  });
}
