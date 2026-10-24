import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/lt_colors.dart';
import '../theme/lt_theme.dart';

/// Glass sphere with a `blue-100` inner glow and `sun` sparkles. When
/// [revealed] the glow brightens and the sparkles appear (one-shot, instant
/// with reduced motion).
class MagicBall extends StatelessWidget {
  const MagicBall({super.key, this.size = 120, this.revealed = false});

  final double size;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final colors = context.colors;
    return Semantics(
      image: true,
      label: revealed ? 'Magic ball, glowing' : 'Magic ball, quiet',
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: revealed ? 1 : 0),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => SizedBox(
          width: size,
          height: size * 1.15,
          child: CustomPaint(
            painter: _BallPainter(t: t, colors: colors),
          ),
        ),
      ),
    );
  }
}

class _BallPainter extends CustomPainter {
  _BallPainter({required this.t, required this.colors});

  final double t;
  final LtColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final c = colors;
    final center = Offset(w / 2, w / 2);
    final r = w * 0.44;

    // Stand.
    final stand = Path()
      ..moveTo(w * 0.28, size.height)
      ..lineTo(w * 0.72, size.height)
      ..lineTo(w * 0.64, w * 0.86)
      ..lineTo(w * 0.36, w * 0.86)
      ..close();
    canvas.drawPath(stand, Paint()..color = c.calmSurface);
    canvas.drawPath(
      stand,
      Paint()
        ..color = c.vizBaseline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Glass sphere with inner glow.
    final glow = Color.lerp(c.chipSelected, c.skyHighlight, t * 0.55)!;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [glow, c.chipSelected, c.bgSurface],
          stops: const [0.0, 0.62, 1.0],
          center: const Alignment(-0.2, -0.2),
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = c.skyHighlight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // Glass highlight.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.72),
      math.pi * 1.1,
      math.pi * 0.35,
      false,
      Paint()
        ..color = c.bgSurface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // Sparkles in `sun`, only once revealed.
    if (t > 0) {
      final spots = [
        (Offset(w * 0.5, w * 0.42), 9.0),
        (Offset(w * 0.64, w * 0.56), 6.0),
        (Offset(w * 0.38, w * 0.6), 5.0),
      ];
      for (final (o, s) in spots) {
        _star(canvas, o, s * t, Paint()..color = c.sun);
      }
    }
  }

  void _star(Canvas canvas, Offset o, double s, Paint paint) {
    final path = Path()
      ..moveTo(o.dx, o.dy - s)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + s, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + s)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - s, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - s)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BallPainter old) => old.t != t || old.colors != colors;
}
