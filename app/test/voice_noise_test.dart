import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_client.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/http_conversation_guide.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:lifesim/voice/voice_indicator.dart';

import 'checkin_controller_test.dart' show FakeCheckinGuide;

/// A server that judges "the TV" to be someone else talking: same state back, `off_topic`.
class OffTopicGuide extends FakeConversationGuide {
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
    if (text != null && text.contains('the TV')) {
      calls.add({'action': action, 'text': text});
      return GuideTurn(state: state!, message: 'Someone else was talking.', complete: false, offTopic: true);
    }
    return super.turn(
      action: action,
      state: state,
      text: text,
      fromTranscript: fromTranscript,
      values: values,
      aiHelper: aiHelper,
      importSource: importSource,
    );
  }
}

class OffTopicCheckinGuide implements CheckinGuide {
  final inner = FakeCheckinGuide();
  @override
  Future<CheckinTurn> start({
    required String kind,
    required String localDate,
    Map<String, dynamic> previous = const {},
    QuickPlan? quick,
  }) => inner.start(kind: kind, localDate: localDate, previous: previous, quick: quick);

  @override
  Future<CheckinTurn> turn({
    required String action,
    required Map<String, dynamic> state,
    String? text,
    bool fromTranscript = false,
  }) async {
    if (text != null && text.contains('the TV')) {
      return CheckinTurn({'state': state, 'message': 'Someone else was talking.', 'off_topic': true});
    }
    return inner.turn(action: action, state: state, text: text, fromTranscript: fromTranscript);
  }
}

void main() {
  test('the server field off_topic is read; absent means false', () {
    final base = {'state': <String, dynamic>{}, 'message': 'x'};
    expect(HttpConversationGuide.parseTurn({...base, 'off_topic': true}).offTopic, isTrue);
    expect(HttpConversationGuide.parseTurn(base).offTopic, isFalse);
    expect(CheckinTurn({...base, 'off_topic': true}).offTopic, isTrue);
    expect(CheckinTurn(base).offTopic, isFalse);
  });

  group('onboarding, hands-free', () {
    late FakeConversationGuide guide;
    late FakeSpeechOutput output;
    late FakeSpeechInput input;
    late VoiceOnboardingController c;

    void begin(FakeAsync fa) {
      c = VoiceOnboardingController(guide: guide, input: input, output: output, handsFree: true);
      c.prepareVoice();
      c.answerConsent(true);
      fa.flushMicrotasks();
    }

    setUp(() {
      guide = FakeConversationGuide();
      output = FakeSpeechOutput();
      input = FakeSpeechInput();
    });

    test('a very long noisy turn cannot hold the mic open: at 30 s what was heard is sent', () {
      fakeAsync((fa) {
        begin(fa);
        expect(c.phase, VoicePhase.listening);
        // New words every second (a TV), so the end-of-turn wait never runs out.
        for (var s = 1; s <= 29; s++) {
          input.onCaption!('words $s');
          fa.elapse(const Duration(seconds: 1));
        }
        expect(c.phase, VoicePhase.listening);
        expect(guide.calls.where((x) => x['action'] == 'reply'), isEmpty);
        input
          ..transcript = 'words 30'
          ..onCaption!('words 30');
        fa.elapse(const Duration(seconds: 1));
        fa.flushMicrotasks();
        expect(guide.calls.last, containsPair('text', 'words 30'));
        c.dispose();
      });
    });

    test('nothing heard (noise gated to an empty caption) never sends and never closes the mic', () {
      fakeAsync((fa) {
        begin(fa);
        input.onCaption!(''); // what the gated input hands over for "[noise]" or "um"
        fa.elapse(const Duration(seconds: 5));
        expect(c.phase, VoicePhase.listening);
        expect(guide.calls.where((x) => x['action'] == 'reply'), isEmpty);
        c.dispose();
      });
    });

    test('off_topic: the question stays, Mochi asks once to hear it again, then listens', () {
      fakeAsync((fa) {
        guide = OffTopicGuide();
        begin(fa);
        void say(String words) {
          input
            ..transcript = words
            ..onCaption!(words);
          fa.elapse(voiceEndOfTurn);
          fa.flushMicrotasks();
        }

        say('turn up the TV');
        expect(output.spoken.last, offTopicLine);
        expect(c.mascotLine, 'How old are you?');
        expect(c.notice, offTopicLine);
        expect(c.phase, VoicePhase.listening);
        final spoken = output.spoken.length;
        say('the TV again');
        expect(output.spoken, hasLength(spoken), reason: 'asked once per question, never in a loop');
        expect(c.phase, VoicePhase.listening);
        say('I am 70');
        expect(output.spoken.last, 'I heard you are 70. Is that right?');
        expect(c.notice, isNull);
        c.dispose();
      });
    });
  });

  group('check-in, hands-free', () {
    final now = DateTime(2026, 10, 24, 10);

    CheckinController make(CheckinGuide guide, FakeSpeechInput input, FakeSpeechOutput output) => CheckinController(
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

    test('a very long noisy turn is sent at 30 s', () {
      fakeAsync((fa) {
        final guide = FakeCheckinGuide();
        final input = FakeSpeechInput();
        final c = make(guide, input, FakeSpeechOutput());
        c.start();
        fa.flushMicrotasks();
        expect(c.phase, CheckinPhase.listening);
        for (var s = 1; s <= 30; s++) {
          input
            ..transcript = 'words $s'
            ..onCaption!('words $s');
          fa.elapse(const Duration(seconds: 1));
        }
        fa.flushMicrotasks();
        expect(guide.calls.last, containsPair('text', 'words 30'));
        c.dispose();
      });
    });

    test('off_topic: same question, one "heard someone else", listening again', () {
      fakeAsync((fa) {
        final input = FakeSpeechInput();
        final output = FakeSpeechOutput();
        final c = make(OffTopicCheckinGuide(), input, output);
        c.start();
        fa.flushMicrotasks();
        final question = c.mascotLine;
        void say(String words) {
          input
            ..transcript = words
            ..onCaption!(words);
          fa.elapse(voiceEndOfTurn);
          fa.flushMicrotasks();
        }

        say('the TV news');
        expect(output.spoken.last, offTopicLine);
        expect(c.mascotLine, question);
        expect(c.phase, CheckinPhase.listening);
        final spoken = output.spoken.length;
        say('the TV again');
        expect(output.spoken, hasLength(spoken));
        expect(c.phase, CheckinPhase.listening);
        c.dispose();
      });
    });
  });

  group('"Reduce background noise" (system Mic Mode menu)', () {
    Future<void> show(WidgetTester t, {required bool noiseLink}) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ListeningNote(noiseLink: noiseLink)),
      ),
    );

    testWidgets('on an iPhone, while listening: a labelled button that opens the menu', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final calls = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('lifetwin/mic_mode'), (m) async {
        calls.add(m.method);
        return true;
      });
      final semantics = t.ensureSemantics();
      await show(t, noiseLink: true);
      final link = find.widgetWithText(TextButton, 'Reduce background noise');
      expect(link, findsOneWidget);
      expect(t.getSize(link).height, greaterThanOrEqualTo(48));
      expect(
        t.getSemantics(link),
        matchesSemantics(
          label: 'Reduce background noise',
          hint: 'Opens the iPhone Mic Mode menu. Choose Voice Isolation.',
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      await t.tap(link);
      expect(calls, ['show']);
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('not listening, or not an iPhone: only the note', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await show(t, noiseLink: false);
      expect(find.text('Reduce background noise'), findsNothing);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await show(t, noiseLink: true);
      expect(find.text('Reduce background noise'), findsNothing);
      expect(find.text('Mochi listens only on this screen.'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
