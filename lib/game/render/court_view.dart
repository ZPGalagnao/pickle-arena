import 'dart:math' as math;
import 'dart:ui';

/// Pinhole camera behind the local player's baseline, looking down the court.
/// When [flip] is true the world is rotated 180 degrees so the local player
/// (on the far half in world coordinates) still appears at the bottom.
class CourtView {
  static const double camY = -11.5;
  static const double camZ = 13.5;
  static const double pitch = 50 * math.pi / 180;
  static final double _cos = math.cos(pitch);
  static final double _sin = math.sin(pitch);

  final bool flip;
  double _scale = 1, _ox = 0, _oy = 0;
  Size _size = Size.zero;

  CourtView({this.flip = false});

  Size get size => _size;

  (double, double, double) _raw(double x, double y, double z) {
    final dy = y - camY, dz = z - camZ;
    final depth = dy * _cos - dz * _sin;
    final up = dy * _sin + dz * _cos;
    return (x / depth, -up / depth, depth);
  }

  /// Fit the court (with its surroundings) inside [size], leaving [top] and
  /// [bottom] pixels free for HUD and controls.
  void layout(Size size, {double top = 90, double bottom = 150, double side = 6}) {
    if (size == _size) return;
    _size = size;
    final pts = [
      _raw(-4.1, -8.9, 0), _raw(4.1, -8.9, 0), _raw(-4.1, 8.9, 0),
      _raw(4.1, 8.9, 0), _raw(0, 8.9, 2.6),
    ];
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.$1);
      maxX = math.max(maxX, p.$1);
      minY = math.min(minY, p.$2);
      maxY = math.max(maxY, p.$2);
    }
    final availW = size.width - side * 2;
    final availH = math.max(100.0, size.height - top - bottom);
    _scale = math.min(availW / (maxX - minX), availH / (maxY - minY));
    _ox = size.width / 2 - (minX + maxX) / 2 * _scale;
    final usedH = (maxY - minY) * _scale;
    _oy = top + (availH - usedH) / 2 - minY * _scale;
  }

  Offset project(double x, double y, double z) {
    if (flip) {
      x = -x;
      y = -y;
    }
    final (sx, sy, _) = _raw(x, y, z);
    return Offset(_ox + sx * _scale, _oy + sy * _scale);
  }

  /// Screen pixels per metre at a world point.
  double pxPerMeter(double x, double y, double z) {
    if (flip) y = -y;
    final dy = y - camY, dz = z - camZ;
    final depth = dy * _cos - dz * _sin;
    return _scale / depth;
  }

  /// Larger = farther from the camera (for painter's-algorithm sorting).
  double depthKey(double y) => flip ? -y : y;
}
