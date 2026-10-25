import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/quiz/quiz_game.dart';
import 'package:lifesim/twin/twin_model.dart' show HealthScoreStatus;
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

  test('the score shows only when the model gave one for an adult, never rescaled', () {
    expect(const WellnessSnapshot().displayScore, isNull);
    expect(const WellnessSnapshot(healthScore: 0.66).displayScore, isNull);
    expect(
      const WellnessSnapshot(healthScore: 0.66, status: HealthScoreStatus.available).displayScore,
      0.66,
    );
    const rough = WellnessSnapshot(healthScore: 1.3, status: HealthScoreStatus.extrapolated);
    expect(rough.displayScore, 1.3);
    expect(rough.roughGuide, isTrue);
    const young = WellnessSnapshot(healthScore: 0.2, status: HealthScoreStatus.underAge);
    expect(young.displayScore, isNull);
    expect(young.underAge, isTrue);
    expect(formatHealthScore(0.66), '+0.66');
    expect(formatHealthScore(-1.26), '−1.26');
    expect(formatHealthScore(0.0), '0.00');
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
