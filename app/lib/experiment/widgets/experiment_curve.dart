import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../twin/twin_model.dart' show TwinAssessment;
import '../../ui/theme.dart';
import '../result_display.dart';

/// Today and the what-if, years 1 to 5, the model's yearly values joined by straight lines
/// (nothing before year 1 or after year 5). Plotted values are the labels' values: today is
/// round(p), the what-if is today plus the rounded gap, so the picture, labels and table agree.
///
/// Zoomed (the default) the axis runs from [zoomFloor] to 100 and is labelled as zoomed
/// by the screen; [full] draws the honest 0 to 100 axis.
class ExperimentCurve extends StatelessWidget {
  const ExperimentCurve({super.key, required this.rows, this.full = false});

  final List<YearRow> rows;
  final bool full;

  /// The bottom of the zoomed axis: the lowest plotted value, minus a margin, down to a multiple of 5.
  static int zoomFloor(List<YearRow> rows) {
    final low = rows.map((r) => math.min(r.today, r.whatIf)).reduce(math.min);
    return (((low - 2) / 5).floor() * 5).clamp(0, 95);
  }

  static String describe(List<YearRow> rows) => [
    '${TwinAssessment.survivalTitle}. Out of 100 people like you, still alive each year.',
    for (final r in rows) 'Year ${r.year}: today ${r.today}, what-if ${r.whatIf}.',
  ].join(' ');

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      image: true,
      label: describe(rows),
      excludeSemantics: true,
      child: SizedBox(
        height: 210 + 30 * (scaler.scale(17) / 17 - 1).clamp(0.0, 1.0),
        width: double.infinity,
        child: CustomPaint(
          painter: ExperimentCurvePainter(rows: rows, lo: full ? 0 : zoomFloor(rows), scaler: scaler),
        ),
      ),
    );
  }
}

class ExperimentCurvePainter extends CustomPainter {
  ExperimentCurvePainter({required this.rows, required this.lo, required this.scaler});
  final List<YearRow> rows;
  final int lo;
  final TextScaler scaler;

  static const _grid = Color(0xFFE9DFD0);
  static const _today = LtColors.control;

  void _text(Canvas c, String s, Offset at, TextStyle st, {Alignment align = Alignment.center}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    c.save();
    c.translate(at.dx - tp.width * (align.x + 1) / 2, at.dy - tp.height * (align.y + 1) / 2);
    tp.paint(c, Offset.zero);
    c.restore();
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final small = LtText.body(size: 17);
    const left = 40.0, right = 44.0, top = 10.0;
    final bottom = 56.0 + 8 * (scaler.scale(17) / 17 - 1).clamp(0.0, 1.0);
    final w = size.width - left - right, h = size.height - top - bottom;
    final hi = 100.0;
    double x(int year) => left + w * (year - 1) / 4;
    double y(num v) => top + h * (1 - (v - lo) / (hi - lo));

    // Gridlines and y labels, every 5 when zoomed, every 25 at full scale.
    final stepV = (hi - lo) <= 30
        ? 5
        : (hi - lo) <= 60
        ? 10
        : 25;
    for (var v = lo; v <= 100; v += stepV) {
      final yy = y(v);
      if (v != lo) {
        _dash(
          canvas,
          Offset(left, yy),
          Offset(left + w, yy),
          Paint()
            ..color = _grid
            ..strokeWidth = 1.2,
        );
      }
      _text(canvas, '$v', Offset(left - 6, yy), small, align: Alignment.centerRight);
    }
    canvas.drawLine(
      Offset(left, y(lo)),
      Offset(left + w, y(lo)),
      Paint()
        ..color = LtColors.container
        ..strokeWidth = 1.5,
    );
    if (lo > 0) {
      // The axis break: this scale does not start at zero.
      final b = Paint()
        ..color = LtColors.ink
        ..strokeWidth = 1.5;
      for (final dx in [left + 4, left + 10]) {
        canvas.drawLine(Offset(dx, y(lo) + 5), Offset(dx + 4, y(lo) - 5), b);
      }
    }
    for (final r in rows) {
      _text(canvas, '${r.year}', Offset(x(r.year), y(lo) + 18), small);
    }
    _text(canvas, 'Years', Offset(left + w / 2, y(lo) + 42), small);

    final pts0 = [for (final r in rows) Offset(x(r.year), y(r.today))];
    final pts1 = [for (final r in rows) Offset(x(r.year), y(r.whatIf))];
    // The gap between them.
    final band = Path()..moveTo(pts1.first.dx, pts1.first.dy);
    for (final p in pts1.skip(1)) {
      band.lineTo(p.dx, p.dy);
    }
    for (final p in pts0.reversed) {
      band.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(band..close(), Paint()..color = LtColors.mint.withValues(alpha: 0.45));

    final dashed = Paint()
      ..color = _today
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < pts0.length - 1; i++) {
      _dash(canvas, pts0[i], pts0[i + 1], dashed, on: 7, off: 5);
    }
    final solid = Paint()
      ..color = LtColors.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(Path()..addPolygon(pts1, false), solid);
    for (final p in pts0) {
      canvas.drawCircle(p, 5, Paint()..color = LtColors.paper);
      canvas.drawCircle(
        p,
        5,
        Paint()
          ..color = _today
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    for (final p in pts1) {
      canvas.drawCircle(p, 5, Paint()..color = LtColors.teal);
    }
    final last = rows.length - 1;
    _text(
      canvas,
      '${rows.last.whatIf}',
      pts1[last] + const Offset(10, 0),
      LtText.display(20, color: LtColors.teal),
      align: Alignment.centerLeft,
    );
    _text(
      canvas,
      '${rows.last.today}',
      pts0[last] + const Offset(10, 4),
      LtText.body(size: 18, color: LtColors.ink),
      align: Alignment.centerLeft,
    );
  }

  void _dash(Canvas canvas, Offset a, Offset b, Paint p, {double on = 4, double off = 4}) {
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy);
    for (final PathMetric m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += on + off) {
        canvas.drawPath(m.extractPath(d, math.min(d + on, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(ExperimentCurvePainter old) => old.rows != rows || old.lo != lo || old.scaler != scaler;
}
