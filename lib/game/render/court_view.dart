import 'dart:math' as math;
import 'dart:ui';

/// Broadcast-style camera behind the local player's baseline (landscape).
/// When [flip] is true the world is rotated 180 degrees so the local player
/// (on the far half in world coordinates) still appears at the bottom.
/// [zoom] / [focusX] / [focusY] push the camera in on a point (victory shot).
class CourtView {
  static const double camY = -21.0;
  static const double camZ = 10.5;
  static const double pitch = 25 * math.pi / 180;
  static final double _cos = math.cos(pitch);
  static final double _sin = math.sin(pitch);

  final bool flip;
  double _scale = 1, _ox = 0, _oy = 0;
  Size _size = Size.zero;
  Rect _area = Rect.zero;
  double zoom = 1;
  double focusX = 0, focusY = 0, focusZ = 1;

  CourtView({this.flip = false});

  Size get size => _size;
  Rect get area => _area;

  (double, double, double) _raw(double x, double y, double z) {
    final dy = y - camY, dz = z - camZ;
    final depth = dy * _cos - dz * _sin;
    final up = dy * _sin + dz * _cos;
    return (x / depth, -up / depth, depth);
  }

  /// Fit the court (with its surroundings) inside [size], leaving room for
  /// the HUD and the side controls.
  void layout(Size size, {double top = 54, double bottom = 6, double side = 6}) {
    if (size == _size) return;
    _size = size;
    final pts = [
      _raw(-4.0, -8.2, 0), _raw(4.0, -8.2, 0), _raw(-4.0, 8.4, 0),
      _raw(4.0, 8.4, 0), _raw(0, 8.0, 2.3),
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
    _area = Rect.fromLTWH(_ox + minX * _scale, _oy + minY * _scale, (maxX - minX) * _scale, usedH);
  }

  Offset _base(double x, double y, double z, bool flipped) {
    if (flipped) {
      x = -x;
      y = -y;
    }
    final (sx, sy, _) = _raw(x, y, z);
    return Offset(_ox + sx * _scale, _oy + sy * _scale);
  }

  Offset _zoomed(Offset p) {
    if (zoom == 1) return p;
    final f = _base(focusX, focusY, focusZ, flip);
    final c = Offset(_size.width / 2, _size.height * 0.55);
    return c + (p - f) * zoom;
  }

  /// World point -> screen.
  Offset project(double x, double y, double z) => _zoomed(_base(x, y, z, flip));

  /// Point given in view space (+y = away from the camera) -> screen.
  Offset projectView(double x, double y, double z) => _zoomed(_base(x, y, z, false));

  /// Screen pixels per metre at a world point.
  double pxPerMeter(double x, double y, double z) => pxPerMeterView(x, flip ? -y : y, z);

  double pxPerMeterView(double x, double y, double z) {
    final dy = y - camY, dz = z - camZ;
    final depth = dy * _cos - dz * _sin;
    return _scale / depth * zoom;
  }

  /// Larger = farther from the camera (for painter's-algorithm sorting).
  double depthKey(double y) => flip ? -y : y;
}
