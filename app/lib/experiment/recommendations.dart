import '../twin/twin_experiment.dart';
import '../twin/twin_model.dart';
import '../twin/twin_repository.dart';

/// Ideas for you (Y-11, Y-14) are built but switched off until `POST /api/recommendations`
/// lands. Flip this when it does, and replace [StubRecommendations] with a client.
const recommendationsEnabled = false;

/// One idea. ASSUMED shape of a `/api/recommendations` item (brief-agentic-v1; the schema has
/// not landed): `{id, title, habit_note_quote|null, tip, wellness_card_id, source_label,
/// source_url, experiment: {lever_id, value}}`.
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

/// Stub data until the endpoint lands: one idea per opportunity card the engine returned
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
