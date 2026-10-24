import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/lt_colors.dart';
import '../theme/lt_cosmetics.dart';
import '../theme/lt_theme.dart';

enum TwinMood { happy, calm, tired, thinking, sick, recovering }

enum TwinSize {
  s(56),
  m(120),
  l(240);

  const TwinSize(this.width);
  final double width;
}

enum TwinHair { shortHair, bob, curly }

enum TwinExtra { none, glasses, headband }

/// What the arms are doing. Poses carry the twin's reaction to an action so
/// the response is on the character, not in a distant toast.
enum TwinPose {
  /// Arms relaxed at the sides.
  rest,

  /// One hand up, greeting.
  wave,

  /// One arm out toward a prop (side set by `Twin.reachSide`).
  reach,

  /// Both arms up: a win.
  cheer,

  /// Arms tucked in close: feeling a bit off (never wilted or sad).
  huddle,
}

/// Cosmetic options only. These never feed any number.
@immutable
class TwinLook {
  const TwinLook({
    this.skin = 1,
    this.hairStyle = TwinHair.shortHair,
    this.hairColor = 0,
    this.top = 0,
    this.extra = TwinExtra.none,
  });

  final int skin;
  final TwinHair hairStyle;
  final int hairColor;
  final int top;
  final TwinExtra extra;

  TwinLook copyWith({
    int? skin,
    TwinHair? hairStyle,
    int? hairColor,
    int? top,
    TwinExtra? extra,
  }) => TwinLook(
    skin: skin ?? this.skin,
    hairStyle: hairStyle ?? this.hairStyle,
    hairColor: hairColor ?? this.hairColor,
    top: top ?? this.top,
    extra: extra ?? this.extra,
  );
}

/// The user's avatar: flat vector, drawn in a 120 x 150 design box.
/// The body shape never depends on any health input.
class Twin extends StatelessWidget {
  const Twin({
    super.key,
    this.mood = TwinMood.happy,
    this.size = TwinSize.m,
    this.look = const TwinLook(),
    this.width,
    this.pose = TwinPose.rest,
    this.reachSide = 1,
    this.lean = 0,
    this.hop = 0,
  });

  final TwinMood mood;
  final TwinSize size;
  final TwinLook look;

  /// Overrides [size] when the stage decides the scale.
  final double? width;

  final TwinPose pose;

  /// -1 reaches to the left, 1 to the right.
  final int reachSide;

  /// Body lean around the feet, -1 (left) .. 1 (right).
  final double lean;

  /// Upward hop in design units (0 = standing on the ground).
  final double hop;

  static const double aspect = 150 / 120;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = width ?? size.width;
    return Semantics(
      image: true,
      label: 'Your twin, feeling ${mood.name}',
      child: SizedBox(
        width: w,
        height: w * aspect,
        child: CustomPaint(
          painter: TwinPainter(
            mood: mood,
            look: look,
            colors: c,
            pose: pose,
            reachSide: reachSide,
            lean: lean,
            hop: hop,
          ),
        ),
      ),
    );
  }
}

class TwinPainter extends CustomPainter {
  TwinPainter({
    required this.mood,
    required this.look,
    required this.colors,
    this.pose = TwinPose.rest,
    this.reachSide = 1,
    this.lean = 0,
    this.hop = 0,
  });

  final TwinMood mood;
  final TwinLook look;
  final LtColors colors;
  final TwinPose pose;
  final int reachSide;
  final double lean;
  final double hop;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 120);
    final c = colors;
    final skin = LtCosmetics.skin[look.skin.clamp(0, 4)];
    final hair = LtCosmetics.hair[look.hairColor.clamp(0, 4)];
    final top = LtCosmetics.tops(c)[look.top.clamp(0, 4)];
    const ink = LtCosmetics.line;
    const head = Offset(60, 52);

    // No outline and no shadow of its own: the habitat paints the contact
    // shadow on its ground plane. Lean pivots around the feet.
    canvas.translate(60, 146 - hop);
    canvas.rotate(lean.clamp(-1.0, 1.0) * 0.12);
    canvas.translate(-60, -146);

    _arms(canvas, top, skin);

    // Body.
    final body = RRect.fromRectAndCorners(
      const Rect.fromLTWH(24, 96, 72, 50),
      topLeft: const Radius.circular(30),
      topRight: const Radius.circular(30),
      bottomLeft: const Radius.circular(20),
      bottomRight: const Radius.circular(20),
    );
    canvas.drawRRect(body, Paint()..color = top);
    // Neck.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(50, 90, 20, 14),
        const Radius.circular(8),
      ),
      Paint()..color = skin,
    );

    // Hair behind head.
    final hairPaint = Paint()..color = hair;
    if (look.hairStyle == TwinHair.bob) {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          const Rect.fromLTWH(7, 30, 106, 66),
          topLeft: const Radius.circular(53),
          topRight: const Radius.circular(53),
          bottomLeft: const Radius.circular(22),
          bottomRight: const Radius.circular(22),
        ),
        hairPaint,
      );
    } else if (look.hairStyle == TwinHair.curly) {
      for (final a in [150, 180, 210, 240, 270, 300, 330, 360, 30]) {
        final r = a * math.pi / 180;
        canvas.drawCircle(
          head + Offset(math.cos(r) * 46, math.sin(r) * 46),
          13,
          hairPaint,
        );
      }
    }

    // Head.
    canvas.drawCircle(head, 50, Paint()..color = skin);

    // Sick: pale green tint over the face.
    if (mood == TwinMood.sick) {
      canvas.drawCircle(
        head,
        50,
        Paint()..color = c.chipPositive.withValues(alpha: 0.55),
      );
    }

    // Hair front.
    switch (look.hairStyle) {
      case TwinHair.shortHair:
        final p = Path()
          ..moveTo(12, 50)
          ..quadraticBezierTo(10, 4, 60, 3)
          ..quadraticBezierTo(110, 4, 108, 50)
          ..quadraticBezierTo(90, 26, 60, 28)
          ..quadraticBezierTo(30, 26, 12, 50)
          ..close();
        canvas.drawPath(p, hairPaint);
      case TwinHair.bob:
        final p = Path()
          ..moveTo(10, 56)
          ..quadraticBezierTo(8, 2, 60, 2)
          ..quadraticBezierTo(112, 2, 110, 56)
          ..quadraticBezierTo(98, 24, 60, 26)
          ..quadraticBezierTo(22, 24, 10, 56)
          ..close();
        canvas.drawPath(p, hairPaint);
      case TwinHair.curly:
        for (final x in [30.0, 45.0, 60.0, 75.0, 90.0]) {
          canvas.drawCircle(
            Offset(x, 14 + (x - 60).abs() * 0.18),
            12,
            hairPaint,
          );
        }
    }

    // Extras.
    if (look.extra == TwinExtra.headband) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(11, 24, 98, 9),
          const Radius.circular(5),
        ),
        Paint()..color = c.actionPrimary,
      );
    }

    // Cheeks.
    final cheek = Paint()..color = LtCosmetics.cheek.withValues(alpha: 0.55);
    canvas.drawCircle(const Offset(36, 66), 7, cheek);
    canvas.drawCircle(const Offset(84, 66), 7, cheek);

    _face(canvas, ink);

    if (look.extra == TwinExtra.glasses) {
      final g = Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(const Offset(44, 54), 11, g);
      canvas.drawCircle(const Offset(76, 54), 11, g);
      canvas.drawLine(const Offset(55, 54), const Offset(65, 54), g);
    }

    _moodExtras(canvas, c);
    canvas.restore();
  }

  void _arms(Canvas canvas, Color top, Color skin) {
    final sleeve = Paint()
      ..color = top
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;
    final hand = Paint()..color = skin;
    const l = Offset(34, 108);
    const r = Offset(86, 108);
    final side = reachSide < 0 ? -1.0 : 1.0;
    final (Offset lh, Offset rh) = switch (pose) {
      TwinPose.rest => (const Offset(20, 134), const Offset(100, 134)),
      TwinPose.wave => (const Offset(20, 134), const Offset(110, 78)),
      TwinPose.cheer => (const Offset(10, 80), const Offset(110, 80)),
      TwinPose.huddle => (const Offset(34, 132), const Offset(86, 132)),
      TwinPose.reach =>
        side > 0
            ? (const Offset(20, 134), const Offset(118, 104))
            : (const Offset(2, 104), const Offset(100, 134)),
    };
    for (final (from, to) in [(l, lh), (r, rh)]) {
      // A slight elbow bend so arms read as drawn, not as sticks.
      final mid =
          Offset.lerp(from, to, 0.5)! + Offset(0, (to.dy < from.dy) ? 4 : -2);
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy),
        sleeve,
      );
      canvas.drawCircle(to, 7, hand);
    }
  }

  void _face(Canvas canvas, Color ink) {
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = ink;
    const l = Offset(44, 54);
    const r = Offset(76, 54);

    switch (mood) {
      case TwinMood.happy:
      case TwinMood.recovering:
        _dotEye(canvas, l, fill);
        _dotEye(canvas, r, fill);
      case TwinMood.calm:
        for (final e in [l, r]) {
          canvas.drawArc(
            Rect.fromCenter(center: e, width: 12, height: 8),
            0.2,
            math.pi - 0.4,
            false,
            stroke,
          );
        }
      case TwinMood.tired:
        for (final e in [l, r]) {
          canvas.drawLine(
            e + const Offset(-6, 0),
            e + const Offset(6, 1),
            stroke,
          );
        }
      case TwinMood.thinking:
        _dotEye(canvas, l + const Offset(2, -3), fill);
        _dotEye(canvas, r + const Offset(2, -3), fill);
      case TwinMood.sick:
        for (final e in [l, r]) {
          canvas.drawArc(
            Rect.fromCenter(center: e, width: 12, height: 8),
            math.pi + 0.3,
            math.pi - 0.6,
            false,
            stroke,
          );
        }
    }

    final m = Path();
    switch (mood) {
      case TwinMood.happy:
        m
          ..moveTo(46, 74)
          ..quadraticBezierTo(60, 88, 74, 74);
      case TwinMood.recovering:
        m
          ..moveTo(48, 75)
          ..quadraticBezierTo(60, 84, 72, 75);
      case TwinMood.calm:
        m
          ..moveTo(50, 76)
          ..quadraticBezierTo(60, 81, 70, 76);
      case TwinMood.tired:
        m
          ..moveTo(52, 78)
          ..lineTo(68, 78);
      case TwinMood.thinking:
        m
          ..moveTo(52, 78)
          ..quadraticBezierTo(60, 74, 68, 79);
      case TwinMood.sick:
        m
          ..moveTo(50, 80)
          ..quadraticBezierTo(60, 73, 70, 80);
    }
    canvas.drawPath(m, stroke);
  }

  /// Dot eye with a small shine toward the upper-left light.
  void _dotEye(Canvas canvas, Offset o, Paint fill) {
    canvas.drawCircle(o, 4, fill);
    canvas.drawCircle(
      o + const Offset(-1.3, -1.4),
      1.4,
      Paint()..color = LtCosmetics.eyeShine,
    );
  }

  void _moodExtras(Canvas canvas, LtColors c) {
    final leaf = Paint()..color = c.vizExperiment;
    final stem = Paint()
      ..color = c.vizExperiment
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    switch (mood) {
      case TwinMood.sick:
        // Droopy sprout and a thermometer.
        final s = Path()
          ..moveTo(60, 4)
          ..quadraticBezierTo(60, -6, 70, -4);
        canvas.drawPath(s, stem);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(75, 0), width: 13, height: 8),
          leaf,
        );
        final t = Paint()
          ..color = c.bgSurface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(70, 78), const Offset(98, 68), t);
        canvas.drawCircle(
          const Offset(70, 78),
          4,
          Paint()..color = c.actionPrimary,
        );
      case TwinMood.recovering:
        final s = Path()
          ..moveTo(60, 4)
          ..quadraticBezierTo(60, -8, 66, -10);
        canvas.drawPath(s, stem);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(70, -10), width: 13, height: 8),
          leaf,
        );
        _spark(canvas, c, const Offset(100, 20), 5);
        _spark(canvas, c, const Offset(14, 30), 4);
      case TwinMood.thinking:
        final dot = Paint()..color = c.skyHighlight;
        canvas.drawCircle(const Offset(106, 20), 3, dot);
        canvas.drawCircle(const Offset(112, 8), 4.5, dot);
      case TwinMood.happy:
      case TwinMood.calm:
      case TwinMood.tired:
        break;
    }
  }

  void _spark(Canvas canvas, LtColors c, Offset o, double r) {
    final p = Paint()..color = c.sun;
    final path = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(TwinPainter old) =>
      old.mood != mood ||
      old.colors != colors ||
      old.pose != pose ||
      old.reachSide != reachSide ||
      old.lean != lean ||
      old.hop != hop ||
      old.look.skin != look.skin ||
      old.look.hairStyle != look.hairStyle ||
      old.look.hairColor != look.hairColor ||
      old.look.top != look.top ||
      old.look.extra != look.extra;
}
