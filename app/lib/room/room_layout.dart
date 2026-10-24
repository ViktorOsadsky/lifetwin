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
    required this.shelfBallAt,
    required this.appleAt,
    required this.bounds,
    required this.bearRadius,
    required this.footprints,
    required this.obstacles,
    required this.waypoints,
    required this.wander,
    required this.spots,
    required this.bgAsset,
    required this.fgBed,
    required this.fgBedFull,
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

  /// World (x, y, z) of the crystal ball on the shelf and of the apple in
  /// the fruit bowl, for the sparkles.
  final (double, double, double) shelfBallAt;
  final (double, double, double) appleAt;

  /// Walkable floor (x, z).
  final Rect bounds;

  /// The twin's footprint radius: how far [obstacles] pad [footprints].
  final double bearRadius;

  /// Each piece of floor furniture's true footprint (x, z), from the
  /// prototype's mesh boxes: bed, table, plant, bolster, dumbbellA, dumbbellB.
  final Map<String, Rect> footprints;

  /// [footprints] padded by [bearRadius]: the twin's feet never enter these,
  /// and no path segment crosses them (except the Sleep hop onto the bed).
  final List<Rect> obstacles;

  /// Detour points for [planPath], and idle wander targets.
  final List<Offset> waypoints;
  final List<Offset> wander;

  /// Named floor spots: exercise, eat, sleepSide, bed, fortune, rug.
  final Map<String, Offset> spots;

  final String bgAsset;

  /// Bed pixels in front of a sleeping twin (quilt edge).
  final RoomLayer fgBed;

  /// The whole bed, drawn over a twin standing behind it ([covers]).
  final RoomLayer fgBedFull;

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

  /// Whether the furniture with [footprint] is drawn over a twin standing
  /// at floor point [p]: unless the twin is on the camera's side of one of
  /// the two faces the camera sees (the front, toward +z, and the side
  /// toward the camera's x), the furniture is between it and the camera.
  bool covers(Rect footprint, Offset p) {
    final t = camToward;
    final inFrontX = t.dx >= 0 ? p.dx > footprint.right : p.dx < footprint.left;
    final inFrontZ = t.dy >= 0 ? p.dy > footprint.bottom : p.dy < footprint.top;
    return !(inFrontX || inFrontZ);
  }

  /// [p] is inside a padded furniture box (where the twin's feet never go).
  bool blocked(Offset p) =>
      obstacles.any((o) => p.dx >= o.left && p.dx <= o.right && p.dy >= o.top && p.dy <= o.bottom);

  /// Whether the straight walk from [a] to [b] stays clear of every padded
  /// furniture box.
  bool clear(Offset a, Offset b) => !obstacles.any((box) => _segHitsBox(a, b, box));

  /// The shortest walk from [a] to [b] that never crosses a padded furniture
  /// box: straight when that is clear, else through the waypoints and the
  /// boxes' corners (a visibility graph). Returns the points after [a].
  List<Offset> planPath(Offset a, Offset b) {
    if (clear(a, b)) return [b];
    final nodes = [a, b, ..._detours];
    final dist = List.filled(nodes.length, double.infinity);
    final prev = List.filled(nodes.length, -1);
    final done = List.filled(nodes.length, false);
    dist[0] = 0;
    while (true) {
      var u = -1;
      for (var i = 0; i < nodes.length; i++) {
        if (!done[i] && dist[i].isFinite && (u < 0 || dist[i] < dist[u])) u = i;
      }
      if (u < 0 || u == 1) break;
      done[u] = true;
      for (var v = 0; v < nodes.length; v++) {
        if (done[v] || !clear(nodes[u], nodes[v])) continue;
        final d = dist[u] + (nodes[u] - nodes[v]).distance;
        if (d < dist[v]) {
          dist[v] = d;
          prev[v] = u;
        }
      }
    }
    if (prev[1] < 0) return [b]; // unreachable: only if a or b is inside a box
    final path = <Offset>[];
    for (var i = 1; i != 0; i = prev[i]) {
      path.insert(0, nodes[i]);
    }
    return path;
  }

  /// Detour points: the waypoints, and each padded box's corners pushed a
  /// hair outward, when they are on the walkable floor.
  List<Offset> get _detours {
    const e = 0.02;
    return [
      ...waypoints,
      for (final o in obstacles)
        for (final c in [
          Offset(o.left - e, o.top - e),
          Offset(o.right + e, o.top - e),
          Offset(o.left - e, o.bottom + e),
          Offset(o.right + e, o.bottom + e),
        ])
          if (bounds.contains(c) && !blocked(c)) c,
    ];
  }

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
