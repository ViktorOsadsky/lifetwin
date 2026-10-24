import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme.dart';

/// The mode tint behind every panel, plus SafeArea. [gradient] overrides the
/// mode's own wash (Room uses it to cross-fade toward mint during the swoosh).
class ModeScaffold extends StatelessWidget {
  const ModeScaffold({super.key, required this.mode, required this.child, this.gradient});

  final LtMode mode;
  final Widget child;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: mode.outer,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient ?? mode.gradient),
        child: SafeArea(child: child),
      ),
    );
  }
}

/// The shared skeleton: a framed window on top, one sheet below that
/// overlaps it by [overlap]. The window takes the space the sheet leaves
/// and shrinks first (down to [minWindow]); after that the whole page
/// scrolls, so large text never overflows.
class PlateSheetLayout extends StatelessWidget {
  const PlateSheetLayout({
    super.key,
    required this.window,
    required this.sheet,
    this.minWindow = 200,
    this.maxWindow = double.infinity,
    this.overlap = 22,
    this.padding = const EdgeInsets.fromLTRB(14, 8, 14, 14),
    this.controller,
  });

  final Widget window;
  final Widget sheet;
  final double minWindow;
  final double maxWindow;
  final double overlap;
  final EdgeInsets padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        controller: controller,
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: (box.maxHeight - padding.vertical).clamp(0, double.infinity)),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: _FixedIntrinsicHeight(
                    height: minWindow,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minWindow, maxHeight: maxWindow),
                      child: window,
                    ),
                  ),
                ),
                // The sheet slides up over the window's bottom edge.
                _OverlapUp(overlap: overlap, child: sheet),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports a fixed intrinsic height so [IntrinsicHeight] never asks the
/// window's contents (which use LayoutBuilder) for theirs.
class _FixedIntrinsicHeight extends SingleChildRenderObjectWidget {
  const _FixedIntrinsicHeight({required this.height, super.child});
  final double height;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFixedIntrinsicHeight(height);

  @override
  void updateRenderObject(BuildContext context, _RenderFixedIntrinsicHeight renderObject) =>
      renderObject.height = height;
}

class _RenderFixedIntrinsicHeight extends RenderProxyBox {
  _RenderFixedIntrinsicHeight(this._height);
  double _height;
  set height(double v) {
    if (v == _height) return;
    _height = v;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) => _height;
  @override
  double computeMaxIntrinsicHeight(double width) => _height;
  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;
}

/// Lays the child out normally but shifts it up by [overlap] and takes
/// [overlap] less height, so the column has no gap at the bottom.
class _OverlapUp extends SingleChildRenderObjectWidget {
  const _OverlapUp({required this.overlap, super.child});
  final double overlap;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOverlapUp(overlap);

  @override
  void updateRenderObject(BuildContext context, _RenderOverlapUp renderObject) => renderObject.overlap = overlap;
}

class _RenderOverlapUp extends RenderShiftedBox {
  _RenderOverlapUp(this._overlap) : super(null);
  double _overlap;
  set overlap(double v) {
    if (v == _overlap) return;
    _overlap = v;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      ((child?.getMinIntrinsicHeight(width) ?? 0) - _overlap).clamp(0, double.infinity);
  @override
  double computeMaxIntrinsicHeight(double width) =>
      ((child?.getMaxIntrinsicHeight(width) ?? 0) - _overlap).clamp(0, double.infinity);

  @override
  void performLayout() {
    final c = child!;
    c.layout(BoxConstraints(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth), parentUsesSize: true);
    (c.parentData! as BoxParentData).offset = Offset(0, -_overlap);
    size = constraints.constrain(Size(c.size.width, (c.size.height - _overlap).clamp(0, double.infinity)));
  }
}

/// The cream (or night) sheet that holds the controls.
class Sheet extends StatelessWidget {
  const Sheet({super.key, required this.child, this.night = false, this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 20)});

  final Widget child;
  final bool night;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: night ? LtColors.night : LtColors.paper,
        borderRadius: BorderRadius.circular(LtRadii.panel),
        border: Border.all(color: night ? LtColors.nightLine : LtColors.container, width: LtBorders.container),
        boxShadow: night ? LtShadows.night : LtShadows.soft,
      ),
      child: night
          ? Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: LtColors.gold.withValues(alpha: 0.7), width: 1),
                        ),
                      ),
                    ),
                  ),
                ),
                body,
              ],
            )
          : body,
    );
  }
}
