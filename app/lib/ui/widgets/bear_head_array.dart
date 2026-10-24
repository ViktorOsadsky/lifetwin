import 'package:flutter/material.dart';

import '../theme.dart';

/// 100 small bear heads in 10 rows of 10; the first [filled] are solid.
/// Empty heads are outlines, so the count never relies on colour alone.
class BearHeadArray extends StatelessWidget {
  const BearHeadArray({
    super.key,
    required this.filled,
    this.filledColor = LtColors.cream,
    this.emptyColor = const Color(0x8CFBF4EA),
    this.semanticLabel,
  });

  final int filled;
  final Color filledColor;
  final Color emptyColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final n = filled.clamp(0, 100);
    return Semantics(
      container: true,
      label: semanticLabel ?? 'About $n of 100 bear heads are filled.',
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 10 / 6.4,
        child: CustomPaint(painter: BearHeadPainter(filled: n, filledColor: filledColor, emptyColor: emptyColor)),
      ),
    );
  }
}

class BearHeadPainter extends CustomPainter {
  BearHeadPainter({required this.filled, required this.filledColor, required this.emptyColor});
  final int filled;
  final Color filledColor;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / 10;
    final cellH = size.height / 10;
    final r = cellW / 2.6 < cellH / 2.3 ? cellW / 2.6 : cellH / 2.3;
    final fill = Paint()..color = filledColor;
    final line = Paint()
      ..color = emptyColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = (r * 0.22).clamp(1.2, 2.2);
    for (var i = 0; i < 100; i++) {
      final c = Offset(cellW * (i % 10 + 0.5), cellH * (i ~/ 10 + 0.55));
      final ears = Path()
        ..addOval(Rect.fromCircle(center: c + Offset(-r * 0.72, -r * 0.78), radius: r * 0.42))
        ..addOval(Rect.fromCircle(center: c + Offset(r * 0.72, -r * 0.78), radius: r * 0.42));
      final head = Path.combine(PathOperation.union, Path()..addOval(Rect.fromCircle(center: c, radius: r)), ears);
      if (i < filled) {
        canvas.drawPath(head, fill);
      } else {
        canvas.drawPath(head, line);
      }
    }
  }

  @override
  bool shouldRepaint(BearHeadPainter old) =>
      old.filled != filled || old.filledColor != filledColor || old.emptyColor != emptyColor;
}
