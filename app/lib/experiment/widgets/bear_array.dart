import 'package:flutter/material.dart';

import '../../ui/theme.dart';

/// 100 people as a 10 by 10 array of bear heads: [today] solid brown, then [gained] solid
/// teal, the rest outlined. Heads are 15 px on a 16 px pitch (a 159 px square), drawn from
/// the top-left, row by row. Empty heads are outlined, so no count relies on colour alone.
///
/// Used only when the modeled difference is one or more people in 100.
class BearArray extends StatelessWidget {
  const BearArray({
    super.key,
    required this.today,
    this.gained = 0,
    required this.semanticLabel,
    this.mintGain = false,
  });

  final int today;
  final int gained;
  final String semanticLabel;

  /// Real updates (Z-34) draw the gained bears mint with a dark outline; what-ifs draw them teal.
  final bool mintGain;

  static const double side = 159;

  @override
  Widget build(BuildContext context) {
    final t = today.clamp(0, 100);
    return Semantics(
      image: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: CustomPaint(
        size: const Size.square(side),
        painter: BearArrayPainter(today: t, gained: gained.clamp(0, 100 - t), mintGain: mintGain),
      ),
    );
  }
}

class BearArrayPainter extends CustomPainter {
  BearArrayPainter({required this.today, required this.gained, this.mintGain = false});
  final int today;
  final int gained;
  final bool mintGain;

  /// The bear head on a 16 by 16 grid, drawn at size [s]: two ears and a face.
  static Path head(double x, double y, double s) {
    final k = s / 16;
    Rect circle(double cx, double cy, double r) =>
        Rect.fromCircle(center: Offset(x + cx * k, y + cy * k), radius: r * k);
    return Path()
      ..addOval(circle(3.7, 4.6, 2.6))
      ..addOval(circle(12.3, 4.6, 2.6))
      ..addOval(circle(8, 9.6, 5.7));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final brown = Paint()..color = LtColors.headBrown;
    final teal = Paint()..color = mintGain ? LtColors.mint : LtColors.teal;
    final gainLine = Paint()
      ..color = const Color(0xFF17594A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final empty = Paint()..color = LtColors.paper;
    final line = Paint()
      ..color = LtColors.control
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < 100; i++) {
      final path = head((i % 10) * 16.0, (i ~/ 10) * 16.0, 15);
      if (i < today) {
        canvas.drawPath(path, brown);
      } else if (i < today + gained) {
        canvas.drawPath(path, teal);
        if (mintGain) canvas.drawPath(path, gainLine);
      } else {
        canvas.drawPath(path, empty);
        canvas.drawPath(path, line);
      }
    }
  }

  @override
  bool shouldRepaint(BearArrayPainter old) => old.today != today || old.gained != gained || old.mintGain != mintGain;
}
