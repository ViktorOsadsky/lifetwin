import 'package:flutter/material.dart';

import '../theme/lt_space.dart';

/// The shared press family for buttons, props and answer tiles: a base edge
/// of [depth] is reserved inside a stationary hit region, and only the face
/// moves down into it while pressed. Restores on release and on cancel.
///
/// Semantics carry the label and an `onTap`, so assistive activation runs the
/// same action as a pointer tap.
class LtPressable extends StatefulWidget {
  const LtPressable({
    super.key,
    required this.label,
    required this.onTap,
    required this.builder,
    this.baseColor,
    this.borderRadius = LtRadius.controlAll,
    this.depth = 4,
    this.selected,
    this.minSize = const Size(LtSpace.touch, LtSpace.touch),
  });

  final String label;

  /// Null disables the control.
  final VoidCallback? onTap;

  /// Builds the face for the current pressed state.
  final Widget Function(BuildContext context, bool pressed) builder;

  /// Colour of the lower edge. Null draws no edge (flat control).
  final Color? baseColor;
  final BorderRadius borderRadius;
  final double depth;
  final bool? selected;
  final Size minSize;

  @override
  State<LtPressable> createState() => _LtPressableState();
}

class _LtPressableState extends State<LtPressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduce = MediaQuery.of(context).disableAnimations;
    final depth = widget.baseColor == null ? 0.0 : widget.depth;
    final pressed = enabled && _pressed;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: widget.minSize.width,
            minHeight: widget.minSize.height,
          ),
          // Passthrough: a face given a tight width (a grid tile) fills it,
          // a loosely constrained face (a compact button) hugs its content.
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              if (depth > 0)
                Positioned.fill(
                  top: depth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.baseColor,
                      borderRadius: widget.borderRadius,
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 90),
                curve: Curves.easeOut,
                margin: EdgeInsets.only(bottom: depth),
                transform: Matrix4.translationValues(0, pressed ? depth : 0, 0),
                child: widget.builder(context, pressed),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
