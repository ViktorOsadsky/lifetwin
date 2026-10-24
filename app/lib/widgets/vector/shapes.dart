import 'package:flutter/widgets.dart';

/// A tiny subset of SVG, enough for the design's drawings: `path` (M L H V C Q Z,
/// absolute and relative), `circle`, `ellipse`, `rect` with rx, and `g` with a transform.
/// Shapes are copied from the artboards as data, so a new drawing is a paste.
sealed class Shape {
  const Shape({this.fill, this.stroke, this.strokeWidth = 0, this.opacity = 1, this.round = false});

  final Color? fill;
  final Color? stroke;
  final double strokeWidth;
  final double opacity;

  /// stroke-linecap/linejoin="round".
  final bool round;

  Path path();
}

class PathShape extends Shape {
  const PathShape(this.d, {super.fill, super.stroke, super.strokeWidth, super.opacity, super.round});
  final String d;
  @override
  Path path() => parseSvgPath(d);
}

class Circle extends Shape {
  const Circle(this.cx, this.cy, this.r, {super.fill, super.stroke, super.strokeWidth, super.opacity});
  final double cx, cy, r;
  @override
  Path path() => Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
}

class Ellipse extends Shape {
  const Ellipse(this.cx, this.cy, this.rx, this.ry, {super.fill, super.stroke, super.strokeWidth, super.opacity});
  final double cx, cy, rx, ry;
  @override
  Path path() => Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: 2 * rx, height: 2 * ry));
}

class RectShape extends Shape {
  const RectShape(this.x, this.y, this.w, this.h, {this.rx = 0, super.fill, super.stroke, super.strokeWidth});
  final double x, y, w, h, rx;
  @override
  Path path() => Path()..addRRect(RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(rx)));
}

/// `<g transform="translate(dx dy) scale(s)">`.
class Group extends Shape {
  const Group(this.children, {this.dx = 0, this.dy = 0, this.scale = 1});
  final List<Shape> children;
  final double dx, dy, scale;
  @override
  Path path() => Path();
}

/// Paints [shapes] from a [viewBox]. [stretch] fills the box like
/// preserveAspectRatio="none" (backgrounds); otherwise it fits and centers ("meet").
class ShapePainter extends CustomPainter {
  const ShapePainter(this.shapes, this.viewBox, {this.stretch = false});

  final List<Shape> shapes;
  final Size viewBox;
  final bool stretch;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / viewBox.width, sy = size.height / viewBox.height;
    canvas.save();
    if (stretch) {
      canvas.scale(sx, sy);
    } else {
      final s = sx < sy ? sx : sy;
      canvas.translate((size.width - viewBox.width * s) / 2, (size.height - viewBox.height * s) / 2);
      canvas.scale(s);
    }
    _paintAll(canvas, shapes);
    canvas.restore();
  }

  static void _paintAll(Canvas canvas, List<Shape> shapes) {
    for (final s in shapes) {
      if (s is Group) {
        canvas.save();
        canvas.translate(s.dx, s.dy);
        canvas.scale(s.scale);
        _paintAll(canvas, s.children);
        canvas.restore();
        continue;
      }
      final p = s.path();
      if (s.fill != null) {
        canvas.drawPath(p, Paint()..color = s.fill!.withValues(alpha: s.fill!.a * s.opacity));
      }
      if (s.stroke != null && s.strokeWidth > 0) {
        canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = s.stroke!.withValues(alpha: s.stroke!.a * s.opacity)
            ..strokeWidth = s.strokeWidth
            ..strokeCap = s.round ? StrokeCap.round : StrokeCap.butt
            ..strokeJoin = s.round ? StrokeJoin.round : StrokeJoin.miter,
        );
      }
    }
  }

  @override
  bool shouldRepaint(ShapePainter old) => old.shapes != shapes || old.viewBox != viewBox || old.stretch != stretch;
}

final _token = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?|[A-Za-z]');

/// Parses SVG path data with the commands M L H V C Q Z (either case). No arcs.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = _token.allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0, cmd = 'M';
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + n();
        y = oy + n();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        cmd = rel ? 'l' : 'L'; // extra pairs after M are lines
      case 'L':
        x = ox + n();
        y = oy + n();
        path.lineTo(x, y);
      case 'H':
        x = ox + n();
        path.lineTo(x, y);
      case 'V':
        y = oy + n();
        path.lineTo(x, y);
      case 'C':
        final x1 = ox + n(), y1 = oy + n(), x2 = ox + n(), y2 = oy + n();
        x = ox + n();
        y = oy + n();
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'Q':
        final x1 = ox + n(), y1 = oy + n();
        x = ox + n();
        y = oy + n();
        path.quadraticBezierTo(x1, y1, x, y);
      case 'Z':
        path.close();
        x = startX;
        y = startY;
        if (i < tokens.length && !isCmd(tokens[i])) throw FormatException('Numbers after Z in "$d"');
      default:
        throw FormatException('Unsupported SVG path command "$cmd" in "$d"');
    }
  }
  return path;
}

/// A fixed-size drawing. Decorative unless [label] is given.
class ShapeView extends StatelessWidget {
  const ShapeView({
    super.key,
    required this.shapes,
    required this.viewBox,
    required this.size,
    this.label,
    this.stretch = false,
  });

  final List<Shape> shapes;
  final Size viewBox;
  final Size size;
  final String? label;
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(size: size, painter: ShapePainter(shapes, viewBox, stretch: stretch));
    return label == null
        ? ExcludeSemantics(child: paint)
        : Semantics(image: true, label: label, excludeSemantics: true, child: paint);
  }
}
