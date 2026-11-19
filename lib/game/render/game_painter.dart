import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../models/profile.dart';
import '../game_state.dart';
import '../physics.dart';
import 'character_painter.dart';
import 'court_painter.dart';
import 'court_view.dart';
import 'effects.dart';

/// Everything the painter needs for one frame.
class GameScene {
  GameState state;
  final List<PlayerProfile> profiles;
  final List<ui.Image?> faces;
  final CourtView view;
  final Effects fx;
  final int localIndex; // -1 = spectator (home screen demo)
  bool showMarker;
  double time = 0;
  double topInset;
  double bottomInset;

  GameScene({
    required this.state,
    required this.profiles,
    required this.faces,
    required this.view,
    required this.fx,
    this.localIndex = 0,
    this.showMarker = true,
    this.topInset = 96,
    this.bottomInset = 150,
  });
}

class GamePainter extends CustomPainter {
  final GameScene scene;
  static const double ballRadius = 0.12; // drawn larger than real for visibility

  GamePainter(this.scene, {super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    final v = scene.view;
    final s = scene.state;
    v.layout(size, top: scene.topInset, bottom: scene.bottomInset);
    canvas.save();
    canvas.translate(scene.fx.shakeOffset().dx, scene.fx.shakeOffset().dy);
    CourtPainter.paintBackground(canvas, size, v, scene.time);
    CourtPainter.paintCourt(canvas, v);

    final li = scene.localIndex;
    if (li >= 0) _paintHints(canvas, v, s, li);
    scene.fx.paintGround(canvas, v);

    // shadows
    final b = s.ball;
    final shadowC = v.project(b.x, b.y, 0);
    final sppm = v.pxPerMeter(b.x, b.y, 0);
    final sr = ballRadius * sppm * (1.1 + math.min(b.z, 3) * 0.12);
    canvas.drawOval(Rect.fromCenter(center: shadowC, width: sr * 2.2, height: sr * 1.2),
        Paint()..color = Color.fromRGBO(0, 0, 0, (0.45 - b.z * 0.08).clamp(0.12, 0.45)));

    // painter's algorithm: far objects first, net in the middle
    final items = <(double, void Function())>[];
    for (var i = 0; i < 2; i++) {
      final p = s.players[i];
      items.add((v.depthKey(p.y), () => _paintPlayer(canvas, v, i)));
    }
    items.add((v.depthKey(b.y) - 0.01, () => _paintBall(canvas, v)));
    items.sort((a, b2) => b2.$1.compareTo(a.$1));
    var netDrawn = false;
    for (final it in items) {
      if (!netDrawn && it.$1 < 0) {
        CourtPainter.paintNet(canvas, v);
        netDrawn = true;
      }
      it.$2();
    }
    if (!netDrawn) CourtPainter.paintNet(canvas, v);
    scene.fx.paintParticles(canvas, v);
    canvas.restore();
    scene.fx.paintScreen(canvas, size);
  }

  void _paintHints(Canvas canvas, CourtView v, GameState s, int li) {
    final me = s.players[li];
    final incoming = s.phase == Phase.rally && s.lastHitter >= 0 && s.lastHitter != li;
    // kitchen warning: standing in the kitchen while a volley is coming
    if (incoming &&
        me.y.abs() < Court.kitchen &&
        s.bouncesOnReceiver == 0 &&
        !s.mustBounce) {
      final y0 = me.side * Court.kitchen;
      final a = v.project(-Court.halfW, 0, 0), bb = v.project(Court.halfW, 0, 0);
      final c = v.project(Court.halfW, y0, 0), d = v.project(-Court.halfW, y0, 0);
      final pulse = 0.25 + 0.15 * math.sin(scene.time * 10);
      canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(bb.dx, bb.dy)
            ..lineTo(c.dx, c.dy)
            ..lineTo(d.dx, d.dy)
            ..close(),
          Paint()..color = Color.fromRGBO(255, 60, 60, pulse));
    }
    // predicted landing spot
    if (scene.showMarker && incoming && s.hasMarker) {
      final c = v.project(s.markerX, s.markerY, 0);
      final ppm = v.pxPerMeter(s.markerX, s.markerY, 0);
      final r = (0.28 + 0.05 * math.sin(scene.time * 8)) * ppm;
      final inside = Court.inCourt(s.markerX, s.markerY, me.side);
      final col = inside ? const Color(0xFFD4F33A) : const Color(0xFFFF5252);
      canvas.drawOval(Rect.fromCenter(center: c, width: r * 2, height: r * 1.15),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = col.withValues(alpha: 0.85));
      canvas.drawOval(Rect.fromCenter(center: c, width: r * 0.6, height: r * 0.35),
          Paint()..color = col.withValues(alpha: 0.5));
    }
    // ring under the local player (brightens when the ball is in reach)
    final feet = v.project(me.x, me.y, 0);
    final ppm = v.pxPerMeter(me.x, me.y, 0);
    final b = s.ball;
    final dist = math.sqrt((b.x - me.x) * (b.x - me.x) + (b.y - me.y) * (b.y - me.y));
    final hot = incoming && dist < 1.05 && b.z < 2.35;
    canvas.drawOval(
        Rect.fromCenter(center: feet, width: 2.1 * ppm, height: 1.05 * ppm),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hot ? 3.5 : 2
          ..color = (hot ? const Color(0xFFD4F33A) : Colors.white).withValues(alpha: hot ? 0.95 : 0.35));
  }

  void _paintPlayer(Canvas canvas, CourtView v, int i) {
    final s = scene.state;
    final p = s.players[i];
    final prof = scene.profiles[i];
    final feet = v.project(p.x, p.y, 0);
    final ppm = v.pxPerMeter(p.x, p.y, 0);
    final backView = v.depthKey(p.y) < 0; // near half: we see their back
    CharacterPainter.paint(
      canvas,
      feet,
      ppm,
      prof.look,
      face: scene.faces[i],
      initials: prof.initials,
      swing: p.swing,
      swingKind: p.swingKind,
      swingHand: p.swingHand,
      runPhase: p.runPhase,
      moveSpeed: math.sqrt(p.vx * p.vx + p.vy * p.vy),
      backView: backView,
      time: scene.time + i * 1.7,
    );
    // name tag
    final tp = TextPainter(
      text: TextSpan(
        text: prof.name,
        style: TextStyle(
          color: Colors.white,
          fontFamily: 'Roboto',
          fontSize: math.max(9.0, ppm * 0.3),
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final tagY = feet.dy - ppm * CharacterPainter.visualScale * 2.42 - tp.height;
    tp.paint(canvas, Offset(feet.dx - tp.width / 2, tagY));
  }

  void _paintBall(Canvas canvas, CourtView v) {
    final b = scene.state.ball;
    scene.fx.paintTrail(canvas, v, ballRadius);
    final c = v.project(b.x, b.y, b.z + ballRadius * 0.5);
    final r = math.max(3.0, ballRadius * v.pxPerMeter(b.x, b.y, b.z));
    Effects.paintBall(canvas, c, r);
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => oldDelegate.scene != scene;
}
