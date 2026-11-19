// The AI opponent. Every decision goes through PickleBrain:
//  * the trajectory network tells it where/when it can meet the ball at
//    several depths, so it picks a legal, comfortable contact point
//    (respecting the two-bounce rule and the kitchen rule);
//  * the shot network picks power / soft / high and left / centre / right.
// In doubles it shares the court with a partner (human or AI): whoever is
// closer to the contact point takes the ball, the other covers its half.
// Difficulty only changes reaction time, speed, noise and randomness.
import 'dart:math' as math;

import '../../models/profile.dart';
import '../game_state.dart';
import '../physics.dart';
import '../shot_planner.dart';
import 'brain.dart';

class AiDifficulty {
  final String id;
  final String label;
  final double reaction; // seconds before reacting to a new shot
  final double speedMul; // movement speed multiplier (never above the stats)
  final double noiseMul; // shot execution error multiplier
  final double temperature; // randomness of shot choice
  final double predictNoise; // metres of misjudged contact point
  final bool attacksNet; // moves up to the kitchen line
  final double specialUse; // chance to fire a ready special at a good moment

  const AiDifficulty(this.id, this.label, this.reaction, this.speedMul, this.noiseMul,
      this.temperature, this.predictNoise, this.attacksNet, this.specialUse);

  static const easy = AiDifficulty('easy', 'Easy', 0.45, 0.80, 1.9, 1.4, 0.40, false, 0.35);
  static const medium = AiDifficulty('medium', 'Medium', 0.32, 0.90, 1.35, 0.8, 0.22, true, 0.5);
  static const hard = AiDifficulty('hard', 'Hard', 0.22, 0.95, 1.0, 0.45, 0.10, true, 0.7);
  static const pro = AiDifficulty('pro', 'Pro', 0.15, 1.0, 0.75, 0.25, 0.05, true, 0.85);
  static const all = [easy, medium, hard, pro];

  int get stars => all.indexOf(this) + 1;

  static AiDifficulty byId(String id) => all.firstWhere((d) => d.id == id, orElse: () => medium);
}

/// Playing style: multiplies the network's probabilities per shot kind.
class AiStyle {
  final double drive, soft, lob;
  const AiStyle(this.drive, this.soft, this.lob);
  static const balanced = AiStyle(1, 1, 1);
}

class AiController {
  final PickleBrain brain;
  final AiDifficulty diff;
  final AiStyle style;
  final int me;
  final math.Random rng;
  final PlayerInput _out = PlayerInput();

  int _seenShot = -1;
  double _react = 0;
  double _think = 0;
  double _nx = 0, _ny = 0;
  bool _hasPlan = false;
  bool _mine = true; // doubles: is this ball mine to take?
  double _cx = 0, _cy = -6.5, _cz = 0.9, _ct = 1;
  double _serveWait = 0;
  double _serveDelay = 1.2;
  int _chosenFor = -1;
  bool _letGo = false; // ball predicted to land out: don't touch it
  ShotKind _chosen = ShotKind.drive;
  double _chosenAim = 0;
  double _chosenDepth = 0;

  /// Last decision, for the "AI thoughts" overlay.
  String lastThought = '';

  AiController(this.brain, this.diff, this.me, {this.style = AiStyle.balanced, math.Random? random})
      : rng = random ?? math.Random();

  double _gauss() {
    final u1 = math.max(rng.nextDouble(), 1e-9);
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * rng.nextDouble());
  }

  PlayerInput update(GameState s, PlayerProfile profile, double dt) {
    _out.clearEdge();
    final p = s.players[me];
    final partner = s.partnerOf(me);
    final sg = -p.side.toDouble(); // world -> canonical (AI on y < 0)
    final mx = p.x * sg, my = p.y * sg;
    final speed = profile.stats.runSpeed * diff.speedMul * (p.frozen > 0 ? 0.35 : 1.0);
    final laneX = s.doubles ? p.lane * 1.5 : 0.0;
    var tx = mx, ty = my;

    switch (s.phase) {
      case Phase.serve:
        _seenShot = -1;
        if (s.server == me) {
          _serveWait += dt * 0.9;
          if (_serveWait > _serveDelay) {
            _serveWait = 0;
            _serveDelay = 0.9 + rng.nextDouble() * 0.9;
            _out.shot = _pickServe();
            _out.aim = (rng.nextDouble() * 1.4 - 0.7);
          }
        } else {
          _serveWait = 0;
          tx = mx;
          ty = my; // stay where the serve formation put us
        }
      case Phase.pointOver:
      case Phase.gameOver:
        tx = mx * 0.98;
        ty = my;
      case Phase.rally:
        final b = s.ball;
        final bx = b.x * sg, by = b.y * sg, bvx = b.vx * sg, bvy = b.vy * sg;
        if (s.hittingTeam != p.team) {
          if (s.shotCount != _seenShot) {
            _seenShot = s.shotCount;
            _react = diff.reaction * (0.75 + 0.5 * rng.nextDouble());
            _nx = _gauss() * diff.predictNoise;
            _ny = _gauss() * diff.predictNoise * 0.6;
            _hasPlan = false;
            _letGo = false;
            _mine = true;
            _think = 0;
          }
          if (_react > 0) {
            _react -= dt;
            final (rx, ry) = _readyPosition(s, bx, laneX);
            tx = rx;
            ty = ry;
          } else {
            _think -= dt;
            if (_think <= 0) {
              _plan(s, bx, by, b.z, bvx, bvy, b.vz, mx, my, speed);
              _think = 0.07;
              if (partner != null && _hasPlan) {
                final pdx = partner.x * sg - _cx, pdy = partner.y * sg - _cy;
                final mdx = mx - _cx, mdy = my - _cy;
                final pd = math.sqrt(pdx * pdx + pdy * pdy), md = math.sqrt(mdx * mdx + mdy * mdy);
                // hysteresis so the partners don't keep swapping
                _mine = _mine ? md <= pd + 0.35 : md < pd - 0.35;
              }
            }
            if (_hasPlan && _mine) {
              tx = _cx - 0.42 + _nx;
              ty = _cy + _ny;
            } else {
              final (rx, ry) = _readyPosition(s, bx, laneX);
              tx = rx;
              ty = ry;
            }
            final dBall = math.sqrt((bx - mx) * (bx - mx) + (by - my) * (by - my));
            final volleyNow = s.bouncesOnReceiver == 0;
            final kitchenVolley = volleyNow && my.abs() < Court.kitchen + 0.05;
            if (_hasPlan && _mine && !_letGo && !kitchenVolley && (dBall < 2.2 || _ct < 0.35)) {
              if (_chosenFor != s.shotCount) {
                _chooseShot(s, sg, profile, b.speed);
                _chosenFor = s.shotCount;
                _maybeSpecial(s, p, profile, sg);
              }
              _out.shot = _chosen;
              _out.aim = _chosenAim;
              _out.depth = _chosenDepth;
            }
          }
        } else {
          final (rx, ry) = _readyPosition(s, bx, laneX);
          tx = rx;
          ty = ry;
        }
    }

    // steer toward the target (canonical frame == the AI's own frame)
    final dx = tx - mx, dy = ty - my;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 0.05) {
      _out.mx = 0;
      _out.my = 0;
    } else {
      final k = math.min(1.0, d / 0.45);
      _out.mx = dx / d * k;
      _out.my = dy / d * k;
    }
    if (_out.shot == null && s.phase == Phase.rally && _hasPlan) {
      _out.aim = _chosenAim;
      _out.depth = _chosenDepth;
    }
    return _out;
  }

  ShotKind _pickServe() {
    final w = [0.45 * style.drive, 0.45 * style.soft, 0.10 * style.lob];
    final r = rng.nextDouble() * (w[0] + w[1] + w[2]);
    if (r < w[0]) return ShotKind.drive;
    if (r < w[0] + w[1]) return ShotKind.soft;
    return ShotKind.lob;
  }

  (double, double) _readyPosition(GameState s, double ballX, double laneX) {
    final myTeam = s.players[me].team;
    final iServed = s.shotCount == 1 && s.hittingTeam == myTeam;
    final returning = s.shotCount == 1 && s.hittingTeam != myTeam;
    final x = s.doubles ? laneX + ballX * 0.25 : ballX * 0.3;
    if (iServed) return (x, -6.6); // serving team waits for the return to bounce
    if (returning) return (x, s.doubles && s.players[me].y.abs() < 4 ? -2.5 : -6.6);
    if (diff.attacksNet && s.shotCount >= 2) return (x, -2.5);
    return (x, -6.2);
  }

  static const _planes = [
    -0.6, -1.2, -1.8, -2.35, -2.8, -3.4, -4.2, -5.0, -5.8, -6.5, -7.2, -7.9, -8.6
  ];

  void _plan(GameState s, double bx, double by, double bz, double vx, double vy, double vz,
      double mx, double my, double speed) {
    if (vy > -0.3 && s.ball.y * s.players[me].side <= 0) {
      return; // ball not coming yet
    }
    final bounced = s.bouncesOnReceiver;
    final must = s.mustBounce;
    double bestScore = -1e9;
    PlanePrediction? best;
    double bestY = 0;
    PlanePrediction? any;
    for (final yp in _planes) {
      if (yp >= by - 0.05) continue;
      final pr = brain.predict(bx, by, bz, vx, vy, vz, yp);
      if (any == null) {
        any = pr;
        // Is the ball going out? (the network also predicts the bounce spot)
        if (bounced == 0 && !must && s.ball.curve == 0) {
          final margin = math.max(pr.bounceX.abs() - Court.halfW, -pr.bounceY - Court.halfL);
          final judgesWell = diff.predictNoise < 0.3 || rng.nextDouble() < 0.5;
          _letGo = pr.bounceY < 0 && margin > 0.15 && judgesWell;
        } else {
          _letGo = false;
        }
      }
      if (pr.reach < 0.5) continue;
      final nb = bounced + pr.likelyBounces;
      if (nb >= 2) continue;
      if (must && nb == 0) continue;
      if (nb == 0 && yp.abs() < Court.kitchen + 0.12) continue;
      if (pr.z < 0.12 || pr.z > 2.25) continue;
      final sx = pr.x - 0.42;
      final travel = math.sqrt((sx - mx) * (sx - mx) + (yp - my) * (yp - my));
      final slack = pr.t - travel / speed;
      if (slack < -0.08) continue;
      var score = math.min(slack, 0.5) * 1.2 - (pr.z - 0.95).abs() * 0.9;
      if (diff.attacksNet) {
        if (nb == 0) score += 0.25;
        if (yp.abs() >= 2.2 && yp.abs() <= 3.2) score += 0.25;
      }
      if (yp.abs() > 7.2) score -= 0.25;
      if (score > bestScore) {
        bestScore = score;
        best = pr;
        bestY = yp;
      }
    }
    if (best != null) {
      _cx = best.x;
      _cy = bestY;
      _cz = best.z;
      _ct = best.t;
      _hasPlan = true;
      lastThought = 'meet ball at (${_cx.toStringAsFixed(1)}, ${_cy.toStringAsFixed(1)}) '
          'h=${_cz.toStringAsFixed(2)}m in ${_ct.toStringAsFixed(2)}s';
    } else if (any != null) {
      // no comfortable option: chase the bounce
      _cx = any.bounceX;
      _cy = math.max(any.bounceY - 1.2, -8.6);
      _cz = 0.5;
      _ct = any.bounceT;
      _hasPlan = true;
      lastThought = 'scramble to the bounce';
    }
  }

  /// Average opponent position in the canonical frame.
  (double, double) _opponents(GameState s, double sg) {
    final myTeam = s.players[me].team;
    var ox = 0.0, oy = 0.0, k = 0;
    for (final o in s.players) {
      if (o.team == myTeam) continue;
      ox += o.x * sg;
      oy += o.y * sg;
      k++;
    }
    return (ox / k, oy / k);
  }

  void _chooseShot(GameState s, double sg, PlayerProfile profile, double inSpeed) {
    final (ox, oy) = _opponents(s, sg);
    final features = [
      _cx,
      _cy,
      _cz,
      ox,
      oy,
      inSpeed,
      s.shotCount <= 1 ? 1.0 : 0.0,
      profile.stats.power.toDouble(),
      profile.stats.control.toDouble(),
    ];
    final probs = brain.shotProbabilities(features);
    final weights = List<double>.filled(9, 0);
    var total = 0.0;
    for (var i = 0; i < 9; i++) {
      final bias = switch (i ~/ 3) { 0 => style.drive, 1 => style.soft, _ => style.lob };
      weights[i] = math.pow(math.max(probs[i], 1e-9), 1 / diff.temperature).toDouble() * bias;
      total += weights[i];
    }
    var r = rng.nextDouble() * total;
    var pick = 8;
    for (var i = 0; i < 9; i++) {
      r -= weights[i];
      if (r <= 0) {
        pick = i;
        break;
      }
    }
    _chosen = ShotKind.values[pick ~/ 3];
    _chosenAim = (pick % 3 - 1).toDouble();
    // tactics: drop it short when they're deep, push them back when they crowd the net
    _chosenDepth = switch (_chosen) {
      ShotKind.soft => oy > 4.5 ? -0.8 : 0.0,
      ShotKind.drive => oy < 3.5 ? -0.4 : 0.3,
      ShotKind.lob => 0.3,
    };
    const zones = ['left', 'centre', 'right'];
    lastThought = '${_chosen.label} ${zones[pick % 3]} (${(probs[pick] * 100).toStringAsFixed(0)}%)';
  }

  void _maybeSpecial(GameState s, PlayerState p, PlayerProfile profile, double sg) {
    if (p.meter < 1 || p.specialArmed) return;
    final (_, oy) = _opponents(s, sg);
    final good = switch (profile.special) {
      SpecialSkill.fireSmash => _cz > 0.55,
      SpecialSkill.iceFreeze => true,
      SpecialSkill.thunderCurve => true,
      SpecialSkill.phantomDrop => oy > 4.0,
      SpecialSkill.tornadoLob => oy < 4.0,
    };
    if (good && rng.nextDouble() < diff.specialUse) {
      _out.special = true;
      lastThought = 'SPECIAL: ${profile.special.label}!';
    }
  }
}
