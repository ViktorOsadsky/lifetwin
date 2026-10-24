import 'dart:convert';

import 'package:http/http.dart' as http;

import 'speech.dart';

const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

/// Calls POST /api/onboarding/turn. The state is held by the app, not the server.
class HttpConversationGuide implements ConversationGuide {
  HttpConversationGuide({http.Client? client, this.baseUrl = apiBaseUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
  }) async {
    final body = <String, dynamic>{
      'action': action,
      'state': ?state,
      'text': ?text,
      'input_mode': fromTranscript ? 'transcript' : 'text',
      // Consent to the server's optional LLM extraction is a separate choice from voice.
      'provider_consent': false,
    };
    try {
      final r = await _client
          .post(Uri.parse('$baseUrl/api/onboarding/turn'),
              headers: {'content-type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw GuideFailure('HTTP ${r.statusCode}');
      return parseTurn(jsonDecode(utf8.decode(r.bodyBytes)));
    } on GuideFailure {
      rethrow;
    } catch (e) {
      throw GuideFailure('$e');
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
    );
  }
}
