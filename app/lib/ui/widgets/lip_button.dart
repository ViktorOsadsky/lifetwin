import 'package:flutter/material.dart';

import '../theme.dart';

enum LipKind {
  /// Mint face on a mint lip: the one primary action per screen.
  primary,

  /// Cream face on a cream lip.
  secondary,

  /// Lavender face: a control that is currently "on" (e.g. listening).
  active,
}

/// The lip look without any gesture handling: a flat face over a darker base
/// offset by [lip] px. A Stack of two rounded rectangles, because
/// BoxDecoration cannot draw inset shadows.
class LipSurface extends StatelessWidget {
  const LipSurface({
    super.key,
    required this.child,
    this.kind = LipKind.primary,
    this.minHeight = 64,
    this.pressed = false,
    this.enabled = true,
    this.lip = 4,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.radius,
  });

  final Widget child;
  final LipKind kind;

  /// Total height including the lip. At least 56 for a primary.
  final double minHeight;
  final bool pressed;
  final bool enabled;
  final double lip;
  final EdgeInsets padding;

  /// Defaults to a full pill.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final (face, base, line) = switch (kind) {
      _ when !enabled => (LtColors.trackOff, LtColors.creamLip, LtColors.control),
      LipKind.primary => (LtColors.mint, LtColors.mintLip, LtColors.controlOnMint),
      LipKind.secondary => (LtColors.paper, LtColors.creamLip, LtColors.control),
      LipKind.active => (LtColors.lavender, const Color(0xFF8E87D6), LtColors.controlOnMint),
    };
    final r = BorderRadius.circular(radius ?? minHeight / 2);
    final down = pressed && enabled;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight, minWidth: 48),
      child: Stack(
        // The face takes the button's full width when the button is full width.
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            top: lip,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: base,
                borderRadius: r,
                border: Border.all(color: line, width: LtBorders.control),
                boxShadow: down ? LtShadows.small : LtShadows.soft,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: down ? lip - 1 : 0, bottom: down ? 1 : lip),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight - lip),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: face,
                  borderRadius: r,
                  border: Border.all(color: line, width: LtBorders.control),
                ),
                child: Padding(
                  padding: padding,
                  child: Center(widthFactor: 1, heightFactor: 1, child: child),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shared button: Fredoka label, optional icon, a lip that presses down.
/// Every target is at least 48pt; primaries default to 64pt.
class LipButton extends StatefulWidget {
  const LipButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = LipKind.primary,
    this.icon,
    this.height = 64,
    this.fontSize,
    this.semanticLabel,
    this.hint,
    this.expand = true,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onTap;
  final LipKind kind;
  final IconData? icon;
  final double height;
  final double? fontSize;
  final String? semanticLabel;
  final String? hint;

  /// Full width when true.
  final bool expand;

  @override
  State<LipButton> createState() => _LipButtonState();
}

class _LipButtonState extends State<LipButton> {
  bool _pressed = false;

  void _press(bool down) {
    if (_pressed != down && mounted) setState(() => _pressed = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final size = widget.fontSize ?? (widget.height >= 72 ? 24.0 : 22.0);
    final label = Text(
      widget.label,
      textAlign: TextAlign.center,
      style: LtText.display(size),
    );
    final content = widget.icon == null
        ? label
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: size + 6, color: LtColors.ink),
              const SizedBox(width: 10),
              Flexible(child: label),
            ],
          );
    final surface = LipSurface(
      kind: widget.kind,
      minHeight: widget.height,
      pressed: _pressed,
      enabled: enabled,
      child: content,
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      hint: widget.hint,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: enabled ? (_) => _press(true) : null,
          onTapUp: enabled ? (_) => _press(false) : null,
          onTapCancel: enabled ? () => _press(false) : null,
          child: widget.expand ? SizedBox(width: double.infinity, child: surface) : surface,
        ),
      ),
    );
  }
}

/// An underlined text link, at least 48pt tall (e.g. "Type instead", "Why?").
class LinkButton extends StatelessWidget {
  const LinkButton({super.key, required this.label, required this.onTap, this.icon, this.color = LtColors.ink});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 22, color: color), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              label,
              style: LtText.body(size: 18, weight: FontWeight.w700, color: color).copyWith(
                decoration: TextDecoration.underline,
                decorationThickness: 2,
                decorationColor: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round 52pt back button with a soft shadow, for the window corner.
class RoundBackButton extends StatelessWidget {
  const RoundBackButton({super.key, required this.onTap, this.label = 'Back'});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: LtColors.paper,
            shape: BoxShape.circle,
            border: Border.all(color: LtColors.control, width: LtBorders.control),
            boxShadow: LtShadows.soft,
          ),
          child: const Icon(Icons.chevron_left_rounded, size: 34, color: LtColors.ink),
        ),
      ),
    );
  }
}
