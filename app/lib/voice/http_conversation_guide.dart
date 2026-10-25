import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_base.dart';
import 'speech.dart';

export 'api_base.dart' show ApiBase, apiBaseUrl;

/// Calls POST /api/onboarding/turn. The state is held by the app, not the server.
class HttpConversationGuide implements ConversationGuide {
  HttpConversationGuide({http.Client? client, String? baseUrl, ApiBase? base})
    : _client = client ?? http.Client(),
      base = base ?? ApiBase(baseUrl ?? apiBaseUrl, client);

  final http.Client _client;
  final ApiBase base;

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
    final body = <String, dynamic>{
      'action': action,
      'state': ?state,
      'text': ?text,
      'values': ?values,
      'import_source': ?importSource,
      'input_mode': fromTranscript ? 'transcript' : 'text',
      // Consent to the server's AI helper is asked separately from voice.
      'provider_consent': aiHelper,
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
    );
  }
}
