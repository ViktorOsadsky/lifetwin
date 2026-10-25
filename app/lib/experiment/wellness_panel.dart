import 'package:flutter/material.dart';

import '../twin/twin_model.dart';
import '../ui/theme.dart';
import '../widgets/whole_word_text.dart';
import 'experiment_copy.dart';
import 'widgets/widgets.dart';

/// The engine's public-health guidance cards (CDC, `derived_from_survival_model: false`),
/// as the Room shows them (Y-12): "Going well" for strengths, "Room to grow" for opportunities.
/// The whole row is "Learn more" (it opens the engine's message word for word); the CDC link is
/// its own button. "info" cards stay out, except weight, which opens the About weight card
/// (never a lever).
class WellnessPanel extends StatelessWidget {
  const WellnessPanel({
    super.key,
    required this.cards,
    this.onWeight,
    this.strengthsOnly = false,
    this.open = defaultOpenUrl,
  });

  final List<WellnessCard> cards;

  /// Opens the About weight screen for the `bmi` card.
  final VoidCallback? onWeight;

  /// The age-not-covered screen shows only what is going well.
  final bool strengthsOnly;
  final OpenUrl open;

  /// A short title for the Room, by card and level; the engine's own title otherwise.
  static String uiTitle(WellnessCard c) => switch ((c.id, c.level)) {
    ('smoking', 'strength') => 'Smoke-free',
    ('smoking', 'opportunity') => 'Help to quit',
    ('activity', 'strength') => 'Active',
    ('activity', 'opportunity') => 'Move a bit more',
    ('sleep', 'strength') => 'Good sleep',
    ('sleep', 'opportunity') => 'More rest',
    ('bmi', _) => ExperimentCopy.aboutWeight,
    _ => c.title,
  };

  static IconData iconFor(WellnessCard c) => switch (c.id) {
    'smoking' => Icons.smoke_free_rounded,
    'activity' => Icons.directions_run_rounded,
    'sleep' => Icons.bedtime_outlined,
    'bmi' => Icons.monitor_weight_outlined,
    _ => Icons.star_border_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final strengths = [
      for (final c in cards)
        if (c.level == 'strength') c,
    ];
    final grow = strengthsOnly
        ? <WellnessCard>[]
        : [
            for (final c in cards)
              if (c.level == 'opportunity') c,
          ];
    final weight = strengthsOnly ? null : cards.where((c) => c.id == 'bmi').firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (strengths.isNotEmpty) ...[
          _Heading(icon: Icons.star_border_rounded, text: ExperimentCopy.goingWell),
          for (final c in strengths) _Row(card: c, strength: true, open: open),
        ],
        if (grow.isNotEmpty) ...[
          _Heading(icon: Icons.eco_outlined, text: ExperimentCopy.roomToGrow),
          for (final c in grow) _Row(card: c, strength: false, open: open),
        ],
        if (weight != null && onWeight != null) ...[
          const SizedBox(height: 8),
          _Row(card: weight, strength: false, open: open, onLearn: onWeight),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Row(
      children: [
        Icon(icon, size: 24, color: LtColors.ink),
        const SizedBox(width: 8),
        Semantics(header: true, child: Text(text, style: LtText.display(22))),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.card, required this.strength, required this.open, this.onLearn});
  final WellnessCard card;
  final bool strength;
  final OpenUrl open;

  /// Replaces the sheet (weight opens its own screen).
  final VoidCallback? onLearn;

  void _learn(BuildContext context) => onLearn != null
      ? onLearn!()
      : showInfoSheet(
          context,
          title: WellnessPanel.uiTitle(card),
          body: card.message,
          extra: SourceLink(
            label: '${SourceLink.siteName(card.sourceUrl)}: ${card.title}',
            url: card.sourceUrl,
            open: open,
          ),
        );

  @override
  Widget build(BuildContext context) {
    final title = WellnessPanel.uiTitle(card);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          color: strength ? LtColors.mintWash : LtColors.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: LtColors.control, width: LtBorders.container),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: '$title: learn more',
                excludeSemantics: true,
                onTap: () => _learn(context),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _learn(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                    child: Row(
                      children: [
                        LeverIcon(WellnessPanel.iconFor(card)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: WholeWordText(title, style: LtText.body(size: 18, weight: FontWeight.w700)),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 28, color: LtColors.ink),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(width: 1.5, height: 40, color: LtColors.container),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SourceLink(label: SourceLink.siteName(card.sourceUrl), url: card.sourceUrl, open: open),
            ),
          ],
        ),
      ),
    );
  }
}
