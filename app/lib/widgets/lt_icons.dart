import 'package:flutter/widgets.dart';

import '../theme/lifetwin_theme.dart';
import 'vector/shapes.dart';

/// The design's line icons (24x24, round ink strokes). Add more by pasting their paths.
enum LtIconKind { back, check, info }

List<Shape> _iconShapes(LtIconKind kind, double w) => switch (kind) {
  LtIconKind.back => [PathShape('M15 5l-7 7 7 7', stroke: LtColors.ink, strokeWidth: w, round: true)],
  LtIconKind.check => [PathShape('M5 12.5l4.5 4.5L19 7.5', stroke: LtColors.ink, strokeWidth: w, round: true)],
  LtIconKind.info => [
    Circle(12, 12, 9, stroke: LtColors.ink, strokeWidth: w),
    PathShape('M12 11v5.5', stroke: LtColors.ink, strokeWidth: w, round: true),
    PathShape('M12 7.8h.01', stroke: LtColors.ink, strokeWidth: w, round: true),
  ],
};

/// A decorative icon; the button or text beside it carries the meaning.
class LtIcon extends StatelessWidget {
  const LtIcon(this.kind, {super.key, this.size = LtSize.icon, this.strokeWidth = 2.4});
  final LtIconKind kind;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) =>
      ShapeView(shapes: _iconShapes(kind, strokeWidth), viewBox: const Size(24, 24), size: Size.square(size));
}
