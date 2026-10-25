import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/quiz/quiz_game.dart';
import 'package:lifesim/wellness/models.dart';
import 'package:lifesim/wellness/outlook_drivers_screen.dart';

Map<String, dynamic> question([String id = 'example.v1']) => {
  'id': id,
  'review_status': 'reviewed',
  'scenario': 'Which label has the smaller serving?',
  'options': [
    {'id': 'a', 'text': 'First label'},
    {'id': 'b', 'text': 'Second label'},
    {'id': 'c', 'text': 'The same'},
  ],
  'correct_option_id': 'b',
  'explanation': 'Read the serving size before comparing the numbers.',
  'sources': [
    {
      'publisher': 'FDA',
      'title': 'Food labels',
      'url': 'https://www.fda.gov/food',
    },
  ],
  'wrong_effect': {'game_health_delta': -5},
  'correct_effect': {'game_health_delta': 5},
  'review_effect': {'game_health_delta': 5},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy numerical effects never reach the directions-only driver copy',
    () {
      expect(
        const OutlookDriver(
          label: 'Movement',
          direction: DriverDirection.higher,
          reason: '0.7 percentage points',
        ).displayReason,
        'A model association, not a promised benefit.',
      );
      expect(
        const OutlookDriver(
          label: 'Sleep',
          direction: DriverDirection.flat,
          reason: 'No supported difference.',
        ).displayReason,
        'No supported difference.',
      );
    },
  );

  test('scores stay unknown until a valid score is supplied', () {
    expect(const WellnessSnapshot().displayScore, isNull);
    expect(const WellnessSnapshot(healthScore: -1).displayScore, isNull);
    expect(const WellnessSnapshot(healthScore: 101).displayScore, isNull);
    expect(const WellnessSnapshot(healthScore: 0).displayScore, 0);
    expect(const WellnessSnapshot(healthScore: 100).displayScore, 100);
  });

  test('trend uses local calendar days, no forward fill and no zero for missing data', () {
    final history = [
      WellnessDay(date: DateTime(2026, 10, 23, 20), healthScore: 72),
      WellnessDay(date: DateTime(2026, 10, 25), healthScore: 80),
    ];
    final days = lastSevenDays(history, DateTime(2026, 10, 24, 23));
    expect(days.length, 7);
    expect(days.first.date, DateTime(2026, 10, 18));
    expect(days.last.date, DateTime(2026, 10, 24));
    expect(days.map((d) => d.healthScore), [
      null,
      null,
      null,
      null,
      null,
      72,
      null,
    ]);
  });

  test('unknown provenance is not invented, estimated stays visible', () {
    expect(ValueSource.fromWire('you_said'), ValueSource.youSaid);
    expect(ValueSource.fromWire('wristband'), ValueSource.wristband);
    expect(ValueSource.fromWire('anything_else'), isNull);
    expect(
      const HistoryValue(label: 'Sleep', value: '7 h').provenance,
      'Source not recorded',
    );
    expect(
      const HistoryValue(
        label: 'Sleep',
        value: '7 h',
        source: ValueSource.appleHealth,
        estimated: true,
      ).provenance,
      'Apple Health · Estimated',
    );
  });

  test(
    'quiz scoring is once per question version, immediate and recoverable once',
    () {
      final q = QuizQuestion.fromJson(question());
      final game = QuizGame([q]);
      addTearDown(game.dispose);
      expect(game.answer(q, 'a'), isTrue);
      expect(game.gameHealth, 95);
      expect(game.answer(q, 'a'), isFalse);
      expect(game.answer(q, 'b'), isFalse);
      expect(game.gameHealth, 95);
      expect(game.review(q), isTrue);
      expect(game.gameHealth, 100);
      expect(game.review(q), isFalse);
      expect(game.answer(q, 'b'), isFalse);
      expect(game.gameHealth, 100);
    },
  );

  test('unreviewed and unknown answers cannot become scored failures', () {
    expect(
      () => QuizQuestion.fromJson({...question(), 'review_status': 'draft'}),
      throwsFormatException,
    );
    final q = QuizQuestion.fromJson(question());
    final game = QuizGame([q]);
    addTearDown(game.dispose);
    expect(game.answer(q, 'missing'), isFalse);
    expect(game.review(q), isFalse);
    expect(game.gameHealth, 100);
  });

  test(
    'all bundled questions are reviewed, load offline and stay bounded',
    () async {
      final questions = await loadReviewedQuiz();
      expect(questions.length, 8);
      final game = QuizGame(questions);
      addTearDown(game.dispose);
      for (final q in questions) {
        final wrong =
            q.options.firstWhere((o) => o['id'] != q.correctId)['id'] as String;
        game.answer(q, wrong);
        expect(game.gameHealth, inInclusiveRange(0, 100));
        game.review(q);
        expect(game.gameHealth, 100);
      }
    },
  );
}
