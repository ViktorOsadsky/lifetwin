import 'dart:convert';

import 'package:http/http.dart' as http;

import '../twin/profile_mapping.dart';
import '../twin/twin_experiment.dart';
import '../twin/twin_repository.dart';
import '../voice/api_base.dart';
import '../voice/backend_http_client.dart';
import '../wellness/coach_client.dart' show coachRequestBody;
import '../wellness/coach_context.dart';

/// One idea, from a `/api/recommendations` item ([Recommendation.fromJson]) or the stub.
///
/// [tip] is Mochi's own words, never presented as a quote from the source. The engine card's
/// text is shown word for word in the source sheet, from the card matching [wellnessCardId].
/// Nothing here carries a model number, and supplements are never suggested.
class Recommendation {
  const Recommendation({
    required this.id,
    required this.title,
    required this.tip,
    required this.wellnessCardId,
    this.habitNoteQuote,
    this.leverId,
    this.leverValue,
    this.whyShort = '',
    this.effect,
    this.sourceTitle,
    this.sourceUrl,
    this.sourceDomain = '',
    this.kind,
    this.lever,
    this.alternatives = const [],
  });

  /// Reads one server item. A lever the app does not know, or a target the server left
  /// empty (the person's current value is missing), is dropped rather than guessed.
  factory Recommendation.fromJson(Map<String, dynamic> json) {
    for (final k in ['id', 'title', 'message', 'wellness_card']) {
      if (json[k] is! String) throw const FormatException('The ideas are unavailable.');
    }
    final lever = _levers.contains(json['experiment_lever']) ? json['experiment_lever'] as String : null;
    final target = json['experiment_target'];
    final value = switch (target) {
      num n => n.toDouble(),
      String code when lever == LeverId.smoking => smokingCodes[code]?.toDouble(),
      _ => null,
    };
    String? text(String k) => json[k] is String && (json[k] as String).isNotEmpty ? json[k] as String : null;
    return Recommendation(
      id: json['id'] as String,
      title: json['title'] as String,
      tip: json['message'] as String,
      wellnessCardId: json['wellness_card'] as String,
      leverId: lever,
      leverValue: lever == null ? null : value,
      whyShort: text('why_short') ?? '',
      effect: text('effect'),
      sourceTitle: text('source_title'),
      sourceUrl: text('source_url'),
      sourceDomain: text('source_domain') ?? '',
      kind: text('kind'),
      lever: text('lever'),
      // Alternatives have the same shape and their own effect and source; one that cannot be read
      // is dropped, and a supplement idea is never shown.
      alternatives: [
        for (final a in (json['alternatives'] is List ? json['alternatives'] as List : const []))
          if (a is Map && !_supplementText('${a['title']} ${a['message']} ${a['why_short']}'))
            ?_tryParse(Map<String, dynamic>.from(a)),
      ].take(3).toList(),
    );
  }

  static Recommendation? _tryParse(Map<String, dynamic> json) {
    try {
      return Recommendation.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  static const _levers = {LeverId.sleepHours, LeverId.moderate, LeverId.vigorous, LeverId.sitting, LeverId.smoking};

  final String id;
  final String title;

  /// A quote of the person's own words from Mochi's notebook (memory on only).
  final String? habitNoteQuote;

  /// What Mochi says.
  final String tip;
  final String wellnessCardId;

  /// The lever "Try it with my twin" opens, and the value to preset (null: leave it where it is).
  final String? leverId;
  final double? leverValue;

  /// One plain line for a two-line card (server only; empty for the stub).
  final String whyShort;

  /// "big", "some", "small" or "tiny" for people like this person; null when not modeled.
  final String? effect;
  final String? sourceTitle;
  final String? sourceUrl;
  final String sourceDomain;

  /// walk | dance | stand | stretch | sleep | eat | social | breath | craving. It picks Mochi's
  /// pose and props only; it never changes the wording or the effect. Null: unknown.
  final String? kind;

  /// The idea's lever as the server names it. The id is opaque; logic keys on this, never on the id.
  final String? lever;

  /// Up to three other ideas for the same lever, each with its own effect and source.
  final List<Recommendation> alternatives;
}

/// A whole `/api/recommendations` answer: the ideas, and `featured` (an idea id or null, stable for
/// the calendar day).
class IdeasResponse {
  const IdeasResponse({required this.recommendations, this.featuredId, this.raw});

  /// Reads the answer. Items that cannot be read throw; supplement ideas are left out.
  factory IdeasResponse.fromJson(Map<String, dynamic> json) {
    if (json['recommendations'] is! List) throw const FormatException('The ideas are unavailable.');
    final recs = [
      for (final item in json['recommendations'] as List)
        if (item is Map && !_supplementText('${item['title']} ${item['message']} ${item['why_short']}'))
          Recommendation.fromJson(Map<String, dynamic>.from(item)),
    ].take(3).toList();
    return IdeasResponse(
      recommendations: recs,
      featuredId: json['featured'] is String ? json['featured'] as String : null,
      raw: json,
    );
  }

  final List<Recommendation> recommendations;
  final String? featuredId;

  /// The server's answer as received, kept so the phone can cache it for the day.
  final Map<String, dynamic>? raw;
}

final _supplementPattern = RegExp(
  r'\b(supplements?|vitamins?|dosage|capsules?|pre-?workout|energy drinks?|caffeine pills?)\b',
  caseSensitive: false,
);
bool _supplementText(String text) => _supplementPattern.hasMatch(text);

abstract class RecommendationsSource {
  Future<List<Recommendation>> load();
}

/// A source that also gives `featured` and takes `excluded_ids` (the ideas hidden today).
abstract interface class FullIdeasSource {
  Future<IdeasResponse> fetch({List<String> excludedIds = const []});
}

class RecommendationsFailure implements Exception {
  const RecommendationsFailure(this.statusCode);
  final int? statusCode;
}

/// The habit-note fields the server's `HabitNote` accepts (it rejects any other key).
const _noteKeys = {
  'topic',
  'kind',
  'with',
  'time_of_day',
  'frequency',
  'barrier',
  'bedtime',
  'wake_time',
  'wakes_for',
  'naps',
  'smoked_years',
  'tried_quitting',
  'quit_aid',
  'quit_ago',
  'feeling',
  'concern',
  'reading',
  'estimate_for',
  'estimate',
  'source',
};

/// The request body: the same profile the coach gets (band values stay on the phone), the
/// last 10 notes only with memory consent, and the outside-AI consent for the one provider.
Map<String, dynamic> recommendationsRequestBody(
  TwinRepository repo, {
  String? localDate,
  List<String> excludedIds = const [],
}) {
  final context = coachRequestBody(coachContext(repo));
  final notes = [
    for (final n in (context['habit_notes'] as List? ?? const []))
      {
        for (final e in (n as Map).entries)
          if (_noteKeys.contains(e.key)) e.key: e.value,
      },
  ];
  return {
    'profile': context['profile'],
    'habit_notes': notes.skip(notes.length > 10 ? notes.length - 10 : 0).toList(),
    'outside_ai_consent': context['outside_ai_consent'],
    'local_date': ?localDate,
    if (excludedIds.isNotEmpty) 'excluded_ids': excludedIds,
  };
}

/// The phone's calendar day, "2026-10-25".
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `POST /api/recommendations`. A failure is a [RecommendationsFailure]; the screen shows a
/// gentle line and the app goes on.
class HttpRecommendations implements RecommendationsSource, FullIdeasSource {
  HttpRecommendations(this.repository, {ApiBase? base, http.Client? client, DateTime Function()? now})
    : _client = client ?? BackendHttpClient(),
      _now = now ?? DateTime.now,
      base = base ?? ApiBase();
  final TwinRepository repository;
  final ApiBase base;
  final http.Client _client;
  final DateTime Function() _now;

  @override
  Future<List<Recommendation>> load() async => (await fetch()).recommendations;

  /// The ideas, `featured` and all. [excludedIds] are the ideas hidden today; a server that does
  /// not know the field ignores it, and the app hides them itself either way.
  @override
  Future<IdeasResponse> fetch({List<String> excludedIds = const []}) async {
    try {
      final url = await base.url();
      final response = await _client
          .post(
            Uri.parse('$url/api/recommendations'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(
              recommendationsRequestBody(repository, localDate: dayKey(_now()), excludedIds: excludedIds),
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw RecommendationsFailure(response.statusCode);
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map) throw const FormatException('The ideas are unavailable.');
      return IdeasResponse.fromJson(Map<String, dynamic>.from(json));
    } on RecommendationsFailure {
      rethrow;
    } catch (_) {
      base.forget();
      throw const RecommendationsFailure(null);
    }
  }
}
