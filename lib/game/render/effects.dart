import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../models/profile.dart';
import '../game_state.dart';
import '../physics.dart';
import 'court_view.dart';

class _Particle {
  double x, y, z, vx, vy, vz, life;
  final double maxLife, size, gravity;
  final Color color;
  _Particle(this.x, this.y, this.z, this.vx, this.vy, this.vz, this.maxLife, this.size, this.color,
      {this.gravity = 9.8})
      : life = maxLife;
}

class _Ring {
  final double x, y;
  double life;
  final double maxLife, radius;
  final Color color;
  _Ring(this.x, this.y, this.maxLife, this.radius, this.color) : life = maxLife;
}

class _Confetti {
  double x, y, vx, vy, rot, vr;
  final Color color;
  _Confetti(this.x, this.y, this.vx, this.vy, this.rot, this.vr, this.color);
}

/// Visual juice: ball trails, hit sparks, special-attack effects, bounce
/// rings, confetti, screen shake, and how excited the crowd is.
class Effects {
  final _rnd = math.Random();
  final List<_Particle> _particles = [];
  final List<_Ring> _rings = [];
  final List<List<double>> _trail = [];
  final List<_Confetti> _confetti = [];
  double shake = 0;
  double excitement = 0.15; // crowd energy 0..1
  double flash = 0; // white flash when a special fires
  Color flashColor = Colors.white;
  bool _confettiOn = false;

  void reset() {
    _particles.clear();
    _rings.clear();
    _trail.clear();
    _confetti.clear();
    _confettiOn = false;
    shake = 0;
    flash = 0;
    excitement = 0.15;
  }

  void _burst(Ball b, int n, double speed, Color color, {double size = 3, double life = 0.45}) {
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final sp = speed * (0.4 + _rnd.nextDouble());
      _particles.add(_Particle(b.x, b.y, b.z, math.cos(a) * sp, math.sin(a) * sp, 1 + _rnd.nextDouble() * 2.5,
          life * (0.7 + _rnd.nextDouble() * 0.6), size, color));
    }
  }

  void onEvent(GameEvent e, GameState s) {
    final ball = s.ball;
    switch (e.type) {
      case 'hit':
      case 'serve':
        _burst(ball, 12, 2.0, const Color(0xFFEFFF8A));
        if (s.rally > 5) excitement = math.min(1, excitement + 0.06);
      case 'smash':
        _burst(ball, 26, 3.5, const Color(0xFFFF8A3D), size: 4);
        shake = 0.35;
        excitement = math.min(1, excitement + 0.4);
      case 'special':
        final color = Color(SpecialSkill.values[e.kind].color);
        _burst(ball, 40, 4.5, color, size: 5, life: 0.7);
        shake = 0.45;
        flash = 0.35;
        flashColor = color;
        excitement = 1;
      case 'freeze':
        for (final p in s.players) {
          if (p.frozen > 0) {
            for (var i = 0; i < 18; i++) {
              final a = _rnd.nextDouble() * math.pi * 2;
              _particles.add(_Particle(p.x, p.y, 1.0 + _rnd.nextDouble(), math.cos(a) * 1.5, math.sin(a) * 1.5,
                  _rnd.nextDouble() * 2, 0.9, 3.5, const Color(0xFFE1F5FE), gravity: 2));
            }
          }
        }
      case 'bounce':
        final inCourt = e.x.abs() <= Court.halfW && e.y.abs() <= Court.halfL;
        _rings.add(_Ring(e.x, e.y, 0.6, 0.45, inCourt ? const Color(0xFFFFFFFF) : const Color(0xFFFF5252)));
      case 'net':
        shake = 0.18;
        excitement = math.min(1, excitement + 0.25);
      case 'point':
        excitement = math.min(1, excitement + 0.7);
      case 'game_over':
        excitement = 1;
        _startConfetti();
    }
  }

  void _startConfetti() {
    _confettiOn = true;
    const colors = [
      Color(0xFFD4F33A), Color(0xFF2D9CDB), Color(0xFFFF7A3D), Color(0xFFE040FB),
      Color(0xFFFFFFFF), Color(0xFF00E5A0),
    ];
    for (var i = 0; i < 160; i++) {
      _confetti.add(_Confetti(_rnd.nextDouble(), -_rnd.nextDouble() * 0.6, (_rnd.nextDouble() - 0.5) * 0.15,
          0.15 + _rnd.nextDouble() * 0.25, _rnd.nextDouble() * 6, (_rnd.nextDouble() - 0.5) * 8,
          colors[i % colors.length]));
    }
  }

  void update(double dt, GameState s, {bool gameOver = false}) {
    final ball = s.ball;
    final trackBall = !s.ballHeld && s.phase == Phase.rally;
    for (final p in _particles) {
      p.life -= dt;
      p.vz -= p.gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.z = math.max(0, p.z + p.vz * dt);
    }
    _particles.removeWhere((p) => p.life <= 0);
    for (final r in _rings) {
      r.life -= dt;
    }
    _rings.removeWhere((r) => r.life <= 0);
    if (trackBall && ball.speed > 4) {
      _trail.add([ball.x, ball.y, ball.z]);
    } else if (_trail.isNotEmpty) {
      _trail.removeAt(0);
    }
    while (_trail.length > (ball.fx != BallFx.none ? 14 : 9)) {
      _trail.removeAt(0);
    }
    // special-ball particles
    if (trackBall && ball.fx != BallFx.none && !ball.rolling) {
      switch (ball.fx) {
        case BallFx.fire:
          for (var i = 0; i < 3; i++) {
            _particles.add(_Particle(ball.x, ball.y, ball.z, (_rnd.nextDouble() - 0.5) * 1.2,
                (_rnd.nextDouble() - 0.5) * 1.2, 1.2 + _rnd.nextDouble(), 0.35, 4.5,
                i == 0 ? const Color(0xFFFFD54F) : const Color(0xFFFF5722), gravity: -2));
          }
        case BallFx.ice:
          _particles.add(_Particle(ball.x, ball.y, ball.z, (_rnd.nextDouble() - 0.5) * 0.8,
              (_rnd.nextDouble() - 0.5) * 0.8, 0, 0.6, 3, const Color(0xFFE1F5FE), gravity: 3));
        case BallFx.tornado:
          final a = s.phaseTime * 30;
          _particles.add(_Particle(ball.x + math.cos(a) * 0.35, ball.y, ball.z + math.sin(a) * 0.35, 0, 0, 0, 0.4,
              3, const Color(0xFF6BFFB0), gravity: 0));
      }
    }
    if (shake > 0) shake = math.max(0, shake - dt);
    if (flash > 0) flash = math.max(0, flash - dt);
    excitement = gameOver ? 1 : math.max(0.12, excitement - dt * 0.35);
    if (_confettiOn) {
      for (final c in _confetti) {
        c.x += c.vx * dt;
        c.y += c.vy * dt;
        c.rot += c.vr * dt;
        if (c.y > 1.1) {
          c.y = -0.05;
          c.x = _rnd.nextDouble();
        }
      }
    }
  }

  Offset shakeOffset() {
    if (shake <= 0) return Offset.zero;
    final m = shake * 14;
    return Offset((_rnd.nextDouble() - 0.5) * m, (_rnd.nextDouble() - 0.5) * m);
  }

  void paintGround(Canvas canvas, CourtView v) {
    for (final r in _rings) {
      final t = 1 - r.life / r.maxLife;
      final c = v.project(r.x, r.y, 0);
      final ppm = v.pxPerMeter(r.x, r.y, 0);
      final rad = (0.12 + r.radius * t) * ppm;
      canvas.drawOval(
          Rect.fromCenter(center: c, width: rad * 2, height: rad * 1.2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 * (1 - t) + 0.5
            ..color = r.color.withValues(alpha: (1 - t) * 0.9));
    }
  }

  static Color trailColor(int fx) => switch (fx) {
        BallFx.fire => const Color(0xFFFF6A1A),
        BallFx.ice => const Color(0xFF7FE3FF),
        BallFx.thunder => const Color(0xFFFFE94D),
        BallFx.phantom => const Color(0xFFB98CFF),
        BallFx.tornado => const Color(0xFF6BFFB0),
        _ => const Color(0xFFE8FF6A),
      };

  void paintTrail(Canvas canvas, CourtView v, double ballRadiusM, int fx) {
    final color = trailColor(fx);
    final strong = fx != BallFx.none && fx != BallFx.phantom;
    if (fx == BallFx.thunder && _trail.length > 2) {
      // jagged lightning bolt along the path
      final path = Path();
      for (var i = 0; i < _trail.length; i++) {
        final p = _trail[i];
        var o = v.project(p[0], p[1], p[2]);
        if (i > 0 && i < _trail.length - 1) o += Offset((_rnd.nextDouble() - 0.5) * 10, (_rnd.nextDouble() - 0.5) * 10);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..color = color.withValues(alpha: 0.35));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);
    }
    for (var i = 0; i < _trail.length; i++) {
      final p = _trail[i];
      final a = (i + 1) / (_trail.length + 1);
      final c = v.project(p[0], p[1], p[2]);
      final r = ballRadiusM * v.pxPerMeter(p[0], p[1], p[2]) * (0.4 + 0.6 * a) * (strong ? 1.6 : 1);
      canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: a * (strong ? 0.55 : fx == BallFx.phantom ? 0.12 : 0.35)));
    }
  }

  void paintParticles(Canvas canvas, CourtView v) {
    for (final p in _particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(v.project(p.x, p.y, p.z), p.size * a + 0.5, Paint()..color = p.color.withValues(alpha: a));
    }
  }

  void paintScreen(Canvas canvas, Size size, {double slowmo = 0}) {
    if (slowmo > 0) {
      // cinematic vignette during slow motion
      final k = slowmo.clamp(0.0, 1.0);
      final rect = Offset.zero & size;
      canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.radial(rect.center, size.longestSide * 0.6, [
              const Color(0x00000000),
              Color.fromRGBO(0, 0, 0, 0.55 * k),
            ], const [0.55, 1]));
    }
    if (flash > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = flashColor.withValues(alpha: flash * 0.9));
    }
    if (!_confettiOn) return;
    final paint = Paint();
    for (final c in _confetti) {
      paint.color = c.color;
      canvas.save();
      canvas.translate(c.x * size.width, c.y * size.height);
      canvas.rotate(c.rot);
      canvas.drawRect(const Rect.fromLTWH(-4, -2.5, 8, 5), paint);
      canvas.restore();
    }
  }

  static void paintBall(Canvas canvas, Offset c, double r, {int fx = BallFx.none, double alpha = 1}) {
    if (fx != BallFx.none && fx != BallFx.phantom) {
      final glow = trailColor(fx);
      canvas.drawCircle(
          c, r * 3, Paint()..shader = ui.Gradient.radial(c, r * 3, [glow.withValues(alpha: 0.7), glow.withValues(alpha: 0)]));
    }
    final colors = switch (fx) {
      BallFx.fire => const [Color(0xFFFFF59D), Color(0xFFFF9800), Color(0xFFD84315)],
      BallFx.ice => const [Color(0xFFFFFFFF), Color(0xFFB3E5FC), Color(0xFF4FC3F7)],
      BallFx.thunder => const [Color(0xFFFFFFFF), Color(0xFFFFEB3B), Color(0xFFFBC02D)],
      BallFx.tornado => const [Color(0xFFE8FFF3), Color(0xFF69F0AE), Color(0xFF00C853)],
      _ => const [Color(0xFFFBFFB0), Color(0xFFD9F23A), Color(0xFF9DB51C)],
    };
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c + Offset(-r * 0.35, -r * 0.35), r * 1.3,
              [for (final col in colors) col.withValues(alpha: alpha)], const [0, 0.55, 1]));
    if (r > 3.5 && alpha > 0.5) {
      final hole = Paint()..color = const Color(0x55556B00);
      for (var i = 0; i < 5; i++) {
        final a = i * 1.256 + 0.4;
        canvas.drawCircle(c + Offset(math.cos(a) * r * 0.5, math.sin(a) * r * 0.5), r * 0.14, hole);
      }
      canvas.drawCircle(c, r * 0.13, hole);
    }
  }
}
