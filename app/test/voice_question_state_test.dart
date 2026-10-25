// Owner report: "switching between typing and speaking gives an infinite loop where the agent is
// confused what question it is doing." One current question, marked done the moment it is
// answered; a clear start and a clear finish, in either mode.
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

/// A microphone whose [finish] can be held, as a real recognizer that is still sending its last words.
class HeldInput extends FakeSpeechInput {
  Completer<String>? hold;

  @override
  Future<String> finish() {
    final h = hold;
    if (h == null) return super.finish();
    finishes++;
    listening = false;
    return h.future;
  }
}

/// Three questions in order. A fitting answer is saved and the next question asked; anything
/// else asks the same question again, as the server does with an answer it can't place.
class ThreeQuestions implements ConversationGuide {
  final calls = <Map<String, dynamic>>[];
  Completer<void>? gate;

  static const fields = ['age', 'sex', 'smoking_status'];
  static const asks = {
    'age': 'How old are you?',
    'sex': 'Are you female or male?',
    'smoking_status': 'Do you smoke?',
  };
  static final fits = {
    'age': RegExp(r'\d'),
    'sex': RegExp(r'\b(fe)?male\b'),
    'smoking_status': RegExp(r'smoke'),
  };

  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    bool aiHelper = false,
    String? importSource,
  }) async {
    calls.add({'action': action, 'text': text, 'field': state?['current_field']});
    if (gate != null) await gate!.future;
    final confirmed = Map<String, dynamic>.from((state?['confirmed_profile'] as Map?) ?? const {});
    final field = state?['current_field'] as String?;
    if (action == 'start') return _ask('age', confirmed, 'Hello! I am Mochi.');
    if (action == 'reply' && text == 'go back') {
      final last = fields.lastWhere(confirmed.containsKey);
      confirmed.remove(last);
      return _ask(last, confirmed, "Okay, let's go back.");
    }
    if (action == 'reply' && field != null && fits[field]!.hasMatch(text ?? '')) {
      confirmed[field] = text;
      final next = fields.where((f) => !confirmed.containsKey(f)).firstOrNull;
      if (next == null) {
        return GuideTurn(
          state: {'phase': 'ready', 'current_field': null, 'confirmed_profile': confirmed},
          message: 'All done. Thank you!',
          complete: true,
          mascotState: 'celebrating',
          providerStatus: 'not_configured',
        );
      }
      return _ask(next, confirmed, 'Got it.');
    }
    return _ask(field ?? 'age', confirmed, 'Sorry, I did not catch that.');
  }

  GuideTurn _ask(String field, Map<String, dynamic> confirmed, String lead) => GuideTurn(
    state: {'phase': 'asking', 'current_field': field, 'confirmed_profile': confirmed},
    message: '$lead ${asks[field]}',
    complete: false,
    mascotState: 'asking',
    providerStatus: 'not_configured',
  );
}

void main() {
  group('onboarding: one current question', () {
    late ThreeQuestions guide;
    late FakeSpeechOutput output;
    late HeldInput input;
    late VoiceOnboardingController c;

    setUp(() {
      guide = ThreeQuestions();
      output = FakeSpeechOutput();
      input = HeldInput();
      c = VoiceOnboardingController(guide: guide, input: input, output: output, handsFree: true);
    });

    void begin(FakeAsync fa) {
      c.answerConsent(true);
      fa.flushMicrotasks();
    }

    void say(FakeAsync fa, String words) {
      input.transcript = words;
      input.onCaption!(words);
      fa.elapse(voiceEndOfTurn);
      fa.flushMicrotasks();
    }

    void run(FakeAsync fa, Future<void> Function() action) {
      action();
      fa.flushMicrotasks();
    }

    test('repro: back to voice after a typed answer says the open question, not the old one', () {
      fakeAsync((fa) {
        begin(fa);
        expect(output.spoken, ['Hello! I am Mochi. How old are you?']);
        run(fa, () => c.setTyping(true));
        run(fa, () => c.submitTyped('70'));
        expect(c.mascotLine, 'Got it. Are you female or male?');
        run(fa, () => c.setTyping(false));
        // Before the fix: the last audio (the age question) was replayed while the screen asked about sex.
        expect(output.replays, 0);
        expect(output.spoken.last, 'Got it. Are you female or male?');
        expect(c.phase, VoicePhase.listening);
        say(fa, 'female');
        expect(guide.calls.last, {'action': 'reply', 'text': 'female', 'field': 'sex'});
      });
    });

    test('repro: a spoken answer still finishing is dropped once a typed one was sent', () {
      fakeAsync((fa) {
        begin(fa);
        input.hold = Completer<String>();
        input.onCaption!('I am 70');
        fa.elapse(voiceEndOfTurn);
        fa.flushMicrotasks();
        expect(c.phase, VoicePhase.interpreting);
        run(fa, () => c.setTyping(true));
        run(fa, () => c.submitTyped('70'));
        expect(c.state!['current_field'], 'sex');
        final sent = guide.calls.length;
        input.hold!.complete('I am 70');
        fa.flushMicrotasks();
        // Before the fix: "I am 70" was sent again, as the answer to "female or male?".
        expect(guide.calls.length, sent);
        expect(c.state!['current_field'], 'sex');
        expect(c.notice, isNull);
      });
    });

    test('a late caption or end-of-turn timer from a closed listen never sends', () {
      fakeAsync((fa) {
        begin(fa);
        final old = input.onCaption!;
        input.onCaption!('I am');
        run(fa, () => c.setTyping(true));
        old('I am 70');
        expect(c.caption, '');
        run(fa, () => c.setTyping(false));
        input.transcript = '';
        fa.elapse(voiceEndOfTurn * 2);
        fa.flushMicrotasks();
        expect(input.finishes, 0);
        expect(guide.calls.map((e) => e['action']), ['start']);
        expect(c.phase, VoicePhase.listening);
      });
    });

    test('an answer is marked done as it is sent; switching mode during the reply resends nothing', () {
      fakeAsync((fa) {
        begin(fa);
        expect(c.questionNumber, 1);
        expect(c.savedNumber, isNull);
        run(fa, () => c.setTyping(true));
        guide.gate = Completer<void>();
        run(fa, () => c.submitTyped('70'));
        expect(c.phase, VoicePhase.interpreting);
        expect(c.savedNumber, 1, reason: 'marked done before the reply');
        expect(c.questionNumber, 2);
        final starts = input.starts;
        run(fa, () => c.setTyping(false));
        run(fa, () => c.setTyping(true));
        run(fa, () => c.setTyping(false));
        expect(input.starts, starts, reason: 'no listening while the reply is on its way');
        guide.gate!.complete();
        guide.gate = null;
        fa.flushMicrotasks();
        expect(guide.calls.map((e) => e['action']), ['start', 'reply']);
        expect(output.spoken.where((s) => s.contains('female or male')).length, 1);
        expect(c.phase, VoicePhase.listening);
        expect(c.savedNumber, 1, reason: '"Question 1 saved" stays with question 2');
        expect(c.questionNumber, 2);
      });
    });

    test('an answer the reply does not take is not marked done', () {
      fakeAsync((fa) {
        begin(fa);
        say(fa, 'blue');
        expect(c.state!['current_field'], 'age');
        expect(c.savedNumber, isNull);
        expect(c.questionNumber, 1);
      });
    });

    test('flipping between typing and voice never resends, rewinds or re-asks a done question', () {
      fakeAsync((fa) {
        begin(fa);
        say(fa, 'I am 70');
        for (var i = 0; i < 4; i++) {
          run(fa, () => c.setTyping(true));
          run(fa, () => c.setTyping(false));
          fa.elapse(const Duration(seconds: 1));
        }
        run(fa, () => c.setTyping(true));
        run(fa, () => c.submitTyped('male'));
        run(fa, () => c.setTyping(false));
        expect(guide.calls.map((e) => e['field']), [null, 'age', 'sex']);
        expect(output.spoken.where((s) => s.contains('How old')).length, 1);
        expect(c.state!['current_field'], 'smoking_status');
        expect(output.spoken.last, 'Got it. Do you smoke?');
      });
    });

    test('starts once: the opening and first question are said a single time', () {
      fakeAsync((fa) {
        begin(fa);
        c.resumeVoice();
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 5));
        c.resumeVoice();
        fa.flushMicrotasks();
        expect(output.spoken, ['Hello! I am Mochi. How old are you?']);
        expect(input.starts, 1);
      });
    });

    test('resumed: a question that came while out of sight is said once on return, then it listens', () {
      fakeAsync((fa) {
        begin(fa);
        input.onCaption!('I am 70');
        guide.gate = Completer<void>();
        fa.elapse(voiceEndOfTurn);
        fa.flushMicrotasks();
        run(fa, c.pauseVoice);
        guide.gate!.complete();
        guide.gate = null;
        fa.flushMicrotasks();
        expect(output.spoken.length, 1, reason: 'nothing is said out of sight');
        c.resumeVoice();
        fa.flushMicrotasks();
        expect(output.spoken.last, 'Got it. Are you female or male?');
        expect(c.phase, VoicePhase.listening);
        c.resumeVoice();
        fa.flushMicrotasks();
        expect(output.spoken.where((s) => s.contains('female or male')).length, 1);
      });
    });

    test('ends clean: one closing line, the microphone closes and stays closed', () {
      fakeAsync((fa) {
        begin(fa);
        say(fa, 'I am 70');
        say(fa, 'female');
        run(fa, () => c.setTyping(true));
        run(fa, () => c.submitTyped('I never smoke'));
        run(fa, () => c.setTyping(false));
        expect(c.phase, VoicePhase.done);
        final starts = input.starts;
        final spoken = output.spoken.length;
        c.resumeVoice();
        run(fa, c.stopSpeaking);
        fa.elapse(const Duration(minutes: 2));
        fa.flushMicrotasks();
        expect(input.listening, isFalse);
        expect(input.starts, starts);
        expect(output.spoken.length, spoken);
        expect(output.replays, 0);
        expect(c.phase, VoicePhase.done);
        expect(c.questionNumber, isNull);
      });
    });

    test('ends clean by voice: the closing line is said once and nothing listens', () {
      fakeAsync((fa) {
        begin(fa);
        say(fa, 'I am 70');
        say(fa, 'female');
        say(fa, 'I used to smoke');
        expect(c.phase, VoicePhase.done);
        expect(output.spoken.last, 'All done. Thank you!');
        expect(output.spoken.where((s) => s == 'All done. Thank you!').length, 1);
        final starts = input.starts;
        fa.elapse(const Duration(minutes: 2));
        c.resumeVoice();
        fa.flushMicrotasks();
        expect(input.starts, starts);
        expect(input.listening, isFalse);
      });
    });

    test('Go back is the one way a done question comes back', () {
      fakeAsync((fa) {
        begin(fa);
        say(fa, 'I am 70');
        run(fa, c.goBack);
        expect(c.state!['current_field'], 'age');
        expect(c.savedNumber, isNull);
        expect(c.questionNumber, 1);
      });
    });
  });

  group('check-in: one current question', () {
    final now = DateTime(2026, 10, 24, 10);
    late FakeCheckinGuide guide;
    late FakeSpeechOutput output;
    late HeldInput input;
    late CheckinController c;

    setUp(() {
      guide = FakeCheckinGuide();
      output = FakeSpeechOutput();
      input = HeldInput();
      c = CheckinController(
        guide: guide,
        input: input,
        output: output,
        store: InMemoryCheckinStore(checkins: [const CheckinEntry(kind: 'quick', date: '2026-10-23', answers: {})]),
        clock: () => now,
        voiceUsable: true,
        handsFree: true,
      );
    });

    void begin(FakeAsync fa) {
      c.start();
      fa.flushMicrotasks();
    }

    void say(FakeAsync fa, String words) {
      input.transcript = words;
      input.onCaption!(words);
      fa.elapse(voiceEndOfTurn);
      fa.flushMicrotasks();
    }

    void run(FakeAsync fa, Future<void> Function() action) {
      action();
      fa.flushMicrotasks();
    }

    const sitting = 'Got it. About how many hours did you spend sitting yesterday?';

    test('repro: back to voice after typed answers says the open question, not the old one', () {
      fakeAsync((fa) {
        begin(fa);
        expect(output.spoken, ['How did you sleep last night?']);
        run(fa, () => c.setTyping(true));
        run(fa, () => c.submitTyped('7'));
        run(fa, () => c.submitTyped('yes'));
        expect(c.mascotLine, sitting);
        run(fa, () => c.setTyping(false));
        expect(output.replays, 0);
        expect(output.spoken.last, sitting);
        expect(c.phase, CheckinPhase.listening);
      });
    });

    test('repro: a late caption from a closed listen neither shows nor sends', () {
      fakeAsync((fa) {
        begin(fa);
        final old = input.onCaption!;
        run(fa, () => c.setTyping(true));
        old('7 hours');
        expect(c.caption, '');
        run(fa, () => c.setTyping(false));
        input.transcript = '';
        fa.elapse(voiceEndOfTurn * 2);
        fa.flushMicrotasks();
        expect(input.finishes, 0);
        expect(guide.calls.map((e) => e['action']), ['start']);
      });
    });

    test('a spoken answer still finishing is dropped once a typed one was sent', () {
      fakeAsync((fa) {
        begin(fa);
        input.hold = Completer<String>();
        input.onCaption!('7 hours');
        fa.elapse(voiceEndOfTurn);
        fa.flushMicrotasks();
        run(fa, () => c.setTyping(true));
        run(fa, () => c.submitTyped('8'));
        final sent = guide.calls.length;
        input.hold!.complete('7 hours');
        fa.flushMicrotasks();
        expect(guide.calls.length, sent);
        expect(c.mascotLine, 'I heard 8. Is that right?');
      });
    });

    test('an answer is marked done as it is sent; switching mode during the reply resends nothing', () {
      fakeAsync((fa) {
        begin(fa);
        say(fa, '7');
        expect(c.confirming, isTrue);
        expect(c.savedNumber, isNull, reason: 'read back, not done yet');
        run(fa, () => c.setTyping(true));
        guide.gate = Completer<void>();
        run(fa, () => c.submitTyped('yes'));
        expect(c.savedNumber, 1);
        expect(c.questionNumber!.$1, 2);
        final starts = input.starts;
        run(fa, () => c.setTyping(false));
        run(fa, () => c.setTyping(true));
        run(fa, () => c.setTyping(false));
        expect(input.starts, starts);
        guide.gate!.complete();
        guide.gate = null;
        fa.flushMicrotasks();
        expect(guide.calls.map((e) => e['text']).toList(), [null, '7', 'yes']);
        expect(output.spoken.where((s) => s == sitting).length, 1);
        expect(c.phase, CheckinPhase.listening);
        expect(c.savedNumber, 1);
      });
    });

    test('starts once, and ends clean: one closing line, then nothing listens', () {
      fakeAsync((fa) {
        begin(fa);
        c.resumeVoice();
        fa.flushMicrotasks();
        expect(output.spoken, ['How did you sleep last night?']);
        say(fa, '7');
        say(fa, 'yes');
        run(fa, () => c.setTyping(true));
        run(fa, () => c.submitTyped('6'));
        run(fa, () => c.setTyping(false));
        say(fa, 'yes');
        expect(c.turn!.complete, isTrue);
        expect(c.phase, CheckinPhase.done);
        expect(output.spoken.where((s) => s.startsWith("Got it. That's all")).length, 1);
        expect(output.spoken.where((s) => s == 'How did you sleep last night?').length, 1);
        final starts = input.starts;
        final spoken = output.spoken.length;
        run(fa, () => c.setTyping(true));
        run(fa, () => c.setTyping(false));
        c.resumeVoice();
        fa.elapse(const Duration(minutes: 2));
        fa.flushMicrotasks();
        expect(input.starts, starts);
        expect(input.listening, isFalse);
        expect(output.spoken.length, spoken);
        expect(output.replays, 0);
        expect(c.questionNumber, isNull);
      });
    });
  });
}
