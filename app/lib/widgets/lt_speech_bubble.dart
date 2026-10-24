import 'package:flutter/material.dart';

import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';

/// Chat bubble. Mascot bubbles are white with a tail on the left, user
/// bubbles are blue with a tail on the right.
class LtSpeechBubble extends StatelessWidget {
  const LtSpeechBubble({
    super.key,
    required this.text,
    this.fromMascot = true,
    this.tailDown = false,
  });

  final String text;
  final bool fromMascot;

  /// Tail at the lower right, pointing down at a speaker below the bubble.
  final bool tailDown;

  /// Padding around the text, for callers that measure the bubble.
  static const padding = EdgeInsets.symmetric(
    horizontal: LtSpace.s16,
    vertical: LtSpace.s12,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = fromMascot ? c.bgSurface : c.actionPrimary;
    final fg = fromMascot ? c.textPrimary : c.bgSurface;
    return Semantics(
      label: '${fromMascot ? 'Pip' : 'You'}: $text',
      excludeSemantics: true,
      child: CustomPaint(
        painter: _TailPainter(color: bg, left: fromMascot, down: tailDown),
        child: Container(
          margin: tailDown
              ? const EdgeInsets.only(bottom: 9)
              : EdgeInsets.only(
                  left: fromMascot ? 8 : 0,
                  right: fromMascot ? 0 : 8,
                ),
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: LtRadius.smallAll,
            // A soft lift, not a ledge: bubbles should float lightly.
            boxShadow: fromMascot
                ? [
                    BoxShadow(
                      color: c.textPrimary.withValues(alpha: 0.06),
                      offset: const Offset(0, 2),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Text(text, style: context.text.callout.copyWith(color: fg)),
        ),
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter({required this.color, required this.left, this.down = false});

  final Color color;
  final bool left;
  final bool down;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 18;
    final path = Path();
    if (down) {
      final x = size.width - 40;
      final b = size.height - 9;
      path
        ..moveTo(x - 9, b - 1)
        ..lineTo(x + 6, size.height)
        ..lineTo(x + 8, b - 1)
        ..close();
    } else if (left) {
      path
        ..moveTo(9, y - 7)
        ..lineTo(0, y + 2)
        ..lineTo(9, y + 8)
        ..close();
    } else {
      final x = size.width;
      path
        ..moveTo(x - 9, y - 7)
        ..lineTo(x, y + 2)
        ..lineTo(x - 9, y + 8)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) =>
      old.color != color || old.left != left || old.down != down;
}
