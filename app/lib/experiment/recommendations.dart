import 'dart:convert';

import 'package:http/http.dart' as http;

import '../twin/twin_experiment.dart';
import '../twin/twin_model.dart';
import '../twin/twin_repository.dart';

import '../voice/api_base.dart';

/// One idea, from a `/api/recommendations` item (`{id, lever, title, message, based_on, wellness_card,
/// source_title, source_url}`).
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
  });

  final String id;
  final String title;

  /// A quote of the person's own words from Mochi's notebook (memory on only).
  final String? habitNoteQuote;

  /// What Mochi says.
  final String tip;
  final String wellnessCardId;

  /// The lever "Try it with my twin" opens.
  final String? leverId;
  final double? leverValue;
}

abstract class RecommendationsSource {
  Future<List<Recommendation>> load();
}

/// Built-in ideas from the engine's own wellness cards, used when the server cannot be reached: one idea per opportunity card the engine returned
/// (at most 3), in Mochi's words from a small table, with a quote from the notebook when
/// memory is on and a note about activity exists.
class StubRecommendations implements RecommendationsSource {
  StubRecommendations(this.repository);
  final TwinRepository repository;

  @override
  Future<List<Recommendation>> load() async {
    final memory = repository.store.memoryConsent;
    final notes = memory ? repository.store.habitNotes : const <Map<String, dynamic>>[];
    String? quoteFor(String topic) {
      for (final n in notes) {
        final note = n['note'];
        if (note is Map && note['topic'] == topic) return '${note['text']}';
      }
      return null;
    }

    final out = <Recommendation>[];
    for (final WellnessCard c in repository.wellnessCards) {
      if (c.level != 'opportunity') continue;
      switch (c.id) {
        case 'smoking':
          out.add(
            const Recommendation(
              id: 'quit',
              title: 'Help to quit',
              tip: 'Quitting helps at any age.',
              wellnessCardId: 'smoking',
              leverId: LeverId.smoking,
              leverValue: 1,
            ),
          );
        case 'activity':
          final q = quoteFor('walks');
          out.add(
            Recommendation(
              id: 'activity',
              title: q == null ? 'First steps count' : 'A longer dog walk',
              habitNoteQuote: q,
              tip: 'A short walk is a great start.',
              wellnessCardId: 'activity',
              leverId: LeverId.moderate,
              leverValue: 90,
            ),
          );
        case 'sleep':
          out.add(
            const Recommendation(
              id: 'sleep',
              title: 'A little more rest',
              tip: 'A bit more sleep can help.',
              wellnessCardId: 'sleep',
              leverId: LeverId.sleepHours,
            ),
          );
      }
    }
    return out.take(3).toList();
  }
}

/// `POST /api/recommendations`: the profile (without wristband values) and, only with memory on, the habit
/// notes. [outsideAiProvider] is set only after a yes to Personal suggestions for that provider; without it
/// the server uses Mochi's own wording and nothing goes to an outside AI. The server keeps nothing. When it
/// cannot be reached, or has nothing to suggest yet, the built-in ideas from the engine's cards are shown.
class HttpRecommendations implements RecommendationsSource {
  HttpRecommendations({required this.repository, required this.base, this.outsideAiProvider, http.Client? client})
    : _client = client ?? http.Client();
  final TwinRepository repository;
  final ApiBase base;
  final String? outsideAiProvider;
  final http.Client _client;

  static const _topics = {'exercise', 'sleep', 'smoking', 'sitting', 'health'};
  static const _noteKeys = ['topic', 'kind', 'with', 'time_of_day', 'frequency', 'barrier'];

  List<Map<String, dynamic>> get _notes {
    if (!repository.store.memoryConsent) return const [];
    return [
      for (final n in repository.store.habitNotes)
        if (n['note'] case final Map note when _topics.contains(note['topic']))
          {
            for (final k in _noteKeys)
              if (note[k] != null) k: note[k],
          },
    ].take(10).toList();
  }

  @override
  Future<List<Recommendation>> load() async {
    try {
      final url = await base.url();
      final r = await _client
          .post(
            Uri.parse('$url/api/recommendations'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'profile': repository.outsideAiProfile(),
              'habit_notes': _notes,
              'outside_ai_consent': {?outsideAiProvider: true},
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return await StubRecommendations(repository).load();
      final ideas = parse(jsonDecode(utf8.decode(r.bodyBytes)));
      return ideas.isEmpty ? await StubRecommendations(repository).load() : ideas;
    } catch (_) {
      base.forget();
      return await StubRecommendations(repository).load();
    }
  }

  /// The ideas in a server reply; empty when it has none yet or is not understood.
  List<Recommendation> parse(Object? json) {
    if (json is! Map || json['status'] != 'ok' || json['recommendations'] is! List) return const [];
    final profile = repository.profile;
    num? has(String k) => profile[k] is num ? profile[k] as num : null;
    final out = <Recommendation>[];
    for (final item in json['recommendations'] as List) {
      if (item is! Map || item['id'] is! String || item['title'] is! String || item['message'] is! String) continue;
      String? lever;
      double? value;
      switch (item['lever']) {
        case 'quit_smoking':
          (lever, value) = (LeverId.smoking, 1);
        case 'vigorous_plus_60':
          (lever, value) = (LeverId.vigorous, (has(LeverId.vigorous) ?? 0) + 60.0);
        case 'moderate_plus_90':
          (lever, value) = (LeverId.moderate, (has(LeverId.moderate) ?? 0) + 90.0);
        case 'short_sleep_plus_1h':
          lever = LeverId.sleepHours;
          value = has(LeverId.sleepHours) == null ? null : (has(LeverId.sleepHours)! + 1).clamp(0, 8).toDouble();
        case 'sitting_minus_60_realistic':
          lever = LeverId.sitting;
          value = has(LeverId.sitting) == null ? null : (has(LeverId.sitting)! - 60).clamp(0, 1440).toDouble();
      }
      out.add(
        Recommendation(
          id: item['id'] as String,
          title: item['title'] as String,
          tip: item['message'] as String,
          wellnessCardId: '${item['wellness_card']}',
          habitNoteQuote: _quote(item['based_on']),
          leverId: lever,
          leverValue: value,
        ),
      );
    }
    return out;
  }

  /// The person's own saved words for the first `note:<topic>` the idea is based on (memory on only).
  String? _quote(Object? basedOn) {
    if (!repository.store.memoryConsent || basedOn is! List) return null;
    for (final b in basedOn) {
      if (b is! String || !b.startsWith('note:')) continue;
      final topic = b.substring(5);
      for (final n in repository.store.habitNotes) {
        final note = n['note'];
        if (note is Map && (note['topic'] == topic || n['topic'] == topic) && note['text'] is String) {
          return note['text'] as String;
        }
      }
    }
    return null;
  }
}
