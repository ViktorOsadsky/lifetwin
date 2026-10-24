import 'package:flutter/material.dart';

import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';
import 'lt_icon.dart';

/// iOS-style stepper: a pill with minus and plus halves split by a hairline.
/// Each half is at least 44 x 44.
class LtStepper extends StatelessWidget {
  const LtStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.label = 'value',
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;

  /// Spoken name, e.g. "Duration".
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canDec = value - step >= min;
    final canInc = value + step <= max;
    return Semantics(
      container: true,
      label: label,
      value: '$value',
      child: Container(
        decoration: BoxDecoration(
          color: c.iconBackdrop,
          borderRadius: BorderRadius.circular(LtRadius.small),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Half(
              icon: LtIcons.minus,
              semantics: 'Decrease $label',
              enabled: canDec,
              onTap: () => onChanged(value - step),
            ),
            Container(
              width: 1,
              height: 22,
              color: c.vizBaseline.withValues(alpha: 0.4),
            ),
            _Half(
              icon: LtIcons.plus,
              semantics: 'Increase $label',
              enabled: canInc,
              onTap: () => onChanged(value + step),
            ),
          ],
        ),
      ),
    );
  }
}

class _Half extends StatelessWidget {
  const _Half({
    required this.icon,
    required this.semantics,
    required this.enabled,
    required this.onTap,
  });

  final LtIcons icon;
  final String semantics;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantics,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 52,
          height: LtSpace.touch,
          child: Center(
            child: LtIcon(
              icon,
              size: 20,
              color: enabled ? c.textPrimary : c.vizBaseline,
            ),
          ),
        ),
      ),
    );
  }
}
