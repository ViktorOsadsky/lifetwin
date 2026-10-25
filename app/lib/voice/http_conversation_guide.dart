import 'dart:convert';

import 'package:http/http.dart' as http;

import '../checkin/consents.dart';
import 'api_base.dart';
import 'backend_http_client.dart';
import 'speech.dart';

export 'api_base.dart' show ApiBase, apiBaseUrl;

/// Calls POST /api/onboarding/turn. The state is held by the app, not the server.
class HttpConversationGuide implements ConversationGuide {
  HttpConversationGuide({http.Client? client, String? baseUrl, ApiBase? base, Future<AiProvider?> Function()? provider})
    : _client = client ?? BackendHttpClient(),
      base = base ?? ApiBase(baseUrl ?? apiBaseUrl, client),
      _providerSource = provider;

  final http.Client _client;
  final ApiBase base;

  /// Who the AI helper sends to (`/api/capabilities` -> `conversation`), asked once when the
  /// AI helper is first on. Tests may pass their own.
  final Future<AiProvider?> Function()? _providerSource;
  Future<AiProvider?>? _provider;

  Future<Map<String, bool>> _helperConsent(bool aiHelper) async {
    if (!aiHelper) return const {};
    final p = await (_provider ??=
        (_providerSource ?? HttpCapabilitiesClient(client: _client, base: base).personalize)());
    if (p == null) _provider = null; // not reached: asked again next turn
    return AiProvider.helperConsent(p, aiHelper: true);
  }

  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    bool aiHelper = false,
    String? importSource,
  }) async {
    // The AI helper's yes is for the provider its switch names (Claude today);
    // the server never sends a turn to Claude without `outside_ai_consent.claude`.
    final consent = await _helperConsent(aiHelper);
    final body = <String, dynamic>{
      'action': action,
      'state': ?state,
      'text': ?text,
      'values': ?values,
      'import_source': ?importSource,
      'input_mode': fromTranscript ? 'transcript' : 'text',
      // Consent to the server's AI helper is asked separately from voice.
      'provider_consent': aiHelper,
      if (consent.isNotEmpty) 'outside_ai_consent': consent,
    };
    try {
      final url = await base.url();
      final r = await _client
          .post(
            Uri.parse('$url/api/onboarding/turn'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 429) {
        throw GuideTooBusy(
          _reason(r.bodyBytes) ?? 'Too many tries in a short time. Please wait a minute, then try again.',
        );
      }
      if (r.statusCode >= 400 && r.statusCode < 500) {
        // Only the server's own explanation means the answer was refused. A bare 4xx (a
        // Wi-Fi sign-in page, a proxy in the way) is a connection problem: try again.
        final reason = _reason(r.bodyBytes);
        if (reason == null) throw GuideFailure('HTTP ${r.statusCode}');
        throw GuideRejected(reason);
      }
      if (r.statusCode != 200) throw GuideFailure('HTTP ${r.statusCode}');
      return parseTurn(jsonDecode(utf8.decode(r.bodyBytes)));
    } on GuideFailure {
      rethrow;
    } catch (e) {
      base.forget();
      throw GuideFailure('$e');
    }
  }

  /// The server's plain-language error message, if the body has one.
  static String? _reason(List<int> body) {
    try {
      final json = jsonDecode(utf8.decode(body));
      final message = json is Map ? json['message'] : null;
      return message is String && message.trim().isNotEmpty ? message.trim() : null;
    } catch (_) {
      return null;
    }
  }

  static GuideTurn parseTurn(Object? json) {
    if (json is! Map || json['state'] is! Map || json['message'] is! String) {
      throw const GuideFailure('unexpected response');
    }
    final events = json['mascot_events'];
    final mascot = events is List && events.isNotEmpty && events.last is Map
        ? (events.last as Map)['state'] as String? ?? 'asking'
        : 'asking';
    return GuideTurn(
      state: Map<String, dynamic>.from(json['state'] as Map),
      message: json['message'] as String,
      complete: json['complete'] == true,
      mascotState: mascot,
      providerStatus: json['provider_status'] as String? ?? 'not_configured',
      modelInputs: json['model_inputs'] is Map ? Map<String, dynamic>.from(json['model_inputs'] as Map) : null,
      clientAction: json['client_action'] as String?,
      emergency: json['emergency'] == true,
      offTopic: json['off_topic'] == true,
      recommendations: [
        for (final r in (json['recommendations'] is List ? json['recommendations'] as List : const []))
          if (r is Map) Map<String, dynamic>.from(r),
      ],
    );
  }
}
