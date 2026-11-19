// Authoritative pickleball simulation: movement, hitting, rules and scoring.
// Runs on the phone in AI mode and on the HOST phone in Wi-Fi multiplayer.
import 'dart:math' as math;

import '../models/profile.dart';
import 'game_state.dart';
import 'physics.dart';
import 'shot_planner.dart';

class MatchConfig {
  int pointsToWin;
  bool rallyScoring;
  double gameSpeed;

  MatchConfig({this.pointsToWin = 11, this.rallyScoring = true, this.gameSpeed = 0.9});

  Map<String, dynamic> toJson() =>
      {'points': pointsToWin, 'rally': rallyScoring, 'speed': gameSpeed};

  factory MatchConfig.fromJson(Map<String, dynamic> j) => MatchConfig(
        pointsToWin: j['points'] as int? ?? 11,
        rallyScoring: j['rally'] as bool? ?? true,
        gameSpeed: (j['speed'] as num?)?.toDouble() ?? 0.9,
      );
}

class GameEngine {
  static const double dt = 1 / 120;
  static const double reach = 1.05;
  static const double armWindow = 0.45;

  final MatchConfig config;
  final List<PlayerProfile> profiles;
  final List<double> noiseMul;
  final List<double> speedMul;
  final List<bool> autoHit;
  final GameState s = GameState();
  final math.Random rng;
  final List<GameEvent> _pending = [];
  double _acc = 0;
  int _seq = 0;
  double _deadTime = 0;
  List<PlayerInput> _inputs = [PlayerInput(), PlayerInput()];

  GameEngine({
    required this.config,
    required this.profiles,
    List<double>? noiseMul,
    List<double>? speedMul,
    List<bool>? autoHit,
    int? firstServer,
    math.Random? random,
  })  : noiseMul = noiseMul ?? [1, 1],
        speedMul = speedMul ?? [1, 1],
        autoHit = autoHit ?? [true, true],
        rng = random ?? math.Random() {
    s.server = firstServer ?? rng.nextInt(2);
    _startPoint();
    s.banner = '${profiles[s.server].name} serves first';
    s.bannerTime = 1.8;
  }

  /// Events since the last call (for the UI on this phone).
  List<GameEvent> drainEvents() {
    final out = List<GameEvent>.of(_pending);
    _pending.clear();
    return out;
  }

  void update(double frameDt, List<PlayerInput> inputs) {
    _inputs = inputs;
    for (var i = 0; i < 2; i++) {
      _applyButtons(i, inputs[i]);
    }
    _acc += math.min(frameDt, 0.05) * config.gameSpeed;
    while (_acc >= dt) {
      _acc -= dt;
      _tick(dt);
    }
  }

  // ------------------------------------------------------------------ input
  void _applyButtons(int i, PlayerInput inp) {
    final shot = inp.shot;
    if (shot == null) return;
    final p = s.players[i];
    if (s.phase == Phase.serve && s.server == i && s.phaseTime > 0.5) {
      _serve(i, shot, inp.aim);
    } else if (s.phase == Phase.rally) {
      p.armed = armWindow;
      p.armedKind = shot;
    }
  }

  // ------------------------------------------------------------------- tick
  void _tick(double dt) {
    s.phaseTime += dt;
    if (s.bannerTime > 0) s.bannerTime -= dt;
    for (var i = 0; i < 2; i++) {
      final p = s.players[i];
      final locked = s.phase == Phase.gameOver ||
          (s.phase == Phase.serve && s.server == i);
      movePlayer(p, _inputs[i], profiles[i].stats.runSpeed * speedMul[i], dt,
          locked: locked);
      if (p.swing > 0) p.swing = math.max(0, p.swing - dt);
    }

    if (s.ballHeld) {
      final srv = s.players[s.server];
      s.ball
        ..x = srv.x + 0.32 * -srv.side
        ..y = srv.y - srv.side * 0.25
        ..z = 0.95 + 0.06 * math.sin(s.phaseTime * 5)
        ..vx = 0
        ..vy = 0
        ..vz = 0
        ..rolling = false;
    } else {
      final events =
          BallPhysics.step(s.ball, dt, netActive: s.phase == Phase.rally);
      for (final ev in events) {
        _onBallEvent(ev);
      }
    }

    if (s.phase == Phase.rally) {
      _tryHits(dt);
      if (s.ball.rolling) {
        _deadTime += dt;
        if (_deadTime > 1.5) {
          // safety net: a dead ball loses for the player on that side
          final side = s.ball.y >= 0 ? 1 : -1;
          final loser = s.players[0].side == side ? 0 : 1;
          _pointTo(1 - loser, 'WINNER!');
        }
      } else {
        _deadTime = 0;
      }
    } else if (s.phase == Phase.pointOver && s.phaseTime > 1.8) {
      if (s.winner >= 0) {
        s.phase = Phase.gameOver;
        s.phaseTime = 0;
        s.banner = '${profiles[s.winner].name} WINS!';
        s.bannerTime = 999;
        _emit('game_over', player: s.winner, text: s.banner);
      } else {
        _startPoint();
      }
    }
  }

  /// Shared with the network client for local movement prediction.
  static void movePlayer(PlayerState p, PlayerInput inp, double speed, double dt,
      {bool locked = false}) {
    var dx = inp.mx * -p.side;
    var dy = inp.my * -p.side;
    final mag = math.sqrt(dx * dx + dy * dy);
    if (mag > 1) {
      dx /= mag;
      dy /= mag;
    }
    final tvx = locked ? 0.0 : dx * speed;
    final tvy = locked ? 0.0 : dy * speed;
    const accel = 26.0;
    var ax = tvx - p.vx, ay = tvy - p.vy;
    final am = math.sqrt(ax * ax + ay * ay);
    final maxDv = accel * dt;
    if (am > maxDv) {
      ax *= maxDv / am;
      ay *= maxDv / am;
    }
    p.vx += ax;
    p.vy += ay;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    p.x = p.x.clamp(-Court.playerMaxX, Court.playerMaxX);
    if (p.side < 0) {
      p.y = p.y.clamp(-Court.playerMaxY, -Court.playerMinY);
    } else {
      p.y = p.y.clamp(Court.playerMinY, Court.playerMaxY);
    }
    final v = math.sqrt(p.vx * p.vx + p.vy * p.vy);
    p.runPhase += v * dt * 2.2;
  }

  // ---------------------------------------------------------------- hitting
  void _tryHits(double dt) {
    final b = s.ball;
    for (var i = 0; i < 2; i++) {
      final p = s.players[i];
      if (p.armed > 0) p.armed = math.max(0, p.armed - dt);
      if (s.phase != Phase.rally) return;
      if (s.lastHitter == i || b.y * p.side <= 0 || b.rolling) {
        p.prevBallDist = 99;
        continue;
      }
      if (s.mustBounce && s.bouncesOnReceiver == 0) continue;
      if (s.bouncesOnReceiver >= 2) continue;
      final dx = b.x - p.x, dy = b.y - p.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      final passing = dist > p.prevBallDist + 1e-4;
      p.prevBallDist = dist;
      final inReach = dist <= reach && b.z >= 0.05 && b.z <= 2.35;
      if (!inReach) continue;
      final goodMoment =
          dist < 0.62 || passing || (b.z < 0.14 && b.vz < 0);
      if (p.armed > 0) {
        if (goodMoment || p.armed < 0.03) {
          _hit(i, p.armedKind, _inputs[i].aim, dist);
        }
      } else if (autoHit[i] && goodMoment && _assistShouldSwing(i)) {
        _hit(i, autoShot(i), _inputs[i].aim, dist);
      }
    }
  }

  /// The assist never volleys from the kitchen and lets clearly-out balls go.
  bool _assistShouldSwing(int i) {
    if (s.bouncesOnReceiver > 0) return true;
    final p = s.players[i];
    if (p.y.abs() < Court.kitchen) return false;
    final (bx, by, _) = BallPhysics.nextBounce(s.ball);
    final out = bx.abs() > Court.halfW + 0.3 || by.abs() > Court.halfL + 0.3;
    return !out;
  }

  /// Shot picked by the auto-hit assist when the player didn't press a button.
  ShotKind autoShot(int i) {
    final p = s.players[i];
    final o = s.players[1 - i];
    final z = s.ball.z;
    if (z > 1.45 && p.y.abs() < 5.5) return ShotKind.drive;
    if (p.y.abs() < 3.4) return z > 1.05 ? ShotKind.drive : ShotKind.soft;
    if (o.y.abs() < 3.6 && p.y.abs() > 5.5) return ShotKind.soft;
    return ShotKind.drive;
  }

  double _gauss() {
    final u1 = math.max(rng.nextDouble(), 1e-9);
    final u2 = rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  void _hit(int i, ShotKind kind, double aim, double dist) {
    final p = s.players[i];
    final b = s.ball;
    final volley = s.bouncesOnReceiver == 0;
    p.swing = 0.32;
    p.swingKind = kind;
    p.swingHand = ((b.x - p.x) * -p.side) >= 0 ? 1 : -1;
    p.armed = 0;
    if (volley && p.y.abs() < Court.kitchen) {
      s.stats[i].kitchenFaults++;
      _fault(i, 'KITCHEN FAULT!');
      return;
    }
    final st = profiles[i].stats;
    final q = (1 - 0.6 * (dist - 0.5).abs() / 0.6 - 0.25 * (b.z - 0.95).abs())
        .clamp(0.35, 1.0);
    final a = aim.clamp(-1.25, 1.25);
    var tx = a * ShotPlanner.zoneX * -p.side;
    var ty = -p.side * ShotPlanner.defaultDepth(kind, b.y);
    final f = ShotPlanner.noiseFactor(st.control.toDouble(), b.speed, b.z) *
        noiseMul[i] *
        (1.5 - 0.5 * q);
    final k = kind.index;
    tx += _gauss() * ShotPlanner.noiseX[k] * f;
    ty += _gauss() * ShotPlanner.noiseY[k] * f;
    final clr = _gauss() * ShotPlanner.noiseC[k] * f;
    final plan = ShotPlanner.plan(kind, b.x, b.y, b.z, tx, ty,
        power: st.power.toDouble(), clearanceOffset: clr);
    final smash = kind == ShotKind.drive && b.z > 1.5;
    b
      ..vx = plan.vx
      ..vy = plan.vy
      ..vz = plan.vz;
    s.lastHitter = i;
    s.shotCount++;
    s.bouncesOnReceiver = 0;
    s.rally++;
    if (smash) s.stats[i].smashes++;
    _updateMarker();
    _emit(smash ? 'smash' : 'hit',
        player: i, x: b.x, y: b.y, kind: kind.index, text: kind.label);
  }

  void _serve(int i, ShotKind kind, double aim) {
    final p = s.players[i];
    final st = profiles[i].stats;
    final hx = p.x + 0.32 * -p.side;
    final hy = p.y - p.side * 0.25;
    const hz = 0.75;
    final boxSign = -s.serveFromX.sign;
    var tx = boxSign * 1.55 + aim.clamp(-1.0, 1.0) * 1.1 * -p.side;
    final depth = switch (kind) {
      ShotKind.drive => 5.55,
      ShotKind.soft => 4.3,
      ShotKind.lob => 5.75,
    };
    var ty = -p.side * depth;
    final f = ShotPlanner.noiseFactor(st.control.toDouble(), 0, hz) * noiseMul[i] * 0.8;
    tx += _gauss() * 0.35 * f;
    ty += _gauss() * 0.40 * f;
    final clr = _gauss() * 0.06 * f;
    final plan = ShotPlanner.plan(kind, hx, hy, hz, tx, ty,
        power: st.power.toDouble(),
        clearanceOffset: clr,
        vmaxOverride: kind == ShotKind.drive ? 14.0 + 0.5 * st.power : null,
        clearanceOverride: switch (kind) {
          ShotKind.drive => 0.32,
          ShotKind.soft => 0.50,
          ShotKind.lob => null,
        });
    s.ball
      ..x = hx
      ..y = hy
      ..z = hz
      ..vx = plan.vx
      ..vy = plan.vy
      ..vz = plan.vz
      ..rolling = false;
    s.ballHeld = false;
    s.phase = Phase.rally;
    s.phaseTime = 0;
    s.lastHitter = i;
    s.shotCount = 1;
    s.bouncesOnReceiver = 0;
    s.rally = 1;
    s.bannerTime = 0;
    p.swing = 0.32;
    p.swingKind = kind;
    p.swingHand = 1;
    _updateMarker();
    _emit('serve', player: i, x: hx, y: hy, kind: kind.index);
  }

  void _updateMarker() {
    final (x, y, _) = BallPhysics.nextBounce(s.ball);
    s.markerX = x;
    s.markerY = y;
    s.hasMarker = true;
  }

  // ------------------------------------------------------------------ rules
  void _onBallEvent(BallEvent ev) {
    if (ev.type == BallEventType.bounce) {
      _emit('bounce', x: ev.x, y: ev.y);
      s.hasMarker = false;
    }
    if (s.phase != Phase.rally) return;
    final h = s.lastHitter;
    if (h < 0) return;
    if (ev.type == BallEventType.net) {
      _emit('net', player: h, x: ev.x);
      _fault(h, 'NET!');
      return;
    }
    final side = ev.y >= 0 ? 1 : -1;
    final hp = s.players[h];
    if (side == hp.side) {
      _fault(h, 'NET!');
      return;
    }
    s.bouncesOnReceiver++;
    if (s.bouncesOnReceiver == 1) {
      final valid = s.shotCount == 1
          ? _inServiceBox(ev.x, ev.y)
          : Court.inCourt(ev.x, ev.y, side);
      if (!valid) {
        _fault(h, s.shotCount == 1 ? 'SERVE OUT!' : 'OUT!');
        return;
      }
      if (ev.startedRolling) _winner(h); // dead ball, cannot be returned
    } else {
      _winner(h);
    }
  }

  bool _inServiceBox(double x, double y) {
    final boxSign = -s.serveFromX.sign;
    return x * boxSign >= -0.02 &&
        x.abs() <= Court.halfW &&
        y.abs() >= Court.kitchen &&
        y.abs() <= Court.halfL;
  }

  void _winner(int h) {
    if (s.shotCount == 1) {
      s.stats[h].aces++;
      _pointTo(h, 'ACE!');
    } else {
      s.stats[h].winners++;
      _pointTo(h, 'WINNER!');
    }
  }

  void _fault(int loser, String reason) {
    s.stats[loser].errors++;
    _pointTo(1 - loser, reason);
  }

  void _pointTo(int w, String reason) {
    if (s.phase != Phase.rally) return;
    s.phase = Phase.pointOver;
    s.phaseTime = 0;
    s.pointWinner = w;
    s.hasMarker = false;
    s.longestRally = math.max(s.longestRally, s.rally);
    for (final p in s.players) {
      p.armed = 0;
    }
    var text = reason;
    if (config.rallyScoring) {
      s.score[w]++;
      s.stats[w].points++;
      s.server = w;
    } else if (w == s.server) {
      s.score[w]++;
      s.stats[w].points++;
    } else {
      s.server = w;
      text = '$reason  SIDE OUT';
    }
    final lead = s.score[w] - s.score[1 - w];
    if (s.score[w] >= config.pointsToWin && lead >= 2) {
      s.winner = w;
    }
    s.banner = text;
    s.bannerTime = 1.7;
    _emit('point', player: w, text: text);
  }

  void _startPoint() {
    s.phase = Phase.serve;
    s.phaseTime = 0;
    s.ballHeld = true;
    s.lastHitter = -1;
    s.shotCount = 0;
    s.bouncesOnReceiver = 0;
    s.rally = 0;
    s.pointWinner = -1;
    s.hasMarker = false;
    _deadTime = 0;
    final srv = s.players[s.server];
    final rcv = s.players[1 - s.server];
    final even = s.score[s.server] % 2 == 0;
    final sx = (even ? 1.4 : -1.4) * -srv.side;
    srv
      ..x = sx
      ..y = srv.side * 6.95
      ..vx = 0
      ..vy = 0
      ..armed = 0;
    rcv
      ..x = -sx
      ..y = rcv.side * 6.6
      ..vx = 0
      ..vy = 0
      ..armed = 0;
    s.serveFromX = sx;
    s.banner = s.scoreCall();
    s.bannerTime = 1.2;
  }

  void _emit(String type,
      {int player = -1, double x = 0, double y = 0, String text = '', int kind = 0}) {
    final e = GameEvent(++_seq, type, player: player, x: x, y: y, text: text, kind: kind);
    _pending.add(e);
    s.recentEvents.add(e);
    if (s.recentEvents.length > 16) s.recentEvents.removeAt(0);
  }
}
