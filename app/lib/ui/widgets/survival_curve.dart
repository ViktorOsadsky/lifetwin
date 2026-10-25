import 'package:flutter/material.dart';

import '../../twin/twin_model.dart' show TwinAssessment;
import '../theme.dart';

/// One point of the model's monthly curve: years from now, share still living.
typedef CurvePoint = ({double years, double survival});

/// The person's own survival curve on an honest 0–100 axis ("out of 100
/// people"), with markers at the horizons the model returns (1, 3, 5).
/// Draws only what the response contains; nothing is extrapolated.
class SurvivalCurve extends StatelessWidget {
  const SurvivalCurve({
    super.key,
    required this.curve,
    required this.markers,
    required this.maxYears,
    this.height = 210,
  });

  final List<CurvePoint> curve;

  /// Horizon years → survival 0..1.
  final Map<int, double> markers;
  final int maxYears;
  final double height;

  static String describe(Map<int, double> markers) {
    final years = markers.keys.toList()..sort();
    final parts = [
      for (final y in years) 'about ${(100 * markers[y]!).round()} after $y ${y == 1 ? 'year' : 'years'}',
    ];
    return '${TwinAssessment.survivalTitle}. Out of 100 people with answers like yours: ${parts.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      container: true,
      label: describe(markers),
      excludeSemantics: true,
      child: SizedBox(
        height: height + 40 * (scaler.scale(17) / 17 - 1).clamp(0, 2),
        width: double.infinity,
        child: CustomPaint(painter: SurvivalCurvePainter(curve: curve, markers: markers, maxYears: maxYears, scaler: scaler)),
      ),
    );
  }
}

class SurvivalCurvePainter extends CustomPainter {
  SurvivalCurvePainter({required this.curve, required this.markers, required this.maxYears, required this.scaler});

  final List<CurvePoint> curve;
  final Map<int, double> markers;
  final int maxYears;
  final TextScaler scaler;

  static const _text = LtColors.cream;

  TextPainter _label(String s, {double size = 15, Color color = _text, FontWeight weight = FontWeight.w400}) =>
      TextPainter(
        text: TextSpan(text: s, style: LtText.body(size: size, color: color, weight: weight)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final y100 = _label('100');
    final left = y100.width + 10;
    final xLabel = _label('5 yrs');
    final bottom = size.height - xLabel.height - 8;
    final top = y100.height + 16; // room for the marker values
    final right = size.width - 8;
    final plot = Rect.fromLTRB(left, top, right, bottom);
    Offset at(double years, double s) =>
        Offset(plot.left + plot.width * (years / maxYears).clamp(0, 1), plot.bottom - plot.height * s.clamp(0, 1));

    // Axis: 0, 50, 100, honestly from zero.
    final grid = Paint()
      ..color = _text.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (final v in [0, 50, 100]) {
      final y = plot.bottom - plot.height * v / 100;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final t = _label('$v');
      t.paint(canvas, Offset(left - 10 - t.width, y - t.height / 2));
      t.dispose();
    }
    final axis = Paint()
      ..color = _text.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axis);

    // X labels: now, then each marker year.
    final xs = <(double, String)>[(0, 'now'), for (final y in markers.keys) (y.toDouble(), '$y ${y == 1 ? 'yr' : 'yrs'}')];
    for (final (years, s) in xs) {
      final t = _label(s);
      final x = at(years, 0).dx;
      t.paint(canvas, Offset((x - t.width / 2).clamp(0, size.width - t.width), plot.bottom + 6));
      t.dispose();
    }

    // The curve.
    final pts = [...curve]..sort((a, b) => a.years.compareTo(b.years));
    if (pts.length >= 2) {
      final path = Path()..moveTo(at(pts.first.years, pts.first.survival).dx, at(pts.first.years, pts.first.survival).dy);
      for (final p in pts.skip(1)) {
        final o = at(p.years, p.survival);
        path.lineTo(o.dx, o.dy);
      }
      final area = Path.from(path)
        ..lineTo(at(pts.last.years, 0).dx, plot.bottom)
        ..lineTo(at(pts.first.years, 0).dx, plot.bottom)
        ..close();
      canvas.drawPath(area, Paint()..color = LtColors.gold.withValues(alpha: 0.14));
      canvas.drawPath(
        path,
        Paint()
          ..color = LtColors.gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Markers with their "N in 100" value.
    for (final e in markers.entries) {
      final o = at(e.key.toDouble(), e.value);
      canvas.drawCircle(o, 7, Paint()..color = LtColors.night);
      canvas.drawCircle(o, 6, Paint()..color = LtColors.gold);
      canvas.drawCircle(
        o,
        6,
        Paint()
          ..color = LtColors.cream
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final t = _label('${(100 * e.value).round()}', size: 17, weight: FontWeight.w700);
      final dx = (o.dx - t.width / 2).clamp(plot.left, size.width - t.width);
      final dy = (o.dy - 12 - t.height).clamp(0.0, size.height);
      t.paint(canvas, Offset(dx, dy));
      t.dispose();
    }
    y100.dispose();
    xLabel.dispose();
  }

  @override
  bool shouldRepaint(SurvivalCurvePainter old) =>
      old.curve != curve || old.markers != markers || old.maxYears != maxYears || old.scaler != scaler;
}
