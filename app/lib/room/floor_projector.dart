import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// World → screen for the pre-rendered room, using the camera the layers
/// were rendered with. This is the only place that knows about the camera,
/// so a different room layer (for example a Flame scene) only has to supply
/// its own projector.
///
/// World units: x right, y up, z toward the viewer; the floor is y = 0.
/// Floor points are `Offset(x, z)`. Screen points are logical px of the
/// render's [viewport].
@immutable
class FloorProjector {
  const FloorProjector({required this.viewProjection, required this.viewport}) : assert(viewProjection.length == 16);

  /// three.js `projection * view`, column-major.
  final List<double> viewProjection;
  final Size viewport;

  double _e(int row, int col) => viewProjection[col * 4 + row];

  /// Any world point to the screen.
  Offset project(double x, double y, double z) {
    final cx = _e(0, 0) * x + _e(0, 1) * y + _e(0, 2) * z + _e(0, 3);
    final cy = _e(1, 0) * x + _e(1, 1) * y + _e(1, 2) * z + _e(1, 3);
    final cw = _e(3, 0) * x + _e(3, 1) * y + _e(3, 2) * z + _e(3, 3);
    return Offset((cx / cw + 1) / 2 * viewport.width, (1 - cy / cw) / 2 * viewport.height);
  }

  /// A floor point (x, z) to the screen: the floor homography.
  Offset floorToScreen(Offset floor) => project(floor.dx, 0, floor.dy);

  /// A screen point back to the floor (x, z): the inverse homography.
  Offset screenToFloor(Offset screen) {
    final u = 2 * screen.dx / viewport.width - 1;
    final v = 1 - 2 * screen.dy / viewport.height;
    // (row0 - u*row3) . (x, z, 1) = 0 and (row1 - v*row3) . (x, z, 1) = 0
    final a1 = _e(0, 0) - u * _e(3, 0), b1 = _e(0, 2) - u * _e(3, 2), c1 = _e(0, 3) - u * _e(3, 3);
    final a2 = _e(1, 0) - v * _e(3, 0), b2 = _e(1, 2) - v * _e(3, 2), c2 = _e(1, 3) - v * _e(3, 3);
    final det = a1 * b2 - a2 * b1;
    return Offset((-c1 * b2 + c2 * b1) / det, (-a1 * c2 + a2 * c1) / det);
  }

  /// Screen px per world unit along [dir] (a world direction) at a point:
  /// used to size sprites and shadows by depth.
  double scaleAt(double x, double y, double z, (double, double, double) dir) {
    final a = project(x, y, z);
    final b = project(x + dir.$1, y + dir.$2, z + dir.$3);
    return (b - a).distance;
  }
}
