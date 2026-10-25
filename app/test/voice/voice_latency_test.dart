import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/voice/cartesia_speech.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/voice_log.dart';

import 'engine_fakes.dart';

/// The two waits the person feels in a hands-free turn, measured from the `[hf]` log with the
/// real Cartesia input and output on fake sockets that answer at once (no network), so what
/// is left is the app's own time:
/// - the end of Mochi's line to the microphone being live;
/// - the end of the person's speech to Mochi starting to answer.
/// The end-of-turn wait ([voiceEndOfTurn], 2.5 s) is a chosen pause, reported apart.
void main() {
  test('hands-free turn latencies (no network)', () async {
    voiceEvents.clear();
    final sockets = Sockets();
    final rec = FakeRecorder();
    final tokens = TokenServer().provider;
    final handled = <FakeSocket, int>{};
    // Cartesia stand-in: TTS answers each request with audio and done; STT answers each
    // finalize with its flush.
    final cartesia = Timer.periodic(const Duration(milliseconds: 2), (_) {
      for (final s in sockets.made) {
        final texts = s.texts;
        for (var i = handled[s] ?? 0; i < texts.length; i++) {
          final t = texts[i];
          if (s.uri.path.contains('tts') && t.contains('transcript')) {
            final id = (jsonDecode(t) as Map)['context_id'];
            s.reply({'context_id': id, 'data': base64Encode(loudChunk())});
            s.reply({'context_id': id, 'type': 'done', 'done': true});
          } else if (t == 'finalize') {
            s.reply({'type': 'flush_done'});
          }
        }
        handled[s] = texts.length;
      }
    });
    final input = CartesiaSpeechInput(tokens: tokens, recorder: rec, connect: sockets.connect);
    final output = CartesiaSpeechOutput(tokens: tokens, player: FakePlayer(), connect: sockets.connect);
    final c = VoiceOnboardingController(guide: FakeConversationGuide(), input: input, output: output, handsFree: true);
    addTearDown(() {
      cartesia.cancel();
      c.dispose();
    });

    DateTime at(String source, String name, {DateTime? after}) => voiceEvents
        .firstWhere(
          (e) => e.source == source && e.name == name && (after == null || !e.at.isBefore(after)),
          orElse: () => throw StateError('no $source $name'),
        )
        .at;
    Future<void> until(bool Function() ok) async {
      for (var i = 0; i < 1000 && !ok(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(ok(), isTrue);
    }

    bool logged(String source, String name, {DateTime? after}) =>
        voiceEvents.any((e) => e.source == source && e.name == name && (after == null || !e.at.isBefore(after)));

    c.answerConsent(true);
    await until(() => logged('onb', 'mic_open'));
    final lineEnd = at('onb', 'tts_end');
    final micLive = at('onb', 'mic_open');
    final recorderOn = at('stt', 'recorder_started');

    // The person answers: a quiet moment, then voice, then the recognizer's words.
    final stt = sockets.made.lastWhere((s) => s.uri.path.contains('stt'));
    for (var i = 0; i < 4; i++) {
      rec.mic.add(Uint8List(3200));
    }
    for (var i = 0; i < 4; i++) {
      rec.mic.add(loudChunk());
    }
    // A live microphone keeps sending (quiet) audio after the words.
    final room = Timer.periodic(const Duration(milliseconds: 100), (_) => rec.mic.add(Uint8List(3200)));
    addTearDown(room.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    stt.reply({'type': 'transcript', 'text': 'I am 70', 'is_final': true});
    await until(() => logged('onb', 'partial'));
    final speechEnd = at('onb', 'partial');
    await until(() => logged('tts', 'audio', after: speechEnd));
    final endOfTurn = at('onb', 'end_of_turn');
    final sent = at('onb', 'send', after: endOfTurn);
    final replied = at('onb', 'turn', after: sent);
    final answerStarts = at('onb', 'tts_start', after: replied);
    final answerAudio = at('tts', 'audio', after: answerStarts);

    int ms(DateTime a, DateTime b) => b.difference(a).inMilliseconds;
    final report = {
      'line end -> mic live (socket open)': ms(lineEnd, micLive),
      'line end -> recorder on (audio kept from here)': ms(lineEnd, recorderOn),
      'speech end -> end of turn (chosen wait)': ms(speechEnd, endOfTurn),
      'end of turn -> request sent': ms(endOfTurn, sent),
      'reply -> Mochi starts the line': ms(replied, answerStarts),
      'line start -> first audio': ms(answerStarts, answerAudio),
      'speech end -> first audio of the answer': ms(speechEnd, answerAudio),
    };
    // ignore: avoid_print
    print('[hf latency] ${report.entries.map((e) => '${e.key}: ${e.value} ms').join('; ')}');

    expect(ms(lineEnd, micLive), lessThan(1000));
    expect(ms(endOfTurn, sent), lessThan(1000));
    expect(ms(replied, answerStarts), lessThan(1000));
    expect(ms(answerStarts, answerAudio), lessThan(1000));
    expect(ms(speechEnd, endOfTurn), inInclusiveRange(2400, 2800)); // voiceEndOfTurn
  }, timeout: const Timeout(Duration(seconds: 20)));
}
