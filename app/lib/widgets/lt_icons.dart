import 'package:flutter/widgets.dart';

import '../theme/lifetwin_theme.dart';
import 'vector/shapes.dart';

/// The design's line icons (24x24, round ink strokes). Add more by pasting their paths.
enum LtIconKind { back, check, info, mic, keyboard, pencil, speaker, stop }

List<Shape> _iconShapes(LtIconKind kind, double w) => switch (kind) {
  LtIconKind.back => [PathShape('M15 5l-7 7 7 7', stroke: LtColors.ink, strokeWidth: w, round: true)],
  LtIconKind.check => [PathShape('M5 12.5l4.5 4.5L19 7.5', stroke: LtColors.ink, strokeWidth: w, round: true)],
  LtIconKind.info => [
    Circle(12, 12, 9, stroke: LtColors.ink, strokeWidth: w),
    PathShape('M12 11v5.5', stroke: LtColors.ink, strokeWidth: w, round: true),
    PathShape('M12 7.8h.01', stroke: LtColors.ink, strokeWidth: w, round: true),
  ],
  // Question.dc.html "Tap to talk"; the arc "a6.5 6.5 0 0 0 13 0" drawn as two cubics.
  LtIconKind.mic => [
    RectShape(9, 3, 6, 11, rx: 3, stroke: LtColors.ink, strokeWidth: w),
    PathShape(
      'M5.5 11C5.5 14.6 8.4 17.5 12 17.5C15.6 17.5 18.5 14.6 18.5 11',
      stroke: LtColors.ink,
      strokeWidth: w,
      round: true,
    ),
    PathShape('M12 17.5V21', stroke: LtColors.ink, strokeWidth: w, round: true),
  ],
  // Question.dc.html "Use the keyboard".
  LtIconKind.keyboard => [
    RectShape(2.5, 6, 19, 12, rx: 2.5, stroke: LtColors.ink, strokeWidth: w),
    PathShape('M6.5 10h.01M10 10h.01M14 10h.01M17.5 10h.01M8 14h8', stroke: LtColors.ink, strokeWidth: w, round: true),
  ],
  // Readback.dc.html "No, change it"; the arc "a2.1 2.1 0 0 1 3 3" drawn as two cubics.
  LtIconKind.pencil => [
    PathShape(
      'M4 20l1-4.5L15.5 5C16.32 4.18 17.68 4.18 18.5 5C19.32 5.82 19.32 7.18 18.5 8L8 18.5Z',
      stroke: LtColors.ink,
      strokeWidth: w,
      round: true,
    ),
    PathShape('M13.5 7l3 3', stroke: LtColors.ink, strokeWidth: w, round: true),
  ],
  // "Hear it again" (not on an artboard; same line style).
  LtIconKind.speaker => [
    PathShape('M4 9.5H7.5L12 5.5V18.5L7.5 14.5H4Z', stroke: LtColors.ink, strokeWidth: w, round: true),
    PathShape('M15.5 9C16.8 10.5 16.8 13.5 15.5 15', stroke: LtColors.ink, strokeWidth: w, round: true),
    PathShape('M18.5 6.5C21 9.5 21 14.5 18.5 17.5', stroke: LtColors.ink, strokeWidth: w, round: true),
  ],
  // "Stop" while Pip speaks (not on an artboard).
  LtIconKind.stop => [RectShape(6.5, 6.5, 11, 11, rx: 2.5, stroke: LtColors.ink, strokeWidth: w)],
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
