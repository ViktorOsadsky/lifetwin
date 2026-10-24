import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'floor_projector.dart';

/// One pre-rendered layer and where it sits in the 390 x 844 render.
@immutable
class RoomLayer {
  const RoomLayer(this.asset, this.rect);
  final String asset;
  final Rect rect;
}

/// Everything the 2D room needs from the 3D prototype: the camera, the
/// walkable floor and the layer images. The values live in
/// `room_layout_data.dart`, generated from `assets/scene/room/room_layers.json`.
@immutable
class RoomLayout {
  const RoomLayout({
    required this.viewport,
    required this.viewProjection,
    required this.cameraAzimuth,
    required this.cameraPitchDeg,
    required this.bearHeight,
    required this.leanDeg,
    required this.sleepY,
    required this.bedTop,
    required this.tableZ,
    required this.shelfBallAt,
    required this.appleAt,
    required this.bounds,
    required this.obstacles,
    required this.waypoints,
    required this.wander,
    required this.spots,
    required this.bgAsset,
    required this.fgBed,
    required this.fgTable,
    required this.shelfEmpty,
    required this.bowlEmpty,
    required this.bowlApple,
  });

  /// Size of the render, in logical px.
  final Size viewport;

  /// three.js `projection * view`, column-major.
  final List<double> viewProjection;
  final double cameraAzimuth;
  final double cameraPitchDeg;

  /// The twin's standing height in world units.
  final double bearHeight;

  /// How far a standing sprite leans back toward the camera.
  final double leanDeg;

  /// Height of the sleeping sprite's baseline on the bed.
  final double sleepY;
  final double bedTop;
  final double tableZ;

  /// World (x, y, z) of the crystal ball on the shelf and of the apple in
  /// the fruit bowl, for the sparkles.
  final (double, double, double) shelfBallAt;
  final (double, double, double) appleAt;

  /// Walkable floor (x, z) and the padded furniture boxes to walk around.
  final Rect bounds;
  final List<Rect> obstacles;

  /// Detour points for [planPath], and idle wander targets.
  final List<Offset> waypoints;
  final List<Offset> wander;

  /// Named floor spots: exercise, eat, sleepSide, bed, fortune, rug.
  final Map<String, Offset> spots;

  final String bgAsset;

  /// Bed pixels in front of a sleeping twin (quilt edge).
  final RoomLayer fgBed;

  /// The table, drawn over a twin standing behind it.
  final RoomLayer fgTable;

  /// The shelf without its crystal ball, shown while the twin holds the ball.
  final RoomLayer shelfEmpty;

  /// The fruit bowl without its apple (a feathered patch), shown while the
  /// twin eats; [bowlApple] then scales the apple back in.
  final RoomLayer bowlEmpty;

  /// The apple alone, cut from the bg, for the refill pop.
  final RoomLayer bowlApple;

  FloorProjector get projector => FloorProjector(viewProjection: viewProjection, viewport: viewport);

  /// Screen right and toward-the-camera on the floor, as (x, z).
  Offset get camRight => Offset(math.cos(cameraAzimuth), -math.sin(cameraAzimuth));
  Offset get camToward => Offset(math.sin(cameraAzimuth), math.cos(cameraAzimuth));

  /// A straight path when it is clear, else through one or two waypoints
  /// (the prototype's `planPath`).
  List<Offset> planPath(Offset a, Offset b) {
    if (_clear(a, b)) return [b];
    List<Offset>? best;
    var bestLen = double.infinity;
    for (final w in waypoints) {
      if (_clear(a, w) && _clear(w, b)) {
        final l = (a - w).distance + (w - b).distance;
        if (l < bestLen) {
          bestLen = l;
          best = [w, b];
        }
      }
    }
    if (best != null) return best;
    for (final w1 in waypoints) {
      for (final w2 in waypoints) {
        if (w1 == w2 || !_clear(a, w1) || !_clear(w1, w2) || !_clear(w2, b)) continue;
        final l = (a - w1).distance + (w1 - w2).distance + (w2 - b).distance;
        if (l < bestLen) {
          bestLen = l;
          best = [w1, w2, b];
        }
      }
    }
    return best ?? [b];
  }

  bool _clear(Offset a, Offset b) => !obstacles.any((box) => _segHitsBox(a, b, box));

  static bool _segHitsBox(Offset a, Offset b, Rect box) {
    var t0 = 0.0, t1 = 1.0;
    final d = [b.dx - a.dx, b.dy - a.dy];
    final p = [a.dx, a.dy];
    final lo = [box.left, box.top], hi = [box.right, box.bottom];
    for (var k = 0; k < 2; k++) {
      if (d[k].abs() < 1e-9) {
        if (p[k] < lo[k] || p[k] > hi[k]) return false;
        continue;
      }
      var u0 = (lo[k] - p[k]) / d[k], u1 = (hi[k] - p[k]) / d[k];
      if (u0 > u1) (u0, u1) = (u1, u0);
      t0 = math.max(t0, u0);
      t1 = math.min(t1, u1);
      if (t0 > t1) return false;
    }
    return true;
  }
}
