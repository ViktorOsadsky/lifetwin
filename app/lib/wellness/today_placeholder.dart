import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../widgets/whole_word_text.dart';
import 'widgets.dart';

/// Home's one "Today with Mochi" slot until `TodayWithMochiCard` lands: Mochi's encouragement and the
/// ways into today's plan, a change to try, and why Mochi sees what it sees. Replace with the real card.
class TodayWithMochiPlaceholder extends StatelessWidget {
  const TodayWithMochiPlaceholder({super.key, this.onPlan, this.onTryChange, this.onWhy});
  final VoidCallback? onPlan;
  final VoidCallback? onTryChange;
  final VoidCallback? onWhy;

  static const line = 'One small thing today is plenty.';

  @override
  Widget build(BuildContext context) => WellnessCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: WholeWordText('Today with Mochi', style: LtText.display(20)),
        ),
        const SizedBox(height: 4),
        WholeWordText(line, style: LtText.body()),
        Wrap(
          children: [
            if (onPlan != null) TextButton(onPressed: onPlan, child: const WholeWordText('Today’s plan')),
            if (onTryChange != null) TextButton(onPressed: onTryChange, child: const WholeWordText('Try a change')),
            if (onWhy != null) TextButton(onPressed: onWhy, child: const WholeWordText('Why?')),
          ],
        ),
      ],
    ),
  );
}
