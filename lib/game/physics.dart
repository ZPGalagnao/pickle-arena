// Ball physics shared by the game, the AI and the network client.
//
// This is a 1:1 port of training/pickle_sim.py. Gravity + linear drag has a
// closed-form solution, so the ball is advanced exactly (no integration drift)
// and the neural network trained in Python predicts this ball perfectly.
import 'dart:math' as math;

class Phys {
  static const double g = 9.81;
  static const double drag = 0.30;
  static const double gt = g / drag;
  static const double restitution = 0.70;
  static const double friction = 0.80;
  static const double rollVz = 0.35;
  static const double rollDrag = 2.4;
}

class Court {
  static const double halfW = 3.05;
  static const double halfL = 6.705;
  static const double kitchen = 2.134;
  static const double netH = 0.88;
  static const double netHalfSpan = 3.35; // net + posts
  static const double playerMaxX = 4.4;
  static const double playerMaxY = 8.9;
  static const double playerMinY = 0.25;

  static bool inCourt(double x, double y, int side) =>
      x.abs() <= halfW && y * side >= 0 && y.abs() <= halfL;
}

class Ball {
  double x, y, z, vx, vy, vz;
  bool rolling;

  Ball({
    this.x = 0,
    this.y = 0,
    this.z = 1,
    this.vx = 0,
    this.vy = 0,
    this.vz = 0,
    this.rolling = false,
  });

  Ball copy() =>
      Ball(x: x, y: y, z: z, vx: vx, vy: vy, vz: vz, rolling: rolling);

  void setFrom(Ball o) {
    x = o.x;
    y = o.y;
    z = o.z;
    vx = o.vx;
    vy = o.vy;
    vz = o.vz;
    rolling = o.rolling;
  }

  double get speed => math.sqrt(vx * vx + vy * vy + vz * vz);
}

enum BallEventType { bounce, net }

class BallEvent {
  final BallEventType type;
  final double x, y;
  final bool startedRolling;
  const BallEvent(this.type, this.x, this.y, {this.startedRolling = false});
}

class BallPhysics {
  static double kfac(double t) => (1.0 - math.exp(-Phys.drag * t)) / Phys.drag;

  /// Exact free flight for time [t] (ignores the ground).
  static void propagate(Ball b, double t) {
    final e = math.exp(-Phys.drag * t);
    final k = (1.0 - e) / Phys.drag;
    final a = b.vz + Phys.gt;
    b.x += b.vx * k;
    b.y += b.vy * k;
    b.z += a * k - Phys.gt * t;
    b.vx *= e;
    b.vy *= e;
    b.vz = a * e - Phys.gt;
  }

  static double heightAfter(double z, double vz, double t) {
    final k = kfac(t);
    return z + (vz + Phys.gt) * k - Phys.gt * t;
  }

  /// First t > 0 with z(t) = 0 (Newton from the drag-free landing time).
  static double timeToGround(double z, double vz) {
    var t = (vz + math.sqrt(math.max(vz * vz + 2 * Phys.g * math.max(z, 0), 0))) /
        Phys.g;
    t = math.max(t, 1e-3);
    final a = vz + Phys.gt;
    for (var i = 0; i < 14; i++) {
      final e = math.exp(-Phys.drag * t);
      final f = z + a * (1 - e) / Phys.drag - Phys.gt * t;
      var fp = a * e - Phys.gt;
      if (fp.abs() < 1e-9) fp = -1e-9;
      t = math.max(t - f / fp, 1e-5);
    }
    return t;
  }

  static void _bounce(Ball b) {
    b.z = 0;
    b.vx *= Phys.friction;
    b.vy *= Phys.friction;
    b.vz = -b.vz * Phys.restitution;
  }

  /// Advance the ball by [dt] seconds, resolving bounces and net hits
  /// exactly. Returns the events that happened during the step.
  static List<BallEvent> step(Ball b, double dt, {bool netActive = true}) {
    final events = <BallEvent>[];
    var rem = dt;
    var guard = 0;
    while (rem > 1e-9 && guard++ < 8) {
      if (b.rolling) {
        const c = Phys.drag + Phys.rollDrag;
        final e = math.exp(-c * rem);
        b.x += b.vx * (1 - e) / c;
        b.y += b.vy * (1 - e) / c;
        b.vx *= e;
        b.vy *= e;
        b.z = 0;
        b.vz = 0;
        break;
      }
      double? tGround;
      if (heightAfter(b.z, b.vz, rem) < 0) {
        tGround = math.min(timeToGround(b.z, b.vz), rem);
      }
      double? tNet;
      if (netActive && b.y != 0 && b.vy != 0) {
        final yEnd = b.y + b.vy * kfac(rem);
        if (yEnd.sign != b.y.sign) {
          final ratio = -b.y * Phys.drag / b.vy;
          if (ratio > 0 && ratio < 1) {
            final t = -math.log(1 - ratio) / Phys.drag;
            final probe = b.copy();
            propagate(probe, t);
            if (probe.z < Court.netH &&
                probe.z > -0.02 &&
                probe.x.abs() <= Court.netHalfSpan &&
                (tGround == null || t < tGround)) {
              tNet = t;
            }
          }
        }
      }
      if (tNet != null) {
        final side = b.y.sign;
        propagate(b, tNet);
        b.y = side * 0.04;
        b.vy = -b.vy * 0.12;
        b.vx *= 0.35;
        b.vz = math.min(b.vz, 0) * 0.3;
        events.add(BallEvent(BallEventType.net, b.x, 0));
        rem -= tNet;
        continue;
      }
      if (tGround != null) {
        propagate(b, tGround);
        _bounce(b);
        var rolled = false;
        if (b.vz < Phys.rollVz) {
          b.rolling = true;
          b.vz = 0;
          rolled = true;
        }
        events.add(BallEvent(BallEventType.bounce, b.x, b.y,
            startedRolling: rolled));
        rem -= tGround;
        continue;
      }
      propagate(b, rem);
      rem = 0;
    }
    return events;
  }

  /// Where and when the ball touches the ground next.
  static (double x, double y, double t) nextBounce(Ball b) {
    if (b.rolling) return (b.x, b.y, 0);
    final t = timeToGround(b.z, b.vz);
    final p = b.copy();
    propagate(p, t);
    return (p.x, p.y, t);
  }
}
