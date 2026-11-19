import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../physics.dart';
import 'court_view.dart';

/// Draws the arena: background, stands, apron, court, lines and the net.
class CourtPainter {
  static const _apron = Color(0xFF1E7A52);
  static const _apronDark = Color(0xFF155C3D);
  static const _court = Color(0xFF2B6CB5);
  static const _kitchen = Color(0xFF3B87D3);
  static const _line = Color(0xFFF7F9FC);

  static Path _quad(CourtView v, double x0, double y0, double x1, double y1,
      [double z = 0]) {
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

  static void paintBackground(Canvas canvas, Size size, CourtView v, double time) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), const [
          Color(0xFF07101F),
          Color(0xFF0E2140),
          Color(0xFF0B1A33),
        ], const [0, 0.45, 1]),
    );
    // stadium stands with twinkling crowd behind the far end
    final farLeft = v.project(-9, 12.5, 0);
    final farRight = v.project(9, 12.5, 0);
    final top = math.max(0.0, farLeft.dy - size.height * 0.16);
    final standRect = Rect.fromLTRB(0, top, size.width, farLeft.dy);
    canvas.drawRect(
      standRect,
      Paint()
        ..shader = ui.Gradient.linear(standRect.topCenter, standRect.bottomCenter,
            const [Color(0xFF13284A), Color(0xFF1A3560)]),
    );
    final crowd = Paint();
    final rnd = math.Random(7);
    final rows = 6;
    for (var r = 0; r < rows; r++) {
      final y = top + (r + 0.5) * (standRect.height / rows);
      for (var x = 4.0; x < size.width; x += 9 + rnd.nextDouble() * 5) {
        final hue = rnd.nextDouble();
        final tw = 0.55 + 0.45 * math.sin(time * (1.5 + hue * 2) + x * 0.13 + r);
        crowd.color = HSLColor.fromAHSL(0.35 + 0.35 * tw, hue * 360, 0.55, 0.62).toColor();
        canvas.drawCircle(Offset(x, y + rnd.nextDouble() * 3), 2.2 + rnd.nextDouble() * 1.4, crowd);
      }
    }
    // stadium lights glow
    for (final fx in [0.12, 0.88]) {
      final c = Offset(size.width * fx, top + 6);
      canvas.drawCircle(
          c,
          60,
          Paint()
            ..shader = ui.Gradient.radial(c, 60, const [Color(0x55FFF6D5), Color(0x00FFF6D5)]));
    }
    // windscreen at the far end
    final ws = Path()
      ..moveTo(farLeft.dx, farLeft.dy)
      ..lineTo(farRight.dx, farRight.dy);
    final wsTopR = v.project(9, 12.5, 1.4);
    final wsTopL = v.project(-9, 12.5, 1.4);
    ws
      ..lineTo(wsTopR.dx, wsTopR.dy)
      ..lineTo(wsTopL.dx, wsTopL.dy)
      ..close();
    canvas.drawPath(ws, Paint()..color = const Color(0xFF0F3B2B));
  }

  static void paintCourt(Canvas canvas, CourtView v) {
    // apron / surround
    final apron = _quad(v, -9, -12.5, 9, 12.5);
    final a0 = v.project(0, -12.5, 0), a1 = v.project(0, 12.5, 0);
    canvas.drawPath(
        apron,
        Paint()
          ..shader = ui.Gradient.linear(a1, a0, const [_apronDark, _apron]));
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
    void vLine(double x, double y0, double y1) =>
        canvas.drawPath(_quad(v, x - w / 2, y0, x + w / 2, y1), lp);
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
    // shadow on the court
    final sh = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(v.project(span, -0.35, 0).dx, v.project(span, -0.35, 0).dy)
      ..lineTo(v.project(-span, -0.35, 0).dx, v.project(-span, -0.35, 0).dy)
      ..close();
    canvas.drawPath(sh, Paint()..color = const Color(0x33000000));
    // mesh
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
      final a = v.project(x, 0, 0), b = v.project(x, 0, 1.0);
      canvas.drawLine(a, b, grid);
    }
    for (var z = 0.08; z < 0.95; z += 0.1) {
      canvas.drawLine(v.project(-span, 0, z), v.project(span, 0, z), grid);
    }
    canvas.restore();
    // tape
    final tape = Path()
      ..moveTo(tl.dx, tl.dy)
      ..quadraticBezierTo(tc.dx, tc.dy + 1, tr.dx, tr.dy);
    canvas.drawPath(
        tape,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, 0.06 * v.pxPerMeter(0, 0, 0.9)));
    // posts
    final post = Paint()
      ..color = const Color(0xFF2A2F3A)
      ..strokeWidth = math.max(3.0, 0.08 * v.pxPerMeter(0, 0, 0.5))
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(bl, tl, post);
    canvas.drawLine(br, tr, post);
  }
}
