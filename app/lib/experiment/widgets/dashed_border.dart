import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// A rounded box with a dashed outline: the "this is not a number" look (Same, Not counted,
/// +0). Dashes are 6 px with 4 px gaps, as in the approved Experiment screens.
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
    this.fill,
    this.width = 1.5,
    this.padding = EdgeInsets.zero,
    this.constraints,
  });

  final Widget child;
  final Color color;
  final double radius;
  final Color? fill;
  final double width;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedPainter(color: color, radius: radius, fill: fill, width: width),
    child: Container(constraints: constraints, padding: padding, child: child),
  );
}

class _DashedPainter extends CustomPainter {
  _DashedPainter({required this.color, required this.radius, required this.fill, required this.width});
  final Color color;
  final double radius;
  final Color? fill;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height).deflate(width / 2),
      Radius.circular(radius),
    );
    if (fill != null) canvas.drawRRect(rrect, Paint()..color = fill!);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final path = Path()..addRRect(rrect);
    for (final PathMetric m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, (d + 6).clamp(0, m.length)), line);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.radius != radius || old.fill != fill || old.width != width;
}
