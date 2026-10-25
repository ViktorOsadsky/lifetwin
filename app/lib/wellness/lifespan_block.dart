import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../widgets/whole_word_text.dart';
import 'models.dart';

/// "Around 2051" with "age 87–109" under it ("age 89–110+" where the table ends), the caption
/// "Estimate, rough guide" always, and the caveat behind (i). Years and ages only, never a day.
/// Hidden (nothing drawn) when the engine has no estimate.
class LifespanBlock extends StatelessWidget {
  const LifespanBlock({super.key, required this.lifespan});
  final LifespanReveal? lifespan;

  @override
  Widget build(BuildContext context) {
    final l = lifespan;
    if (l == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: WholeWordText('Around ${l.expectedYear}', style: LtText.display(36)),
                ),
              ),
              if (l.caveat != null)
                IconButton(
                  tooltip: 'About this estimate',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.info_outline_rounded, color: LtColors.ink),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (d) => AlertDialog(
                      content: Text(l.caveat!, style: LtText.body()),
                      actions: [TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Close'))],
                    ),
                  ),
                ),
            ],
          ),
          Semantics(
            label: '${l.rangeText}. $lifespanCaption.',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WholeWordText(l.rangeText, style: LtText.body(weight: FontWeight.w700)),
                WholeWordText(lifespanCaption, style: LtText.body(color: LtColors.secondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
