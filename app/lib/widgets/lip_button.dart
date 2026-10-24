import 'package:flutter/material.dart';

import '../theme/lifetwin_theme.dart';

/// Colors and shape of one lip-button style. The parts in lt_buttons.dart are presets.
class LipStyle {
  const LipStyle({
    required this.face,
    required this.lip,
    required this.radius,
    required this.lipDepth,
    required this.minHeight,
    this.outline = LtOutline.width,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  });

  final Color face;
  final Color lip;
  final BorderRadius radius;
  final double lipDepth;

  /// Height of the face; the lip adds [lipDepth] below it.
  final double minHeight;
  final double outline;
  final EdgeInsets padding;

  static const disabledFace = LtColors.lavenderTrack;
  static const disabledOutline = LtColors.inkMuted;
}

/// The design's chunky button: a face with a navy outline over a solid "lip" in a
/// darker shade. Pressing drops the face onto the lip. Disabled buttons sit flat,
/// grey-lavender, and are announced as disabled. Keyboard focus draws a 4 pt ink ring.
class LipButton extends StatefulWidget {
  const LipButton({
    super.key,
    required this.style,
    required this.onPressed,
    required this.child,
    this.semanticLabel,
    this.selected,
  });

  final LipStyle style;
  final VoidCallback? onPressed;
  final Widget child;

  /// Replaces the child's text for screen readers when set.
  final String? semanticLabel;

  /// For toggle-like buttons (tiles): announced as selected / not selected.
  final bool? selected;

  @override
  State<LipButton> createState() => _LipButtonState();
}

class _LipButtonState extends State<LipButton> {
  bool _down = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.style;
    final enabled = _enabled;
    final drop = enabled && _down ? s.lipDepth : 0.0;
    final lipVisible = enabled && !_down;

    final face = Container(
      constraints: BoxConstraints(minHeight: s.minHeight),
      padding: s.padding,
      decoration: BoxDecoration(
        color: enabled ? s.face : LipStyle.disabledFace,
        borderRadius: s.radius,
        border: Border.all(color: enabled ? LtColors.ink : LipStyle.disabledOutline, width: s.outline),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: enabled ? LtColors.ink : LipStyle.disabledOutline),
        textAlign: TextAlign.center,
        // Centered, but only as wide as the content unless the parent stretches it.
        child: Align(
          widthFactor: 1,
          child: IconTheme.merge(data: const IconThemeData(color: LtColors.ink), child: widget.child),
        ),
      ),
    );

    final body = Padding(
      padding: EdgeInsets.only(bottom: s.lipDepth),
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough, // a stretched parent stretches the face too
        children: [
          // The lip: the face's shape, filled, offset straight down.
          if (lipVisible)
            Positioned(
              left: 0,
              right: 0,
              top: s.lipDepth,
              bottom: -s.lipDepth,
              child: DecoratedBox(decoration: BoxDecoration(color: s.lip, borderRadius: s.radius)),
            ),
          Transform.translate(offset: Offset(0, drop), child: face),
          if (_focused)
            Positioned(
              left: -LtOutline.focusOffset,
              right: -LtOutline.focusOffset,
              top: -LtOutline.focusOffset + drop,
              bottom: -LtOutline.focusOffset - s.lipDepth + drop,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: s.radius.add(BorderRadius.circular(LtOutline.focusOffset)),
                    border: Border.all(color: LtColors.ink, width: LtOutline.focusRing),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: widget.selected,
        label: widget.semanticLabel,
        excludeSemantics: widget.semanticLabel != null,
        onTap: widget.onPressed,
        child: FocusableActionDetector(
          enabled: enabled,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed?.call()),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapDown: enabled ? (_) => _set(true) : null,
            onTapUp: enabled ? (_) => _set(false) : null,
            onTapCancel: enabled ? () => _set(false) : null,
            onTap: widget.onPressed,
            child: body,
          ),
        ),
      ),
    );
  }
}
