import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/voice/cartesia_speech.dart';
import 'package:lifesim/voice/speech.dart';

import 'engine_fakes.dart';

/// Bug hunt B (voice pipeline under demo conditions): the real Cartesia input and output
/// with fake sockets, recorder and player.
void main() {
  micStallTests();

  group('a TTS socket that closes before any audio', () {
    test('is tried once more with a new token, then fails (never "said" in silence)', () async {
      final sockets = Sockets();
      final server = TokenServer();
      final out = CartesiaSpeechOutput(tokens: server.provider, player: FakePlayer(), connect: sockets.connect);
      Object? error;
      final speaking = out.speak('How old are you?').catchError((Object e) => error = e);
      await pumpEventQueue();
      expect(sockets.made, hasLength(1));
      await sockets.last.incoming.close(); // Cartesia closes the stream, no audio, no error
      await pumpEventQueue();
      expect(sockets.made, hasLength(2), reason: 'one retry, with a fresh token');
      expect(server.mints, 2);
      await sockets.last.incoming.close();
      await speaking;
      expect(error, isA<VoiceFailure>(), reason: 'the controller then shows "I couldn\'t say that out loud"');
    });

    test('a close after some audio plays what came, with no retry', () async {
      final sockets = Sockets();
      final player = FakePlayer();
      final out = CartesiaSpeechOutput(tokens: TokenServer().provider, player: player, connect: sockets.connect);
      final speaking = out.speak('Hello');
      await pumpEventQueue();
      final id = (jsonDecode(sockets.last.texts.last) as Map)['context_id'];
      sockets.last.reply({'context_id': id, 'data': base64Encode(loudChunk())});
      await pumpEventQueue();
      await sockets.last.incoming.close();
      await speaking;
      expect(sockets.made, hasLength(1));
      expect(player.calls, contains('feed'));
    });
  });

  group('a lost STT connection, restarted at once (as hands-free does)', () {
    test('the restarted listen really listens: recorder on and a new socket', () async {
      final rec = FakeRecorder()..latency = const Duration(milliseconds: 2);
      final sockets = Sockets();
      final input = CartesiaSpeechInput(tokens: TokenServer().provider, recorder: rec, connect: sockets.connect);
      Future<void>? restarted;
      await input.start(
        (_) {},
        onDropped: (_) {
          // The controller restarts the recognizer straight from the drop callback: it asks for
          // the permission, then starts.
          restarted = input.hasPermission().then((_) => input.start((_) {}));
        },
      );
      expect(sockets.made, hasLength(1));
      await sockets.last.incoming.close(); // Cartesia drops the socket mid-listen
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(restarted, isNotNull);
      await restarted;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rec.recording, isTrue, reason: 'the restart must leave the microphone on');
      expect(sockets.made, hasLength(2), reason: 'the restart must open a new socket');
      rec.mic.add(loudChunk());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sockets.last.audio, isNotEmpty, reason: 'audio reaches the new socket');
    });
  });
}

/// Plugging in headphones (a route change) stops iOS's audio engine, and a phone call or Siri
/// (an audio session interruption) pauses the recorder: either way the microphone just stops
/// sending audio, with no error. A listen that keeps "Listening" on a dead microphone never
/// hears the answer.
void micStallTests() {
  group('a microphone that stops sending audio mid-listen', () {
    test('is reported as a lost connection, so hands-free restarts it', () async {
      final rec = FakeRecorder();
      final input = CartesiaSpeechInput(
        tokens: TokenServer().provider,
        recorder: rec,
        connect: Sockets().connect,
        micStallLimit: const Duration(milliseconds: 100),
      );
      Object? dropped;
      await input.start((_) {}, onDropped: (e) => dropped = e);
      rec.mic.add(loudChunk());
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(dropped, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 150)); // no audio since
      expect(dropped, isA<VoiceFailure>());
      expect(rec.recording, isFalse, reason: 'the stalled recorder is stopped, ready to start again');
    });

    test('a microphone that keeps sending is never reported', () async {
      final rec = FakeRecorder();
      final input = CartesiaSpeechInput(
        tokens: TokenServer().provider,
        recorder: rec,
        connect: Sockets().connect,
        micStallLimit: const Duration(milliseconds: 100),
      );
      Object? dropped;
      await input.start((_) {}, onDropped: (e) => dropped = e);
      for (var i = 0; i < 8; i++) {
        rec.mic.add(loudChunk());
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(dropped, isNull);
      expect(rec.recording, isTrue);
      await input.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(dropped, isNull, reason: 'a listen that ended is not watched any more');
    });

    test('the default limit is 2 s (the recorder sends every few tens of ms)', () {
      expect(sttMicStallLimit, const Duration(seconds: 2));
    });
  });
}
