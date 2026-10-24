import 'package:flutter/material.dart';

import '../theme/lifetwin_theme.dart';

/// Where the bubble's tail points: down toward Pip below (Question), left toward Pip
/// beside it (Listening), or no tail.
enum BubbleTail { down, left, none }

/// White speech bubble with a navy outline and a pointed tail.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    super.key,
    required this.child,
    this.tail = BubbleTail.down,
    this.tailOffset = 52,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
    this.radius = LtRadii.bubble,
  });

  final Widget child;
  final BubbleTail tail;

  /// Distance of the tail from the bubble's left edge (down) or top edge (left).
  final double tailOffset;
  final EdgeInsets padding;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: LtColors.white,
        borderRadius: radius,
        border: Border.all(color: LtColors.ink, width: LtOutline.width),
      ),
      child: child,
    );
    if (tail == BubbleTail.none) return bubble;
    final down = tail == BubbleTail.down;
    // Artboard geometry: down tail 30x20 at bottom -17; left tail 18x26 at left -15.
    return Padding(
      padding: EdgeInsets.only(bottom: down ? 17 : 0, left: down ? 0 : 15),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          bubble,
          Positioned(
            left: down ? tailOffset : -15,
            top: down ? null : tailOffset,
            bottom: down ? -17 : null,
            child: ExcludeSemantics(
              child: CustomPaint(size: down ? const Size(30, 20) : const Size(18, 26), painter: _TailPainter(down)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter(this.down);
  final bool down;

  @override
  void paint(Canvas canvas, Size size) {
    // Open paths, as in the SVG: the white fill covers the bubble's outline at the root.
    final p = down
        ? (Path()
            ..moveTo(2, 0)
            ..lineTo(10, 17)
            ..lineTo(28, 0))
        : (Path()
            ..moveTo(18, 2)
            ..lineTo(2, 13)
            ..lineTo(18, 24));
    canvas.drawPath(p, Paint()..color = LtColors.white);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = LtColors.ink
        ..strokeWidth = LtOutline.width
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.down != down;
}
