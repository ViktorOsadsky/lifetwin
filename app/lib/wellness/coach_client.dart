import 'dart:convert';

import 'package:http/http.dart' as http;

import '../voice/api_base.dart';

class CoachFailure implements Exception {
  const CoachFailure(this.statusCode);
  final int? statusCode;
}

class DailyPlan {
  DailyPlan._(this.json, this.items);
  final Map<String, dynamic> json;
  final List<Map<String, dynamic>> items;

  static bool _supplementText(String text) => RegExp(
    r'\b(supplements?|vitamins?|dosage|capsules?)\b',
    caseSensitive: false,
  ).hasMatch(text);

  factory DailyPlan.fromJson(Object? value) {
    if (value is! Map ||
        value['schema_version'] != '1.0' ||
        !['ok', 'emergency'].contains(value['status']) ||
        value['items'] is! List) {
      throw const FormatException('The plan is unavailable.');
    }
    final json = Map<String, dynamic>.from(value);
    if (json['status'] == 'ok' &&
        (json['revision_id'] is! String ||
            json['local_date'] is! String ||
            json['inputs'] is! Map ||
            (json['inputs'] as Map)['snapshot_id'] is! String)) {
      throw const FormatException('The plan is unavailable.');
    }
    final items = <Map<String, dynamic>>[];
    for (final raw in json['items'] as List) {
      if (raw is! Map) throw const FormatException('The plan is unavailable.');
      final item = Map<String, dynamic>.from(raw);
      // The assigned UI must never render supplement suggestions. Unknown kinds
      // are not silently promoted to a supported action.
      if (!['workout', 'diet', 'habit', 'encourage'].contains(item['kind']) ||
          _supplementText(
            '${item['title']} ${item['message']} ${item['why']}',
          )) {
        continue;
      }
      if ([
        'id',
        'catalog_id',
        'title',
        'message',
        'why',
        'time_of_day',
        'source_url',
        'source_title',
      ].any((k) => item[k] is! String)) {
        throw const FormatException('The plan is unavailable.');
      }
      final source = Uri.tryParse(item['source_url'] as String);
      if (!['morning', 'afternoon', 'evening'].contains(item['time_of_day']) ||
          item['minutes'] != null &&
              (item['minutes'] is! int ||
                  item['minutes'] < 1 ||
                  item['minutes'] > 120) ||
          items.any((other) => other['id'] == item['id']) ||
          source == null ||
          source.scheme != 'https' ||
          source.host.isEmpty ||
          item['causal_interpretation'] != false) {
        throw const FormatException('The plan is unavailable.');
      }
      items.add(Map.unmodifiable(item));
    }
    return DailyPlan._(Map.unmodifiable(json), List.unmodifiable(items));
  }

  bool get emergency =>
      json['emergency'] == true || json['status'] == 'emergency';
  bool get paused => emergency || json['movement_paused'] == true;
  /// Nothing new arrived since the earlier plan: the same revision came back.
  bool get reusedPrevious => json['reused_previous'] == true;
  bool get general => json['plan_type'] == 'general';
  String? get revision => json['revision_id'] as String?;
  /// One line per real change to the day's activity, food or habit, in the coach's own words: kept items and
  /// Mochi's fresh encouragement are not changes.
  List<String> get changedLines {
    final kinds = {for (final i in items) i['id']: i['kind']};
    return [
      for (final c in json['changes'] as List? ?? const [])
        if (c is Map &&
            c['explanation'] is String &&
            c['change'] != 'kept' &&
            kinds[c['item_id']] != 'encourage' &&
            !_supplementText(c['explanation'] as String))
          c['explanation'] as String,
    ];
  }

  List<String> get changes => [
    for (final c in json['changes'] as List? ?? const [])
      if (c is Map &&
          c['explanation'] is String &&
          !_supplementText(c['explanation'] as String))
        c['explanation'] as String,
  ];

  List<Map<String, dynamic>> get trace => [
    for (final raw in json['trace'] as List? ?? const [])
      if (raw is Map &&
          ['rule', 'evidence', 'action'].every((k) => raw[k] is String) &&
          !_supplementText(
            '${raw['rule']} ${raw['evidence']} ${raw['action']}',
          ))
        Map<String, dynamic>.from(raw),
  ];

  Map<String, dynamic> previousPlan() => {
    'revision_id': revision,
    'based_on': json['based_on'],
    'local_date': json['local_date'],
    'input_snapshot_id': (json['inputs'] as Map)['snapshot_id'],
    'items': [
      for (final item in json['items'] as List)
        {
          for (final key in [
            'id',
            'kind',
            'catalog_id',
            'minutes',
            'time_of_day',
            'callback_note_id',
          ])
            key: (item as Map)[key],
        },
    ],
  };
}

/// The coach's request wants `general_health` as a label; the phone keeps the model's 1-5.
/// 1 excellent, 2 very good, 3 good, 4 fair, 5 poor. A label already there is passed through unchanged.
const _generalHealthLabels = {1: 'excellent', 2: 'very_good', 3: 'good', 4: 'fair', 5: 'poor'};

Map<String, dynamic> coachRequestBody(Map<String, dynamic> context) {
  final profile = context['profile'];
  if (profile is! Map) return context;
  final health = profile['general_health'];
  final number = health is num && health == health.roundToDouble() ? health.toInt() : null;
  final label = number == null ? null : _generalHealthLabels[number];
  if (label == null) return context;
  return {
    ...context,
    'profile': {...profile, 'general_health': label},
  };
}

abstract class CoachClient {
  Future<DailyPlan> plan(Map<String, dynamic> confirmedContext);
  void close() {}
}

class HttpCoachClient implements CoachClient {
  HttpCoachClient({ApiBase? base, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      base = base ?? ApiBase();
  final ApiBase base;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<DailyPlan> plan(Map<String, dynamic> confirmedContext) async {
    try {
      final url = await base.url();
      final response = await _client
          .post(
            Uri.parse('$url/api/coach/plan'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(coachRequestBody(confirmedContext)),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw CoachFailure(response.statusCode);
      return DailyPlan.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } on CoachFailure {
      rethrow;
    } catch (_) {
      base.forget();
      throw const CoachFailure(null);
    }
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
