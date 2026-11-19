// Turns "hit a DRIVE to that spot" into a launch velocity.
// Port of plan_shot() in training/pickle_sim.py - keep both in sync.
import 'dart:math' as math;

import 'physics.dart';

enum ShotKind { drive, soft, lob }

extension ShotKindLabel on ShotKind {
  String get label => switch (this) {
        ShotKind.drive => 'DRIVE',
        ShotKind.soft => 'DINK',
        ShotKind.lob => 'LOB',
      };
}

class ShotPlan {
  final double vx, vy, vz, flightTime;
  const ShotPlan(this.vx, this.vy, this.vz, this.flightTime);
}

class ShotPlanner {
  static const double tMin = 0.35;
  static const double tMax = 3.2;

  /// Execution-noise model (same numbers as training/train_ai.py).
  static const noiseX = [0.40, 0.28, 0.45];
  static const noiseY = [0.45, 0.30, 0.50];
  static const noiseC = [0.07, 0.06, 0.10];

  /// Zone aim lines used by the AI (left / centre / right).
  static const double zoneX = 2.0;

  static double noiseFactor(double control, double inSpeed, double contactZ) =>
      (1.30 - 0.06 * control) *
      (1.0 + inSpeed / 25.0) *
      (1.0 + math.max(0.0, 0.6 - contactZ) * 0.6);

  static (double, double, double) velocityFor(
      double x0, double y0, double z0, double tx, double ty, double t) {
    final k = BallPhysics.kfac(t);
    return ((tx - x0) / k, (ty - y0) / k, (Phys.gt * t - z0) / k - Phys.gt);
  }

  static double _clearance(
      double x0, double y0, double z0, double tx, double ty, double t) {
    final (vx, vy, vz) = velocityFor(x0, y0, z0, tx, ty, t);
    final ratio = (-y0 * Phys.drag / (vy == 0 ? 1e-9 : vy)).clamp(0.0, 0.999999);
    final tn = -math.log(1 - ratio) / Phys.drag;
    final zn = BallPhysics.heightAfter(z0, vz, tn);
    return zn - Court.netH;
  }

  static double _speed(
      double x0, double y0, double z0, double tx, double ty, double t) {
    final (vx, vy, vz) = velocityFor(x0, y0, z0, tx, ty, t);
    return math.sqrt(vx * vx + vy * vy + vz * vz);
  }

  static double solveFlightTime(double x0, double y0, double z0, double tx,
      double ty, double clearance, double vmax, double tFloor) {
    var lo = tMin, hi = tMax;
    for (var i = 0; i < 30; i++) {
      final mid = 0.5 * (lo + hi);
      if (_clearance(x0, y0, z0, tx, ty, mid) >= clearance) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    final tClear = hi;
    lo = tMin;
    hi = 1.5;
    for (var i = 0; i < 30; i++) {
      final mid = 0.5 * (lo + hi);
      if (_speed(x0, y0, z0, tx, ty, mid) <= vmax) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    final tSpeed = hi;
    return math.max(math.max(tClear, tSpeed), tFloor);
  }

  /// Distance past the net that each shot aims for.
  static double defaultDepth(ShotKind kind, double hitterY) => switch (kind) {
        ShotKind.drive => 5.3,
        ShotKind.soft => hitterY.abs() < 4.0 ? 1.3 : 1.6,
        ShotKind.lob => 5.6,
      };

  static ShotPlan plan(ShotKind kind, double x0, double y0, double z0,
      double tx, double ty,
      {double power = 4, double clearanceOffset = 0, double? vmaxOverride, double? clearanceOverride}) {
    final clearance = clearanceOverride ??
        switch (kind) {
          ShotKind.drive => 0.20,
          ShotKind.soft => 0.28,
          ShotKind.lob => 0.60,
        };
    final vmax = vmaxOverride ??
        switch (kind) {
          ShotKind.drive => 15.0 + 1.0 * power,
          ShotKind.soft => 13.0,
          ShotKind.lob => 16.0,
        };
    final dist = math.sqrt((tx - x0) * (tx - x0) + (ty - y0) * (ty - y0));
    final tFloor = switch (kind) {
      ShotKind.drive => tMin,
      ShotKind.soft => 0.6 + 0.07 * dist,
      ShotKind.lob => 1.85 + 0.03 * dist,
    };
    final t = solveFlightTime(
        x0, y0, z0, tx, ty, clearance + clearanceOffset, vmax, tFloor);
    final (vx, vy, vz) = velocityFor(x0, y0, z0, tx, ty, t);
    return ShotPlan(vx, vy, vz, t);
  }
}
