import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../models/profile.dart';
import '../shot_planner.dart';

/// Bobble-head pickleball player. The head always faces the camera so each
/// player's own face photo is visible during the match.
class CharacterPainter {
  static const double visualScale = 1.35;

  static void paint(
    Canvas canvas,
    Offset feet,
    double ppm,
    CharacterLook look, {
    ui.Image? face,
    String initials = '',
    double swing = 0,
    ShotKind swingKind = ShotKind.drive,
    int swingHand = 1,
    double runPhase = 0,
    double moveSpeed = 0,
    bool backView = true,
    double time = 0,
    bool shadow = true,
  }) {
    final u = ppm * visualScale;
    final move = (moveSpeed / 3.5).clamp(0.0, 1.0);
    final bob = math.sin(runPhase * math.pi * 2).abs() * 0.035 * u * move;
    final skin = Color(look.skin);
    final jersey = Color(look.jersey);

    if (shadow) {
      canvas.drawOval(
          Rect.fromCenter(center: feet, width: 0.95 * u, height: 0.3 * u),
          Paint()..color = const Color(0x55000000));
    }
    canvas.save();
    canvas.translate(feet.dx, feet.dy - bob);

    // ------------------------------------------------------------ legs
    final legSwing = math.sin(runPhase * math.pi * 2) * 0.5 * move;
    final legPaint = Paint()
      ..color = skin
      ..strokeWidth = 0.13 * u
      ..strokeCap = StrokeCap.round;
    final shoePaint = Paint()..color = Color(look.shoes);
    for (final s in [-1, 1]) {
      final hip = Offset(s * 0.11 * u, -0.74 * u);
      final a = legSwing * s;
      final foot = hip + Offset(math.sin(a) * 0.7 * u, math.cos(a) * 0.7 * u);
      canvas.drawLine(hip, foot, legPaint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: foot + Offset(0, -0.02 * u), width: 0.22 * u, height: 0.1 * u),
              Radius.circular(0.05 * u)),
          shoePaint);
    }
    // ----------------------------------------------------------- shorts
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(-0.25 * u, -0.95 * u, 0.25 * u, -0.66 * u), Radius.circular(0.07 * u)),
        Paint()..color = Color(look.shorts));

    // ------------------------------------------------------------ arms
    final handSide = (backView ? 1 : -1) * (swingHand >= 0 ? 1 : -1);
    final t = swing > 0 ? (1 - swing / 0.32).clamp(0.0, 1.0) : -1.0;
    double theta; // 0 = arm hanging down, positive = raised outward
    if (t < 0) {
      theta = 0.95 + math.sin(time * 2.2) * 0.06;
    } else {
      final e = 1 - math.pow(1 - t, 3).toDouble();
      final (from, to) = switch (swingKind) {
        ShotKind.drive => (2.5, -1.0),
        ShotKind.soft => (1.3, 0.1),
        ShotKind.lob => (0.2, 2.6),
      };
      theta = from + (to - from) * e;
    }
    final shoulderY = -1.36 * u;
    final paddleShoulder = Offset(handSide * 0.28 * u, shoulderY);
    final otherShoulder = Offset(-handSide * 0.28 * u, shoulderY);
    final armPaint = Paint()
      ..color = skin
      ..strokeWidth = 0.11 * u
      ..strokeCap = StrokeCap.round;
    // free arm
    final freeHand = otherShoulder +
        Offset(-handSide * 0.16 * u, 0.36 * u + math.sin(runPhase * math.pi * 2) * 0.05 * u);
    canvas.drawLine(otherShoulder, freeHand, armPaint);

    // ---------------------------------------------------------- torso
    final torso = RRect.fromRectAndRadius(
        Rect.fromLTRB(-0.28 * u, -1.46 * u, 0.28 * u, -0.86 * u), Radius.circular(0.13 * u));
    canvas.drawRRect(
        torso,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, -1.46 * u), Offset(0, -0.86 * u),
              [Color.lerp(jersey, Colors.white, 0.18)!, jersey]));
    canvas.drawRRect(
        torso,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.02 * u
          ..color = const Color(0x33000000));
    final numberSize = backView ? 0.3 * u : 0.15 * u;
    final tp = TextPainter(
      text: TextSpan(
        text: '${look.number}',
        style: TextStyle(
          color: jersey.computeLuminance() > 0.55 ? const Color(0xFF111111) : Colors.white,
          fontSize: numberSize,
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final numberPos = backView
        ? Offset(-tp.width / 2, -1.16 * u - tp.height / 2)
        : Offset(0.06 * u, -1.3 * u);
    tp.paint(canvas, numberPos);

    // paddle arm (drawn after torso so it can swing in front)
    final hand = paddleShoulder +
        Offset(math.sin(theta) * handSide * 0.42 * u, math.cos(theta) * 0.42 * u);
    canvas.drawLine(paddleShoulder, hand, armPaint);
    _paddle(canvas, hand, theta, handSide, u, look);

    // ------------------------------------------------------------- head
    canvas.drawRect(Rect.fromLTRB(-0.06 * u, -1.56 * u, 0.06 * u, -1.42 * u),
        Paint()..color = Color.lerp(skin, Colors.black, 0.12)!);
    final wobble = math.sin(time * 9 + runPhase) * 0.05 * move;
    canvas.save();
    canvas.translate(0, -1.82 * u);
    canvas.rotate(wobble);
    paintFace(canvas, Offset.zero, 0.36 * u, look, face: face, initials: initials);
    canvas.restore();

    canvas.restore();
  }

  static void _paddle(Canvas canvas, Offset hand, double theta, int side, double u,
      CharacterLook look) {
    canvas.save();
    canvas.translate(hand.dx, hand.dy);
    // paddle points along the arm direction
    canvas.rotate(-theta * side);
    final handle = Paint()
      ..color = const Color(0xFF222222)
      ..strokeWidth = 0.05 * u
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(0, 0.12 * u), handle);
    final faceRect = Rect.fromCenter(center: Offset(0, 0.27 * u), width: 0.24 * u, height: 0.3 * u);
    final rr = RRect.fromRectAndRadius(faceRect, Radius.circular(0.1 * u));
    final color = Color(look.paddle);
    canvas.drawRRect(rr, Paint()..color = color);
    canvas.save();
    canvas.clipRRect(rr);
    final accent = Paint()..color = Color.lerp(color, Colors.black, 0.35)!;
    switch (look.pattern) {
      case PaddlePattern.solid:
        canvas.drawRect(
            Rect.fromLTRB(faceRect.left, faceRect.top, faceRect.right, faceRect.top + 0.05 * u),
            accent);
      case PaddlePattern.stripes:
        accent.strokeWidth = 0.035 * u;
        for (var i = -4; i < 6; i++) {
          final x = faceRect.left + i * 0.07 * u;
          canvas.drawLine(Offset(x, faceRect.bottom), Offset(x + 0.3 * u, faceRect.top), accent);
        }
      case PaddlePattern.dots:
        for (var i = 0; i < 3; i++) {
          for (var j = 0; j < 4; j++) {
            canvas.drawCircle(
                Offset(faceRect.left + (i + 0.5) * faceRect.width / 3,
                    faceRect.top + (j + 0.5) * faceRect.height / 4),
                0.022 * u,
                accent);
          }
        }
      case PaddlePattern.flame:
        final flame = Path()
          ..moveTo(faceRect.left, faceRect.bottom)
          ..quadraticBezierTo(faceRect.left + 0.02 * u, faceRect.center.dy, faceRect.left + 0.06 * u,
              faceRect.top + 0.06 * u)
          ..quadraticBezierTo(faceRect.center.dx, faceRect.center.dy, faceRect.center.dx + 0.02 * u,
              faceRect.top)
          ..quadraticBezierTo(faceRect.center.dx + 0.06 * u, faceRect.center.dy,
              faceRect.right - 0.03 * u, faceRect.top + 0.08 * u)
          ..quadraticBezierTo(faceRect.right, faceRect.center.dy, faceRect.right, faceRect.bottom)
          ..close();
        canvas.drawPath(
            flame,
            Paint()
              ..shader = ui.Gradient.linear(faceRect.bottomCenter, faceRect.topCenter,
                  const [Color(0xFFFF3D00), Color(0xFFFFC400)]));
    }
    canvas.restore();
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.025 * u
          ..color = const Color(0xFF1A1A1A));
    canvas.restore();
  }

  /// Circular face: the player's photo, or a cartoon face if none.
  static void paintFace(Canvas canvas, Offset c, double r, CharacterLook look,
      {ui.Image? face, String initials = '', bool ring = true}) {
    final circle = Rect.fromCircle(center: c, radius: r);
    if (ring) {
      canvas.drawCircle(c, r * 1.1, Paint()..color = Colors.white);
      canvas.drawCircle(c, r * 1.1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.07
            ..color = Color(look.jersey));
    }
    if (face != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(circle));
      final src = Rect.fromLTWH(0, 0, face.width.toDouble(), face.height.toDouble());
      final side = math.min(src.width, src.height);
      final crop = Rect.fromCenter(center: src.center, width: side, height: side);
      canvas.drawImageRect(face, crop, circle, Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
    } else {
      _cartoonFace(canvas, c, r, look);
    }
    _accessory(canvas, c, r, look);
  }

  static void _cartoonFace(Canvas canvas, Offset c, double r, CharacterLook look) {
    final skin = Color(look.skin);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c + Offset(-r * 0.3, -r * 0.3), r * 1.4,
              [Color.lerp(skin, Colors.white, 0.18)!, skin, Color.lerp(skin, Colors.black, 0.15)!],
              const [0, 0.6, 1]));
    // hair
    final hair = Paint()..color = Color(look.hair);
    final hp = Path()
      ..moveTo(c.dx - r, c.dy - r * 0.05)
      ..quadraticBezierTo(c.dx - r * 0.95, c.dy - r * 1.15, c.dx, c.dy - r * 1.05)
      ..quadraticBezierTo(c.dx + r * 0.95, c.dy - r * 1.15, c.dx + r, c.dy - r * 0.05)
      ..quadraticBezierTo(c.dx + r * 0.55, c.dy - r * 0.55, c.dx + r * 0.1, c.dy - r * 0.45)
      ..quadraticBezierTo(c.dx - r * 0.5, c.dy - r * 0.6, c.dx - r, c.dy - r * 0.05)
      ..close();
    canvas.drawPath(hp, hair);
    canvas.restore();
    // eyes
    final white = Paint()..color = Colors.white;
    final dark = Paint()..color = const Color(0xFF1B1B1B);
    for (final s in [-1, 1]) {
      final e = c + Offset(s * r * 0.34, r * 0.02);
      canvas.drawOval(Rect.fromCenter(center: e, width: r * 0.3, height: r * 0.36), white);
      canvas.drawCircle(e + Offset(0, r * 0.03), r * 0.1, dark);
      canvas.drawCircle(e + Offset(-r * 0.03, -r * 0.02), r * 0.035, white);
      canvas.drawLine(
          c + Offset(s * r * 0.2, -r * 0.24),
          c + Offset(s * r * 0.48, -r * 0.27),
          Paint()
            ..color = Color(look.hair)
            ..strokeWidth = r * 0.07
            ..strokeCap = StrokeCap.round);
    }
    // cheeks + smile
    final blush = Paint()..color = const Color(0x44FF5A7A);
    canvas.drawCircle(c + Offset(-r * 0.55, r * 0.32), r * 0.13, blush);
    canvas.drawCircle(c + Offset(r * 0.55, r * 0.32), r * 0.13, blush);
    final smile = Path()
      ..moveTo(c.dx - r * 0.28, c.dy + r * 0.36)
      ..quadraticBezierTo(c.dx, c.dy + r * 0.62, c.dx + r * 0.28, c.dy + r * 0.36);
    canvas.drawPath(
        smile,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.08
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF6B2B2B));
  }

  static void _accessory(Canvas canvas, Offset c, double r, CharacterLook look) {
    final jersey = Color(look.jersey);
    switch (look.accessory) {
      case Accessory.none:
        break;
      case Accessory.cap:
        final cap = Path()
          ..addArc(Rect.fromCircle(center: c + Offset(0, -r * 0.05), radius: r * 1.06), math.pi,
              math.pi)
          ..close();
        canvas.drawPath(cap, Paint()..color = jersey);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(c.dx - r * 1.15, c.dy - r * 0.16, c.dx + r * 0.75, c.dy + r * 0.02),
                Radius.circular(r * 0.1)),
            Paint()..color = Color.lerp(jersey, Colors.black, 0.3)!);
        canvas.drawCircle(c + Offset(0, -r * 1.08), r * 0.1, Paint()..color = Colors.white);
      case Accessory.headband:
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 1.1)));
        canvas.drawRect(Rect.fromLTRB(c.dx - r * 1.2, c.dy - r * 0.62, c.dx + r * 1.2, c.dy - r * 0.36),
            Paint()..color = jersey);
        canvas.drawRect(Rect.fromLTRB(c.dx - r * 1.2, c.dy - r * 0.52, c.dx + r * 1.2, c.dy - r * 0.46),
            Paint()..color = Colors.white);
        canvas.restore();
      case Accessory.visor:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(c.dx - r * 1.15, c.dy - r * 0.62, c.dx + r * 1.15, c.dy - r * 0.38),
                Radius.circular(r * 0.12)),
            Paint()..color = jersey);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(c.dx - r * 1.0, c.dy - r * 0.42, c.dx + r * 1.0, c.dy - r * 0.26),
                Radius.circular(r * 0.1)),
            Paint()..color = const Color(0xAA0B3D5C));
      case Accessory.shades:
        final lens = Paint()
          ..shader = ui.Gradient.linear(c + Offset(0, -r * 0.2), c + Offset(0, r * 0.15),
              const [Color(0xFF263238), Color(0xFF7E57C2)]);
        for (final s in [-1, 1]) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: c + Offset(s * r * 0.38, -r * 0.05), width: r * 0.62, height: r * 0.36),
                  Radius.circular(r * 0.14)),
              lens);
        }
        canvas.drawLine(c + Offset(-r * 0.1, -r * 0.1), c + Offset(r * 0.1, -r * 0.1),
            Paint()
              ..color = const Color(0xFF263238)
              ..strokeWidth = r * 0.07);
      case Accessory.crown:
        final crown = Path()
          ..moveTo(c.dx - r * 0.6, c.dy - r * 0.8)
          ..lineTo(c.dx - r * 0.7, c.dy - r * 1.45)
          ..lineTo(c.dx - r * 0.32, c.dy - r * 1.12)
          ..lineTo(c.dx, c.dy - r * 1.6)
          ..lineTo(c.dx + r * 0.32, c.dy - r * 1.12)
          ..lineTo(c.dx + r * 0.7, c.dy - r * 1.45)
          ..lineTo(c.dx + r * 0.6, c.dy - r * 0.8)
          ..close();
        canvas.drawPath(
            crown,
            Paint()
              ..shader = ui.Gradient.linear(c + Offset(0, -r * 1.6), c + Offset(0, -r * 0.8),
                  const [Color(0xFFFFF176), Color(0xFFFFA000)]));
        canvas.drawCircle(c + Offset(0, -r * 1.05), r * 0.09, Paint()..color = const Color(0xFFE53935));
    }
  }
}
