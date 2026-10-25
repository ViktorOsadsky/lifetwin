import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class QuizQuestion {
  QuizQuestion._(this.json);
  final Map<String, dynamic> json;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final options = json['options'];
    if (json['review_status'] != 'reviewed' ||
        json['id'] is! String ||
        json['scenario'] is! String ||
        json['explanation'] is! String ||
        options is! List ||
        options.length < 3 ||
        !options.any((o) => o is Map && o['id'] == json['correct_option_id'])) {
      throw const FormatException('A reviewed question is required.');
    }
    for (final key in ['wrong_effect', 'correct_effect', 'review_effect']) {
      if (json[key] is! Map || json[key]['game_health_delta'] is! int) {
        throw const FormatException('A reviewed game effect is required.');
      }
    }
    return QuizQuestion._(Map.unmodifiable(json));
  }

  String get id => json['id'] as String;
  String get scenario => json['scenario'] as String;
  String get explanation => json['explanation'] as String;
  String get correctId => json['correct_option_id'] as String;
  List<Map<String, dynamic>> get options => [
    for (final o in json['options'] as List)
      Map<String, dynamic>.from(o as Map),
  ];
  List<Map<String, dynamic>> get sources => [
    for (final s in json['sources'] as List)
      Map<String, dynamic>.from(s as Map),
  ];
  int effect(String name) => (json[name] as Map)['game_health_delta'] as int;
}

Future<List<QuizQuestion>> loadReviewedQuiz({AssetBundle? bundle}) async {
  final bank = jsonDecode(
    await (bundle ?? rootBundle).loadString('assets/quiz/questions.json'),
  ) as Map;
  final questions = [
    for (final q in bank['questions'] as List)
      QuizQuestion.fromJson(Map<String, dynamic>.from(q as Map)),
  ];
  if (questions.isEmpty ||
      questions.map((q) => q.id).toSet().length != questions.length) {
    throw const FormatException('A unique reviewed question bank is required.');
  }
  return List.unmodifiable(questions);
}

/// Deliberately has no health profile, forecast, score or repository reference.
/// Scoring is immediate, bounded and once per question version, including retries.
class QuizGame extends ChangeNotifier {
  QuizGame(this.questions);
  final List<QuizQuestion> questions;
  final Map<String, String> _answers = {};
  final Set<String> _reviewed = {};
  int _gameHealth = 100;

  int get gameHealth => _gameHealth;
  String? answerFor(QuizQuestion question) => _answers[question.id];
  bool reviewed(QuizQuestion question) => _reviewed.contains(question.id);

  bool answer(QuizQuestion question, String optionId) {
    if (!questions.contains(question) ||
        _answers.containsKey(question.id) ||
        !question.options.any((o) => o['id'] == optionId)) {
      return false;
    }
    _answers[question.id] = optionId;
    _apply(
      question.effect(
        optionId == question.correctId ? 'correct_effect' : 'wrong_effect',
      ),
    );
    return true;
  }

  bool review(QuizQuestion question) {
    final answer = _answers[question.id];
    if (answer == null ||
        answer == question.correctId ||
        !_reviewed.add(question.id)) {
      return false;
    }
    _apply(question.effect('review_effect'));
    return true;
  }

  void _apply(int delta) {
    _gameHealth = (_gameHealth + delta).clamp(0, 100);
    notifyListeners();
  }
}
