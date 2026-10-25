import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/voice/cartesia_speech.dart';

import 'engine_fakes.dart';

void main() {
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
