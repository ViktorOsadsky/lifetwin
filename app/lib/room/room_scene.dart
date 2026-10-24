import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/twin_sprite.dart';
import 'room_layout.dart';
import 'room_sim.dart';

/// The room, as three pre-rendered layers with the twin between them:
/// `room_bg`, then the twin sprite (placed and sized by the [FloorProjector]
/// of [RoomLayout], with a blob shadow), then the foreground pieces that
/// cover it (the quilt edge while it sleeps, the table when it stands
/// behind it). Everything is laid out in the 390 x 844 render and
/// cover-fitted to the screen.
///
/// Swap point: a future room engine (for example Flame) replaces this widget
/// and its projector; [RoomSim] and the screen around it stay the same.
class RoomScene extends StatefulWidget {
  const RoomScene({super.key, required this.sim, required this.appearance});

  final RoomSim sim;
  final TwinAppearance appearance;

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
    _rest = Timer(Duration(milliseconds: (sim.idleLeft * 1000).round()), () {
      sim.endRest();
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
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
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
              ..._twin(layout),
              if (sim.inBed) _layer(layout.fgBed),
              if (sim.pos.dy < layout.tableZ - 0.2) _layer(layout.fgTable),
              for (final z in sim.zs) _z(layout, z),
            ],
          ),
        ),
      ),
    );
  }

  Widget _layer(RoomLayer l) => Positioned.fromRect(
    rect: l.rect,
    child: IgnorePointer(
      child: ExcludeSemantics(child: Image.asset(l.asset, fit: BoxFit.fill, gaplessPlayback: true)),
    ),
  );

  List<Widget> _twin(RoomLayout layout) {
    final proj = layout.projector;
    final (twinPose, shape) = resolveRoomPose(widget.appearance, sim.pose);
    final asset = twinAsset(widget.appearance.type, widget.appearance.look, twinPose);
    final size = twinSpriteSize1x[asset] ?? const Size(180, 180);
    final x = sim.pos.dx, z = sim.pos.dy, y = sim.yOff + sim.bob;
    final az = layout.cameraAzimuth;
    // The billboard leans back toward the camera; lying down, it faces it.
    final lean = (shape == RoomPose.sleep ? layout.cameraPitchDeg : layout.leanDeg) * math.pi / 180;
    final h = layout.bearHeight * (_poseHeight[shape] ?? 1);
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

    final sprite = TwinSprite(
      appearance: widget.appearance,
      pose: twinPose,
      height: boxH,
      shadow: false,
      hero: true,
      glow: sim.glow,
    );
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
          hint: sim.onBed ? 'Tap to wake' : 'Tap to hop',
          onTap: sim.tapTwin,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: sim.tapTwin,
            child: Opacity(
              opacity: sim.opacity.clamp(0.0, 1.0),
              child: Transform(
                alignment: FractionalOffset(0.5, feetInBox / boxH),
                transform: Matrix4.identity()
                  ..rotateZ(-sim.tilt)
                  ..scaleByDouble(sim.flip / math.sqrt(sim.sq), sim.sq, 1, 1),
                child: sprite,
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
