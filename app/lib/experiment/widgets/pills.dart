import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import 'dashed_border.dart';

/// "What-if" (lilac) and "Today" (paper): the two labels over the twins and on the screens.
class ModePill extends StatelessWidget {
  const ModePill.whatIf({super.key}) : label = 'What-if', lilac = true;
  const ModePill.today({super.key}) : label = 'Today', lilac = false;

  final String label;
  final bool lilac;

  @override
  Widget build(BuildContext context) => Semantics(
    label: lilac ? 'What-if. Nothing here changes your answers.' : 'Today, your real answers.',
    excludeSemantics: true,
    child: Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lilac ? LtColors.lavender : LtColors.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LtColors.control, width: 1.5),
      ),
      child: Text(label, style: LtText.display(17), maxLines: 1, softWrap: false),
    ),
  );
}

/// A lilac chip for one change in the what-if: "Moderate exercise 2 h a week".
class WhatIfChip extends StatelessWidget {
  const WhatIfChip({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 36),
    padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
    decoration: BoxDecoration(
      color: const Color(0xFFE9E6FB),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: LtColors.control, width: 1.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: LtColors.ink),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label, style: LtText.body(weight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

/// "Not counted": a dashed tag. Wherever it appears there is no number.
class NotCountedPill extends StatelessWidget {
  const NotCountedPill({super.key, this.label = 'Not counted'});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label. The model has no number for this.',
    excludeSemantics: true,
    child: DashedBox(
      color: LtColors.control,
      radius: 16,
      fill: LtColors.paper,
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        widthFactor: 1,
        child: Text(label, style: LtText.body(weight: FontWeight.w700), maxLines: 1, softWrap: false),
      ),
    ),
  );
}

/// "Same": a dashed chip for "no change from today". Not a score.
class SamePill extends StatelessWidget {
  const SamePill({super.key, this.label = 'Same'});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label. No change from today.',
    excludeSemantics: true,
    child: DashedBox(
      color: LtColors.control,
      radius: 18,
      width: 1.5,
      fill: LtColors.paper,
      constraints: const BoxConstraints(minHeight: 40, minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: LtText.body(weight: FontWeight.w700, color: LtColors.secondary),
          maxLines: 1,
        ),
      ),
    ),
  );
}
