import 'dart:convert';

import 'package:http/http.dart' as http;

import '../voice/api_base.dart';

/// Daily is the light 1-minute chat; weekly is the longer read-back of the week.
enum CheckInKind { daily, weekly }

/// A check-in or change-conversation reply (`contracts/checkin.schema.json`,
/// `contracts/change.schema.json`). [raw] is kept whole because `TwinRepository.applyCheckin`
/// takes the reply as it came.
class CheckInResponse {
  CheckInResponse(this.raw);

  final Map<String, dynamic> raw;

  String get message => raw['message'] as String? ?? '';
  Map<String, dynamic> get state => Map<String, dynamic>.from(raw['state'] as Map? ?? const {});
  bool get complete => raw['complete'] == true;

  /// A calm pause: nothing is saved, no next question, state unchanged (never auto-dial).
  bool get emergency => raw['emergency'] == true;
  String get phase => state['phase'] as String? ?? 'asking';
  String? get currentField => state['current_field'] as String?;
  List<String> get questions => [for (final q in state['questions'] as List? ?? const []) '$q'];
  Map<String, dynamic> get confirmed => Map<String, dynamic>.from(state['confirmed'] as Map? ?? const {});
  Map<String, dynamic> get pending => Map<String, dynamic>.from(state['pending'] as Map? ?? const {});
  List<String> get skipped => [for (final q in state['skipped_fields'] as List? ?? const []) '$q'];

  /// Non-null fields of `profile_update`: what a finished weekly check-in or change sets.
  Map<String, dynamic> get profileUpdate => {
    for (final e in (raw['profile_update'] as Map? ?? const {}).entries)
      if (e.value != null) '${e.key}': e.value,
  };

  /// The change conversation's habit note (`{field, text}`), only with memory consent.
  Map<String, dynamic>? get habitNote =>
      raw['habit_note'] is Map ? Map<String, dynamic>.from(raw['habit_note'] as Map) : null;
}

/// The check-in conversation: `POST /api/checkin/start` and `/turn`. The state is held by the app.
abstract class CheckInClient {
  Future<CheckInResponse> start(CheckInKind kind, {String? localDate, Map<String, dynamic> previous = const {}});

  /// [action]: reply | confirm | skip | cancel | resume.
  Future<CheckInResponse> turn({
    required String action,
    required Map<String, dynamic> state,
    String? text,
    bool fromTranscript = false,
  });
}

class CheckInFailure implements Exception {
  const CheckInFailure(this.message);
  final String message;
  @override
  String toString() => 'CheckInFailure($message)';
}

/// The check-in over HTTP (no personal data beyond the answers; the server keeps nothing).
class HttpCheckInClient implements CheckInClient {
  HttpCheckInClient({http.Client? client, ApiBase? base}) : _client = client ?? http.Client(), base = base ?? ApiBase();

  final http.Client _client;
  final ApiBase base;

  @override
  Future<CheckInResponse> start(CheckInKind kind, {String? localDate, Map<String, dynamic> previous = const {}}) =>
      _post('/api/checkin/start', {
        'kind': kind.name,
        'local_date': ?localDate,
        if (previous.isNotEmpty) 'previous': previous,
      });

  @override
  Future<CheckInResponse> turn({
    required String action,
    required Map<String, dynamic> state,
    String? text,
    bool fromTranscript = false,
  }) => _post('/api/checkin/turn', {
    'action': action,
    'state': state,
    'text': ?text,
    'input_mode': fromTranscript ? 'transcript' : 'text',
  });

  Future<CheckInResponse> _post(String path, Map<String, dynamic> body) async {
    try {
      final url = await base.url();
      final r = await _client
          .post(Uri.parse('$url$path'), headers: {'content-type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw CheckInFailure('HTTP ${r.statusCode}');
      final json = jsonDecode(utf8.decode(r.bodyBytes));
      if (json is! Map || json['state'] is! Map || json['message'] is! String) {
        throw const CheckInFailure('unexpected reply');
      }
      return CheckInResponse(Map<String, dynamic>.from(json));
    } on CheckInFailure {
      rethrow;
    } catch (e) {
      base.forget();
      throw CheckInFailure('$e');
    }
  }
}
