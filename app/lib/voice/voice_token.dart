import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_base.dart';
import 'backend_http_client.dart';
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
///
/// While voice is in use a fresh token is kept ready: [prefetch] mints one ahead of the first
/// Talk, and a token is re-minted in the background once less than [refreshBefore] of it is
/// left, so speaking and listening never wait for a mint mid-conversation. The background
/// refresh stops once voice has not been used for [keepWarmFor].
class VoiceTokenProvider {
  VoiceTokenProvider({
    http.Client? client,
    String? baseUrl,
    ApiBase? base,
    DateTime Function()? now,
    this.refreshBefore = const Duration(seconds: 60),
    this.keepWarmFor = const Duration(minutes: 5),
  }) : _client = client ?? BackendHttpClient(),
       base = base ?? ApiBase(baseUrl ?? apiBaseUrl, client),
       _now = now ?? DateTime.now;

  final http.Client _client;
  final ApiBase base;
  final DateTime Function() _now;
  final Duration refreshBefore;
  final Duration keepWarmFor;
  VoiceToken? _cached;
  Future<VoiceToken>? _minting;
  Timer? _refresh;
  DateTime? _lastUse;

  /// Returns a cached token while it is fresh; [forceNew] re-mints (after a socket error).
  /// Callers at the same time share one mint.
  Future<VoiceToken> get({bool forceNew = false}) {
    _lastUse = _now();
    final c = _cached;
    if (!forceNew && c != null && c.isFresh(_now())) return Future.value(c);
    return _mintShared();
  }

  /// Voice is about to be used (consent given, voice mode on): have a token ready.
  Future<VoiceToken> prefetch() => get();

  Future<VoiceToken> _mintShared() => _minting ??= _mint().whenComplete(() => _minting = null);

  void _scheduleRefresh(VoiceToken t) {
    _refresh?.cancel();
    _refresh = null;
    final wait = t.expiresAt.subtract(refreshBefore).difference(_now());
    if (wait <= Duration.zero) return; // too short-lived to refresh ahead
    _refresh = Timer(wait, () {
      _refresh = null;
      final last = _lastUse;
      if (last == null || _now().difference(last) > keepWarmFor) return; // voice not in use: let it lapse
      _mintShared().ignore(); // a failed refresh is retried on demand by the next get()
    });
  }

  Future<VoiceToken> _mint() async {
    try {
      final url = await base.url();
      final r = await _client
          .post(
            Uri.parse('$url/api/voice/token'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'voice_consent': true}),
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 503) throw const VoiceUnavailableException();
      if (r.statusCode != 200) throw VoiceFailure('token HTTP ${r.statusCode}');
      final t = _cached = VoiceToken.fromJson(
        jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>,
        now: _now(),
      );
      _scheduleRefresh(t);
      return t;
    } on VoiceUnavailableException {
      rethrow;
    } on VoiceFailure {
      rethrow;
    } catch (e) {
      base.forget();
      throw VoiceFailure('token: $e');
    }
  }
}
