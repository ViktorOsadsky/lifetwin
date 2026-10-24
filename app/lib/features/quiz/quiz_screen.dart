import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/game_health.dart';
import '../../state/twin_look.dart';
import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_button.dart';
import '../../widgets/lt_chips.dart';
import '../../widgets/lt_game_health_meter.dart';
import '../../widgets/lt_habitat.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_list.dart';
import '../../widgets/lt_scaffold.dart';
import '../../widgets/lt_twin.dart';
import 'quiz_state.dart';

/// F9 + F10: question, answer choices, game-health hearts and the twin's
/// reaction, all on one screen. A wrong answer makes the twin feel off
/// (pale tint, droopy sprout, thermometer) right here; a right answer is a
/// sparkle recovery. Game health only: the outlook never changes.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _react;

  @override
  void initState() {
    super.initState();
    _react = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void dispose() {
    _react.dispose();
    super.dispose();
  }

  void _answer(int index, int chosen) {
    if (ref.read(gameHealthProvider).outcome != QuizOutcome.none) return;
    final answer = QuizAnswer(questionIndex: index, chosen: chosen);
    // Commit the outcome first, then let the twin react.
    ref.read(lastAnswerProvider.notifier).set(answer);
    ref.read(gameHealthProvider.notifier).answer(correct: answer.isCorrect);
    if (!MediaQuery.of(context).disableAnimations) _react.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(quizProgressProvider);
    final health = ref.watch(gameHealthProvider);
    final look = ref.watch(twinLookProvider);
    final last = ref.watch(lastAnswerProvider);
    final done = index >= sampleQuestions.length;
    final answer = health.outcome != QuizOutcome.none ? last : null;

    final pose = switch (health.outcome) {
      QuizOutcome.wrong => TwinPose.huddle,
      QuizOutcome.correct => TwinPose.cheer,
      QuizOutcome.none => TwinPose.rest,
    };

    return LtPage(
      title: 'Quiz arena',
      sheetToBottom: true,
      child: LayoutBuilder(
        builder: (context, box) {
          // A smaller stage at large text keeps the answers in first view.
          final big = MediaQuery.textScalerOf(context).scale(10) > 13;
          final stageH = (box.maxHeight * (big ? 0.22 : 0.32)).clamp(
            124.0,
            260.0,
          );
          // The meadow runs under the sheet so its feather has no seam.
          const tuck = 64.0;
          final twinW = ((stageH - 18 - 24) / Twin.aspect).clamp(48.0, 200.0);
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: stageH + tuck,
                child: AnimatedBuilder(
                  animation: _react,
                  builder: (context, _) {
                    final v = _react.value;
                    final correct = health.outcome == QuizOutcome.correct;
                    return Habitat(
                      tier: 2,
                      contactLine: (stageH - 18) / (stageH + tuck),
                      fadeTop: 40,
                      fadeBottom: 120,
                      actors: [
                        // Right of centre, clear of the hearts.
                        HabitatActor(
                          x: 0.62,
                          footprint: twinW * 0.78,
                          child: Twin(
                            width: twinW,
                            look: look,
                            mood: health.mood,
                            pose: pose,
                            hop: correct ? math.sin(math.pi * v) * 10 : 0,
                            lean: correct ? 0 : math.sin(math.pi * 2 * v) * 0.4,
                          ),
                        ),
                      ],
                      overlay: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          LtSpace.gutter,
                          LtSpace.s4,
                          LtSpace.gutter,
                          0,
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: GameHealthMeter(hearts: health.hearts),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned.fill(
                top: stageH,
                child: LtSheetPanel(
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(
                            top: LtSpace.s8,
                            bottom: LtSpace.s24,
                          ),
                          children: [
                            if (done)
                              _Done(
                                onAgain: () => ref
                                    .read(quizProgressProvider.notifier)
                                    .restart(),
                              )
                            else
                              _Question(
                                index: index,
                                answer: answer,
                                onAnswer: (chosen) => _answer(index, chosen),
                              ),
                          ],
                        ),
                      ),
                      // The recovery path / next step stays pinned in view
                      // while the twin reacts above.
                      if (!done && answer != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            LtSpace.gutter,
                            LtSpace.s8,
                            LtSpace.gutter,
                            LtSpace.s12,
                          ),
                          child: answer.isCorrect
                              ? LtButton(
                                  label: index >= sampleQuestions.length - 1
                                      ? 'Finish sample round'
                                      : 'Next question',
                                  variant: LtButtonVariant.positive,
                                  onPressed: () {
                                    ref
                                        .read(gameHealthProvider.notifier)
                                        .settle();
                                    ref
                                        .read(quizProgressProvider.notifier)
                                        .next();
                                  },
                                )
                              : LtButton(
                                  label: 'Help it recover',
                                  onPressed: () => ref
                                      .read(gameHealthProvider.notifier)
                                      .settle(),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.onAgain});

  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LtSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sample round done', style: context.text.title2),
          const SizedBox(height: LtSpace.s8),
          Text(
            'Those were the three sample questions. Real questions will '
            'arrive later.',
            style: context.text.subhead,
          ),
          const SizedBox(height: LtSpace.s16),
          LtButton(
            label: 'Back to the room',
            onPressed: () => context.go('/room'),
          ),
          LtTextButton(label: 'Play again', center: true, onPressed: onAgain),
        ],
      ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.index,
    required this.answer,
    required this.onAnswer,
  });

  final int index;
  final QuizAnswer? answer;
  final ValueChanged<int> onAnswer;

  @override
  Widget build(BuildContext context) {
    final q = sampleQuestions[index];
    final c = context.colors;
    final a = answer;
    const pad = EdgeInsets.symmetric(horizontal: LtSpace.gutter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Question ${index + 1} of ${sampleQuestions.length} · sample',
                style: context.text.caption,
              ),
              const SizedBox(height: LtSpace.s4),
              Semantics(
                header: true,
                child: Text(q.prompt, style: context.text.headline),
              ),
            ],
          ),
        ),
        const SizedBox(height: LtSpace.s8),
        LtRowGroup(
          children: [
            for (final (i, choice) in q.choices.indexed)
              _Choice(
                letter: String.fromCharCode(65 + i),
                text: choice,
                state: a == null
                    ? _ChoiceState.open
                    : i == q.correct
                    ? _ChoiceState.right
                    : i == a.chosen
                    ? _ChoiceState.missed
                    : _ChoiceState.locked,
                onTap: a == null ? () => onAnswer(i) : null,
              ),
          ],
        ),
        Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (a != null) ...[
                const SizedBox(height: LtSpace.s16),
                Text(
                  a.isCorrect
                      ? 'That’s right! Your twin perks right up.'
                      : 'Not quite — your twin has a little sniffle. '
                            'Let’s help it feel better.',
                  style: context.text.headline,
                ),
                const SizedBox(height: LtSpace.s4),
                Text(
                  q.explanation,
                  style: context.text.callout.copyWith(color: c.textSecondary),
                ),
              ],
              const SizedBox(height: LtSpace.s16),
              LtNote(
                label: a == null
                    ? 'Game health only — never your outlook'
                    : 'Game health only — your outlook didn’t change',
                icon: LtIcons.info,
              ),
              const SizedBox(height: LtSpace.s4),
              Text(
                'Sample content, not medical advice.',
                style: context.text.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _ChoiceState { open, right, missed, locked }

/// An answer as a plain row: a lettered circle, the text, and after
/// answering a calm tint plus icon (green for right, blue for yours; never
/// red). The press tint fills the row; semantics run the same action.
class _Choice extends StatefulWidget {
  const _Choice({
    required this.letter,
    required this.text,
    required this.state,
    this.onTap,
  });

  final String letter;
  final String text;
  final _ChoiceState state;
  final VoidCallback? onTap;

  @override
  State<_Choice> createState() => _ChoiceState2();
}

class _ChoiceState2 extends State<_Choice> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = widget.state;
    final (tint, mark, markColor, word) = switch (state) {
      _ChoiceState.open => (c.clear, null, c.actionPrimary, ''),
      _ChoiceState.right => (
        c.chipPositive.withValues(alpha: 0.7),
        LtIcons.check,
        c.textPositive,
        'correct answer',
      ),
      // Attention is blue, never red.
      _ChoiceState.missed => (
        c.chipSelected.withValues(alpha: 0.7),
        LtIcons.info,
        c.actionPrimary,
        'your answer',
      ),
      _ChoiceState.locked => (c.clear, null, c.textSecondary, ''),
    };
    final enabled = widget.onTap != null;
    final locked = state == _ChoiceState.locked;
    return Semantics(
      button: true,
      enabled: enabled,
      label: word.isEmpty ? widget.text : '${widget.text}, $word',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 120),
          color: _pressed ? c.chipSelected.withValues(alpha: 0.55) : tint,
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(
            horizontal: LtSpace.gutter,
            vertical: LtSpace.s8,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: mark == null
                      ? (locked ? c.calmSurface : c.iconBackdrop)
                      : c.bgSurface,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: mark == null
                      ? Text(
                          widget.letter,
                          style: context.text.headline.copyWith(
                            color: markColor,
                          ),
                        )
                      : LtIcon(mark, color: markColor, size: 24),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.text,
                  style: context.text.body.copyWith(
                    color: locked ? c.textSecondary : c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
