import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A clearly labelled sample question. This is placeholder game content, not
/// reviewed medical advice, and no answer ever changes an outlook figure.
class QuizQuestion {
  const QuizQuestion({
    required this.prompt,
    required this.choices,
    required this.correct,
    required this.explanation,
  });

  final String prompt;
  final List<String> choices;
  final int correct;
  final String explanation;
}

const sampleQuestions = [
  QuizQuestion(
    prompt:
        'Health guidelines for adults suggest at least how many minutes of '
        'moderate activity a week?',
    choices: ['75 minutes', '150 minutes', '400 minutes'],
    correct: 1,
    explanation:
        'WHO guidance for adults recommends at least 150 minutes of '
        'moderate activity a week. Some is better than none.',
  ),
  QuizQuestion(
    prompt:
        'A supplement label claims a big benefit. Does that prove it works?',
    choices: ['Yes, labels must be proven', 'No, a claim is not evidence'],
    correct: 1,
    explanation:
        'A label is a claim, not evidence. LifeTwin assumes no benefit for a '
        'supplement unless research supports one.',
  ),
  QuizQuestion(
    prompt: 'What does an observational association tell you?',
    choices: [
      'The cause, proven',
      'A pattern in data that may have other explanations',
      'Nothing at all',
    ],
    correct: 1,
    explanation:
        'Associations show patterns in groups of people. Other factors can '
        'explain them, which is why outlooks here are never promises.',
  ),
];

@immutable
class QuizAnswer {
  const QuizAnswer({required this.questionIndex, required this.chosen});

  final int questionIndex;
  final int chosen;

  QuizQuestion get question => sampleQuestions[questionIndex];
  bool get isCorrect => chosen == question.correct;
}

/// Which sample question is next. Advances only after a correct answer.
class QuizProgressNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void next() => state = state + 1;
  void restart() => state = 0;
}

final quizProgressProvider = NotifierProvider<QuizProgressNotifier, int>(
  QuizProgressNotifier.new,
);

class LastAnswerNotifier extends Notifier<QuizAnswer?> {
  @override
  QuizAnswer? build() => null;

  void set(QuizAnswer a) => state = a;
}

final lastAnswerProvider = NotifierProvider<LastAnswerNotifier, QuizAnswer?>(
  LastAnswerNotifier.new,
);
