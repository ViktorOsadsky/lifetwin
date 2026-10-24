import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'room_layout.dart';

/// The twin's room poses, as in the prototype. [RoomScene] maps them to the
/// chosen twin's sprites (the human lacks some and falls back).
enum RoomPose { stand, wave, walk, walkFront, walkBack, sit, eat, jump, stretch, think, ball, sleep, dizzy }

/// The activity buttons, plus Fortune.
enum RoomAction { exercise, eat, sleep, fortune }

enum _Mode { idle, walk, fade, arrived, act, extra }

/// A floating "z" while the twin sleeps (world position, velocity, age).
class RoomZ {
  RoomZ(this.x, this.y, this.z, this.vx, this.vy, this.vz, this.life);
  double x, y, z;
  final double vx, vy, vz, life;
  double age = 0;
}

enum RoomFxKind { sparkle, drop }

/// A small effect particle (sparkle or sweat drop) in world units: position,
/// velocity, lifetime, world size and spin, as in the prototype's `spawn`.
class RoomFx {
  RoomFx(this.kind, this.x, this.y, this.z, this.vx, this.vy, this.vz, this.life, this.size, {this.spin = 0});
  final RoomFxKind kind;
  double x, y, z;
  final double vx, vy, vz, life, size, spin;
  double age = 0;
}

/// The room's behaviour, ported from the prototype (`design/room3d`): idle
/// wander, walking with direction-picked poses, idle sit or wave, the
/// Exercise / Eat / Sleep / Fortune actions, the tap hop, the long-press
/// dizzy reaction, blinks and the effect particles. Pure state:
/// call [step] with elapsed seconds; [RoomScene] draws it.
class RoomSim extends ChangeNotifier {
  RoomSim({required this.layout, this.reduced = false, math.Random? random})
    : _rng = random ?? math.Random(7),
      pos = const Offset(0.35, 0.3);

  final RoomLayout layout;

  /// Reduced motion: crossfade teleports instead of long walks, shorter
  /// loops, no bob or tilt.
  bool reduced;
  final math.Random _rng;

  /// Called once when the Fortune action has the ball glowing; the screen
  /// then opens the ceremony and calls [fortuneDone] when it returns.
  VoidCallback? onFortune;

  // ---- what the scene draws ---------------------------------------------
  Offset pos; // floor (x, z)
  RoomPose pose = RoomPose.stand;
  int flip = 1;
  double yOff = 0, bob = 0, tilt = 0, sq = 1, opacity = 1, glow = 0;
  String status = 'Hanging out';
  RoomAction? action;
  bool onBed = false;
  bool ballTaken = false;
  final zs = <RoomZ>[];

  /// Sparkles and sweat drops. None are spawned under reduced motion.
  final fx = <RoomFx>[];

  /// The apple is out of the bowl (being eaten).
  bool appleTaken = false;
  double _applePop = -1;

  /// While the apple pops back into the bowl after Eat: its scale (0..~1.1).
  double? get appleScale => _applePop < 0 ? null : math.max(0.01, _easeBack(math.min(1, _applePop / 0.5)));

  /// The standing twin has its eyes shut for a moment.
  bool get blinking => _blinkT > 0 && pose == RoomPose.stand;

  // ---- internal state ------------------------------------------------------
  _Mode _mode = _Mode.idle;
  double idleLeft = 1.2;
  double _extraIn = 9;
  List<Offset> _path = const [];
  VoidCallback? _onArrive;
  double _step = 0;
  double _actT = 0;
  String _phase = '';
  double _hop = -1;
  double _dizzy = -1;
  double _blinkIn = 2.5, _blinkT = 0;
  int _cycle = -1, _bite = -1, _sparkStep = -1;
  double _fade = 0;
  Offset? _fadeTarget;
  RoomAction? _pending;
  double _zIn = 0;
  bool _opened = false;
  String _extra = '';
  double _extraT = 0, _extraDur = 0;
  double _clock = 0;

  /// True while nothing moves: the scene can stop ticking for [restFor] s.
  bool get resting =>
      _mode == _Mode.idle &&
      _hop < 0 &&
      _dizzy < 0 &&
      action == null &&
      zs.isEmpty &&
      fx.isEmpty &&
      _applePop < 0 &&
      _blinkT <= 0 &&
      idleLeft > 0 &&
      _blinkIn > 0;

  /// How long the room can rest: until the next wander or the next blink.
  double get restFor => math.min(idleLeft, _blinkIn);

  /// The bed's foreground layer covers the twin only while it is on the bed.
  bool get inBed => onBed || (action == RoomAction.sleep && (_phase == 'climb' || _phase == 'getup'));

  /// The shadow sits on the quilt while the twin is on the bed.
  bool get shadowOnBed => onBed || (action == RoomAction.sleep && _phase == 'climb' && _actT > 0.3);

  void _setStatus(String s) => status = s;

  // ---- input --------------------------------------------------------------

  /// An activity button. Pressing the running one again ends it (or wakes).
  void press(RoomAction a) {
    if (action == a) {
      if (a == RoomAction.sleep) {
        wake();
      } else {
        _finish('Hanging out');
      }
    } else {
      startAction(a);
    }
    notifyListeners();
  }

  void startAction(RoomAction name) {
    if (onBed) {
      _pending = name == RoomAction.sleep ? null : name;
      wake();
      return;
    }
    if (action == RoomAction.sleep && _phase == 'climb') {
      // Mid-hop onto the bed: land, then get up and go (never walk off
      // through the bed).
      _pending = name == RoomAction.sleep ? null : name;
      return;
    }
    _cancel();
    action = name;
    const go = {
      RoomAction.exercise: 'Off to the mat',
      RoomAction.eat: 'Snack time!',
      RoomAction.sleep: 'Off to bed',
      RoomAction.fortune: 'Off to the shelf',
    };
    final spot = layout.spots[name == RoomAction.sleep ? 'sleepSide' : name.name]!;
    _walkTo(spot, () => _beginAct(), go[name]);
    notifyListeners();
  }

  /// Tap on the twin: a hop with sparkles, or waking up in bed.
  void tapTwin() {
    if (onBed) {
      wake();
    } else if (_hop < 0 && _mode != _Mode.act) {
      _hop = 0;
      _setStatus('Wheee!');
      _burst(_head(), 3);
    }
    notifyListeners();
  }

  /// Long press on the twin: the dizzy pose (the quiz's wrong-answer
  /// reaction, shown as a demo). Game health only, never a prediction.
  void longPressTwin() {
    if (onBed || _mode == _Mode.act) return;
    _dizzy = 0;
    _hop = -1;
    _setStatus('Whoa, dizzy!');
    notifyListeners();
  }

  void wake() {
    if (!onBed || _phase == 'getup') return;
    _phase = 'getup';
    _actT = 0;
    _setStatus('Good morning!');
  }

  /// The ceremony has closed: put the ball back.
  void fortuneDone() {
    if (action == RoomAction.fortune) _finish('Hanging out');
    notifyListeners();
  }

  /// The scene rested for [seconds] without ticking: count that time down
  /// (the next wander, the 8 to 12 s sit or wave, the next blink).
  void rested(double seconds) {
    idleLeft -= seconds;
    _extraIn -= seconds;
    _blinkIn -= seconds;
  }

  // ---- simulation ------------------------------------------------------------

  void _walkTo(Offset pt, VoidCallback? onArrive, [String? say]) {
    final total = (pt - pos).distance;
    _onArrive = onArrive;
    if (say != null) _setStatus(say);
    if (total < 0.05) {
      _mode = _Mode.arrived;
      return;
    }
    if (reduced && total > 0.8) {
      _mode = _Mode.fade;
      _fade = 0;
      _fadeTarget = pt;
      pose = RoomPose.stand;
    } else {
      _mode = _Mode.walk;
      _path = layout.planPath(pos, pt);
    }
  }

  void _beginAct() {
    _mode = _Mode.act;
    _actT = 0;
    _phase = '';
    _opened = false;
    _cycle = _bite = _sparkStep = -1;
  }

  void _cancel() {
    ballTaken = false;
    appleTaken = false;
    glow = 0;
    action = null;
  }

  void _finish(String msg) {
    _cancel();
    _mode = _Mode.idle;
    idleLeft = 2.2;
    pose = RoomPose.stand;
    _setStatus(msg);
  }

  void _chooseWalkPose(double dx, double dz) {
    final r = layout.camRight, t = layout.camToward;
    final sx = dx * r.dx + dz * r.dy;
    final sy = dx * t.dx + dz * t.dy;
    final len = math.sqrt(sx * sx + sy * sy);
    final toward = sy / (len == 0 ? 1 : len);
    const enter = 0.6, stay = 0.45;
    if (toward > (pose == RoomPose.walkFront ? stay : enter)) {
      pose = RoomPose.walkFront;
      flip = 1;
    } else if (toward < -(pose == RoomPose.walkBack ? stay : enter)) {
      pose = RoomPose.walkBack;
      flip = 1;
    } else {
      pose = RoomPose.walk;
      flip = sx < 0 ? -1 : 1;
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static double _easeIO(double k) => k < 0.5 ? 2 * k * k : 1 - math.pow(-2 * k + 2, 2) / 2;
  static double _easeBack(double k) {
    const c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * math.pow(k - 1, 3) + c1 * math.pow(k - 1, 2);
  }

  // ---- effects ----------------------------------------------------------------

  void _spawn(
    RoomFxKind kind,
    (double, double, double) p,
    (double, double, double) v,
    double life,
    double size, {
    double spin = 0,
  }) {
    if (reduced) return;
    fx.add(RoomFx(kind, p.$1, p.$2, p.$3, v.$1, v.$2, v.$3, life, size, spin: spin));
  }

  /// The prototype's `headPos`: above the feet, a little toward the camera.
  (double, double, double) _head() {
    final t = layout.camToward;
    return (pos.dx + t.dx * 0.05, layout.bearHeight * 0.82, pos.dy + t.dy * 0.05);
  }

  /// [n] sparkles fanning out and up from [p].
  void _burst((double, double, double) p, int n) {
    final r = layout.camRight;
    for (var i = 0; i < n; i++) {
      final a = n == 1 ? 0.0 : i / (n - 1) * 2 - 1; // -1 .. 1 across the screen
      _spawn(
        RoomFxKind.sparkle,
        (p.$1 + r.dx * a * 0.28, p.$2 + 0.05 + (1 - a.abs()) * 0.12, p.$3 + r.dy * a * 0.28),
        (r.dx * a * 0.3, 0.35, r.dy * a * 0.3),
        0.7,
        0.15,
        spin: 2,
      );
    }
  }

  /// Where the held ball is, roughly (the ball sits left of the sprite's
  /// centre, about half way up).
  (double, double, double) _ballHeld() {
    final r = layout.camRight, t = layout.camToward;
    return (pos.dx - r.dx * 0.08 * flip + t.dx * 0.04, 0.51 + yOff, pos.dy - r.dy * 0.08 * flip + t.dy * 0.04);
  }

  /// Advances the room by [dt] seconds.
  void step(double dt) {
    dt = math.min(dt, 0.05);
    _clock += dt;
    _blinkIn -= dt;
    // The 8 to 12 s idle flourish counts real time (walks too), not actions.
    if (action == null && _mode != _Mode.extra) _extraIn -= dt;
    tilt = 0;
    bob = 0;
    sq = 1;
    yOff = 0;
    final h = layout.bearHeight;

    if (_mode == _Mode.walk) {
      final tgt = _path.first;
      final dx = tgt.dx - pos.dx, dz = tgt.dy - pos.dy;
      final d = math.sqrt(dx * dx + dz * dz), stepLen = 0.82 * dt;
      if (d <= stepLen) {
        pos = tgt;
        _path = _path.sublist(1);
        if (_path.isEmpty) _mode = _Mode.arrived;
      } else {
        pos = Offset(pos.dx + dx / d * stepLen, pos.dy + dz / d * stepLen);
      }
      if (d > 1e-4) _chooseWalkPose(dx, dz);
      _step += stepLen / 0.26 * math.pi; // one footfall per 0.26 units
      final s = math.sin(_step);
      if (!reduced) {
        tilt = s * 3.5 * math.pi / 180;
        bob = math.cos(_step).abs() * 0.026 * h;
        sq = 1 - 0.028 * math.pow(s.abs(), 6);
      }
    }
    if (_mode == _Mode.fade) {
      _fade += dt;
      final k = _fade / 0.22;
      if (k < 1) {
        opacity = 1 - k;
      } else if (k < 2) {
        if (_fadeTarget != null) {
          pos = _fadeTarget!;
          _fadeTarget = null;
        }
        opacity = k - 1;
      } else {
        opacity = 1;
        _mode = _Mode.arrived;
      }
    }
    if (_mode == _Mode.arrived) {
      _mode = _Mode.idle;
      pose = RoomPose.stand;
      final cb = _onArrive;
      _onArrive = null;
      cb?.call();
    }

    if (_mode == _Mode.idle) {
      if (pose != RoomPose.stand && _hop < 0 && _dizzy < 0) pose = RoomPose.stand;
      idleLeft -= dt;
      if (idleLeft <= 0 && _hop < 0 && _dizzy < 0 && action == null) {
        if (_extraIn <= 0) {
          _extraIn = 8 + _rng.nextDouble() * 4;
          if (_rng.nextDouble() < 0.5) {
            _walkTo(layout.spots['rug']!, () => _startExtra('sit', 4 + _rng.nextDouble() * 2), 'Taking a stroll');
          } else {
            _startExtra('wave', 1.8);
          }
        } else {
          Offset pt;
          do {
            pt = layout.wander[_rng.nextInt(layout.wander.length)];
          } while ((pt - pos).distance < 0.6);
          _walkTo(pt, () {
            idleLeft = 1.6 + _rng.nextDouble() * 2.4;
            _setStatus('Hanging out');
          }, 'Taking a stroll');
        }
      }
    }

    if (_mode == _Mode.extra) {
      _extraT += dt;
      if (_extra == 'wave' && !reduced) tilt = math.sin(_extraT * 9) * 0.05;
      if (_extraT >= (reduced ? _extraDur * 0.6 : _extraDur)) {
        _mode = _Mode.idle;
        idleLeft = 1.5;
        pose = RoomPose.stand;
        _setStatus('Hanging out');
      }
    }

    if (_mode == _Mode.act) _act(dt, h);

    if (_hop >= 0) {
      _hop += dt;
      final k = _hop / 0.6;
      pose = RoomPose.jump;
      if (k < 0.15) {
        sq = 1 - 0.08 * (k / 0.15);
      } else if (k < 0.85) {
        final a = (k - 0.15) / 0.7;
        yOff += math.sin(a * math.pi) * (reduced ? 0.06 : 0.22);
        sq = 1 + 0.05 * math.sin(a * math.pi);
      } else {
        sq = 1 - 0.05 * math.sin((k - 0.85) / 0.15 * math.pi);
      }
      if (k >= 1) {
        _hop = -1;
        pose = RoomPose.stand;
        if (_mode == _Mode.idle) _setStatus('Hanging out');
      }
    }
    if (_dizzy >= 0) {
      _dizzy += dt;
      pose = RoomPose.dizzy;
      tilt = math.sin(_dizzy * 7) * 0.12 * (1 - _dizzy / 2.2);
      if (_dizzy >= 2.2) {
        _dizzy = -1;
        pose = RoomPose.stand;
        _setStatus('All better');
      }
    }
    if (_applePop >= 0) {
      _applePop += dt;
      if (_applePop >= 0.5) _applePop = -1;
    }
    if (_blinkIn <= 0) {
      _blinkT = 0.13;
      _blinkIn = 2.5 + _rng.nextDouble() * 3;
    } else if (_blinkT > 0) {
      _blinkT -= dt;
    }
    if (reduced) {
      sq = 1;
      tilt = 0;
    }

    for (final z in zs) {
      z.age += dt;
      z.x += z.vx * dt;
      z.y += z.vy * dt;
      z.z += z.vz * dt;
    }
    zs.removeWhere((z) => z.age >= z.life);
    for (final p in fx) {
      p.age += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.z += p.vz * dt;
    }
    fx.removeWhere((p) => p.age >= p.life);
    notifyListeners();
  }

  void _startExtra(String kind, double dur) {
    _mode = _Mode.extra;
    _extra = kind;
    _extraT = 0;
    _extraDur = dur;
    pose = kind == 'sit' ? RoomPose.sit : RoomPose.wave;
    _setStatus(kind == 'sit' ? 'Sitting on the rug' : 'Hi there!');
  }

  void _act(double dt, double h) {
    _actT += dt;
    final t = _actT;
    switch (action) {
      case RoomAction.exercise:
        final dur = reduced ? 2.0 : 4.2;
        const p = 0.9;
        if (t < dur) {
          final u = (t % p) / p;
          final up = u >= 0.5;
          pose = up ? RoomPose.jump : RoomPose.stretch;
          _setStatus('Jumping jacks!');
          if (up) {
            final k = (u - 0.5) / 0.5;
            yOff = math.sin(k * math.pi) * 0.13;
            sq = 1 + 0.05 * math.sin(k * math.pi);
          } else {
            sq = 1 - 0.07 * math.sin(u / 0.5 * math.pi);
          }
          final cyc = (t / p).floor();
          if (cyc != _cycle) {
            // A sweat drop off one side, a sparkle off the other, each rep.
            _cycle = cyc;
            final hp = _head(), r = layout.camRight;
            _spawn(
              RoomFxKind.drop,
              (hp.$1 + r.dx * 0.28, hp.$2 + 0.02, hp.$3 + r.dy * 0.28),
              (r.dx * 0.25, 0.35, r.dy * 0.25),
              0.9,
              0.11,
            );
            _spawn(
              RoomFxKind.sparkle,
              (hp.$1 - r.dx * 0.3, hp.$2 + 0.12, hp.$3 - r.dy * 0.3),
              (0, 0.3, 0),
              0.9,
              0.2,
              spin: 2,
            );
          }
        } else if (t < dur + 1.2) {
          pose = RoomPose.wave;
          _setStatus('Great workout!');
          tilt = math.sin(t * 9) * 0.04;
        } else {
          _finish('Feeling strong');
        }
      case RoomAction.eat:
        final dur = reduced ? 2.2 : 4.4;
        if (t < 0.25) {
          pose = RoomPose.stand;
        } else if (t < dur) {
          if (!appleTaken) {
            // The apple leaves the bowl with a sparkle.
            appleTaken = true;
            final a = layout.appleAt;
            _spawn(RoomFxKind.sparkle, (a.$1, a.$2 + 0.1, a.$3), (0, 0.3, 0), 0.6, 0.18);
          }
          pose = RoomPose.eat;
          _setStatus('Crunch, crunch!');
          sq = 1 + 0.025 * math.sin((t * 2.2) % 1 * math.pi * 2);
          tilt = math.sin(t * 4.4) * 0.025;
          final bite = (t * 1.1).floor();
          if (bite != _bite) {
            // Crumb sparkles at the mouth.
            _bite = bite;
            final hp = _head(), r = layout.camRight;
            _spawn(
              RoomFxKind.sparkle,
              (hp.$1 + r.dx * 0.18, hp.$2 - 0.12, hp.$3 + r.dy * 0.18),
              (r.dx * 0.2, 0.25, r.dy * 0.2),
              0.7,
              0.12,
              spin: 3,
            );
          }
        } else if (t < dur + 1.0) {
          if (pose != RoomPose.jump) _burst(_head(), 3);
          pose = RoomPose.jump;
          _setStatus('Yum!');
          yOff = math.sin(math.min(1, (t - dur) * 1.6) * math.pi) * 0.08;
        } else {
          _finish('Full and happy');
          // The apple pops back into the bowl (at once under reduced motion).
          if (!reduced) _applePop = 0;
        }
      case RoomAction.sleep:
        final side = layout.spots['sleepSide']!, top = layout.spots['bed']!;
        if (_phase == '') {
          _phase = 'climb';
          _actT = 0;
        }
        if (_phase == 'climb') {
          final k = math.min(1.0, _actT / (reduced ? 0.01 : 0.6)), e = _easeIO(k);
          pos = Offset(_lerp(side.dx, top.dx, e), _lerp(side.dy, top.dy, e));
          yOff = _lerp(0, layout.sleepY, e) + math.sin(k * math.pi) * 0.35;
          pose = k < 0.6 ? RoomPose.jump : RoomPose.sleep;
          if (k >= 1) {
            _phase = 'sleep';
            _actT = 0;
            onBed = true;
            _zIn = 0;
            if (_pending != null) wake();
          }
        }
        if (_phase == 'sleep') {
          pose = RoomPose.sleep;
          _setStatus('Sleeping. Tap to wake');
          yOff = layout.sleepY;
          sq = 1 + math.sin(_actT * 1.4) * 0.015;
          _zIn -= dt;
          if (_zIn <= 0) {
            _zIn = reduced ? 2.4 : 1.1;
            final r = layout.camRight;
            zs.add(
              RoomZ(
                pos.dx - r.dx * 0.3,
                layout.bedTop + 0.55,
                pos.dy - r.dy * 0.3,
                r.dx * 0.12 + 0.02,
                0.32,
                r.dy * 0.12,
                reduced ? 1.6 : 2.4,
              ),
            );
          }
        }
        if (_phase == 'getup') {
          final k = math.min(1.0, _actT / (reduced ? 0.01 : 0.55)), e = _easeIO(k);
          pos = Offset(_lerp(top.dx, side.dx, e), _lerp(top.dy, side.dy, e));
          yOff = _lerp(layout.sleepY, 0, e) + math.sin(k * math.pi) * 0.3;
          pose = RoomPose.jump;
          if (k >= 1) {
            onBed = false;
            _finish('Good morning!');
            final p = _pending;
            _pending = null;
            if (p != null) startAction(p);
          }
        }
      case RoomAction.fortune:
        final pulse = reduced ? 0.6 : 0.9, t0 = reduced ? 0.4 : 0.9;
        if (t < t0) {
          pose = RoomPose.think;
          _setStatus('Hmm, let me see');
          tilt = math.sin(t * 3) * 0.02;
        } else {
          if (!ballTaken) {
            // The ball leaves the shelf with a sparkle.
            final b = layout.shelfBallAt;
            _spawn(RoomFxKind.sparkle, b, (0, -0.2, 0), 0.6, 0.25);
          }
          pose = RoomPose.ball;
          ballTaken = true;
          final k = (t - t0) / pulse;
          // Two glow pulses, then a soft steady glow; steady under reduced motion.
          glow = reduced ? 0.5 : (k < 2 ? math.pow(math.sin(k * math.pi), 2).toDouble() : 0.35);
          _setStatus(k < 2 ? 'The ball glows!' : 'Your look ahead');
          sq = 1 + 0.02 * glow;
          final sp = (k * 3).floor();
          if (k < 2 && sp != _sparkStep) {
            _sparkStep = sp;
            final bp = _ballHeld(), r = layout.camRight, j = (_rng.nextDouble() - 0.5) * 0.3;
            _spawn(
              RoomFxKind.sparkle,
              (bp.$1 + r.dx * j, bp.$2 + 0.1, bp.$3 + r.dy * j),
              (0, 0.25, 0),
              0.8,
              0.16,
              spin: 2,
            );
          }
          if (k >= 2.2 && !_opened) {
            _opened = true;
            onFortune?.call();
          }
        }
      case null:
        break;
    }
  }

  /// Seconds since the sim started (for the scene's idle flourishes).
  double get clock => _clock;
}
