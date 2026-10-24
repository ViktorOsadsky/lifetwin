import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/game_health.dart';
import '../../state/twin_look.dart';
import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_button.dart';
import '../../widgets/lt_card.dart';
import '../../widgets/lt_chips.dart';
import '../../widgets/lt_game_health_meter.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_scaffold.dart';
import '../../widgets/lt_twin.dart';
import '../quiz/quiz_state.dart';

/// F10: the twin's reaction. A wrong answer makes it sick (pale green tint,
/// droopy sprout, thermometer); a right one is a sparkle recovery. Game
/// health only: the outlook never changes.
class QuizFeedbackScreen extends ConsumerWidget {
  const QuizFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final answer = ref.watch(lastAnswerProvider);
    final health = ref.watch(gameHealthProvider);
    final look = ref.watch(twinLookProvider);

    // Opened without an answer (for example a direct link): nothing to react to.
    if (answer == null) {
      return LtPage(
        title: 'Quiz feedback',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(LtSpace.gutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Answer a question first.', style: context.text.title2),
                const SizedBox(height: LtSpace.s16),
                LtButton(
                  label: 'Go to the quiz',
                  expand: false,
                  onPressed: () => context.go('/quiz'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final correct = answer.isCorrect;
    final q = answer.question;
    final isLast = answer.questionIndex >= sampleQuestions.length - 1;

    return LtPage(
      title: 'Quiz feedback',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          LtSpace.gutter,
          LtSpace.s8,
          LtSpace.gutter,
          LtSpace.s24,
        ),
        children: [
          Center(child: GameHealthMeter(hearts: health.hearts)),
          const SizedBox(height: LtSpace.s16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: LtSpace.s16),
            decoration: BoxDecoration(
              color: correct ? c.chipPositive : c.calmSurface,
              borderRadius: LtRadius.cardAll,
            ),
            child: Column(
              children: [
                Twin(
                  size: TwinSize.l,
                  look: look,
                  mood: correct ? TwinMood.recovering : TwinMood.sick,
                ),
                const SizedBox(height: LtSpace.s8),
                Text(
                  correct
                      ? 'Sparkle! Feeling better.'
                      : 'Your twin feels a bit off.',
                  style: context.text.title2,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: LtSpace.s12),
          Center(
            child: LtChip(
              label: 'Game health only — your outlook didn’t change',
              background: c.chipSelected,
              foreground: c.textPrimary,
              icon: LtIcons.info,
            ),
          ),
          const SizedBox(height: LtSpace.s16),
          LtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  correct ? 'That’s right' : 'Not quite',
                  style: context.text.headline,
                ),
                const SizedBox(height: LtSpace.s8),
                Text(q.explanation, style: context.text.callout),
                if (!correct) ...[
                  const SizedBox(height: LtSpace.s8),
                  Text(
                    'Answer: ${q.choices[q.correct]}',
                    style: context.text.subhead.copyWith(color: c.textPositive),
                  ),
                ],
                const SizedBox(height: LtSpace.s8),
                Text(
                  'Sample content, not medical advice.',
                  style: context.text.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: LtSpace.s20),
          if (correct)
            LtButton(
              label: isLast ? 'Finish sample round' : 'Next question',
              variant: LtButtonVariant.positive,
              onPressed: () {
                ref.read(gameHealthProvider.notifier).settle();
                ref.read(quizProgressProvider.notifier).next();
                context.pop();
              },
            )
          else
            LtButton(
              label: 'Help it recover',
              onPressed: () {
                ref.read(gameHealthProvider.notifier).settle();
                context.pop();
              },
            ),
          const SizedBox(height: LtSpace.s8),
          LtButton(
            label: 'Back to the room',
            variant: LtButtonVariant.ghost,
            onPressed: () {
              ref.read(gameHealthProvider.notifier).settle();
              context.go('/room');
            },
          ),
        ],
      ),
    );
  }
}
