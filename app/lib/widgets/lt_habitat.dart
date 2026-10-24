import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/lt_scene.dart';
import '../theme/lt_theme.dart';

/// Something standing in the habitat: the twin, Pip or a prop. Its bottom
/// edge sits on the contact plane at [x], over a contact shadow.
class HabitatActor {
  const HabitatActor({
    required this.x,
    required this.footprint,
    required this.child,
    this.lift = 0,
  });

  /// Horizontal centre, 0 (left edge) .. 1 (right edge).
  final double x;

  /// Contact-shadow width in logical px, roughly the actor's base width.
  final double footprint;

  /// Height above the ground in logical px (Pip floats a little).
  final double lift;

  final Widget child;
}

/// The twin's home: a small meadow with sky, distant hills, midground bushes,
/// a ground plane with contact shadows, foreground tufts and one light from
/// the upper left. Tier 1 Resting .. 4 Thriving picks the Scene palette.
///
/// Paints only inside its own bounds; give it a height (or put it in an
/// Expanded). Tier changes crossfade over 700 ms (easeOutCubic); with
/// reduced motion the swap is instant and nothing drifts.
///
/// The scene dissolves into the page (§7b.1): over [fadeTop] the sky eases
/// to the page `ground` colour at the top edge, and over [fadeBottom] the
/// meadow feathers into it at the bottom, so there is no seam or rectangle
/// edge where content begins. Contact shadows and actors stay crisp above
/// the fades. With [splitTier] the right half is the same meadow in another
/// tier, joined by a soft vertical fade rather than two boxed tiles.
class Habitat extends StatefulWidget {
  const Habitat({
    super.key,
    required this.tier,
    this.actors = const [],
    this.horizon = 0.58,
    this.contactLine = 0.86,
    this.overlay,
    this.fadeTop = 0,
    this.fadeBottom = 0,
    this.splitTier,
    this.split = 0.5,
  });

  final int tier;

  /// Height of the feather into the page ground at the top edge.
  final double fadeTop;

  /// Height of the feather into the page ground at the bottom edge
  /// (at least 120 where content follows the scene).
  final double fadeBottom;

  /// Optional tier for the right-hand part of a split comparison.
  final int? splitTier;

  /// Where the split's soft fade is centred, 0..1 of the width.
  final double split;
  final List<HabitatActor> actors;

  /// Where sky meets the ground plane, as a fraction of height.
  final double horizon;

  /// Where actors' feet touch the ground, as a fraction of height.
  final double contactLine;

  /// HUD layer (chips, meters) above the scene.
  final Widget? overlay;

  static const crossfade = Duration(milliseconds: 700);

  @override
  State<Habitat> createState() => _HabitatState();
}

class _HabitatState extends State<Habitat> with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDrift();
  }

  @override
  void didUpdateWidget(Habitat old) {
    super.didUpdateWidget(old);
    if (old.tier != widget.tier || old.splitTier != widget.splitTier) {
      _syncDrift();
    }
  }

  int get _topTier => math.max(widget.tier, widget.splitTier ?? 0);

  bool get _drifting =>
      !MediaQuery.of(context).disableAnimations && _topTier >= 3;

  void _syncDrift() {
    if (_drifting) {
      if (!_drift.isAnimating) _drift.repeat();
    } else if (_drift.isAnimating) {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  Widget _scene(int tier, bool reduce) => TweenAnimationBuilder<LtScene>(
    tween: _SceneTween(end: LtScene.of(tier)),
    duration: reduce ? Duration.zero : Habitat.crossfade,
    curve: Curves.easeOutCubic,
    builder: (context, scene, _) => CustomPaint(
      painter: _ScenePainter(
        scene: scene,
        horizon: widget.horizon,
        bloom: tier >= 4 ? 1.0 : (tier == 3 ? 0.75 : 0.55),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final tier = widget.tier.clamp(1, 4);
    final right = widget.splitTier?.clamp(1, 4);
    final page = context.colors.bgGround;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final contactY = h * widget.contactLine;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _scene(tier, reduce),
              if (right != null)
                ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => LinearGradient(
                    colors: [page.withValues(alpha: 0), page],
                    stops: [
                      (widget.split - 0.14).clamp(0.0, 1.0),
                      (widget.split + 0.14).clamp(0.0, 1.0),
                    ],
                  ).createShader(r),
                  child: _scene(right, reduce),
                ),
              if (_drifting)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _DriftPainter(
                      t: _drift,
                      sparkle: _topTier >= 4,
                      horizon: widget.horizon,
                      sun: LtScene.of(_topTier).light,
                      fromX: right != null && right > tier ? widget.split : 0,
                    ),
                  ),
                ),
              if (widget.fadeTop > 0 || widget.fadeBottom > 0)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _FadePainter(
                      color: page,
                      top: widget.fadeTop,
                      bottom: widget.fadeBottom,
                    ),
                  ),
                ),
              if (widget.actors.isNotEmpty)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ShadowPainter(
                      color: LtScene.of(tier).contactShadow,
                      contactLine: widget.contactLine,
                      shadows: [
                        for (final a in widget.actors)
                          (a.x, a.footprint, a.lift),
                      ],
                    ),
                  ),
                ),
              for (final a in widget.actors)
                Positioned(
                  left: a.x * w,
                  bottom: h - contactY + a.lift,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, 0),
                    child: a.child,
                  ),
                ),
              ?widget.overlay,
            ],
          ),
        );
      },
    );
  }
}

/// Feathers the scene into the page colour at the top and bottom edges.
/// The curve eases in so the meadow stays readable until near the edge.
class _FadePainter extends CustomPainter {
  _FadePainter({required this.color, required this.top, required this.bottom});

  final Color color;
  final double top;
  final double bottom;

  static const _stops = [0.0, 0.35, 0.7, 1.0];

  List<Color> get _ramp => [
    color,
    color.withValues(alpha: 0.72),
    color.withValues(alpha: 0.22),
    color.withValues(alpha: 0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (top > 0) {
      final r = Rect.fromLTWH(0, 0, size.width, math.min(top, size.height));
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _ramp,
            stops: _stops,
          ).createShader(r),
      );
    }
    if (bottom > 0) {
      final hgt = math.min(bottom, size.height);
      final r = Rect.fromLTWH(0, size.height - hgt, size.width, hgt);
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: _ramp,
            stops: _stops,
          ).createShader(r),
      );
    }
  }

  @override
  bool shouldRepaint(_FadePainter old) =>
      old.color != color || old.top != top || old.bottom != bottom;
}

/// Contact shadows, nudged lower-right, away from the upper-left light.
class _ShadowPainter extends CustomPainter {
  _ShadowPainter({
    required this.color,
    required this.contactLine,
    required this.shadows,
  });

  final Color color;
  final double contactLine;
  final List<(double, double, double)> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height * contactLine;
    for (final (x, footprint, lift) in shadows) {
      final k = lift > 0 ? 0.7 : 1.0;
      final sw = footprint * k;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x * w + sw * 0.05, cy + 1),
          width: sw,
          height: math.max(6, sw * 0.16),
        ),
        Paint()
          ..color = color.withValues(alpha: lift > 0 ? 0.18 : 0.32)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(_ShadowPainter old) =>
      old.color != color ||
      old.contactLine != contactLine ||
      !_sameShadows(old.shadows, shadows);

  static bool _sameShadows(
    List<(double, double, double)> a,
    List<(double, double, double)> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _SceneTween extends Tween<LtScene> {
  _SceneTween({super.end});

  @override
  LtScene lerp(double t) => LtScene.lerp(begin ?? end!, end!, t);
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.scene,
    required this.horizon,
    required this.bloom,
  });

  final LtScene scene;
  final double horizon;
  final double bloom;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final hy = h * horizon;
    final s = scene;

    // Sky.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [s.skyTop, s.skyBottom],
        ).createShader(Rect.fromLTWH(0, 0, w, hy + 1)),
    );

    // Sun bloom, upper left: the one light direction.
    final sun = Offset(w * 0.14, h * 0.12);
    final sunR = math.max(w, h) * 0.55;
    canvas.drawCircle(
      sun,
      sunR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            s.light.withValues(alpha: 0.85 * bloom),
            s.light.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: sun, radius: sunR)),
    );

    // Distant hills: foliage-deep pushed toward the sky for air.
    final far = Color.lerp(s.foliageDeep, s.skyBottom, 0.62)!;
    final near = Color.lerp(s.foliageDeep, s.skyBottom, 0.38)!;
    canvas.drawPath(
      Path()
        ..moveTo(0, hy)
        ..lineTo(0, hy - h * 0.10)
        ..quadraticBezierTo(w * 0.22, hy - h * 0.22, w * 0.48, hy - h * 0.08)
        ..quadraticBezierTo(w * 0.72, hy - h * 0.20, w, hy - h * 0.12)
        ..lineTo(w, hy)
        ..close(),
      Paint()..color = far,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.30, hy)
        ..quadraticBezierTo(w * 0.62, hy - h * 0.13, w * 1.05, hy - h * 0.05)
        ..lineTo(w, hy)
        ..close(),
      Paint()..color = near,
    );

    // Midground bushes at the edges, leaving the stage centre clear.
    final unit = math.min(w, h);
    _bush(canvas, Offset(w * 0.04, hy), unit * 0.13);
    _bush(canvas, Offset(w * 0.17, hy + unit * 0.01), unit * 0.08);
    _bush(canvas, Offset(w * 0.95, hy - unit * 0.005), unit * 0.15);

    // Ground plane: a gentle mound, lit along its upper-left rim.
    final ground = Path()
      ..moveTo(0, hy + h * 0.02)
      ..quadraticBezierTo(w * 0.5, hy - h * 0.035, w, hy + h * 0.02)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      ground,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(s.ground, s.light, 0.35)!,
            s.ground,
            Color.lerp(s.ground, s.foliage, 0.25)!,
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromLTWH(0, hy - h * 0.04, w, h - hy)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, hy + h * 0.02)
        ..quadraticBezierTo(w * 0.5, hy - h * 0.035, w, hy + h * 0.02),
      Paint()
        ..color = Color.lerp(s.ground, s.light, 0.7)!.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Foreground tufts frame the bottom corners.
    _tuft(canvas, Offset(w * 0.06, h), unit * 0.09);
    _tuft(canvas, Offset(w * 0.90, h), unit * 0.07);
  }

  void _bush(Canvas canvas, Offset base, double r) {
    final s = scene;
    final body = Paint()..color = s.foliage;
    final shade = Paint()..color = s.foliageDeep.withValues(alpha: 0.55);
    final lit = Paint()..color = Color.lerp(s.foliage, s.light, 0.45)!;
    final blobs = [
      (Offset(-r * 0.7, -r * 0.55), r * 0.62),
      (Offset(0, -r * 0.85), r * 0.78),
      (Offset(r * 0.75, -r * 0.5), r * 0.58),
    ];
    // Shade first, offset lower-right.
    for (final (o, rr) in blobs) {
      canvas.drawCircle(base + o + Offset(rr * 0.16, rr * 0.14), rr, shade);
    }
    for (final (o, rr) in blobs) {
      canvas.drawCircle(base + o, rr, body);
    }
    // Light catches the upper-left of the biggest blob.
    canvas.drawCircle(
      base + Offset(-r * 0.22, -r * 1.12),
      r * 0.22,
      lit..color = lit.color.withValues(alpha: 0.7),
    );
  }

  void _tuft(Canvas canvas, Offset base, double r) {
    final p = Paint()..color = scene.foliageDeep.withValues(alpha: 0.75);
    final blade = Path();
    for (final (dx, hgt, lean) in [
      (-0.6, 0.9, -0.35),
      (-0.15, 1.3, -0.1),
      (0.3, 1.05, 0.25),
      (0.7, 0.7, 0.4),
    ]) {
      final x = base.dx + dx * r;
      blade
        ..moveTo(x - r * 0.14, base.dy)
        ..quadraticBezierTo(
          x + lean * r * 0.4,
          base.dy - hgt * r * 0.6,
          x + lean * r,
          base.dy - hgt * r,
        )
        ..quadraticBezierTo(
          x + lean * r * 0.2,
          base.dy - hgt * r * 0.5,
          x + r * 0.14,
          base.dy,
        )
        ..close();
    }
    canvas.drawPath(blade, p);
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.scene != scene || old.horizon != horizon || old.bloom != bloom;
}

/// Gentle air particles in the sky (Good) or sun sparkles (Thriving).
class _DriftPainter extends CustomPainter {
  _DriftPainter({
    required this.t,
    required this.sparkle,
    required this.horizon,
    required this.sun,
    this.fromX = 0,
  }) : super(repaint: t);

  /// Particles only drift right of this fraction (the livelier half).
  final double fromX;

  final Animation<double> t;
  final bool sparkle;
  final double horizon;
  final Color sun;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(11);
    final count = sparkle ? 9 : 7;
    final skyH = size.height * horizon;
    for (var i = 0; i < count; i++) {
      final x0 = fromX + rnd.nextDouble() * (1 - fromX);
      final speed = 0.5 + rnd.nextDouble() * 0.5;
      final phase = rnd.nextDouble();
      final p = (t.value * speed + phase) % 1;
      final y = skyH * (0.95 - p * 0.85);
      final x = (x0 + math.sin((p + phase) * math.pi * 2) * 0.02) * size.width;
      final a = math.sin(p * math.pi).clamp(0.0, 1.0);
      if (sparkle) {
        final r = 3 + rnd.nextDouble() * 3;
        final o = Offset(x, y);
        canvas.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - r)
            ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
            ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
            ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
            ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
            ..close(),
          Paint()..color = sun.withValues(alpha: 0.9 * a),
        );
      } else {
        canvas.drawCircle(
          Offset(x, y),
          1.6 + rnd.nextDouble() * 2,
          Paint()..color = sun.withValues(alpha: 0.75 * a),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DriftPainter old) =>
      old.sparkle != sparkle ||
      old.horizon != horizon ||
      old.sun != sun ||
      old.fromX != fromX;
}
