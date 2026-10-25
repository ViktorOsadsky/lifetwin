import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../twin/twin_state.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/twin_sprite.dart';
import 'room_layout.dart';
import 'room_mood_pose.dart';
import 'room_sim.dart';

/// The room, as three pre-rendered layers with the twin between them:
/// `room_bg`, then the twin sprite (placed and sized by the [FloorProjector]
/// of [RoomLayout], with a blob shadow), then the foreground pieces that
/// cover it (the quilt edge while it sleeps; the whole bed or the table
/// when it stands behind them, see [RoomLayout.covers]), then the effect
/// particles. Everything is laid out in the 390 x 844 render and
/// cover-fitted to the screen; on short screens the render slides up so the
/// mat stays clear of the UI ([clear]).
///
/// Swap point: a future room engine (for example Flame) replaces this widget
/// and its projector; [RoomSim] and the screen around it stay the same.
class RoomScene extends StatefulWidget {
  const RoomScene({super.key, required this.sim, required this.appearance, this.clear = EdgeInsets.zero, this.twinState});

  final RoomSim sim;
  final TwinAppearance appearance;

  /// The character's state; while the twin just stands around it shows this pose. Null: plain standing.
  final TwinState? twinState;

  /// How much of the screen the UI covers at the top and the bottom.
  final EdgeInsets clear;

  @override
  State<RoomScene> createState() => _RoomSceneState();
}

/// The twin's painted height in each room pose, in standing heights
/// (the prototype's sprite table).
const Map<RoomPose, double> _poseHeight = {
  RoomPose.stand: 1.0,
  RoomPose.wave: 1.0,
  RoomPose.walk: 1.0,
  RoomPose.walkFront: 1.0,
  RoomPose.walkBack: 1.0,
  RoomPose.sit: 0.8,
  RoomPose.eat: 0.8,
  RoomPose.jump: 1.06,
  RoomPose.stretch: 1.1,
  RoomPose.think: 1.0,
  RoomPose.ball: 1.0,
  RoomPose.sleep: 0.72,
  RoomPose.dizzy: 0.98,
};

const Map<RoomPose, TwinPose> _twinPose = {
  RoomPose.stand: TwinPose.stand,
  RoomPose.wave: TwinPose.wave,
  RoomPose.walk: TwinPose.walkSide,
  RoomPose.walkFront: TwinPose.walkFront,
  RoomPose.walkBack: TwinPose.walkBack,
  RoomPose.sit: TwinPose.sit,
  RoomPose.eat: TwinPose.eat,
  RoomPose.jump: TwinPose.jump,
  RoomPose.stretch: TwinPose.stretch,
  RoomPose.think: TwinPose.think,
  RoomPose.ball: TwinPose.holdBall,
  RoomPose.sleep: TwinPose.sleep,
  RoomPose.dizzy: TwinPose.dizzy,
};

/// What the chosen twin can show for a room pose: its own art when it has
/// it, else the closest pose it does have (the human has no front or back
/// walk, eat, stretch, think or sleep art), else standing.
@visibleForTesting
(TwinPose, RoomPose) resolveRoomPose(TwinAppearance look, RoomPose pose) {
  bool has(RoomPose p) => twinHasPose(look.type, look.look, _twinPose[p]!);
  if (has(pose)) return (_twinPose[pose]!, pose);
  final fallback = switch (pose) {
    RoomPose.walkFront || RoomPose.walkBack => RoomPose.walk,
    RoomPose.eat || RoomPose.sleep => RoomPose.sit,
    RoomPose.stretch => RoomPose.wave,
    _ => RoomPose.stand,
  };
  if (has(fallback)) return (_twinPose[fallback]!, fallback);
  return (TwinPose.stand, RoomPose.stand);
}

/// Where the cover-fitted render sits vertically, as a [FittedBox]
/// alignment y: centred, but slid up (within the render's own edges) until
/// the twin at the mat, mid-jump with its shadow, sits above the bottom UI.
/// If it cannot clear both, the bottom wins (the mat is where it moves).
@visibleForTesting
double roomAlignmentY(RoomLayout layout, Size box, EdgeInsets clear) {
  final vp = layout.viewport;
  final s = math.max(box.width / vp.width, box.height / vp.height);
  final spare = box.height - vp.height * s; // <= 0: how much is cropped
  if (spare > -0.5) return 0;
  final mat = layout.spots['exercise']!;
  final proj = layout.projector;
  final matBottom = proj.floorToScreen(mat).dy + 16;
  final matTop = proj.project(mat.dx, layout.bearHeight * 1.1 + 0.15, mat.dy).dy;
  var dy = spare / 2;
  dy = math.max(dy, clear.top - matTop * s);
  dy = math.min(dy, box.height - clear.bottom - matBottom * s);
  dy = dy.clamp(spare, 0.0);
  return 2 * dy / spare - 1;
}

/// The bear's eyes in its standing sprite (`bear/pose/stand.png`, and the
/// same spot in `bear/pose_nohat/stand.png`, which shares its canvas), as
/// fractions of the square sprite box, measured from the v2 art (darkest
/// blobs in the head). Re-measure when that file is swapped for new art.
const _eyes = [Offset(0.4123, 0.2959), Offset(0.6007, 0.2932)];
const _standAssets = {'assets/twin/bear/pose/stand.png', 'assets/twin/bear/pose_nohat/stand.png'};

class _RoomSceneState extends State<RoomScene> {
  late final Ticker _ticker = Ticker(_tick);
  Duration _last = Duration.zero;
  Timer? _rest;

  RoomSim get sim => widget.sim;

  @override
  void initState() {
    super.initState();
    sim.addListener(_onSim);
    _runOrRest();
  }

  @override
  void didUpdateWidget(RoomScene old) {
    super.didUpdateWidget(old);
    if (old.sim != sim) {
      old.sim.removeListener(_onSim);
      sim.addListener(_onSim);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only the visible, current room ticks (the swoosh route keeps it on stage).
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    _ticker.muted = !(TickerMode.valuesOf(context).enabled && current);
  }

  @override
  void dispose() {
    sim.removeListener(_onSim);
    _rest?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onSim() {
    if (!sim.resting) _run();
    if (mounted) setState(() {});
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    sim.step(dt);
    if (sim.resting) _restNow();
  }

  void _runOrRest() => sim.resting ? _restNow() : _run();

  /// Nothing moves: stop ticking until the next wander.
  void _restNow() {
    if (_ticker.isActive) _ticker.stop();
    _rest?.cancel();
    final wait = sim.restFor;
    _rest = Timer(Duration(milliseconds: (wait * 1000).round()), () {
      sim.rested(wait);
      _run();
    });
  }

  void _run() {
    _rest?.cancel();
    _rest = null;
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = sim.layout;
    final vp = layout.viewport;
    return LayoutBuilder(
      builder: (context, box) => ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment(0, roomAlignmentY(layout, box.biggest, widget.clear)),
          child: SizedBox(
            width: vp.width,
            height: vp.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Image.asset(
                    layout.bgAsset,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    semanticLabel: 'A cozy room with a bed, a table, a yoga mat and a shelf with a crystal ball',
                  ),
                ),
                if (sim.ballTaken) _layer(layout.shelfEmpty),
                ..._bowl(layout),
                ..._twin(layout),
                // On the bed, only the quilt edge tucks it in; behind the bed, the whole bed covers it.
                if (sim.inBed)
                  _layer(layout.fgBed)
                else if (layout.covers(layout.footprints['bed']!, sim.pos))
                  _layer(layout.fgBedFull, key: const ValueKey('room-bed-over')),
                // The table layer holds the bowl too: patch it again on top.
                if (layout.covers(layout.footprints['table']!, sim.pos)) ...[
                  _layer(layout.fgTable, key: const ValueKey('room-table-over')),
                  ..._bowl(layout),
                ],
                for (final z in sim.zs) _z(layout, z),
                if (sim.fx.isNotEmpty)
                  Positioned.fill(
                    key: const ValueKey('room-fx'),
                    child: IgnorePointer(child: CustomPaint(painter: _FxPainter(layout, List.of(sim.fx)))),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The fruit bowl while the apple is out (eaten) or popping back in.
  List<Widget> _bowl(RoomLayout layout) {
    final pop = sim.appleScale;
    if (!sim.appleTaken && pop == null) return const [];
    // Scale about the apple's centre, projected from the world.
    final r = layout.bowlApple.rect, a = layout.appleAt;
    final c = layout.projector.project(a.$1, a.$2, a.$3);
    final pivot = Alignment((c.dx - r.left) / r.width * 2 - 1, (c.dy - r.top) / r.height * 2 - 1);
    return [
      _layer(layout.bowlEmpty),
      if (pop != null)
        Positioned.fromRect(
          rect: layout.bowlApple.rect,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Transform.scale(
                key: const ValueKey('room-apple-pop'),
                scale: pop,
                alignment: pivot,
                child: Image.asset(layout.bowlApple.asset, fit: BoxFit.fill, gaplessPlayback: true),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _layer(RoomLayer l, {Key? key}) => Positioned.fromRect(
    key: key,
    rect: l.rect,
    child: IgnorePointer(
      child: ExcludeSemantics(child: Image.asset(l.asset, fit: BoxFit.fill, gaplessPlayback: true)),
    ),
  );

  List<Widget> _twin(RoomLayout layout) {
    final proj = layout.projector;
    final (roomPose, roomShape) = resolveRoomPose(widget.appearance, sim.pose);
    final (twinPose, shape, moodScale) = applyMoodPose(widget.appearance, roomPose, roomShape, widget.twinState);
    final asset = twinAsset(widget.appearance.type, widget.appearance.look, twinPose);
    final size = twinSpriteSize1x[asset] ?? const Size(180, 180);
    final x = sim.pos.dx, z = sim.pos.dy, y = sim.yOff + sim.bob;
    final az = layout.cameraAzimuth;
    // The billboard leans back toward the camera; lying down, it faces it.
    final lean = (shape == RoomPose.sleep ? layout.cameraPitchDeg : layout.leanDeg) * math.pi / 180;
    final h = layout.bearHeight * (_poseHeight[shape] ?? 1) * moodScale;
    final feet = proj.project(x, y, z);
    final head = proj.project(
      x - math.sin(lean) * math.sin(az) * h,
      y + math.cos(lean) * h,
      z - math.sin(lean) * math.cos(az) * h,
    );
    final contentPx = (head - feet).distance;
    // The cut-out sprites have about 3.5% padding top and bottom.
    final imgH = contentPx / 0.93;
    final boxH = size.height >= size.width ? imgH : imgH * size.width / size.height;
    final anchor = twinFeetAnchor(widget.appearance.type, widget.appearance.look, twinPose);
    final feetInBox = boxH - (1 - anchor) * imgH;

    // Blob shadow on the floor (or the quilt), smaller and lighter in the air.
    final air = math.max(0.0, sim.bob + (sim.inBed ? 0 : sim.yOff));
    final floorY = sim.shadowOnBed ? layout.bedTop + 0.065 : 0.012;
    final r = layout.camRight;
    final ppu = proj.scaleAt(x, floorY, z, (r.dx, 0, r.dy));
    final sw =
        (shape == RoomPose.sleep ? 1.05 : (shape == RoomPose.sit || shape == RoomPose.eat ? 0.78 : 0.62)) *
        layout.bearHeight *
        (1 - math.min(0.5, air * 1.4));
    final sp = proj.project(x, floorY, z);
    final shadowW = sw * ppu, shadowH = shadowW * 0.62 * math.sin(layout.cameraPitchDeg * math.pi / 180);
    final shadowA = shape == RoomPose.sleep ? 0.0 : 1 - math.min(0.6, air * 1.6);

    final Widget sprite = TwinSprite(
      appearance: widget.appearance,
      pose: twinPose,
      height: boxH,
      shadow: false,
      hero: true,
      glow: sim.glow,
    );
    // Blinks: eyes painted shut on the standing bear for a moment.
    final blink = sim.blinking && _standAssets.contains(asset);
    return [
      if (shadowA > 0)
        Positioned(
          left: sp.dx - shadowW / 2,
          top: sp.dy - shadowH / 2,
          width: shadowW,
          height: shadowH,
          child: IgnorePointer(
            child: Opacity(
              opacity: shadowA * sim.opacity,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.all(Radius.elliptical(1000, 1000)),
                  gradient: RadialGradient(
                    colors: [Color(0x6B5A3723), Color(0x385A3723), Color(0x005A3723)],
                    stops: [0, 0.6, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
      Positioned(
        key: const ValueKey('room-twin'),
        left: feet.dx - boxH / 2,
        top: feet.dy - feetInBox,
        width: boxH,
        height: boxH,
        child: Semantics(
          button: true,
          // Named, so VoiceOver never meets an unlabelled button.
          label: twinDescription(widget.appearance.type, widget.appearance.look),
          hint: sim.onBed ? 'Tap to wake' : 'Tap to hop, hold for dizzy',
          onTap: sim.tapTwin,
          onLongPress: sim.longPressTwin,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: sim.tapTwin,
            onLongPress: sim.longPressTwin,
            child: Opacity(
              opacity: sim.opacity.clamp(0.0, 1.0),
              child: Transform(
                alignment: FractionalOffset(0.5, feetInBox / boxH),
                transform: Matrix4.identity()
                  ..rotateZ(-sim.tilt)
                  ..scaleByDouble(sim.flip / math.sqrt(sim.sq), sim.sq, 1, 1),
                child: blink
                    ? Stack(
                        children: [
                          sprite,
                          Positioned.fill(
                            key: const ValueKey('room-blink'),
                            child: IgnorePointer(child: CustomPaint(painter: _BlinkPainter())),
                          ),
                        ],
                      )
                    : sprite,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _z(RoomLayout layout, RoomZ z) {
    final p = layout.projector.project(z.x, z.y, z.z);
    final k = z.age / z.life;
    final opacity = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8;
    final size = 18 * (1 + 0.6 * k);
    return Positioned(
      left: p.dx - size / 2,
      top: p.dy - size / 2,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Text(
              'z',
              style: LtText.display(size, color: const Color(0xFF4E63B0)).copyWith(
                shadows: const [
                  Shadow(color: LtColors.paper, blurRadius: 0, offset: Offset(1.5, 1.5)),
                  Shadow(color: LtColors.paper, blurRadius: 0, offset: Offset(-1.5, -1.5)),
                  Shadow(color: LtColors.paper, blurRadius: 0, offset: Offset(1.5, -1.5)),
                  Shadow(color: LtColors.paper, blurRadius: 0, offset: Offset(-1.5, 1.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two eyes painted shut over the standing bear (the prototype's
/// `makeBlink`): a fur patch and a closed-lid arc on each eye.
class _BlinkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final fur = Paint()..color = const Color(0xFFBA7949); // fur around the v2 eyes
    final lid = Paint()
      ..color = const Color(0xFF2E1A12)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.0085;
    for (final e in _eyes) {
      final c = Offset(e.dx * w, e.dy * size.height);
      canvas.drawOval(Rect.fromCenter(center: c, width: w * 0.052, height: w * 0.060), fur);
      final r = w * 0.0185;
      canvas.drawArc(
        Rect.fromCircle(center: c.translate(0, -w * 0.008), radius: r),
        0.25 * math.pi,
        0.5 * math.pi,
        false,
        lid,
      );
    }
  }

  @override
  bool shouldRepaint(_BlinkPainter old) => false;
}

/// The effect particles, projected from the world like the twin: sparkles
/// (a soft glow and a four-point star) and sweat drops. Fade in over the
/// first fifth of their life, out over the rest, with a little pop at birth.
class _FxPainter extends CustomPainter {
  _FxPainter(this.layout, this.fx);
  final RoomLayout layout;
  final List<RoomFx> fx;

  static double _easeBack(double k) {
    const c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * math.pow(k - 1, 3) + c1 * math.pow(k - 1, 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final proj = layout.projector;
    final r = layout.camRight;
    for (final p in fx) {
      final k = (p.age / p.life).clamp(0.0, 1.0);
      final a = (k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8).clamp(0.0, 1.0);
      final c = proj.project(p.x, p.y, p.z);
      final ppu = proj.scaleAt(p.x, p.y, p.z, (r.dx, 0, r.dy));
      final d = p.size * ppu * (k < 0.15 ? _easeBack(k / 0.15) : 1); // sprite size in px
      if (d <= 0.5) continue;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      if (p.kind == RoomFxKind.sparkle) {
        canvas.rotate(p.spin * p.age);
        _sparkle(canvas, d, a);
      } else {
        _drop(canvas, d, a);
      }
      canvas.restore();
    }
  }

  void _sparkle(Canvas canvas, double d, double a) {
    final h = d / 2;
    canvas.drawCircle(
      Offset.zero,
      h,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF8D6).withValues(alpha: a),
            const Color(0xFFFFE696).withValues(alpha: 0.55 * a),
            const Color(0x00FFE696),
          ],
          stops: const [0, 0.25, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: h)),
    );
    final star = Path();
    for (var i = 0; i < 8; i++) {
      final ang = i * math.pi / 4, rr = i.isOdd ? h * 0.14 : h * 0.81;
      final pt = Offset(math.cos(ang) * rr, math.sin(ang) * rr);
      i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = const Color(0xFFFFF4C8).withValues(alpha: a));
  }

  void _drop(Canvas canvas, double d, double a) {
    final u = d / 128; // the prototype's 128 px drop, centred
    final drop = Path()
      ..moveTo(0, -50 * u)
      ..cubicTo(36 * u, -2 * u, 32 * u, 48 * u, 0, 48 * u)
      ..cubicTo(-32 * u, 48 * u, -36 * u, -2 * u, 0, -50 * u)
      ..close();
    canvas.drawPath(
      drop,
      Paint()
        ..color = Colors.white.withValues(alpha: a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 * u,
    );
    canvas.drawPath(drop, Paint()..color = const Color(0xFF8EC5EE).withValues(alpha: a));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-12 * u, 18 * u), width: 16 * u, height: 28 * u),
      Paint()..color = Colors.white.withValues(alpha: 0.85 * a),
    );
  }

  @override
  bool shouldRepaint(_FxPainter old) => true;
}
