import 'package:flutter/material.dart';

import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';
import 'lt_icon.dart';
import 'lt_pressable.dart';

enum LtButtonVariant { primary, positive, secondary, ghost }

/// Pill button. States: default, pressed (face drops onto its edge and
/// darkens to `action/primary-pressed`), disabled
/// (`onPressed == null`) and loading (spinner, taps ignored).
class LtButton extends StatefulWidget {
  const LtButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = LtButtonVariant.primary,
    this.loading = false,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final LtButtonVariant variant;
  final bool loading;
  final LtIcons? icon;
  final bool expand;

  @override
  State<LtButton> createState() => _LtButtonState();
}

class _LtButtonState extends State<LtButton> {
  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disabled = widget.onPressed == null;
    late Color bg;
    late Color bgPressed;
    late Color fg;
    Color? base;
    switch (widget.variant) {
      case LtButtonVariant.primary:
        bg = c.actionPrimary;
        bgPressed = c.actionPrimaryPressed;
        base = c.actionPrimaryPressed;
        fg = c.bgSurface;
      case LtButtonVariant.positive:
        bg = c.textPositive;
        bgPressed = Color.lerp(c.textPositive, c.textPrimary, 0.3)!;
        base = bgPressed;
        fg = c.bgSurface;
      case LtButtonVariant.secondary:
        // Tinted ghost: a faint blue face, no edge, no outline (§7b.6).
        bg = c.chipSelected.withValues(alpha: 0.6);
        bgPressed = c.chipSelected;
        fg = c.actionPrimary;
      case LtButtonVariant.ghost:
        bg = c.clear;
        bgPressed = c.chipSelected;
        fg = c.actionPrimary;
    }
    if (disabled) {
      bg = widget.variant == LtButtonVariant.ghost ? c.clear : c.line;
      bgPressed = bg;
      base = null;
      fg = c.textSecondary;
    }

    // The one filled action per screen is a true pill; quieter variants use
    // the small radius so a screen keeps to two corner radii (§7b.8).
    final filled =
        widget.variant == LtButtonVariant.primary ||
        widget.variant == LtButtonVariant.positive;
    final radius = filled ? LtRadius.chipAll : LtRadius.smallAll;
    return LtPressable(
      label: widget.loading ? '${widget.label}, loading' : widget.label,
      onTap: _enabled ? widget.onPressed : null,
      baseColor: base,
      borderRadius: radius,
      depth: 3,
      builder: (context, pressed) => Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
          horizontal: LtSpace.s20,
          vertical: LtSpace.s12,
        ),
        decoration: BoxDecoration(
          color: pressed ? bgPressed : bg,
          borderRadius: radius,
        ),
        child: Row(
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.loading) ...[
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
              ),
              const SizedBox(width: LtSpace.s8),
            ] else if (widget.icon != null) ...[
              LtIcon(widget.icon!, color: fg, size: 20),
              const SizedBox(width: LtSpace.s8),
            ],
            Flexible(
              child: Text(
                widget.label,
                style: context.text.headline.copyWith(color: fg),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
