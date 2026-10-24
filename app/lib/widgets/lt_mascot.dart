import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/lt_colors.dart';
import '../theme/lt_theme.dart';

enum MascotState { idle, listening, thinking, speaking, celebrating }

/// Pip, the guide: a round orb with a leaf sprout. Deliberately a different
/// silhouette from the Twin (no head/body, no hair).
class Mascot extends StatelessWidget {
  const Mascot({
    super.key,
    this.state = MascotState.idle,
    this.width = 96,
    this.shadow = true,
  });

  final MascotState state;
  final double width;

  /// Off when a habitat paints the contact shadow on its ground plane.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Pip, your guide, ${state.name}',
      child: SizedBox(
        width: width,
        height: width * 1.1,
        child: CustomPaint(
          painter: MascotPainter(
            state: state,
            colors: context.colors,
            shadow: shadow,
          ),
        ),
      ),
    );
  }
}

class MascotPainter extends CustomPainter {
  MascotPainter({
    required this.state,
    required this.colors,
    this.shadow = true,
  });

  final MascotState state;
  final LtColors colors;
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100);
    final c = colors;
    final ink = c.textPrimary;
    const orb = Offset(50, 62);
    const radius = 38.0;

    if (shadow) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(50, 104), width: 60, height: 8),
        Paint()
          ..color = ink.withValues(alpha: 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    // Sprout.
    final stem = Paint()
      ..color = c.vizExperiment
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(50, 26)
        ..quadraticBezierTo(50, 12, 56, 8),
      stem,
    );
    final leaf = Path()
      ..moveTo(56, 8)
      ..quadraticBezierTo(70, 2, 76, 12)
      ..quadraticBezierTo(64, 20, 56, 8)
      ..close();
    canvas.drawPath(leaf, Paint()..color = c.vizExperiment);
    final leaf2 = Path()
      ..moveTo(52, 14)
      ..quadraticBezierTo(40, 6, 32, 12)
      ..quadraticBezierTo(42, 22, 52, 14)
      ..close();
    canvas.drawPath(leaf2, Paint()..color = c.fillVitality);

    // Body.
    final rect = Rect.fromCircle(center: orb, radius: radius);
    canvas.drawCircle(
      orb,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.skyHighlight, c.fillVitality],
        ).createShader(rect),
    );
    // Highlight.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(36, 44), width: 14, height: 9),
      Paint()..color = c.bgSurface.withValues(alpha: 0.55),
    );

    _face(canvas, ink);
    _extras(canvas, c);
    canvas.restore();
  }

  void _face(Canvas canvas, Color ink) {
    final fill = Paint()..color = ink;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const l = Offset(38, 62);
    const r = Offset(62, 62);
    switch (state) {
      case MascotState.idle:
      case MascotState.speaking:
        canvas.drawCircle(l, 4, fill);
        canvas.drawCircle(r, 4, fill);
      case MascotState.listening:
        canvas.drawCircle(l, 5.5, fill);
        canvas.drawCircle(r, 5.5, fill);
      case MascotState.thinking:
        canvas.drawCircle(l + const Offset(2, -3), 4, fill);
        canvas.drawCircle(r + const Offset(2, -3), 4, fill);
      case MascotState.celebrating:
        for (final e in [l, r]) {
          canvas.drawArc(
            Rect.fromCenter(center: e, width: 12, height: 9),
            math.pi + 0.3,
            math.pi - 0.6,
            false,
            stroke,
          );
        }
    }
    switch (state) {
      case MascotState.speaking:
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(50, 76), width: 12, height: 10),
          fill,
        );
      case MascotState.celebrating:
        canvas.drawPath(
          Path()
            ..moveTo(40, 72)
            ..quadraticBezierTo(50, 86, 60, 72),
          stroke,
        );
      case MascotState.thinking:
        canvas.drawLine(const Offset(45, 76), const Offset(55, 75), stroke);
      case MascotState.idle:
      case MascotState.listening:
        canvas.drawPath(
          Path()
            ..moveTo(43, 74)
            ..quadraticBezierTo(50, 80, 57, 74),
          stroke,
        );
    }
  }

  void _extras(Canvas canvas, LtColors c) {
    switch (state) {
      case MascotState.listening:
        final p = Paint()
          ..color = c.actionPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          Rect.fromCenter(center: const Offset(50, 62), width: 92, height: 92),
          -0.5,
          1.0,
          false,
          p,
        );
        canvas.drawArc(
          Rect.fromCenter(center: const Offset(50, 62), width: 92, height: 92),
          math.pi - 0.5,
          1.0,
          false,
          p,
        );
      case MascotState.thinking:
        final dot = Paint()..color = c.skyHighlight;
        canvas.drawCircle(const Offset(88, 24), 2.5, dot);
        canvas.drawCircle(const Offset(94, 12), 4, dot);
      case MascotState.celebrating:
        final sun = Paint()..color = c.sun;
        for (final o in const [
          Offset(14, 28),
          Offset(88, 34),
          Offset(92, 80),
        ]) {
          canvas.drawPath(
            Path()
              ..moveTo(o.dx, o.dy - 6)
              ..quadraticBezierTo(o.dx, o.dy, o.dx + 6, o.dy)
              ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + 6)
              ..quadraticBezierTo(o.dx, o.dy, o.dx - 6, o.dy)
              ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - 6)
              ..close(),
            sun,
          );
        }
      case MascotState.idle:
      case MascotState.speaking:
        break;
    }
  }

  @override
  bool shouldRepaint(MascotPainter old) =>
      old.state != state || old.colors != colors || old.shadow != shadow;
}
