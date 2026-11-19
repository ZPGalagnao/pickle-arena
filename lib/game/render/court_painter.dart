import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../physics.dart';
import 'court_view.dart';

class _Fan {
  final double x, y, z; // view space (metres)
  final Color shirt, skin;
  final double phase, eagerness;
  final int sign; // 0 = none, else a colored sign/flag
  _Fan(this.x, this.y, this.z, this.shirt, this.skin, this.phase, this.eagerness, this.sign);
}

/// Draws the arena: sky, stands full of fans, apron, court, lines and net.
class CourtPainter {
  static const _apron = Color(0xFF1E7A52);
  static const _apronDark = Color(0xFF155C3D);
  static const _court = Color(0xFF2B6CB5);
  static const _kitchen = Color(0xFF3B87D3);
  static const _line = Color(0xFFF7F9FC);

  static List<_Fan>? _fans;

  static List<_Fan> _crowd() {
    if (_fans != null) return _fans!;
    final r = math.Random(11);
    const shirts = [
      Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFFFDD835), Color(0xFF43A047), Color(0xFFFFFFFF),
      Color(0xFFFF7A3D), Color(0xFF8E24AA), Color(0xFF00ACC1), Color(0xFFD4F33A), Color(0xFF263238),
    ];
    const skins = [Color(0xFFFFE0BD), Color(0xFFF1C27D), Color(0xFFE0AC69), Color(0xFFC68642), Color(0xFF8D5524)];
    final fans = <_Fan>[];
    _Fan make(double x, double y, double z) => _Fan(
          x, y, z, shirts[r.nextInt(shirts.length)], skins[r.nextInt(skins.length)],
          r.nextDouble() * math.pi * 2, r.nextDouble(), r.nextDouble() < 0.12 ? 1 + r.nextInt(4) : 0);
    // stand behind the far baseline
    for (var row = 0; row < 5; row++) {
      for (var x = -12.0; x <= 12.0; x += 1.05 + r.nextDouble() * 0.25) {
        fans.add(make(x + r.nextDouble() * 0.3, 11.5 + row * 0.95, 0.6 + row * 0.75));
      }
    }
    // side stands (left and right of the court)
    for (final s in [-1.0, 1.0]) {
      for (var row = 0; row < 4; row++) {
        for (var y = -7.5; y <= 10.5; y += 1.25 + r.nextDouble() * 0.3) {
          fans.add(make(s * (7.6 + row * 0.95), y + r.nextDouble() * 0.3, 0.6 + row * 0.75));
        }
      }
    }
    // far fans first (painter's algorithm)
    fans.sort((a, b) => (b.y + b.x.abs() * 0.01).compareTo(a.y + a.x.abs() * 0.01));
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

  /// [excitement] 0..1 makes the crowd jump, wave and raise their arms.
  static void paintBackground(Canvas canvas, Size size, CourtView v, double time, {double excitement = 0}) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), const [
          Color(0xFF060D1C),
          Color(0xFF0E2140),
          Color(0xFF0B1A33),
        ], const [0, 0.45, 1]),
    );
    // stadium light glows
    for (final fx in [0.08, 0.32, 0.68, 0.92]) {
      final c = Offset(size.width * fx, 6);
      canvas.drawCircle(
          c, 70, Paint()..shader = ui.Gradient.radial(c, 70, const [Color(0x66FFF6D5), Color(0x00FFF6D5)]));
      canvas.drawCircle(c, 4, Paint()..color = const Color(0xFFFFFBE6));
    }
    // stand structures
    final standPaint = Paint()..color = const Color(0xFF14284A);
    canvas.drawPath(
        _viewPoly(v, [
          [-14, 11, 0], [14, 11, 0], [14, 17, 4.6], [-14, 17, 4.6]
        ]),
        standPaint);
    for (final s in [-1.0, 1.0]) {
      canvas.drawPath(
          _viewPoly(v, [
            [s * 7.2, -9, 0], [s * 7.2, 11, 0], [s * 11.8, 11, 3.6], [s * 11.8, -9, 3.6]
          ]),
          standPaint);
    }
    // advertising boards
    final board = Paint()..color = const Color(0xFF0F3B2B);
    canvas.drawPath(_viewPoly(v, [[-12, 10.6, 0], [12, 10.6, 0], [12, 10.6, 1.0], [-12, 10.6, 1.0]]), board);
    for (final s in [-1.0, 1.0]) {
      canvas.drawPath(_viewPoly(v, [[s * 6.9, -9, 0], [s * 6.9, 10.6, 0], [s * 6.9, 10.6, 0.9], [s * 6.9, -9, 0.9]]),
          board);
    }
    _paintCrowd(canvas, v, time, excitement);
  }

  static void _paintCrowd(Canvas canvas, CourtView v, double time, double excitement) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final f in _crowd()) {
      final cheering = f.eagerness < excitement;
      final jump = cheering ? (math.sin(time * 9 + f.phase).abs() * 0.28 * excitement) : 0.0;
      final sway = math.sin(time * 1.6 + f.phase) * 0.05;
      final base = v.projectView(f.x + sway, f.y, f.z + jump);
      final ppm = v.pxPerMeterView(f.x, f.y, f.z);
      if (base.dy < -20 || base.dx < -20 || base.dx > v.size.width + 20) continue;
      final u = ppm * 1.15;
      // body
      paint.color = f.shirt;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: base + Offset(0, -0.45 * u), width: 0.5 * u, height: 0.6 * u),
              Radius.circular(0.18 * u)),
          paint);
      // arms
      paint
        ..color = f.skin
        ..strokeWidth = math.max(1.0, 0.11 * u);
      final sh = base + Offset(0, -0.68 * u);
      if (cheering) {
        final wave = math.sin(time * 12 + f.phase) * 0.12 * u;
        canvas.drawLine(sh + Offset(-0.2 * u, 0), sh + Offset(-0.38 * u + wave, -0.55 * u), paint);
        canvas.drawLine(sh + Offset(0.2 * u, 0), sh + Offset(0.38 * u - wave, -0.55 * u), paint);
      }
      // head
      canvas.drawCircle(sh + Offset(0, -0.2 * u), 0.17 * u, paint);
      // sign / flag held up high
      if (f.sign > 0 && (cheering || f.sign.isEven)) {
        const colors = [Color(0xFFD4F33A), Color(0xFFFF4D8D), Color(0xFF2D9CDB), Color(0xFFFFFFFF)];
        paint.color = colors[f.sign - 1];
        final top = sh + Offset(0, -0.75 * u - (cheering ? 0.1 * u : 0));
        canvas.drawRect(Rect.fromCenter(center: top, width: 0.75 * u, height: 0.42 * u), paint);
      }
    }
  }

  static void paintCourt(Canvas canvas, CourtView v) {
    // apron / surround
    final apron = _quad(v, -6.9, -10.5, 6.9, 10.6);
    final a0 = v.project(0, -10.5, 0), a1 = v.project(0, 10.6, 0);
    canvas.drawPath(apron, Paint()..shader = ui.Gradient.linear(a1, a0, const [_apronDark, _apron]));
    // playing surface
    final c0 = v.project(0, -Court.halfL, 0), c1 = v.project(0, Court.halfL, 0);
    canvas.drawPath(
        _quad(v, -Court.halfW, -Court.halfL, Court.halfW, Court.halfL),
        Paint()
          ..shader = ui.Gradient.linear(
              c1, c0, const [Color(0xFF235C9E), _court, Color(0xFF2F74C0)], const [0, 0.5, 1]));
    final kitchenPaint = Paint()..color = _kitchen;
    canvas.drawPath(_quad(v, -Court.halfW, -Court.kitchen, Court.halfW, 0), kitchenPaint);
    canvas.drawPath(_quad(v, -Court.halfW, 0, Court.halfW, Court.kitchen), kitchenPaint);

    // lines (perspective-correct quads, 5 cm wide)
    final lp = Paint()..color = _line;
    const w = 0.05;
    void hLine(double y) =>
        canvas.drawPath(_quad(v, -Court.halfW - w / 2, y - w / 2, Court.halfW + w / 2, y + w / 2), lp);
    void vLine(double x, double y0, double y1) => canvas.drawPath(_quad(v, x - w / 2, y0, x + w / 2, y1), lp);
    hLine(-Court.halfL);
    hLine(Court.halfL);
    hLine(-Court.kitchen);
    hLine(Court.kitchen);
    vLine(-Court.halfW, -Court.halfL, Court.halfL);
    vLine(Court.halfW, -Court.halfL, Court.halfL);
    vLine(0, -Court.halfL, -Court.kitchen);
    vLine(0, Court.kitchen, Court.halfL);
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
      ..strokeWidth = 0.7;
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
          ..strokeWidth = math.max(2.0, 0.06 * v.pxPerMeter(0, 0, 0.9)));
    final post = Paint()
      ..color = const Color(0xFF2A2F3A)
      ..strokeWidth = math.max(3.0, 0.08 * v.pxPerMeter(0, 0, 0.5))
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(bl, tl, post);
    canvas.drawLine(br, tr, post);
  }
}
