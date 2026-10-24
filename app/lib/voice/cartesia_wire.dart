import 'dart:convert';
import 'dart:typed_data';

import 'voice_token.dart';

/// Every Cartesia wire detail lives here, so a wrong guess is a one-file fix.
/// Message type names are UNVERIFIED against live Cartesia; parsing is defensive.
class CartesiaWire {
  const CartesiaWire._();

  static Uri ttsUri(VoiceToken t) => _withQuery(t.ttsUrl, {
        'cartesia_version': t.cartesiaVersion,
        'access_token': t.token,
      });

  static Uri sttUri(VoiceToken t) => _withQuery(t.sttUrl, {
        'model': t.sttModel,
        'encoding': t.sttEncoding,
        'sample_rate': '${t.sttSampleRate}',
        'cartesia_version': t.cartesiaVersion,
        'access_token': t.token,
      });

  static Uri _withQuery(String base, Map<String, String> q) {
    final u = Uri.parse(base);
    return u.replace(queryParameters: {...u.queryParameters, ...q});
  }

  static String ttsRequest(VoiceToken t, String text, String contextId) => jsonEncode({
        'model_id': t.ttsModel,
        'transcript': text,
        'voice': {'id': t.voiceId},
        'output_format': {'container': 'raw', 'encoding': 'pcm_s16le', 'sample_rate': t.ttsSampleRate},
        'context_id': contextId,
        'continue': false,
        'language': 'en',
        'generation_config': {'speed': t.speed, 'volume': 1.0, 'emotion': t.emotion},
      });

  static String ttsCancel(String contextId) => jsonEncode({'context_id': contextId, 'cancel': true});

  static const sttFinalize = 'finalize';
  static const sttClose = 'close';

  static TtsEvent parseTts(String raw, {String? contextId}) {
    final m = _decode(raw);
    if (m == null) return const TtsIgnored();
    final id = m['context_id'];
    if (contextId != null && id is String && id != contextId) return const TtsIgnored();
    final type = (m['type'] as String?)?.toLowerCase();
    if (type == 'error' || m['error'] != null) {
      return TtsError('${m['error'] ?? m['message'] ?? m['title'] ?? 'error'}');
    }
    final data = m['data'];
    if (data is String && data.isNotEmpty) {
      try {
        return TtsAudio(base64Decode(data));
      } on FormatException {
        return const TtsIgnored();
      }
    }
    if (type == 'done' || m['done'] == true) return const TtsDone();
    return const TtsIgnored();
  }

  static SttEvent parseStt(String raw) {
    final m = _decode(raw);
    if (m == null) return const SttIgnored();
    final type = (m['type'] as String?)?.toLowerCase() ?? '';
    if (type == 'error' || m['error'] != null) {
      return SttError('${m['error'] ?? m['message'] ?? 'error'}');
    }
    final text = m['text'];
    if (type == 'transcript' && text is String) {
      return SttTranscript(text, isFinal: m['is_final'] == true);
    }
    if (type.contains('flush') || type.contains('finalize') || type == 'done') return const SttFlushed();
    return const SttIgnored();
  }

  static Map<String, dynamic>? _decode(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }
}

sealed class TtsEvent {
  const TtsEvent();
}

class TtsAudio extends TtsEvent {
  const TtsAudio(this.pcm);
  final Uint8List pcm;
}

class TtsDone extends TtsEvent {
  const TtsDone();
}

class TtsError extends TtsEvent {
  const TtsError(this.message);
  final String message;
}

class TtsIgnored extends TtsEvent {
  const TtsIgnored();
}

sealed class SttEvent {
  const SttEvent();
}

class SttTranscript extends SttEvent {
  const SttTranscript(this.text, {required this.isFinal});
  final String text;
  final bool isFinal;
}

/// Server acknowledged "finalize" (or finished).
class SttFlushed extends SttEvent {
  const SttFlushed();
}

class SttError extends SttEvent {
  const SttError(this.message);
  final String message;
}

class SttIgnored extends SttEvent {
  const SttIgnored();
}

/// Re-cuts arbitrary mic chunks into fixed sizes (default 100 ms of 16 kHz PCM16 mono).
class ChunkBuffer {
  ChunkBuffer({this.chunkBytes = 3200});
  final int chunkBytes;
  final _pending = BytesBuilder(copy: false);

  List<Uint8List> add(Uint8List data) {
    _pending.add(data);
    final all = _pending.takeBytes();
    final out = <Uint8List>[];
    var i = 0;
    while (all.length - i >= chunkBytes) {
      out.add(Uint8List.sublistView(all, i, i + chunkBytes));
      i += chunkBytes;
    }
    if (i < all.length) _pending.add(Uint8List.sublistView(all, i));
    return out;
  }

  /// The leftover tail (call when listening stops).
  Uint8List? flush() {
    final rest = _pending.takeBytes();
    return rest.isEmpty ? null : rest;
  }
}
