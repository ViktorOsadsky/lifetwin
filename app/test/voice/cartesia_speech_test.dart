import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/voice/cartesia_speech.dart';

import 'engine_fakes.dart';

void main() {
  drainTests();
  speakingTests();

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
