import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/voice/cartesia_wire.dart';
import 'package:lifesim/voice/http_conversation_guide.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:lifesim/voice/voice_token.dart';

final tokenJson = {
  'schema_version': '1.0',
  'token': 'tok123',
  'expires_in': 300,
  'cartesia_version': '2025-04-16',
  'stt': {
    'model': 'ink-whisper',
    'encoding': 'pcm_s16le',
    'sample_rate': 16000,
    'url': 'wss://api.cartesia.ai/stt/websocket',
  },
  'tts': {
    'model': 'sonic-3',
    'voice_id': 'voice-1',
    'encoding': 'pcm_s16le',
    'sample_rate': 24000,
    'speed': 0.9,
    'emotion': 'calm',
    'url': 'wss://api.cartesia.ai/tts/websocket',
  },
};

void main() {
  final now = DateTime(2026, 10, 24, 12);
  final token = VoiceToken.fromJson(tokenJson, now: now);

  test('token expiry', () {
    expect(token.isFresh(now.add(const Duration(seconds: 200))), true);
    expect(token.isFresh(now.add(const Duration(seconds: 280))), false);
  });

  test('TTS url carries version and token', () {
    final u = CartesiaWire.ttsUri(token);
    expect(u.scheme, 'wss');
    expect(u.path, '/tts/websocket');
    expect(u.queryParameters, {'cartesia_version': '2025-04-16', 'access_token': 'tok123'});
  });

  test('STT url carries model, encoding, rate, version and token', () {
    final u = CartesiaWire.sttUri(token);
    expect(u.path, '/stt/websocket');
    expect(u.queryParameters, {
      'model': 'ink-whisper',
      'encoding': 'pcm_s16le',
      'sample_rate': '16000',
      'cartesia_version': '2025-04-16',
      'access_token': 'tok123',
    });
  });

  test('TTS request has the agreed shape', () {
    final m = jsonDecode(CartesiaWire.ttsRequest(token, 'Hello', 'ctx1')) as Map<String, dynamic>;
    expect(m, {
      'model_id': 'sonic-3',
      'transcript': 'Hello',
      'voice': {'id': 'voice-1'},
      'output_format': {'container': 'raw', 'encoding': 'pcm_s16le', 'sample_rate': 24000},
      'context_id': 'ctx1',
      'continue': false,
      'language': 'en',
      'generation_config': {'speed': 0.9, 'volume': 1.0, 'emotion': 'calm'},
    });
  });

  test('cancel message', () {
    expect(jsonDecode(CartesiaWire.ttsCancel('ctx1')), {'context_id': 'ctx1', 'cancel': true});
  });

  test('TTS parsing: chunk, done, error, other contexts, junk', () {
    final pcm = Uint8List.fromList([1, 0, 2, 0]);
    final chunk = jsonEncode({'type': 'chunk', 'context_id': 'ctx1', 'data': base64Encode(pcm)});
    final e = CartesiaWire.parseTts(chunk, contextId: 'ctx1');
    expect(e, isA<TtsAudio>());
    expect((e as TtsAudio).pcm, pcm);

    expect(CartesiaWire.parseTts(jsonEncode({'type': 'done', 'context_id': 'ctx1'}), contextId: 'ctx1'), isA<TtsDone>());
    expect(CartesiaWire.parseTts(jsonEncode({'done': true}), contextId: 'ctx1'), isA<TtsDone>());
    expect(CartesiaWire.parseTts(jsonEncode({'type': 'error', 'error': 'bad voice'})), isA<TtsError>());
    expect(CartesiaWire.parseTts(chunk, contextId: 'other'), isA<TtsIgnored>());
    expect(CartesiaWire.parseTts(jsonEncode({'type': 'timestamps'})), isA<TtsIgnored>());
    expect(CartesiaWire.parseTts('not json'), isA<TtsIgnored>());
    expect(CartesiaWire.parseTts(jsonEncode({'data': '!!!'})), isA<TtsIgnored>());
  });

  test('STT parsing: partial, final, flush, error, junk', () {
    final p = CartesiaWire.parseStt(jsonEncode({'type': 'transcript', 'is_final': false, 'text': 'I am'})) as SttTranscript;
    expect((p.text, p.isFinal), ('I am', false));
    final f = CartesiaWire.parseStt(jsonEncode({'type': 'transcript', 'is_final': true, 'text': 'I am 70'})) as SttTranscript;
    expect((f.text, f.isFinal), ('I am 70', true));
    expect(CartesiaWire.parseStt(jsonEncode({'type': 'flush_done'})), isA<SttFlushed>());
    expect(CartesiaWire.parseStt(jsonEncode({'type': 'done'})), isA<SttFlushed>());
    expect(CartesiaWire.parseStt(jsonEncode({'type': 'error', 'message': 'x'})), isA<SttError>());
    expect(CartesiaWire.parseStt('[]'), isA<SttIgnored>());
    expect(CartesiaWire.parseStt('oops'), isA<SttIgnored>());
  });

  test('ChunkBuffer cuts 100 ms chunks and keeps the tail', () {
    final b = ChunkBuffer(chunkBytes: 4);
    expect(b.add(Uint8List.fromList([1, 2, 3])), isEmpty);
    final out = b.add(Uint8List.fromList([4, 5, 6, 7, 8, 9]));
    expect(out.map((c) => c.toList()), [
      [1, 2, 3, 4],
      [5, 6, 7, 8]
    ]);
    expect(b.flush(), Uint8List.fromList([9]));
    expect(b.flush(), isNull);
  });

  test('server turn parsing', () {
    final t = HttpConversationGuide.parseTurn({
      'state': {'phase': 'confirming', 'confirmed_profile': {'age': 70}},
      'message': 'Is that right?',
      'complete': false,
      'mascot_events': [
        {'state': 'thinking', 'caption': 'x'},
        {'state': 'confirming', 'caption': 'y'}
      ],
    });
    expect(t.isConfirming, true);
    expect(t.mascotState, 'confirming');
    expect(() => HttpConversationGuide.parseTurn({'message': 'x'}), throwsA(isA<GuideFailure>()));
  });

  test('transcript pieces are joined exactly as Ink sends them (live sequence)', () {
    expect(CartesiaWire.joinTranscript([" I'", 'm about', ' five', ' foot eight, I think.'], ''),
        "I'm about five foot eight, I think.");
    expect(CartesiaWire.joinTranscript([' I weigh'], ' about 160'), 'I weigh about 160');
    expect(CartesiaWire.joinTranscript([], ''), '');
  });
}

