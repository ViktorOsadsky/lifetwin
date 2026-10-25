import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/voice/cartesia_speech.dart';
import 'package:lifesim/voice/cartesia_wire.dart';
import 'package:lifesim/voice/heard_gate.dart';

import 'engine_fakes.dart';

/// [n] chunks of 100 ms at [level] through [g]; returns what would be sent.
List<Uint8List> feed(HeardGate g, int n, [int level = 4000]) => [for (var i = 0; i < n; i++) g.audio(loudChunk(level))];

bool silent(Uint8List pcm) => pcm.every((b) => b == 0);

void main() {
  group('HeardGate', () {
    test('the first 300 ms after the mic opens are sent as silence', () {
      final g = HeardGate();
      final out = [...feed(g, 3, 0), ...feed(g, 2)];
      expect(out.take(3).every(silent), isTrue);
      expect(out.skip(3).any(silent), isFalse);
      expect(g.voiced, isTrue);
    });

    test('speech already going when the mic opened is muted until the first quiet moment', () {
      final g = HeardGate();
      final before = feed(g, 6); // loud from the start: Mochi's tail or a TV sentence in progress
      expect(before.every(silent), isTrue);
      expect(g.voiced, isFalse);
      feed(g, 1, 0); // a gap
      final after = feed(g, 3);
      expect(after.any(silent), isFalse);
      expect(g.voiced, isTrue);
    });

    test('sound that never pauses is muted for at most 1 s', () {
      final g = HeardGate();
      final out = feed(g, 15);
      expect(out.take(10).every(silent), isTrue);
      expect(out.skip(10).any(silent), isFalse);
    });

    test('noise words never count: labels, hesitations and too little voice give no caption', () {
      final g = HeardGate();
      feed(g, 3, 0);
      feed(g, 1); // 100 ms of voice: below the 200 ms minimum
      expect(g.caption('I am 70'), '', reason: 'too little voice was heard');
      feed(g, 1);
      for (final noise in ['[noise]', '(music)', '♪ ♪', 'um', 'Uh... hmm.', '[BLANK_AUDIO] mm', '<unk>']) {
        expect(g.caption(noise), '', reason: noise);
      }
      expect(g.caption('[noise] I am 70'), 'I am 70');
      expect(g.caption('uh-huh'), 'uh-huh', reason: 'can mean yes');
      expect(g.caption('70'), '70');
    });

    test('low confidence is dropped; no confidence (Ink today) is kept', () {
      final g = HeardGate();
      expect(g.keep(null), isTrue);
      expect(g.keep(0.9), isTrue);
      expect(g.keep(0.2), isFalse);
    });
  });

  group('CartesiaSpeechInput with the gate', () {
    late FakeRecorder rec;
    late Sockets sockets;
    late CartesiaSpeechInput input;
    late List<String> shown;

    setUp(() async {
      rec = FakeRecorder();
      sockets = Sockets();
      input = CartesiaSpeechInput(tokens: TokenServer().provider, recorder: rec, connect: sockets.connect);
      shown = [];
      await input.start(shown.add);
    });

    Future<void> mic(int n, [int level = 4000]) async {
      for (var i = 0; i < n; i++) {
        rec.mic.add(loudChunk(level));
      }
      await pumpEventQueue();
    }

    Future<void> hear(String text, {bool isFinal = false, double? confidence}) async {
      sockets.last.reply({'type': 'transcript', 'text': text, 'is_final': isFinal, 'confidence': ?confidence});
      await pumpEventQueue();
    }

    test('speech before the listen goes out as silence, and its words are not shown', () async {
      await mic(5); // loud from the first chunk
      expect(sockets.last.audio.every(silent), isTrue);
      await hear('the weather tonight');
      expect(shown, isEmpty);
      expect(await input.finish(), '');
    });

    test('noise partials never reach the caller, so no end-of-turn wait starts', () async {
      await mic(3, 0);
      await mic(3);
      await hear('[noise]');
      await hear('um');
      await hear('(music)', isFinal: true);
      expect(shown, isEmpty);
      await hear(' I am 70');
      expect(shown, ['I am 70']);
    });

    test('a low-confidence partial or final is ignored', () async {
      await mic(3, 0);
      await mic(3);
      await hear('turn it up', confidence: 0.1);
      await hear(' turn it up', isFinal: true, confidence: 0.2);
      expect(shown, isEmpty);
      await hear(' I am 70', isFinal: true, confidence: 0.9);
      expect(shown, ['I am 70']);
      expect(await input.finish(), 'I am 70');
    });

    test('the same caption again is not handed over again', () async {
      await mic(3, 0);
      await mic(3);
      await hear('I am');
      await hear('I am');
      await hear('I am');
      expect(shown, ['I am']);
    });

    test('words with too little voice behind them finish as nothing', () async {
      await mic(3, 0);
      await mic(1, 200); // faint: below the voice level
      await hear(' someone far away', isFinal: true);
      expect(shown, isEmpty);
      expect(await input.finish(), '');
    });
  });

  test('STT parsing keeps a confidence when one is sent', () {
    final t = CartesiaWire.parseStt('{"type":"transcript","text":"hi","is_final":true,"confidence":0.25}');
    expect(t, isA<SttTranscript>().having((e) => e.confidence, 'confidence', 0.25));
    final n = CartesiaWire.parseStt('{"type":"transcript","text":"hi","is_final":true}');
    expect(n, isA<SttTranscript>().having((e) => e.confidence, 'confidence', isNull));
  });
}
