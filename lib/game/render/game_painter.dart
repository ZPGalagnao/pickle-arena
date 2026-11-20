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
  double victoryTime = 0; // seconds since game over (camera push-in)
  double dpr; // device pixel ratio for crisp cached layers
  int quality; // 0 = low, 1 = medium, 2 = high
  bool screenShake;

  GameScene({
    required this.state,
    required this.profiles,
    required this.faces,
    required this.view,
    required this.fx,
    this.localIndex = 0,
    this.showMarker = true,
    this.topInset = 24,
    this.dpr = 2,
    this.quality = 2,
    this.screenShake = true,
  });
}

class GamePainter extends CustomPainter {
  final GameScene scene;
  static const double ballRadius = 0.12; // drawn larger than real for visibility

  GamePainter(this.scene, {super.repaint});

  // ---- cached layers (shared: one game screen at a time) -----------------
  static ui.Image? _static;
  static ui.Image? _net;
  static Rect _netRect = Rect.zero;
  static Object? _cacheKey;
  static final Map<String, TextPainter> _tags = {};

  void _ensureLayers(Size size) {
    final v = scene.view;
    final key = Object.hash(v.layoutKey, scene.dpr, scene.quality);
    if (key == _cacheKey && _static != null) return;
    _cacheKey = key;
    _static?.dispose();
    _net?.dispose();
    final dpr = scene.dpr;
    // stadium + court (+ a still crowd on low quality)
    var rec = ui.PictureRecorder();
    var c = Canvas(rec);
    c.scale(dpr);
    CourtPainter.paintStatic(c, size, v);
    if (scene.quality == 0) CourtPainter.paintCrowd(c, v, 0, 0.15, density: 0.6);
    var pic = rec.endRecording();
    _static = pic.toImageSync((size.width * dpr).ceil(), (size.height * dpr).ceil());
    pic.dispose();
    // net (only its bounding box)
    _netRect = CourtPainter.netBounds(v);
    rec = ui.PictureRecorder();
    c = Canvas(rec);
    c.scale(dpr);
    c.translate(-_netRect.left, -_netRect.top);
    CourtPainter.paintNet(c, v);
    pic = rec.endRecording();
    _net = pic.toImageSync((_netRect.width * dpr).ceil(), (_netRect.height * dpr).ceil());
    pic.dispose();
  }

  void _drawLayer(Canvas canvas, ui.Image img, Rect dst) {
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst,
        Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = scene.view;
    final s = scene.state;
    v.layout(size, top: scene.topInset);
    _ensureLayers(size);
    _updateCamera(s);
    canvas.save();
    if (scene.screenShake) {
      final sh = scene.fx.shakeOffset();
      canvas.translate(sh.dx, sh.dy);
    }
    v.applyZoom(canvas);
    _drawLayer(canvas, _static!, Offset.zero & size);
    if (scene.quality > 0) {
      CourtPainter.paintCrowd(canvas, v, scene.time, scene.fx.excitement, density: scene.quality == 1 ? 0.55 : 1.0);
    }

    final li = scene.localIndex;
    if (li >= 0 && s.phase != Phase.gameOver) _paintHints(canvas, v, s, li);
    scene.fx.paintGround(canvas, v);

    // ball shadow (the phantom ball hides its shadow too)
    final b = s.ball;
    final ghost = _ballAlpha(s);
    final shadowC = v.project(b.x, b.y, 0);
    final sppm = v.pxPerMeter(b.x, b.y, 0);
    final sr = ballRadius * sppm * (1.1 + math.min(b.z, 3) * 0.12);
    canvas.drawOval(Rect.fromCenter(center: shadowC, width: sr * 2.2, height: sr * 1.2),
        Paint()..color = Color.fromRGBO(0, 0, 0, (0.45 - b.z * 0.08).clamp(0.12, 0.45) * ghost));

    // painter's algorithm: farthest first; the net sits at depth 0
    const ballId = -1, netId = -2;
    final items = <(double, int)>[
      for (var i = 0; i < s.players.length; i++) (v.depthKey(s.players[i].y), i),
      (v.depthKey(b.y) - 0.01, ballId),
      (0.0, netId),
    ]..sort((a, c) => c.$1.compareTo(a.$1));
    for (final (_, id) in items) {
      if (id == netId) {
        _drawLayer(canvas, _net!, _netRect);
      } else if (id == ballId) {
        _paintBall(canvas, v, ghost);
      } else {
        _paintPlayer(canvas, v, id);
      }
    }
    // name tags + meters on top of everything (never hidden by the net or another player)
    if (!(s.phase == Phase.gameOver && s.winner >= 0)) {
      for (var i = 0; i < s.players.length; i++) {
        _paintTag(canvas, v, i);
      }
    }
    scene.fx.paintParticles(canvas, v);
    canvas.restore();
    scene.fx.paintScreen(canvas, size, slowmo: s.phase == Phase.gameOver ? 0 : s.slowmo);
  }

  /// Victory: push the camera in on the winning team.
  void _updateCamera(GameState s) {
    final v = scene.view;
    if (s.phase == Phase.gameOver && s.winner >= 0) {
      final winners = s.teamPlayers(s.winner);
      var fx = 0.0, fy = 0.0;
      for (final p in winners) {
        fx += p.x;
        fy += p.y;
      }
      final k = Curves.easeInOut.transform((scene.victoryTime / 1.6).clamp(0.0, 1.0));
      v.focusX = fx / winners.length * 0.7;
      v.focusY = fy / winners.length * 0.55;
      v.focusZ = 1.2;
      v.zoom = 1 + 0.45 * k;
    } else {
      v.zoom = 1;
    }
  }

  /// PHANTOM DROP fades the ball out over the net.
  double _ballAlpha(GameState s) {
    if (s.ball.fx != BallFx.phantom || s.phase != Phase.rally || s.ball.fxBounces > 0) return 1;
    final hitter = s.lastHitter < 0 ? null : s.players[s.lastHitter];
    if (hitter == null) return 1;
    if (s.ball.y * hitter.side < 0) return 0.12;
    return 0.12 + 0.88 * ((s.ball.y * hitter.side).abs() / 4).clamp(0.0, 1.0);
  }

  void _paintHints(Canvas canvas, CourtView v, GameState s, int li) {
    final me = s.players[li];
    final incoming = s.phase == Phase.rally && s.lastHitter >= 0 && s.hittingTeam != me.team;
    if (incoming && me.y.abs() < Court.kitchen && s.bouncesOnReceiver == 0 && !s.mustBounce) {
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
    if (scene.showMarker && incoming && s.hasMarker) {
      final c = v.project(s.markerX, s.markerY, 0);
      final ppm = v.pxPerMeter(s.markerX, s.markerY, 0);
      final r = (0.28 + 0.05 * math.sin(scene.time * 8)) * ppm;
      final inside = Court.inCourt(s.markerX, s.markerY, me.side);
      final col = inside ? const Color(0xFFD4F33A) : const Color(0xFFFF5252);
      canvas.drawOval(Rect.fromCenter(center: c, width: r * 2, height: r * 0.9),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = col.withValues(alpha: 0.85));
      canvas.drawOval(Rect.fromCenter(center: c, width: r * 0.6, height: r * 0.27),
          Paint()..color = col.withValues(alpha: 0.5));
    }
    final feet = v.project(me.x, me.y, 0);
    final ppm = v.pxPerMeter(me.x, me.y, 0);
    final b = s.ball;
    final dist = math.sqrt((b.x - me.x) * (b.x - me.x) + (b.y - me.y) * (b.y - me.y));
    final hot = incoming && dist < 1.05 && b.z < 2.35;
    canvas.drawOval(
        Rect.fromCenter(center: feet, width: 2.1 * ppm, height: 0.8 * ppm),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hot ? 4 : 2.2
          ..color = (hot ? const Color(0xFFD4F33A) : Colors.white).withValues(alpha: hot ? 0.95 : 0.4));
  }

  TextPainter _tag(String name, double size, bool mine) {
    final px = size.round().clamp(9, 30);
    final key = '$name|$px|$mine';
    return _tags.putIfAbsent(key, () {
      if (_tags.length > 64) _tags.clear();
      return TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            color: mine ? const Color(0xFFD4F33A) : Colors.white,
            fontFamily: 'Roboto',
            fontSize: px.toDouble(),
            fontWeight: FontWeight.w800,
            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  void _paintPlayer(Canvas canvas, CourtView v, int i) {
    final s = scene.state;
    final p = s.players[i];
    final prof = scene.profiles[i];
    final feet = v.project(p.x, p.y, 0);
    final ppm = v.pxPerMeter(p.x, p.y, 0);
    final backView = v.depthKey(p.y) < 0; // near half: we see their back
    var pose = 0;
    if (s.phase == Phase.gameOver && s.winner >= 0) pose = p.team == s.winner ? 1 : 2;
    final skillColor = Color(prof.special.color);
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
      pose: pose,
      aura: pose == 0 && (p.specialArmed || p.meter >= 1) ? skillColor : null,
      auraStrength: p.specialArmed ? 1.0 : 0.45,
      frozen: p.frozen > 0 && pose == 0,
    );
  }

  void _paintTag(Canvas canvas, CourtView v, int i) {
    final p = scene.state.players[i];
    final prof = scene.profiles[i];
    final feet = v.project(p.x, p.y, 0);
    final ppm = v.pxPerMeter(p.x, p.y, 0);
    final backView = v.depthKey(p.y) < 0;
    final skillColor = Color(prof.special.color);
    final tp = _tag(prof.name, math.max(9.0, ppm * 0.26), i == scene.localIndex);
    // far-side players get their tag under their feet so it never runs into the top HUD
    final tagY = backView ? feet.dy - ppm * CharacterPainter.visualScale * 2.42 - tp.height - 6 : feet.dy + 3;
    tp.paint(canvas, Offset(feet.dx - tp.width / 2, tagY));
    final w = math.max(26.0, ppm * 0.9), h = math.max(3.0, ppm * 0.07);
    final bar = Rect.fromLTWH(feet.dx - w / 2, tagY + tp.height + 1, w, h);
    canvas.drawRRect(RRect.fromRectAndRadius(bar, Radius.circular(h)), Paint()..color = const Color(0x99000000));
    final ready = p.meter >= 1;
    final fill = Rect.fromLTWH(bar.left, bar.top, w * p.meter.clamp(0.0, 1.0), h);
    canvas.drawRRect(
        RRect.fromRectAndRadius(fill, Radius.circular(h)),
        Paint()
          ..color = ready
              ? Color.lerp(skillColor, Colors.white, 0.4 + 0.4 * math.sin(scene.time * 10))!
              : skillColor.withValues(alpha: 0.85));
  }

  void _paintBall(Canvas canvas, CourtView v, double alpha) {
    final b = scene.state.ball;
    if (scene.quality > 0) scene.fx.paintTrail(canvas, v, ballRadius, b.fx);
    final c = v.project(b.x, b.y, b.z + ballRadius * 0.5);
    final r = math.max(3.5, ballRadius * v.pxPerMeter(b.x, b.y, b.z));
    Effects.paintBall(canvas, c, r, fx: b.fx, alpha: alpha);
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => oldDelegate.scene != scene;
}
