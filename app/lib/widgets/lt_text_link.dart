import 'package:flutter/material.dart';

import '../theme/lifetwin_theme.dart';
import 'whole_word_text.dart';

/// Underlined text action ("Skip this question"). At least 56 pt tall, no box.
class LtTextLink extends StatelessWidget {
  const LtTextLink({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final style = LtText.link.copyWith(
      color: enabled ? LtColors.ink : LtColors.inkMuted,
      decorationColor: enabled ? LtColors.ink : LtColors.inkMuted,
    );
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        onTap: onPressed,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onPressed,
          child: FocusableActionDetector(
            enabled: enabled,
            actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => onPressed?.call())},
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: LtSize.smallTap),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[ExcludeSemantics(child: icon!), const SizedBox(width: LtSpace.sm)],
                    Flexible(
                      child: WholeWordText(label, textAlign: TextAlign.center, style: style),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
