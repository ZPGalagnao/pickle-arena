import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../physics.dart';
import 'court_view.dart';

class _Fan {
  final double x, y, z; // view space (metres)
  final int shirt, skin; // ARGB
  final double phase, eagerness;
  final int sign; // 0 = none, else a colored sign
  _Fan(this.x, this.y, this.z, this.shirt, this.skin, this.phase, this.eagerness, this.sign);
}

/// Draws the arena. Everything that never moves (sky, stands, court, lines,
/// net) is painted once into cached images by the game painter; the crowd is
/// drawn every frame as ONE batched triangle mesh.
class CourtPainter {
  static const _apron = Color(0xFF1E7A52);
  static const _apronDark = Color(0xFF155C3D);
  static const _court = Color(0xFF2B6CB5);
  static const _kitchen = Color(0xFF3B87D3);
  static const _line = Color(0xFFF7F9FC);

  static List<_Fan>? _fans;

  // tiered side stands: row k spans x = _standX + k*_rowW .. +_rowW at height (k+1)*_rowH
  static const double _standX = 8.3, _rowW = 0.85, _rowH = 0.42;
  static const int _rows = 7;
  static const double _standY0 = -12, _standY1 = 12;
  static const double _backY = 12.4; // back stand starts here (rows run away from the court)

  /// A small crowd sitting on random seats (most seats stay empty).
  static List<_Fan> _crowd() {
    if (_fans != null) return _fans!;
    final r = math.Random(11);
    const shirts = [
      0xFFE53935, 0xFF1E88E5, 0xFFFDD835, 0xFF43A047, 0xFFFFFFFF, 0xFFFF7A3D, 0xFF8E24AA, 0xFF00ACC1,
      0xFFD4F33A, 0xFF37474F,
    ];
    const skins = [0xFFFFE0BD, 0xFFF1C27D, 0xFFE0AC69, 0xFFC68642, 0xFF8D5524];
    final fans = <_Fan>[];
    int dim(int c, double k) => Color.lerp(Color(c), const Color(0xFF0E2140), k)!.toARGB32();
    _Fan make(double x, double y, double z) => _Fan(x, y, z, dim(shirts[r.nextInt(shirts.length)], 0.2),
        dim(skins[r.nextInt(skins.length)], 0.1), r.nextDouble() * math.pi * 2, r.nextDouble(),
        r.nextDouble() < 0.14 ? 1 + r.nextInt(4) : 0);
    for (final side in [-1.0, 1.0]) {
      for (var k = 0; k < _rows; k++) {
        for (var y = _standY0 + 0.5; y < _standY1; y += 0.62) {
          // fuller near the middle of the court, emptier at the ends
          final p = 0.3 * (1 - (y.abs() / 12).clamp(0.0, 1.0)) + 0.04;
          if (r.nextDouble() < p) fans.add(make(side * (_standX + (k + 0.55) * _rowW), y, (k + 1) * _rowH));
        }
      }
    }
    for (var k = 0; k < 4; k++) {
      for (var x = -7.0; x <= 7.0; x += 0.62) {
        if (r.nextDouble() < 0.18) fans.add(make(x, _backY + (k + 0.55) * _rowW, (k + 1) * _rowH));
      }
    }
    // farthest from the (high) camera first
    double depth(_Fan f) =>
        (f.y - CourtView.camY) * math.cos(CourtView.pitch) - (f.z - CourtView.camZ) * math.sin(CourtView.pitch);
    fans.sort((a, b) => depth(b).compareTo(depth(a)));
    return _fans = fans;
  }

  static Path _quad(CourtView v, double x0, double y0, double x1, double y1, [double z = 0]) {
    final a = v.project(x0, y0, z);
    final b = v.project(x1, y0, z);
    final c = v.project(x1, y1, z);
    final d = v.project(x0, y1, z);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
  }

  static Path _viewPoly(CourtView v, List<List<double>> pts) {
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = v.projectView(pts[i][0], pts[i][1], pts[i][2]);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    return path..close();
  }

  /// Floor, stands, boards, apron, court and lines (cached by the painter).
  static void paintStatic(Canvas canvas, Size size, CourtView v) {
    // arena floor (with a margin so screen-shake never shows an edge)
    canvas.drawRect(
      const Offset(-40, -40) & Size(size.width + 80, size.height + 80),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height),
            const [Color(0xFF0A1730), Color(0xFF112646), Color(0xFF0D1F3B)], const [0, 0.5, 1]),
    );
    canvas.drawPath(_viewPoly(v, [[-30, -16, 0], [30, -16, 0], [30, 16, 0], [-30, 16, 0]]),
        Paint()..color = const Color(0xFF15304F));

    // side stands, outermost row first
    for (final sd in [-1.0, 1.0]) {
      for (var k = _rows - 1; k >= 0; k--) {
        final x0 = sd * (_standX + k * _rowW), x1 = sd * (_standX + (k + 1) * _rowW);
        final z0 = k * _rowH, z1 = (k + 1) * _rowH;
        // riser (faces the court) then tread
        canvas.drawPath(_viewPoly(v, [[x0, _standY0, z0], [x0, _standY1, z0], [x0, _standY1, z1], [x0, _standY0, z1]]),
            Paint()..color = const Color(0xFF0C1C36));
        canvas.drawPath(_viewPoly(v, [[x0, _standY0, z1], [x0, _standY1, z1], [x1, _standY1, z1], [x1, _standY0, z1]]),
            Paint()..color = k.isEven ? const Color(0xFF1B3A63) : const Color(0xFF183457));
        // seats
        final seat = Paint()..color = k.isEven ? const Color(0xFF2A5185) : const Color(0xFF26497A);
        for (var y = _standY0 + 0.5; y < _standY1; y += 0.62) {
          final xs = x0 + sd * 0.12, xe = x0 + sd * 0.5;
          canvas.drawPath(_viewPoly(v, [[xs, y, z1 + 0.01], [xs, y + 0.42, z1 + 0.01], [xe, y + 0.42, z1 + 0.01], [xe, y, z1 + 0.01]]),
              seat);
        }
      }
      // stand end walls / top rail
      final xo = sd * (_standX + _rows * _rowW);
      canvas.drawPath(
          _viewPoly(v, [[xo, _standY0, _rows * _rowH], [xo, _standY1, _rows * _rowH], [xo + sd * 6, _standY1, _rows * _rowH + 1.5], [xo + sd * 6, _standY0, _rows * _rowH + 1.5]]),
          Paint()..color = const Color(0xFF0B1A31));
    }
    // back stand (mostly above the top of the screen)
    for (var k = 3; k >= 0; k--) {
      final y0 = _backY + k * _rowW, y1 = y0 + _rowW, z0 = k * _rowH, z1 = (k + 1) * _rowH;
      canvas.drawPath(_viewPoly(v, [[-14, y0, z0], [14, y0, z0], [14, y0, z1], [-14, y0, z1]]),
          Paint()..color = const Color(0xFF0C1C36));
      canvas.drawPath(_viewPoly(v, [[-14, y0, z1], [14, y0, z1], [14, y1, z1], [-14, y1, z1]]),
          Paint()..color = k.isEven ? const Color(0xFF1B3A63) : const Color(0xFF183457));
    }

    // low boards around the court with lime ad stripes
    final boardFace = Paint()..color = const Color(0xFF0F3B2B);
    final boardTop = Paint()..color = const Color(0xFF1C5A40);
    final stripe = Paint()..color = const Color(0x77D4F33A);
    for (final sd in [-1.0, 1.0]) {
      final x = sd * 7.4;
      canvas.drawPath(_viewPoly(v, [[x, -11, 0], [x, 11, 0], [x, 11, 0.8], [x, -11, 0.8]]), boardFace);
      canvas.drawPath(_viewPoly(v, [[x, -11, 0.8], [x, 11, 0.8], [x + sd * 0.25, 11, 0.8], [x + sd * 0.25, -11, 0.8]]),
          boardTop);
      for (var y = -10.0; y < 10.0; y += 4.0) {
        canvas.drawPath(_viewPoly(v, [[x - sd * 0.01, y, 0.3], [x - sd * 0.01, y + 2.4, 0.3], [x - sd * 0.01, y + 2.4, 0.55], [x - sd * 0.01, y, 0.55]]),
            stripe);
      }
    }
    canvas.drawPath(_viewPoly(v, [[-7.4, 11, 0], [7.4, 11, 0], [7.4, 11, 0.8], [-7.4, 11, 0.8]]), boardFace);
    for (var x = -6.6; x < 6.6; x += 4.0) {
      canvas.drawPath(_viewPoly(v, [[x, 10.99, 0.3], [x + 2.4, 10.99, 0.3], [x + 2.4, 10.99, 0.55], [x, 10.99, 0.55]]),
          stripe);
    }
    paintCourt(canvas, v);
  }

  /// [excitement] 0..1 makes the crowd jump, wave and raise their arms.
  /// [density] 0..1 draws only part of the crowd (graphics quality).
  static Float32List _pos = Float32List(0);
  static Int32List _col = Int32List(0);

  static void paintCrowd(Canvas canvas, CourtView v, double time, double excitement, {double density = 1}) {
    final fans = _crowd();
    final step = density >= 0.99 ? 1 : (1 / density).round().clamp(1, 4);
    final maxVerts = (fans.length ~/ step + 1) * 42;
    if (_pos.length < maxVerts * 2) {
      _pos = Float32List(maxVerts * 2);
      _col = Int32List(maxVerts);
    }
    var pv = 0, cv = 0;
    void tri(double ax, double ay, double bx, double by, double cx, double cy, int color) {
      _pos[pv++] = ax;
      _pos[pv++] = ay;
      _pos[pv++] = bx;
      _pos[pv++] = by;
      _pos[pv++] = cx;
      _pos[pv++] = cy;
      _col[cv++] = color;
      _col[cv++] = color;
      _col[cv++] = color;
    }

    void rect(double l, double t, double r, double b, int color) {
      tri(l, t, r, t, r, b, color);
      tri(l, t, r, b, l, b, color);
    }

    void limb(double x0, double y0, double x1, double y1, double w, int color) {
      final dx = x1 - x0, dy = y1 - y0;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-3) return;
      final nx = -dy / len * w / 2, ny = dx / len * w / 2;
      tri(x0 + nx, y0 + ny, x1 + nx, y1 + ny, x1 - nx, y1 - ny, color);
      tri(x0 + nx, y0 + ny, x1 - nx, y1 - ny, x0 - nx, y0 - ny, color);
    }

    const signColors = [0xFFD4F33A, 0xFFFF4D8D, 0xFF2D9CDB, 0xFFFFFFFF];
    final w = v.size.width;
    for (var i = 0; i < fans.length; i += step) {
      final f = fans[i];
      final cheering = f.eagerness < excitement;
      final jump = cheering ? (math.sin(time * 9 + f.phase).abs() * 0.28 * excitement) : 0.0;
      final base = v.projectView(f.x + math.sin(time * 1.6 + f.phase) * 0.05, f.y, f.z + jump);
      if (base.dx < -30 || base.dx > w + 30 || base.dy < -30) continue;
      final u = v.pxPerMeterView(f.x, f.y, f.z) * 0.75;
      final bx = base.dx, by = base.dy;
      // body
      rect(bx - 0.25 * u, by - 0.75 * u, bx + 0.25 * u, by - 0.15 * u, f.shirt);
      final shy = by - 0.68 * u;
      if (cheering) {
        final wave = math.sin(time * 12 + f.phase) * 0.12 * u;
        limb(bx - 0.2 * u, shy, bx - 0.38 * u + wave, shy - 0.55 * u, 0.11 * u, f.skin);
        limb(bx + 0.2 * u, shy, bx + 0.38 * u - wave, shy - 0.55 * u, 0.11 * u, f.skin);
      }
      // head (hexagon)
      final hx = bx, hy = shy - 0.2 * u, hr = 0.17 * u;
      for (var k = 0; k < 6; k++) {
        final a0 = k * math.pi / 3, a1 = (k + 1) * math.pi / 3;
        tri(hx, hy, hx + math.cos(a0) * hr, hy + math.sin(a0) * hr, hx + math.cos(a1) * hr, hy + math.sin(a1) * hr,
            f.skin);
      }
      if (f.sign > 0 && (cheering || f.sign.isEven)) {
        final ty = shy - 0.75 * u - (cheering ? 0.1 * u : 0);
        rect(bx - 0.37 * u, ty - 0.21 * u, bx + 0.37 * u, ty + 0.21 * u, signColors[f.sign - 1]);
      }
    }
    if (pv == 0) return;
    final vertices = ui.Vertices.raw(ui.VertexMode.triangles, Float32List.sublistView(_pos, 0, pv),
        colors: Int32List.sublistView(_col, 0, cv));
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
  }

  static void paintCourt(Canvas canvas, CourtView v) {
    final apron = _quad(v, -7.4, -11.0, 7.4, 11.0);
    final a0 = v.project(0, -11.0, 0), a1 = v.project(0, 11.0, 0);
    canvas.drawPath(apron, Paint()..shader = ui.Gradient.linear(a1, a0, const [_apronDark, _apron]));
    final c0 = v.project(0, -Court.halfL, 0), c1 = v.project(0, Court.halfL, 0);
    canvas.drawPath(
        _quad(v, -Court.halfW, -Court.halfL, Court.halfW, Court.halfL),
        Paint()
          ..shader = ui.Gradient.linear(
              c1, c0, const [Color(0xFF235C9E), _court, Color(0xFF2F74C0)], const [0, 0.5, 1]));
    final kitchenPaint = Paint()..color = _kitchen;
    canvas.drawPath(_quad(v, -Court.halfW, -Court.kitchen, Court.halfW, 0), kitchenPaint);
    canvas.drawPath(_quad(v, -Court.halfW, 0, Court.halfW, Court.kitchen), kitchenPaint);
    final lp = Paint()..color = _line;
    const lw = 0.06;
    void hLine(double y) =>
        canvas.drawPath(_quad(v, -Court.halfW - lw / 2, y - lw / 2, Court.halfW + lw / 2, y + lw / 2), lp);
    void vLine(double x, double y0, double y1) => canvas.drawPath(_quad(v, x - lw / 2, y0, x + lw / 2, y1), lp);
    hLine(-Court.halfL);
    hLine(Court.halfL);
    hLine(-Court.kitchen);
    hLine(Court.kitchen);
    vLine(-Court.halfW, -Court.halfL, Court.halfL);
    vLine(Court.halfW, -Court.halfL, Court.halfL);
    vLine(0, -Court.halfL, -Court.kitchen);
    vLine(0, Court.kitchen, Court.halfL);
  }

  /// Screen rectangle covered by the net (for its cached image).
  static Rect netBounds(CourtView v) {
    const span = Court.netHalfSpan;
    final pts = [
      v.project(-span, 0, 0), v.project(span, 0, 0), v.project(-span, 0, 1.0), v.project(span, 0, 1.0),
      v.project(span, -0.35, 0), v.project(-span, -0.35, 0),
    ];
    var r = Rect.fromPoints(pts[0], pts[1]);
    for (final p in pts) {
      r = r.expandToInclude(Rect.fromCircle(center: p, radius: 4));
    }
    return r;
  }

  static void paintNet(Canvas canvas, CourtView v) {
    const span = Court.netHalfSpan;
    final bl = v.project(-span, 0, 0), br = v.project(span, 0, 0);
    final tl = v.project(-span, 0, 0.914), tr = v.project(span, 0, 0.914);
    final tc = v.project(0, 0, Court.netH);
    final s0 = v.project(span, -0.35, 0), s1 = v.project(-span, -0.35, 0);
    canvas.drawPath(
        Path()
          ..moveTo(bl.dx, bl.dy)
          ..lineTo(br.dx, br.dy)
          ..lineTo(s0.dx, s0.dy)
          ..lineTo(s1.dx, s1.dy)
          ..close(),
        Paint()..color = const Color(0x33000000));
    final mesh = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(tr.dx, tr.dy)
      ..quadraticBezierTo(tc.dx, tc.dy + 1, tl.dx, tl.dy)
      ..close();
    canvas.drawPath(mesh, Paint()..color = const Color(0x8C0A0F1A));
    canvas.save();
    canvas.clipPath(mesh);
    final grid = Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 0.8;
    for (var x = -span; x <= span; x += 0.12) {
      canvas.drawLine(v.project(x, 0, 0), v.project(x, 0, 1.0), grid);
    }
    for (var z = 0.08; z < 0.95; z += 0.1) {
      canvas.drawLine(v.project(-span, 0, z), v.project(span, 0, z), grid);
    }
    canvas.restore();
    final tape = Path()
      ..moveTo(tl.dx, tl.dy)
      ..quadraticBezierTo(tc.dx, tc.dy + 1, tr.dx, tr.dy);
    canvas.drawPath(
        tape,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, 0.07 * v.pxPerMeter(0, 0, 0.9)));
    final post = Paint()
      ..color = const Color(0xFF2A2F3A)
      ..strokeWidth = math.max(3.0, 0.09 * v.pxPerMeter(0, 0, 0.5))
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(bl, tl, post);
    canvas.drawLine(br, tr, post);
  }
}
