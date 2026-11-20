import 'dart:math' as math;
import 'dart:ui';

/// Broadcast-style camera behind the local player's baseline (landscape).
/// A low, distant camera keeps the court and the players big on screen.
/// When [flip] is true the world is rotated 180 degrees so the local player
/// (on the far half in world coordinates) still appears at the bottom.
/// [zoom] / [focusX] / [focusY] push the camera in on a point; the painter
/// applies it once as a canvas transform (see [applyZoom]).
class CourtView {
  static const double camY = -24.0;
  static const double camZ = 7.8;
  static const double pitch = 15 * math.pi / 180;
  static final double _cos = math.cos(pitch);
  static final double _sin = math.sin(pitch);

  final bool flip;
  double _scale = 1, _ox = 0, _oy = 0;
  Size _size = Size.zero;
  double zoom = 1;
  double focusX = 0, focusY = 0, focusZ = 1;

  CourtView({this.flip = false});

  Size get size => _size;

  /// Changes whenever the layout changes (used to invalidate cached layers).
  int get layoutKey => Object.hash(_size, flip, _scale);

  (double, double, double) _raw(double x, double y, double z) {
    final dy = y - camY, dz = z - camZ;
    final depth = dy * _cos - dz * _sin;
    final up = dy * _sin + dz * _cos;
    return (x / depth, -up / depth, depth);
  }

  /// Fit the playing area inside [size], leaving room for the HUD.
  void layout(Size size, {double top = 10, double bottom = 0, double side = 0}) {
    if (size == _size) return;
    _size = size;
    // near players' feet ... far players' heads (characters are drawn
    // bigger than life, so the far head goes up to ~3.4 m)
    final pts = [
      _raw(-3.3, -7.4, 0), _raw(3.3, -7.4, 0), _raw(-3.3, 7.6, 0), _raw(3.3, 7.6, 0), _raw(0, 7.1, 3.2),
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

  Offset _base(double x, double y, double z, bool flipped) {
    if (flipped) {
      x = -x;
      y = -y;
    }
    final (sx, sy, _) = _raw(x, y, z);
    return Offset(_ox + sx * _scale, _oy + sy * _scale);
  }

  /// World point -> screen (before zoom).
  Offset project(double x, double y, double z) => _base(x, y, z, flip);

  /// Point given in view space (+y = away from the camera) -> screen.
  Offset projectView(double x, double y, double z) => _base(x, y, z, false);

  /// Screen pixels per metre at a world point (before zoom).
  double pxPerMeter(double x, double y, double z) => pxPerMeterView(x, flip ? -y : y, z);

  double pxPerMeterView(double x, double y, double z) {
    final dy = y - camY, dz = z - camZ;
    final depth = dy * _cos - dz * _sin;
    return _scale / depth;
  }

  /// Larger = farther from the camera (for painter's-algorithm sorting).
  double depthKey(double y) => flip ? -y : y;

  /// Apply the victory push-in as one canvas transform.
  void applyZoom(Canvas canvas) {
    if (zoom == 1) return;
    final f = _base(focusX, focusY, focusZ, flip);
    final c = Offset(_size.width / 2, _size.height * 0.55);
    canvas.translate(c.dx, c.dy);
    canvas.scale(zoom);
    canvas.translate(-f.dx, -f.dy);
  }
}
