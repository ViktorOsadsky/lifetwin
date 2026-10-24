import 'package:flutter/material.dart';

import '../../widgets/whole_word_text.dart';
import '../theme.dart';

/// Which edge the tail points out of ([none]: no tail, e.g. under the window).
enum BubbleTail { left, bottom, none }

/// The twin's speech bubble: paper, a soft 1.5px outline, a 26px radius and
/// a tail drawn in the same path, so the outline is seamless.
class Bubble extends StatelessWidget {
  const Bubble({
    super.key,
    required this.text,
    this.tail = BubbleTail.bottom,
    this.tailAt = 0.2,
    this.fontSize = 22,
    this.liveRegion = false,
    this.header = false,
    this.maxHeight,
  });

  final String text;
  final BubbleTail tail;

  /// Where along that edge (0..1) the tail sits.
  final double tailAt;
  final double fontSize;

  /// Announce changes (the mascot's current line).
  final bool liveRegion;
  final bool header;

  /// When set, long lines scroll inside the bubble instead of overflowing.
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final label = WholeWordText(text, style: LtText.display(fontSize));
    Widget body = Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 14), child: label);
    if (maxHeight != null) {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight!),
        child: SingleChildScrollView(child: body),
      );
    }
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      header: header,
      child: CustomPaint(
        painter: _BubblePainter(tail: tail, tailAt: tailAt),
        child: Padding(
          // Room for the tail outside the rounded body.
          padding: EdgeInsets.only(left: tail == BubbleTail.left ? 11 : 0, bottom: tail == BubbleTail.bottom ? 11 : 0),
          child: body,
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.tail, required this.tailAt});
  final BubbleTail tail;
  final double tailAt;

  @override
  void paint(Canvas canvas, Size size) {
    final left = tail == BubbleTail.left ? 11.0 : 0.0;
    final bottom = tail == BubbleTail.bottom ? 11.0 : 0.0;
    final body = Rect.fromLTRB(left, 0, size.width, size.height - bottom);
    final r = RRect.fromRectAndRadius(body, const Radius.circular(LtRadii.chip));
    final Path t;
    if (tail == BubbleTail.bottom) {
      final x = (body.left + 26 + (body.width - 52 - 22) * tailAt.clamp(0.0, 1.0));
      t = Path()
        ..moveTo(x, body.bottom - 2)
        ..lineTo(x + 2, size.height)
        ..lineTo(x + 20, body.bottom - 2)
        ..close();
    } else if (tail == BubbleTail.left) {
      final y = (body.top + 18 + (body.height - 36 - 20) * tailAt.clamp(0.0, 1.0));
      t = Path()
        ..moveTo(body.left + 2, y)
        ..lineTo(0, y + 12)
        ..lineTo(body.left + 2, y + 20)
        ..close();
    } else {
      t = Path();
    }
    final shape = Path.combine(PathOperation.union, Path()..addRRect(r), t);
    canvas.drawShadow(shape, LtColors.ink.withValues(alpha: 0.5), 3, false);
    canvas.drawPath(shape, Paint()..color = LtColors.paper);
    canvas.drawPath(
      shape,
      Paint()
        ..color = LtColors.container
        ..style = PaintingStyle.stroke
        ..strokeWidth = LtBorders.container,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.tail != tail || old.tailAt != tailAt;
}
