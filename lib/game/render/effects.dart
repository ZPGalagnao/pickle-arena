import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../game_state.dart';
import '../physics.dart';
import 'court_view.dart';

class _Particle {
  double x, y, z, vx, vy, vz, life;
  final double maxLife, size;
  final Color color;
  _Particle(this.x, this.y, this.z, this.vx, this.vy, this.vz, this.maxLife, this.size, this.color)
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

/// Visual juice: ball trail, hit sparks, bounce rings, confetti, screen shake.
class Effects {
  final _rnd = math.Random();
  final List<_Particle> _particles = [];
  final List<_Ring> _rings = [];
  final List<List<double>> _trail = [];
  final List<_Confetti> _confetti = [];
  double shake = 0;
  bool _confettiOn = false;

  void reset() {
    _particles.clear();
    _rings.clear();
    _trail.clear();
    _confetti.clear();
    _confettiOn = false;
    shake = 0;
  }

  void onEvent(GameEvent e, Ball ball) {
    switch (e.type) {
      case 'hit':
      case 'serve':
      case 'smash':
        final smash = e.type == 'smash';
        final n = smash ? 26 : 12;
        for (var i = 0; i < n; i++) {
          final a = _rnd.nextDouble() * math.pi * 2;
          final sp = (smash ? 3.5 : 2.0) * (0.4 + _rnd.nextDouble());
          _particles.add(_Particle(ball.x, ball.y, ball.z, math.cos(a) * sp, math.sin(a) * sp,
              1 + _rnd.nextDouble() * 2.5, 0.35 + _rnd.nextDouble() * 0.25, smash ? 4 : 3,
              smash ? const Color(0xFFFF8A3D) : const Color(0xFFEFFF8A)));
        }
        if (smash) shake = 0.35;
      case 'bounce':
        final inCourt = e.x.abs() <= Court.halfW && e.y.abs() <= Court.halfL;
        _rings.add(_Ring(e.x, e.y, 0.6, 0.45,
            inCourt ? const Color(0xFFFFFFFF) : const Color(0xFFFF5252)));
      case 'net':
        shake = 0.18;
      case 'game_over':
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
      _confetti.add(_Confetti(_rnd.nextDouble(), -_rnd.nextDouble() * 0.6,
          (_rnd.nextDouble() - 0.5) * 0.15, 0.15 + _rnd.nextDouble() * 0.25,
          _rnd.nextDouble() * 6, (_rnd.nextDouble() - 0.5) * 8, colors[i % colors.length]));
    }
  }

  void update(double dt, Ball ball, bool trackBall) {
    for (final p in _particles) {
      p.life -= dt;
      p.vz -= 9.8 * dt;
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
    while (_trail.length > 9) {
      _trail.removeAt(0);
    }
    if (shake > 0) shake = math.max(0, shake - dt);
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

  void paintTrail(Canvas canvas, CourtView v, double ballRadiusM) {
    for (var i = 0; i < _trail.length; i++) {
      final p = _trail[i];
      final a = (i + 1) / (_trail.length + 1);
      final c = v.project(p[0], p[1], p[2]);
      final r = ballRadiusM * v.pxPerMeter(p[0], p[1], p[2]) * (0.4 + 0.6 * a);
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFE8FF6A).withValues(alpha: a * 0.35));
    }
  }

  void paintParticles(Canvas canvas, CourtView v) {
    for (final p in _particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(v.project(p.x, p.y, p.z), p.size * a + 0.5,
          Paint()..color = p.color.withValues(alpha: a));
    }
  }

  void paintScreen(Canvas canvas, Size size) {
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

  static void paintBall(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c + Offset(-r * 0.35, -r * 0.35), r * 1.3,
              const [Color(0xFFFBFFB0), Color(0xFFD9F23A), Color(0xFF9DB51C)], const [0, 0.55, 1]));
    if (r > 3.5) {
      final hole = Paint()..color = const Color(0x55556B00);
      for (var i = 0; i < 5; i++) {
        final a = i * 1.256 + 0.4;
        canvas.drawCircle(c + Offset(math.cos(a) * r * 0.5, math.sin(a) * r * 0.5), r * 0.14, hole);
      }
      canvas.drawCircle(c, r * 0.13, hole);
    }
  }
}
