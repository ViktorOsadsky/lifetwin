import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_conversation_guide.dart';
import 'speech.dart';

/// Short-lived Cartesia access token plus the settings the server chose.
class VoiceToken {
  const VoiceToken({
    required this.token,
    required this.expiresAt,
    required this.cartesiaVersion,
    required this.sttModel,
    required this.sttEncoding,
    required this.sttSampleRate,
    required this.sttUrl,
    required this.ttsModel,
    required this.voiceId,
    required this.ttsSampleRate,
    required this.speed,
    required this.emotion,
    required this.ttsUrl,
  });

  final String token;
  final DateTime expiresAt;
  final String cartesiaVersion;
  final String sttModel;
  final String sttEncoding;
  final int sttSampleRate;
  final String sttUrl;
  final String ttsModel;
  final String voiceId;
  final int ttsSampleRate;
  final num speed;
  final String emotion;
  final String ttsUrl;

  factory VoiceToken.fromJson(Map<String, dynamic> j, {required DateTime now}) {
    final stt = Map<String, dynamic>.from(j['stt'] as Map);
    final tts = Map<String, dynamic>.from(j['tts'] as Map);
    return VoiceToken(
      token: j['token'] as String,
      expiresAt: now.add(Duration(seconds: (j['expires_in'] as num).toInt())),
      cartesiaVersion: j['cartesia_version'] as String,
      sttModel: stt['model'] as String,
      sttEncoding: (stt['encoding'] as String?) ?? 'pcm_s16le',
      sttSampleRate: (stt['sample_rate'] as num?)?.toInt() ?? 16000,
      sttUrl: (stt['url'] as String?) ?? 'wss://api.cartesia.ai/stt/websocket',
      ttsModel: tts['model'] as String,
      voiceId: tts['voice_id'] as String,
      ttsSampleRate: (tts['sample_rate'] as num?)?.toInt() ?? 24000,
      speed: (tts['speed'] as num?) ?? 1.0,
      emotion: (tts['emotion'] as String?) ?? 'calm',
      ttsUrl: (tts['url'] as String?) ?? 'wss://api.cartesia.ai/tts/websocket',
    );
  }

  bool isFresh(DateTime now) => now.isBefore(expiresAt.subtract(const Duration(seconds: 30)));
}

/// Mints tokens from our server (the Cartesia key never reaches the app).
class VoiceTokenProvider {
  VoiceTokenProvider({http.Client? client, this.baseUrl = apiBaseUrl, DateTime Function()? now})
      : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final http.Client _client;
  final String baseUrl;
  final DateTime Function() _now;
  VoiceToken? _cached;

  /// Returns a cached token while it is fresh; [forceNew] re-mints (after a socket error).
  Future<VoiceToken> get({bool forceNew = false}) async {
    final c = _cached;
    if (!forceNew && c != null && c.isFresh(_now())) return c;
    try {
      final r = await _client
          .post(Uri.parse('$baseUrl/api/voice/token'),
              headers: {'content-type': 'application/json'}, body: jsonEncode({'voice_consent': true}))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 503) throw const VoiceUnavailableException();
      if (r.statusCode != 200) throw VoiceFailure('token HTTP ${r.statusCode}');
      return _cached = VoiceToken.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>, now: _now());
    } on VoiceUnavailableException {
      rethrow;
    } on VoiceFailure {
      rethrow;
    } catch (e) {
      throw VoiceFailure('token: $e');
    }
  }
}
