import 'package:flutter/material.dart';

import '../twin/twin_model.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';
import '../widgets/whole_word_text.dart';
import 'experiment_page.dart';
import 'experiment_twins.dart';
import 'lever_copy.dart';
import 'recommendations.dart';
import 'widgets/widgets.dart';

/// "Ideas for you" (Y-11 with Mochi's notebook, Y-14 without): up to three ideas, two shown, each
/// grounded in an engine wellness card.
///
/// What is on the card is Mochi's own words (and, with memory on, the person's own words from
/// the notebook), never a quote from the source. The source chip opens a sheet with the engine
/// card's text word for word and its link. "Try it with my twin" opens the lever in the
/// Experiment. No numbers, and no supplements, ever.
class IdeasScreen extends StatelessWidget {
  const IdeasScreen({
    super.key,
    required this.appearance,
    required this.ideas,
    required this.cards,
    required this.memoryOn,
    required this.onBack,
    required this.onTry,
    this.onMemory,
    this.open = defaultOpenUrl,
  });

  final TwinAppearance appearance;
  final List<Recommendation> ideas;
  final List<WellnessCard> cards;

  /// Mochi's notebook is on: quotes may show.
  final bool memoryOn;
  final VoidCallback onBack;

  /// "Try it with my twin": opens the lever.
  final void Function(Recommendation idea) onTry;

  /// Memory is off: opens the memory setting (it never turns on by itself).
  final VoidCallback? onMemory;
  final OpenUrl open;

  @override
  Widget build(BuildContext context) {
    final shown = ideas.take(2).toList();
    return ExperimentPage(
      mode: LtMode.room,
      onBack: onBack,
      backLabel: 'Back to room',
      dock: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom),
        child: LipButton(label: 'Go to my room', icon: Icons.home_rounded, fontSize: 24, onTap: onBack),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentPlate(
            appearance: appearance,
            twins: const [TwinSlot(state: steadyTwin, x: 0.3)],
            bubble: memoryOn ? 'I listened! Two ideas:' : 'Two ideas to start with.',
          ),
          const SizedBox(height: 14),
          Sheet(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(header: true, child: Text('Ideas for you', style: LtText.display(28))),
                    ),
                    if (memoryOn)
                      Container(
                        constraints: const BoxConstraints(minHeight: 32),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: LtColors.control, width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.favorite_border_rounded, size: 18, color: LtColors.ink),
                            const SizedBox(width: 6),
                            Text('Notebook on', style: LtText.body(weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
                if (!memoryOn && onMemory != null) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    button: true,
                    label: 'Let Mochi remember the little things. Opens memory settings.',
                    excludeSemantics: true,
                    onTap: onMemory,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onMemory,
                      child: DashedBox(
                        color: LtColors.control,
                        radius: 22,
                        width: 2,
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                        constraints: const BoxConstraints(minHeight: 64),
                        child: Row(
                          children: [
                            const LeverIcon(Icons.favorite_border_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ideas that fit your day?',
                                    style: LtText.body(size: 18, weight: FontWeight.w700),
                                  ),
                                  WholeWordText(
                                    'Let me remember the little things.',
                                    style: LtText.body(color: LtColors.secondary),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: 28, color: LtColors.ink),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final i in shown) ...[
            const SizedBox(height: 14),
            _IdeaCard(idea: i, memoryOn: memoryOn, cards: cards, onTry: onTry, open: open),
          ],
        ],
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    required this.idea,
    required this.memoryOn,
    required this.cards,
    required this.onTry,
    required this.open,
  });
  final Recommendation idea;
  final bool memoryOn;
  final List<WellnessCard> cards;
  final void Function(Recommendation) onTry;
  final OpenUrl open;

  @override
  Widget build(BuildContext context) {
    final card = cards.where((c) => c.id == idea.wellnessCardId).firstOrNull;
    final copy = idea.leverId == null ? null : LeverCopy.of(idea.leverId!);
    final quote = memoryOn ? idea.habitNoteQuote : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: LtColors.paper,
        borderRadius: BorderRadius.circular(LtRadii.panel),
        border: Border.all(color: LtColors.container, width: LtBorders.container),
        boxShadow: LtShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LeverIcon(copy?.icon ?? Icons.eco_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(header: true, child: Text(idea.title, style: LtText.display(22))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (quote != null)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: const BoxDecoration(
                color: Color(0xFFF1EFFD),
                border: Border(left: BorderSide(color: LtColors.lavender, width: 4)),
                borderRadius: BorderRadius.horizontal(right: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: LtColors.ink),
                  const SizedBox(width: 8),
                  Expanded(child: WholeWordText('You said: “$quote”', style: LtText.body())),
                ],
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.chat_bubble_outline_rounded, size: 18, color: LtColors.ink),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WholeWordText.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Mochi: ',
                          style: LtText.body(weight: FontWeight.w700),
                        ),
                        TextSpan(text: idea.tip, style: LtText.body()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          if (card != null) _SourceChip(card: card, open: open),
          const SizedBox(height: 4),
          LipButton(
            label: 'Try it with my twin',
            icon: Icons.eco_outlined,
            kind: LipKind.secondary,
            height: 56,
            fontSize: 21,
            semanticLabel: 'Try it with my twin: opens ${copy?.full ?? 'the Experiment'}',
            onTap: idea.leverId == null ? null : () => onTry(idea),
          ),
        ],
      ),
    );
  }
}

/// The source chip: opens a sheet with the engine card's text word for word, and its link.
class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.card, required this.open});
  final WellnessCard card;
  final OpenUrl open;

  @override
  Widget build(BuildContext context) {
    final label = '${SourceLink.siteName(card.sourceUrl)}: ${card.title}';
    void tap() => showInfoSheet(
      context,
      title: card.title,
      body: card.message,
      extra: SourceLink(label: label, url: card.sourceUrl, open: open),
    );
    return Semantics(
      button: true,
      label: 'Source: $label, opens the guidance',
      excludeSemantics: true,
      onTap: tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              const Icon(Icons.open_in_new_rounded, size: 22, color: LtColors.ink),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: LtText.body(weight: FontWeight.w700)
                      .copyWith(decoration: TextDecoration.underline, decorationThickness: 2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
