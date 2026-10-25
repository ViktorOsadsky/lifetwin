import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/voice/cartesia_speech.dart';
import 'package:lifesim/voice/speech.dart';

import 'engine_fakes.dart';

void main() {
  drainTests();
  speakingTests();
  hangTests();

  group('listening', () {
    late TokenServer server;
    late FakeRecorder rec;
    late Sockets sockets;
    late CartesiaSpeechInput input;

    setUp(() {
      server = TokenServer();
      rec = FakeRecorder();
      sockets = Sockets(autoOpen: false);
      input = CartesiaSpeechInput(tokens: server.provider, recorder: rec, connect: sockets.connect);
    });

    test('the mic starts before the token arrives; early audio is sent once the socket opens', () async {
      server.gate = Completer();
      final starting = input.start((_) {});
      await pumpEventQueue();
      expect(rec.starts, 1, reason: 'recording while the token is still being minted');
      expect(server.mints, 0);
      expect(sockets.made, isEmpty);
      rec.mic.add(loudChunk());
      rec.mic.add(loudChunk(3000));
      await pumpEventQueue();
      server.gate!.complete();
      await pumpEventQueue();
      expect(sockets.made, hasLength(1));
      expect(sockets.last.audio, isEmpty, reason: 'held until the socket is open');
      sockets.last.open();
      await starting;
      await pumpEventQueue();
      expect(sockets.last.audio, hasLength(2));
      rec.mic.add(loudChunk());
      await pumpEventQueue();
      expect(sockets.last.audio, hasLength(3), reason: 'later audio goes straight out');
    });

    test('cancel while the token is pending stops the mic and never connects', () async {
      server.gate = Completer();
      final starting = input.start((_) {});
      await pumpEventQueue();
      await input.cancel();
      expect(rec.recording, false);
      server.gate!.complete();
      await starting;
      await pumpEventQueue();
      expect(sockets.made, isEmpty);
    });
  });
}

/// The context id of the last speak request on [s].
String contextOf(FakeSocket s) => (jsonDecode(s.texts.last) as Map)['context_id'] as String;

void speakingTests() {
  group('speaking', () {
    test('the player sets up while the socket opens, not after', () async {
      final server = TokenServer();
      final sockets = Sockets(autoOpen: false);
      final player = FakePlayer();
      final out = CartesiaSpeechOutput(tokens: server.provider, player: player, connect: sockets.connect);
      final speaking = out.speak('Hello');
      await pumpEventQueue();
      expect(sockets.made, hasLength(1));
      expect(player.calls, contains('begin'), reason: 'begun before the socket is open');
      sockets.last.open();
      await pumpEventQueue();
      final id = contextOf(sockets.last);
      sockets.last.reply({'context_id': id, 'data': base64Encode(loudChunk())});
      sockets.last.reply({'context_id': id, 'type': 'done'});
      await speaking;
      expect(player.calls, ['stop', 'begin', 'feed', 'finish']);
    });
  });
}

/// Short stand-ins for the real limits, so the tests run in real time.
const _ready = Duration(milliseconds: 150);
const _silence = Duration(milliseconds: 200);
Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void hangTests() {
  group('no hangs', () {
    test('the limits: 3 s for a socket to open, 4 s of no TTS audio', () {
      expect(socketReadyLimit, const Duration(seconds: 3));
      expect(ttsSilenceLimit, const Duration(seconds: 4));
      final t = TokenServer().provider;
      expect(CartesiaSpeechOutput(tokens: t, player: FakePlayer()).readyLimit, socketReadyLimit);
      expect(CartesiaSpeechOutput(tokens: t, player: FakePlayer()).silenceLimit, ttsSilenceLimit);
      expect(CartesiaSpeechInput(tokens: t, recorder: FakeRecorder()).readyLimit, socketReadyLimit);
    });

    test('a TTS socket that never opens fails at the ready limit (after one re-mint)', () async {
      final sockets = Sockets(autoOpen: false);
      final out = CartesiaSpeechOutput(
        tokens: TokenServer().provider,
        player: FakePlayer(),
        connect: sockets.connect,
        readyLimit: _ready,
      );
      Object? error;
      final speaking = out.speak('Hello').catchError((Object e) => error = e);
      await _wait(100);
      expect(error, isNull);
      await _wait(100); // the first socket gave up; one retry
      expect(sockets.made, hasLength(2));
      await speaking;
      expect(error, isA<VoiceFailure>());
    });

    test('TTS audio that stops coming ends the line after the silence limit', () async {
      final sockets = Sockets();
      final player = FakePlayer();
      final out = CartesiaSpeechOutput(
        tokens: TokenServer().provider,
        player: player,
        connect: sockets.connect,
        silenceLimit: _silence,
      );
      var done = false;
      final speaking = out.speak('Hello').then((_) => done = true);
      await pumpEventQueue();
      sockets.last.reply({'context_id': contextOf(sockets.last), 'data': base64Encode(loudChunk())});
      await _wait(120);
      expect(done, false);
      await speaking.timeout(const Duration(seconds: 1));
      expect(player.calls.last, 'finish', reason: 'what did arrive is played out');
    });

    test('TTS with no audio at all fails instead of speaking for ever', () async {
      final out = CartesiaSpeechOutput(
        tokens: TokenServer().provider,
        player: FakePlayer(),
        connect: Sockets().connect,
        silenceLimit: _silence,
      );
      await expectLater(out.speak('Hello').timeout(const Duration(seconds: 2)), throwsA(isA<VoiceFailure>()));
    });

    test('an STT socket that never opens fails start at the ready limit and closes the mic', () async {
      final rec = FakeRecorder();
      final input = CartesiaSpeechInput(
        tokens: TokenServer().provider,
        recorder: rec,
        connect: Sockets(autoOpen: false).connect,
        readyLimit: _ready,
      );
      Object? error;
      final starting = input.start((_) {}).catchError((Object e) => error = e);
      await _wait(80);
      expect(error, isNull);
      expect(rec.recording, true);
      await starting.timeout(const Duration(seconds: 1));
      expect(error, isA<VoiceFailure>());
      expect(rec.recording, false);
    });

    test('a connection lost mid-listen ends listening at once and reports it', () async {
      final rec = FakeRecorder();
      final sockets = Sockets();
      final input = CartesiaSpeechInput(tokens: TokenServer().provider, recorder: rec, connect: sockets.connect);
      Object? dropped;
      await input.start((_) {}, onDropped: (e) => dropped = e);
      expect(rec.recording, true);
      await sockets.last.incoming.close();
      await pumpEventQueue();
      expect(dropped, isA<VoiceFailure>());
      expect(rec.recording, false);
      expect(await input.finish(), '');
    });
  });
}

void drainTests() {
  group('playback drain', () {
    test('a drain that came before finish is remembered: no wait', () {
      fakeAsync((fa) {
        final d = PlaybackDrain()..fed();
        d.remaining(0);
        var done = false;
        d.wait(const Duration(seconds: 10)).then((_) => done = true);
        fa.flushMicrotasks();
        expect(done, true);
      });
    });

    test('waits for the drain, ignores low-buffer events, and new audio clears the flag', () {
      fakeAsync((fa) {
        final d = PlaybackDrain()..fed();
        d.remaining(0);
        d.fed(); // more audio after an underrun
        var done = false;
        d.wait(const Duration(seconds: 10)).then((_) => done = true);
        d.remaining(500);
        fa.elapse(const Duration(seconds: 2));
        expect(done, false);
        d.remaining(0);
        fa.flushMicrotasks();
        expect(done, true);
      });
    });

    test('a drain event that never comes ends at the limit', () {
      fakeAsync((fa) {
        final d = PlaybackDrain()..fed();
        var done = false;
        d.wait(const Duration(seconds: 3)).then((_) => done = true);
        fa.elapse(const Duration(milliseconds: 2999));
        expect(done, false);
        fa.elapse(const Duration(milliseconds: 1));
        expect(done, true);
      });
    });
  });
}
