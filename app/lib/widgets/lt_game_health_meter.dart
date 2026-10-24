import 'package:flutter/material.dart';

import '../state/game_health.dart';
import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';
import 'lt_icon.dart';

/// Game-health hearts. Quiz/game health only, never a medical figure.
/// Plain drawn hearts, no discs (§7b): kept hearts are green, resting
/// hearts are a quiet outline (never red), and the count is also written.
class GameHealthMeter extends StatelessWidget {
  const GameHealthMeter({super.key, required this.hearts});

  final int hearts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Game health: $hearts of ${GameHealth.max} hearts',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < GameHealth.max; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            LtIcon(
              LtIcons.heart,
              size: 22,
              color: i < hearts ? c.vizExperiment : c.vizBaseline,
            ),
          ],
          const SizedBox(width: LtSpace.s8),
          Text(
            '$hearts / ${GameHealth.max}',
            style: context.text.footnote.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
              fontVariations: const [FontVariation('wght', 600)],
            ),
          ),
        ],
      ),
    );
  }
}
