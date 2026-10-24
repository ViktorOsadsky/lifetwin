import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/lt_twin.dart';

enum QuizOutcome { none, wrong, correct }

/// Quiz / game health. Deliberately separate from every medical input: a
/// wrong answer changes only these hearts and the twin's sick/recovery
/// reaction, never an outlook figure.
@immutable
class GameHealth {
  const GameHealth({this.hearts = max, this.outcome = QuizOutcome.none});

  static const max = 3;

  final int hearts;
  final QuizOutcome outcome;

  TwinMood get mood => switch (outcome) {
    QuizOutcome.wrong => TwinMood.sick,
    QuizOutcome.correct => hearts < max ? TwinMood.recovering : TwinMood.happy,
    QuizOutcome.none => hearts < max ? TwinMood.tired : TwinMood.calm,
  };
}

class GameHealthNotifier extends Notifier<GameHealth> {
  @override
  GameHealth build() => const GameHealth();

  void answer({required bool correct}) {
    state = correct
        ? GameHealth(
            hearts: (state.hearts + 1).clamp(0, GameHealth.max),
            outcome: QuizOutcome.correct,
          )
        : GameHealth(
            hearts: (state.hearts - 1).clamp(0, GameHealth.max),
            outcome: QuizOutcome.wrong,
          );
  }

  /// The reaction has been seen; the twin settles.
  void settle() => state = GameHealth(hearts: state.hearts);
}

final gameHealthProvider = NotifierProvider<GameHealthNotifier, GameHealth>(
  GameHealthNotifier.new,
);
