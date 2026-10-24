import 'package:flutter/material.dart';

import '../theme/lt_colors.dart';
import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';

/// Obviously schematic placeholder curves. The shapes are fixed art, not
/// data: no axis values, and a visible "Schematic shape" caption. Lines are
/// told apart by style as well as colour (dashed baseline, solid You,
/// thicker experiment).
class LtCurveChart extends StatelessWidget {
  const LtCurveChart({
    super.key,
    this.showExperiment = false,
    this.showBaseline = true,
    this.height = 160,
  });

  final bool showExperiment;
  final bool showBaseline;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Schematic outlook curves. Placeholder shapes, not data.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: CustomPaint(
                painter: _CurvePainter(
                  colors: c,
                  showExperiment: showExperiment,
                  showBaseline: showBaseline,
                ),
              ),
            ),
          ),
          const SizedBox(height: LtSpace.s8),
          Wrap(
            spacing: LtSpace.s16,
            runSpacing: LtSpace.s4,
            children: [
              _Key(label: 'You', color: c.actionPrimary),
              if (showBaseline)
                _Key(
                  label: 'Similar people',
                  color: c.vizBaseline,
                  dashed: true,
                ),
              if (showExperiment)
                _Key(label: 'Experiment', color: c.vizExperiment, thick: true),
            ],
          ),
          const SizedBox(height: LtSpace.s8),
          Text(
            'Schematic shape — not data. Time runs left to right.',
            style: context.text.caption,
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.color,
    this.dashed = false,
    this.thick = false,
  });

  final String label;
  final Color color;
  final bool dashed;
  final bool thick;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(24, 8),
          painter: _KeyPainter(color: color, dashed: dashed, thick: thick),
        ),
        const SizedBox(width: LtSpace.s4 + 2),
        Text(label, style: context.text.caption),
      ],
    );
  }
}

class _KeyPainter extends CustomPainter {
  _KeyPainter({required this.color, required this.dashed, required this.thick});

  final Color color;
  final bool dashed;
  final bool thick;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thick ? 4 : 2.5
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (dashed) {
      canvas.drawLine(Offset(0, y), Offset(8, y), paint);
      canvas.drawLine(Offset(14, y), Offset(size.width, y), paint);
    } else {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_KeyPainter old) =>
      old.color != color || old.dashed != dashed || old.thick != thick;
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.colors,
    required this.showExperiment,
    required this.showBaseline,
  });

  final LtColors colors;
  final bool showExperiment;
  final bool showBaseline;

  Path _curve(Size s, double drop, double bend) {
    final w = s.width;
    final h = s.height;
    return Path()
      ..moveTo(0, h * 0.08)
      ..cubicTo(
        w * bend,
        h * 0.08,
        w * (bend + 0.25),
        h * drop,
        w,
        h * drop + h * 0.12,
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    // Axes.
    final axis = Paint()
      ..color = c.line
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, 0), Offset(0, size.height), axis);
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axis,
    );

    if (showBaseline) {
      final path = _curve(size, 0.78, 0.18);
      final paint = Paint()
        ..color = c.vizBaseline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (final m in path.computeMetrics()) {
        var d = 0.0;
        while (d < m.length) {
          canvas.drawPath(m.extractPath(d, d + 8), paint);
          d += 14;
        }
      }
    }
    canvas.drawPath(
      _curve(size, 0.66, 0.24),
      Paint()
        ..color = c.actionPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    if (showExperiment) {
      canvas.drawPath(
        _curve(size, 0.5, 0.32),
        Paint()
          ..color = c.vizExperiment
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.showExperiment != showExperiment ||
      old.showBaseline != showBaseline ||
      old.colors != colors;
}
