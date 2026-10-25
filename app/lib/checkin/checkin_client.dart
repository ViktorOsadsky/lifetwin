/// `POST /api/checkin/start` and `/api/checkin/turn` (contracts/checkin.*.schema.json).
/// The server keeps nothing: the app holds the state and sends it back every turn.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../voice/api_base.dart';
import '../voice/backend_http_client.dart';
import '../voice/speech.dart' show GuideFailure, GuideRejected, GuideTooBusy;
import 'checkin_models.dart';

export '../voice/speech.dart' show GuideFailure, GuideRejected, GuideTooBusy;

/// One server turn. [raw] is the whole response, kept for the store.
class CheckinTurn {
  CheckinTurn(this.raw) : state = Map<String, dynamic>.from(raw['state'] as Map), message = raw['message'] as String;

  final Map<String, dynamic> raw;
  final Map<String, dynamic> state;
  final String message;

  bool get complete => raw['complete'] == true;

  /// Something urgent was said: the check-in is paused on the same question. Show the
  /// "Call 911" button (the person taps it) and Continue.
  bool get emergency => raw['emergency'] == true;
  String get phase => (state['phase'] as String?) ?? 'asking';
  bool get isConfirming => phase == 'confirming';
  String get kind => '${state['kind']}';
  String? get currentField => state['current_field'] as String?;

  /// Apple Health's value is offered (quick: in the question, "Does that sound right?"),
  /// or the held exercise minutes came from it.
  bool get fromHealth => state['from_health'] == true;

  /// Answers heard but not saved yet (quick and daily: everything said so far; weekly:
  /// the answer being read back). Null values are left out.
  Map<String, dynamic> get pending => {
    for (final e in Map<String, dynamic>.from(state['pending'] as Map? ?? const {}).entries)
      if (e.value != null) e.key: e.value,
  };

  /// Quick and daily: the fields of [pending] the check question is about ("Did I hear
  /// 15 hours of sleep? That's a lot for one night...").
  List<String> get checking => [for (final f in state['checking'] as List? ?? const []) '$f'];

  /// Quick and daily: the one read-back of every answer at the end (no open question).
  bool get isFinalReadback => isConfirming && currentField == null;

  /// Quick and daily: the one warm reply to a clearly low mood answer is open; the next reply is "keep going" or
  /// "stop". It is not the emergency pause.
  bool get careQuestionOpen => state['care_question_open'] == true;

  /// Quick and daily: a yes/no check about one unusual answer, mid check-in.
  bool get isCheckQuestion => isConfirming && checking.isNotEmpty;

  /// Quick: Apple Health's value is offered in the open question; "Looks right" is the
  /// `confirm` action, and any other answer replaces it.
  bool get offersHealthValue =>
      phase == 'asking' && fromHealth && currentField != null && (state['suggested'] as Map?)?[currentField] != null;

  /// `slower` or `louder`, when the person asked for it.
  String? get speechHint => raw['speech_hint'] as String?;

  String get mascotState {
    final events = raw['mascot_events'];
    if (events is List && events.isNotEmpty && events.last is Map) {
      return ((events.last as Map)['state'] as String?) ?? 'asking';
    }
    return 'asking';
  }

  /// Quick check-ins: the confirmed answers as parts of daily_logs rows.
  List<DayLog> get dailyLogs => [
    for (final row in raw['daily_logs'] as List? ?? const [])
      if (row is Map) DayLog.fromJson(Map<String, dynamic>.from(row)),
  ];

  /// Weekly check-ins: the confirmed answers as profile values (non-null only).
  Map<String, dynamic> get profileUpdate => {
    for (final e in Map<String, dynamic>.from(raw['profile_update'] as Map? ?? const {}).entries)
      if (e.value != null) e.key: e.value,
  };

  /// Questions answered (saved or heard) or skipped (for "question 2 of 3"), not counting
  /// the open one.
  Set<String> get doneFields => {
    for (final e in Map<String, dynamic>.from(state['confirmed'] as Map? ?? const {}).entries)
      if (e.value != null) e.key,
    for (final f in pending.keys)
      if (!checking.contains(f)) f,
    for (final f in state['skipped_fields'] as List? ?? const []) '$f',
  }..remove(currentField);

  List<String> get questions => [for (final q in state['questions'] as List? ?? const []) '$q'];

  static CheckinTurn parse(Object? json) {
    if (json is! Map || json['state'] is! Map || json['message'] is! String) {
      throw const GuideFailure('unexpected response');
    }
    return CheckinTurn(Map<String, dynamic>.from(json));
  }
}

abstract class CheckinGuide {
  /// [kind] is `quick`, `daily` or `weekly`. [previous] holds the last answers, so
  /// "same as yesterday" works; [quick] is the scheduler's plan.
  Future<CheckinTurn> start({
    required String kind,
    required String localDate,
    Map<String, dynamic> previous = const {},
    QuickPlan? quick,
  });

  /// [action] is reply, confirm, skip, cancel or resume.
  Future<CheckinTurn> turn({
    required String action,
    required Map<String, dynamic> state,
    String? text,
    bool fromTranscript = false,
  });
}

class HttpCheckinClient implements CheckinGuide {
  HttpCheckinClient({http.Client? client, ApiBase? base, this.age, this.aiConsent})
    : _client = client ?? BackendHttpClient(),
      base = base ?? ApiBase(apiBaseUrl, client);

  final http.Client _client;
  final ApiBase base;

  /// The profile's age, sent with the start request so Mochi's everyday examples fit (optional; only 18 to 120).
  final Object? Function()? age;

  /// The person's outside-AI consent for the current provider (e.g. `{"claude": true}`), sent with
  /// each turn so the care reply may be worded by that provider. Empty: Mochi's own words.
  final Map<String, bool> Function()? aiConsent;

  @override
  Future<CheckinTurn> start({
    required String kind,
    required String localDate,
    Map<String, dynamic> previous = const {},
    QuickPlan? quick,
  }) => _post('/api/checkin/start', {
    'kind': kind,
    'local_date': localDate,
    'previous': previous,
    if (quick != null) 'quick': quick.toJson(),
    if (age?.call() case final num a when a >= 18 && a <= 120) 'age': a.round(),
  });

  @override
  Future<CheckinTurn> turn({
    required String action,
    required Map<String, dynamic> state,
    String? text,
    bool fromTranscript = false,
  }) => _post('/api/checkin/turn', {
    'action': action,
    'state': state,
    'text': ?text,
    'input_mode': fromTranscript ? 'transcript' : 'text',
    if (_consent() case final c when c.isNotEmpty) 'outside_ai_consent': c,
  });

  // The server knows only these provider ids; anything else would be refused.
  Map<String, bool> _consent() => {
    for (final e in (aiConsent?.call() ?? const <String, bool>{}).entries)
      if (e.value && (e.key == 'claude' || e.key == 'muse')) e.key: true,
  };

  Future<CheckinTurn> _post(String path, Map<String, dynamic> body) async {
    try {
      final url = await base.url();
      final r = await _client
          .post(Uri.parse('$url$path'), headers: {'content-type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 429) {
        throw GuideTooBusy(
          _reason(r.bodyBytes) ?? 'Too many tries in a short time. Please wait a minute, then try again.',
        );
      }
      if (r.statusCode >= 400 && r.statusCode < 500) {
        // Only the server's own explanation means it refused; a bare 4xx is the network.
        final reason = _reason(r.bodyBytes);
        if (reason == null) throw GuideFailure('HTTP ${r.statusCode}');
        throw GuideRejected(reason);
      }
      if (r.statusCode != 200) throw GuideFailure('HTTP ${r.statusCode}');
      return CheckinTurn.parse(jsonDecode(utf8.decode(r.bodyBytes)));
    } on GuideFailure {
      rethrow;
    } catch (e) {
      base.forget();
      throw GuideFailure('$e');
    }
  }

  static String? _reason(List<int> body) {
    try {
      final json = jsonDecode(utf8.decode(body));
      final message = json is Map ? json['message'] : null;
      return message is String && message.trim().isNotEmpty ? message.trim() : null;
    } catch (_) {
      return null;
    }
  }
}
