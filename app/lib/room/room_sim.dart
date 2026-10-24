import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'room_layout.dart';

/// The twin's room poses, as in the prototype. [RoomScene] maps them to the
/// chosen twin's sprites (the human lacks some and falls back).
enum RoomPose { stand, wave, walk, walkFront, walkBack, sit, eat, jump, stretch, think, ball, sleep }

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

/// The room's behaviour, ported from the prototype (`design/room3d`): idle
/// wander, walking with direction-picked poses, idle sit or wave, the
/// Exercise / Eat / Sleep / Fortune actions and the tap hop. Pure state:
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
  double _fade = 0;
  Offset? _fadeTarget;
  RoomAction? _pending;
  double _zIn = 0;
  bool _opened = false;
  String _extra = '';
  double _extraT = 0, _extraDur = 0;
  double _clock = 0;

  /// True while nothing moves: the scene can stop ticking for [idleLeft] s.
  bool get resting => _mode == _Mode.idle && _hop < 0 && action == null && zs.isEmpty && idleLeft > 0;

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

  /// Tap on the twin: a hop, or waking up in bed.
  void tapTwin() {
    if (onBed) {
      wake();
    } else if (_hop < 0 && _mode != _Mode.act) {
      _hop = 0;
      _setStatus('Wheee!');
    }
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

  /// Ends the rest early (the scene's timer calls this).
  void endRest() {
    idleLeft = 0;
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
  }

  void _cancel() {
    ballTaken = false;
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

  /// Advances the room by [dt] seconds.
  void step(double dt) {
    dt = math.min(dt, 0.05);
    _clock += dt;
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
      if (pose != RoomPose.stand && _hop < 0) pose = RoomPose.stand;
      idleLeft -= dt;
      _extraIn -= dt;
      if (idleLeft <= 0 && _hop < 0 && action == null) {
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
          pose = RoomPose.eat;
          _setStatus('Crunch, crunch!');
          sq = 1 + 0.025 * math.sin((t * 2.2) % 1 * math.pi * 2);
          tilt = math.sin(t * 4.4) * 0.025;
        } else if (t < dur + 1.0) {
          pose = RoomPose.jump;
          _setStatus('Yum!');
          yOff = math.sin(math.min(1, (t - dur) * 1.6) * math.pi) * 0.08;
        } else {
          _finish('Full and happy');
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
          pose = RoomPose.ball;
          ballTaken = true;
          final k = (t - t0) / pulse;
          glow = k < 1 ? math.pow(math.sin(k * math.pi), 2).toDouble() : 0.35;
          _setStatus(k < 1 ? 'The ball glows!' : 'Your look ahead');
          sq = 1 + 0.02 * glow;
          if (k >= 1 && !_opened) {
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
