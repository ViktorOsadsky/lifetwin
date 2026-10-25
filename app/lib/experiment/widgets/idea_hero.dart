import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../ui/twin_appearance.dart';
import '../../ui/widgets/widgets.dart';
import '../../widgets/whole_word_text.dart';
import '../recommendations.dart';
import 'idea_card.dart';
import 'idea_scene.dart';

/// "Today's idea" (I2-1): Mochi in the room in the pose for the idea's kind, then the card with the
/// pager, the server's title and line, its effect word (or the Guideline chip), "Try it with my twin",
/// "Another idea" and "Not for me".
///
/// For VoiceOver the title, line, effect and pager are one element ("Today's idea: …. Idea 1 of 4."),
/// opening the details, and "Another idea" and "Not for me" are both separate buttons and custom
/// actions on it.
class IdeaHero extends StatelessWidget {
  const IdeaHero({
    super.key,
    required this.idea,
    required this.appearance,
    required this.position,
    required this.total,
    required this.onOpen,
    required this.onEffect,
    required this.onNotForMe,
    this.onTry,
    this.onAnother,
  });

  final Recommendation idea;
  final TwinAppearance appearance;

  /// 1-based place in the deck, and its size.
  final int position;
  final int total;
  final VoidCallback onOpen;
  final VoidCallback onEffect;
  final VoidCallback onNotForMe;
  final VoidCallback? onTry;

  /// Null when there is nothing else to step to.
  final VoidCallback? onAnother;

  String get why => idea.whyShort.isNotEmpty ? idea.whyShort : idea.tip;

  @override
  Widget build(BuildContext context) {
    final word = effectWord(idea.effect);
    final pager = total > 1 ? 'Idea $position of $total' : null;
    final spoken = [
      'Today’s idea: ${idea.title}.',
      why,
      if (word != null)
        'Modeled effect: ${word.toLowerCase()}.'
      else
        'Guideline, not modeled.',
      if (pager != null) '$pager.',
    ].join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IdeaScene(
          key: ValueKey('scene-${idea.id}'),
          appearance: appearance,
          kind: idea.kind,
        ),
        const SizedBox(height: 10),
        Sheet(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                container: true,
                button: true,
                label: spoken,
                hint: 'Opens the details',
                excludeSemantics: true,
                onTap: onOpen,
                customSemanticsActions: {
                  const CustomSemanticsAction(label: 'Another idea'):
                      ?onAnother,
                  const CustomSemanticsAction(label: 'Not for me'): onNotForMe,
                  if (word != null)
                    const CustomSemanticsAction(label: 'What does this mean?'):
                        onEffect,
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 22,
                            color: LtColors.ink,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Today’s idea',
                              style: LtText.body(
                                weight: FontWeight.w700,
                                color: LtColors.secondary,
                              ),
                            ),
                          ),
                          if (pager != null)
                            Text(
                              pager,
                              style: LtText.body(
                                weight: FontWeight.w700,
                                color: LtColors.secondary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      WholeWordText(idea.title, style: LtText.display(28)),
                      const SizedBox(height: 4),
                      WholeWordText(why, style: LtText.body(size: 18)),
                      const SizedBox(height: 8),
                      if (word != null)
                        // Its own tap opens the effect sheet; it is part of the merged element for VoiceOver.
                        EffectCue(effect: idea.effect, onTap: onEffect)
                      else
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: GuidelineChip(),
                        ),
                      const SizedBox(height: 6),
                      WholeWordText(
                        basedOn(idea),
                        style: LtText.body(color: LtColors.secondary),
                      ),
                    ],
                  ),
                ),
              ),
              if (onTry != null) ...[
                const SizedBox(height: 10),
                LipButton(
                  label: 'Try it with my twin',
                  icon: Icons.eco_outlined,
                  height: 56,
                  fontSize: 21,
                  semanticLabel: 'Try it with my twin: ${idea.title}',
                  onTap: onTry,
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                spacing: 12,
                children: [
                  if (onAnother != null)
                    SizedBox(
                      width: 190,
                      child: LipButton(
                        label: 'Another idea',
                        icon: Icons.shuffle_rounded,
                        kind: LipKind.secondary,
                        height: 56,
                        fontSize: 19,
                        onTap: onAnother,
                      ),
                    ),
                  _NotForMe(onTap: onNotForMe),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotForMe extends StatelessWidget {
  const _NotForMe({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Not for me',
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block_rounded, size: 22, color: LtColors.ink),
            const SizedBox(width: 6),
            Text(
              'Not for me',
              style: LtText.body(weight: FontWeight.w700).copyWith(
                decoration: TextDecoration.underline,
                decorationThickness: 2,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The last card of the deck: nothing more to step to today.
class IdeasEndCard extends StatelessWidget {
  const IdeasEndCard({
    super.key,
    required this.appearance,
    required this.onFirst,
  });
  final TwinAppearance appearance;
  final VoidCallback onFirst;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      IdeaScene(
        key: const ValueKey('scene-end'),
        appearance: appearance,
        kind: 'craving',
      ),
      const SizedBox(height: 10),
      Sheet(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: WholeWordText(
                'That’s all for today',
                style: LtText.display(28),
              ),
            ),
            const SizedBox(height: 10),
            LipButton(
              label: 'Back to the first',
              icon: Icons.replay_rounded,
              kind: LipKind.secondary,
              height: 56,
              fontSize: 20,
              onTap: onFirst,
            ),
          ],
        ),
      ),
    ],
  );
}
