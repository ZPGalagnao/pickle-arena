// Authoritative pickleball simulation for singles (2 players) and doubles
// (4 players): movement, hitting, special attacks, rules and scoring.
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
  bool doubles;
  String botLevel; // difficulty of AI fill-ins in Wi-Fi doubles

  MatchConfig({
    this.pointsToWin = 11,
    this.rallyScoring = true,
    this.gameSpeed = 0.9,
    this.doubles = false,
    this.botLevel = 'medium',
  });

  int get playerCount => doubles ? 4 : 2;

  Map<String, dynamic> toJson() => {
        'points': pointsToWin,
        'rally': rallyScoring,
        'speed': gameSpeed,
        'doubles': doubles,
        'bots': botLevel,
      };

  factory MatchConfig.fromJson(Map<String, dynamic> j) => MatchConfig(
        pointsToWin: j['points'] as int? ?? 11,
        rallyScoring: j['rally'] as bool? ?? true,
        gameSpeed: (j['speed'] as num?)?.toDouble() ?? 0.9,
        doubles: j['doubles'] as bool? ?? false,
        botLevel: j['bots'] as String? ?? 'medium',
      );
}

class GameEngine {
  static const double dt = 1 / 120;
  static const double reach = 1.05;
  static const double armWindow = 0.45;
  static const double slowmoScale = 0.3;

  final MatchConfig config;
  final List<PlayerProfile> profiles;
  final List<double> noiseMul;
  final List<double> speedMul;
  final List<bool> autoHit;
  final List<bool> moveAssist;
  final GameState s;
  final math.Random rng;
  final List<GameEvent> _pending = [];
  double _acc = 0;
  int _seq = 0;
  double _deadTime = 0;
  bool _iceDone = false, _fireDone = false;
  int _assistTick = 0;
  final List<double?> _assistX;
  List<PlayerInput> _inputs;

  GameEngine({
    required this.config,
    required this.profiles,
    List<double>? noiseMul,
    List<double>? speedMul,
    List<bool>? autoHit,
    List<bool>? moveAssist,
    int? firstServer,
    math.Random? random,
  })  : s = GameState(playerCount: profiles.length),
        noiseMul = noiseMul ?? List.filled(profiles.length, 1.0),
        speedMul = speedMul ?? List.filled(profiles.length, 1.0),
        autoHit = autoHit ?? List.filled(profiles.length, true),
        moveAssist = moveAssist ?? List.filled(profiles.length, false),
        rng = random ?? math.Random(),
        _assistX = List.filled(profiles.length, null),
        _inputs = [for (var i = 0; i < profiles.length; i++) PlayerInput()] {
    if (s.doubles) {
      for (final p in s.players) {
        p.lane = p.index.isEven ? 1 : -1; // first player of each team starts on the right
      }
      s.server = firstServer ?? rng.nextInt(2) * 2;
      s.serverNumber = config.rallyScoring ? 1 : 2; // traditional doubles starts at 0-0-2
    } else {
      s.server = firstServer ?? rng.nextInt(2);
    }
    _startPoint();
    s.banner = '${profiles[s.server].name} serves first';
    s.bannerTime = 1.8;
  }

  int get n => profiles.length;

  /// Events since the last call (for the UI on this phone).
  List<GameEvent> drainEvents() {
    final out = List<GameEvent>.of(_pending);
    _pending.clear();
    return out;
  }

  void update(double frameDt, List<PlayerInput> inputs) {
    _inputs = inputs;
    for (var i = 0; i < n; i++) {
      _applyButtons(i, inputs[i]);
    }
    final real = math.min(frameDt, 0.05);
    var scale = config.gameSpeed;
    if (s.slowmo > 0) {
      scale *= slowmoScale;
      s.slowmo = math.max(0, s.slowmo - real);
    }
    _acc += real * scale;
    while (_acc >= dt) {
      _acc -= dt;
      _tick(dt);
    }
  }

  // ------------------------------------------------------------------ input
  void _applyButtons(int i, PlayerInput inp) {
    final p = s.players[i];
    if (inp.special && p.meter >= 1 && s.phase != Phase.gameOver) {
      p.specialArmed = true;
    }
    final shot = inp.shot;
    if (shot == null) return;
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
    s.specialTime += dt;
    if (s.bannerTime > 0) s.bannerTime -= dt;
    _assistTick++;
    for (var i = 0; i < n; i++) {
      final p = s.players[i];
      if (p.frozen > 0) p.frozen = math.max(0, p.frozen - dt);
      final locked = s.phase == Phase.gameOver || (s.phase == Phase.serve && s.server == i);
      final inp = _assistedInput(i, _inputs[i]);
      final speed = profiles[i].stats.runSpeed * speedMul[i] * (p.frozen > 0 ? 0.35 : 1.0);
      movePlayer(p, inp, speed, dt, locked: locked);
      if (p.swing > 0) p.swing = math.max(0, p.swing - dt);
    }
    if (s.doubles) _separatePartners();

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
      final prevY = s.ball.y;
      final events = BallPhysics.step(s.ball, dt, netActive: s.phase == Phase.rally);
      for (final ev in events) {
        _onBallEvent(ev);
      }
      _checkNetCrossingEffects(prevY);
    }

    if (s.phase == Phase.rally) {
      _tryHits(dt);
      if (s.ball.rolling) {
        _deadTime += dt;
        if (_deadTime > 1.5) {
          final side = s.ball.y >= 0 ? 1 : -1;
          final losingTeam = side < 0 ? 0 : 1;
          _pointTo(1 - losingTeam, 'WINNER!');
        }
      } else {
        _deadTime = 0;
      }
    } else if (s.phase == Phase.pointOver && s.phaseTime > 1.8) {
      if (s.winner >= 0) {
        s.phase = Phase.gameOver;
        s.phaseTime = 0;
        s.slowmo = 3.0; // victory cinematic
        s.ball.clearFx();
        s.hasMarker = false;
        for (final p in s.players) {
          p
            ..frozen = 0
            ..burned = false
            ..specialArmed = false;
        }
        s.banner = s.doubles
            ? '${profiles[s.teamPlayers(s.winner)[0].index].name} & '
                '${profiles[s.teamPlayers(s.winner)[1].index].name} WIN!'
            : '${profiles[s.winner].name} WINS!';
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
    const accel = 30.0;
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

  void _separatePartners() {
    for (var t = 0; t < 2; t++) {
      final a = s.players[t * 2], b = s.players[t * 2 + 1];
      final dx = b.x - a.x, dy = b.y - a.y;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < 0.75) {
        final push = (0.75 - d) / 2;
        final ux = d < 1e-4 ? (a.lane >= b.lane ? -1.0 : 1.0) : dx / d;
        final uy = d < 1e-4 ? 0.0 : dy / d;
        a.x -= ux * push;
        a.y -= uy * push;
        b.x += ux * push;
        b.y += uy * push;
      }
    }
  }

  /// Move assist: when a human isn't touching the joystick, slide them
  /// sideways toward where the incoming ball will pass.
  PlayerInput _assistedInput(int i, PlayerInput inp) {
    if (!moveAssist[i] || s.phase != Phase.rally) return inp;
    if (inp.mx.abs() + inp.my.abs() > 0.15) return inp;
    final p = s.players[i];
    if (s.lastHitter < 0 || s.hittingTeam == p.team) return inp;
    if (_assistTick % 6 == 0 || _assistX[i] == null) {
      _assistX[i] = _crossingX(p.y);
    }
    var target = _assistX[i];
    if (target == null) return inp;
    final partner = s.partnerOf(i);
    if (partner != null && (partner.x - target).abs() < (p.x - target).abs() - 0.3) return inp;
    target += 0.4 * p.side; // ball on the forehand side
    final dx = target - p.x;
    if (dx.abs() < 0.08) return inp;
    final worldX = dx.sign * math.min(1.0, dx.abs() / 0.6) * 0.9;
    return PlayerInput(mx: worldX * -p.side, my: 0, aim: inp.aim);
  }

  double? _crossingX(double py) {
    final b = s.ball.copy();
    final d0 = b.y - py;
    for (var k = 0; k < 150; k++) {
      BallPhysics.step(b, 1 / 60, netActive: false);
      if ((b.y - py) * d0 <= 0) return b.x;
      if (b.rolling) return b.x;
    }
    return null;
  }

  // ---------------------------------------------------------------- hitting
  void _tryHits(double dt) {
    final b = s.ball;
    final hTeam = s.hittingTeam;
    int? best;
    double bestDist = 99;
    for (var i = 0; i < n; i++) {
      final p = s.players[i];
      if (p.armed > 0) p.armed = math.max(0, p.armed - dt);
      if (p.team == hTeam || b.y * p.side <= 0 || b.rolling) {
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
      final goodMoment = dist < 0.62 || passing || (b.z < 0.14 && b.vz < 0);
      final wants = (p.specialArmed && goodMoment) ||
          (p.armed > 0 && (goodMoment || p.armed < 0.03)) ||
          (autoHit[i] && goodMoment && _assistShouldSwing(i));
      if (wants && dist < bestDist) {
        best = i;
        bestDist = dist;
      }
    }
    if (best != null) {
      final p = s.players[best];
      final kind = p.armed > 0 ? p.armedKind : autoShot(best);
      _hit(best, kind, _inputs[best].aim, _inputs[best].depth, bestDist);
    }
  }

  /// The assist never volleys from the kitchen and lets clearly-out balls go.
  bool _assistShouldSwing(int i) {
    if (s.bouncesOnReceiver > 0) return true;
    final p = s.players[i];
    if (p.y.abs() < Court.kitchen) return false;
    if (s.ball.curve != 0) return true; // can't judge a curving ball
    final (bx, by, _) = BallPhysics.nextBounce(s.ball);
    final out = bx.abs() > Court.halfW + 0.3 || by.abs() > Court.halfL + 0.3;
    return !out;
  }

  /// Shot picked by the auto-swing assist when the player didn't press a button.
  ShotKind autoShot(int i) {
    final p = s.players[i];
    final z = s.ball.z;
    var oppY = 0.0;
    for (final o in s.players) {
      if (o.team != p.team) oppY = math.max(oppY, o.y.abs());
    }
    if (z > 1.45 && p.y.abs() < 5.5) return ShotKind.drive;
    if (p.y.abs() < 3.4) return z > 1.05 ? ShotKind.drive : ShotKind.soft;
    if (oppY < 3.6 && p.y.abs() > 5.5) return ShotKind.soft;
    return ShotKind.drive;
  }

  double _gauss() {
    final u1 = math.max(rng.nextDouble(), 1e-9);
    final u2 = rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  static double depthOffset(ShotKind kind, double depth) => switch (kind) {
        ShotKind.drive => depth.clamp(-1.0, 1.0) * 0.8,
        ShotKind.soft => depth.clamp(-1.0, 1.0) * 0.6,
        ShotKind.lob => depth.clamp(-1.0, 1.0) * 0.4,
      };

  void _hit(int i, ShotKind kind, double aim, double depth, double dist) {
    final p = s.players[i];
    final b = s.ball;
    final volley = s.bouncesOnReceiver == 0;
    p.swing = 0.32;
    p.swingKind = kind;
    p.swingHand = ((b.x - p.x) * -p.side) >= 0 ? 1 : -1;
    p.armed = 0;
    if (volley && p.y.abs() < Court.kitchen) {
      p.specialArmed = false;
      s.stats[i].kitchenFaults++;
      _fault(i, 'KITCHEN FAULT!');
      return;
    }
    s.stats[i].hits++;
    if (p.specialArmed && p.meter >= 1) {
      _hitSpecial(i, aim, depth);
      return;
    }
    p.specialArmed = false;
    final st = profiles[i].stats;
    final q = (1 - 0.6 * (dist - 0.5).abs() / 0.6 - 0.25 * (b.z - 0.95).abs()).clamp(0.35, 1.0);
    final a = aim.clamp(-1.25, 1.25);
    var tx = a * ShotPlanner.zoneX * -p.side;
    var ty = -p.side * (ShotPlanner.defaultDepth(kind, b.y) + depthOffset(kind, depth));
    var f = ShotPlanner.noiseFactor(st.control.toDouble(), b.speed, b.z) * noiseMul[i] * (1.5 - 0.5 * q);
    if (p.burned) {
      f *= 2.4; // FIRE SMASH burned this paddle
      p.burned = false;
    }
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
      ..vz = plan.vz
      ..clearFx();
    _afterHit(i);
    _charge(p, 0.07 + 0.05 * q);
    if (smash) s.stats[i].smashes++;
    _updateMarker();
    _emit(smash ? 'smash' : 'hit', player: i, x: b.x, y: b.y, kind: kind.index, text: kind.label);
  }

  void _afterHit(int i) {
    s.lastHitter = i;
    s.shotCount++;
    s.bouncesOnReceiver = 0;
    s.rally++;
    _iceDone = false;
    _fireDone = false;
    for (final o in s.players) {
      o.prevBallDist = 99;
    }
  }

  void _hitSpecial(int i, double aim, double depth) {
    final p = s.players[i];
    final b = s.ball;
    final st = profiles[i].stats;
    final skill = profiles[i].special;
    p.meter = 0;
    p.specialArmed = false;
    s.stats[i].specials++;
    final side = p.side;
    final tx = (aim.clamp(-1.0, 1.0) * 2.0 + (rng.nextDouble() - 0.5) * 0.3) * -side;
    ShotPlan plan;
    b.clearFx();
    switch (skill) {
      case SpecialSkill.fireSmash:
        plan = ShotPlanner.plan(ShotKind.drive, b.x, b.y, b.z, tx, -side * (5.6 + depth * 0.4),
            power: st.power.toDouble(), vmaxOverride: 23 + 0.8 * st.power, clearanceOverride: 0.15);
        b.fx = BallFx.fire;
        p.swingKind = ShotKind.drive;
      case SpecialSkill.iceFreeze:
        plan = ShotPlanner.plan(ShotKind.drive, b.x, b.y, b.z, tx, -side * (5.0 + depth * 0.6),
            power: st.power.toDouble(), vmaxOverride: 17, clearanceOverride: 0.3);
        b.fx = BallFx.ice;
        p.swingKind = ShotKind.drive;
      case SpecialSkill.thunderCurve:
        // aim at the mirror spot, then bend back hard onto the real target
        final dir = tx == 0 ? (rng.nextBool() ? 1.0 : -1.0) : tx.sign;
        const curveAcc = 9.0;
        final curve = dir * curveAcc;
        final ty = -side * (5.2 + depth * 0.5);
        final first = ShotPlanner.plan(ShotKind.drive, b.x, b.y, b.z, tx, ty,
            power: st.power.toDouble(), vmaxOverride: 18, clearanceOverride: 0.3);
        final shift = 0.5 * curve * first.flightTime * first.flightTime;
        final startX = (tx - shift).clamp(-4.5, 4.5);
        plan = ShotPlanner.plan(ShotKind.drive, b.x, b.y, b.z, startX, ty,
            power: st.power.toDouble(), vmaxOverride: 18, clearanceOverride: 0.3);
        b.fx = BallFx.thunder;
        b.curve = curve;
        p.swingKind = ShotKind.drive;
      case SpecialSkill.phantomDrop:
        plan = ShotPlanner.plan(ShotKind.soft, b.x, b.y, b.z, tx * 0.8, -side * (0.85 + depth * 0.3),
            power: st.power.toDouble(), clearanceOverride: 0.22);
        b.fx = BallFx.phantom;
        p.swingKind = ShotKind.soft;
      case SpecialSkill.tornadoLob:
        plan = ShotPlanner.plan(ShotKind.lob, b.x, b.y, b.z, tx * 0.7, -side * (5.9 + depth * 0.2),
            power: st.power.toDouble());
        b.fx = BallFx.tornado;
        b.kick = (rng.nextBool() ? 1 : -1) * 3.6;
        p.swingKind = ShotKind.lob;
    }
    b
      ..vx = plan.vx
      ..vy = plan.vy
      ..vz = plan.vz;
    _afterHit(i);
    s.slowmo = 1.1;
    s.specialPlayer = i;
    s.specialTime = 0;
    s.banner = skill.label;
    s.bannerTime = 1.3;
    _updateMarker();
    // curving and invisible balls don't show their landing spot
    if (b.fx == BallFx.thunder || b.fx == BallFx.phantom) s.hasMarker = false;
    _emit('special', player: i, x: b.x, y: b.y, kind: skill.index, text: skill.label);
  }

  void _checkNetCrossingEffects(double prevY) {
    final b = s.ball;
    if (s.lastHitter < 0 || prevY * b.y > 0) return;
    final rcvTeam = 1 - s.hittingTeam;
    if (b.fx == BallFx.ice && !_iceDone) {
      _iceDone = true;
      for (final p in s.teamPlayers(rcvTeam)) {
        p.frozen = 1.5;
      }
      _emit('freeze', player: s.lastHitter, x: b.x, y: b.y);
    }
    if (b.fx == BallFx.fire && !_fireDone) {
      _fireDone = true;
      for (final p in s.teamPlayers(rcvTeam)) {
        p.burned = true;
      }
    }
  }

  void _charge(PlayerState p, double amount) {
    final before = p.meter;
    p.meter = math.min(1.0, p.meter + amount);
    if (before < 1 && p.meter >= 1) _emit('ready', player: p.index);
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
      ..rolling = false
      ..clearFx();
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
      final valid = s.shotCount == 1 ? _inServiceBox(ev.x, ev.y) : Court.inCourt(ev.x, ev.y, side);
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
      _pointTo(s.teamOf(h), 'ACE!');
    } else {
      s.stats[h].winners++;
      _pointTo(s.teamOf(h), s.ball.fx != BallFx.none ? 'SPECIAL WINNER!' : 'WINNER!');
    }
  }

  void _fault(int loser, String reason) {
    s.stats[loser].errors++;
    _pointTo(1 - s.teamOf(loser), reason);
  }

  void _pointTo(int team, String reason) {
    if (s.phase != Phase.rally) return;
    s.phase = Phase.pointOver;
    s.phaseTime = 0;
    s.pointWinner = team;
    s.hasMarker = false;
    s.longestRally = math.max(s.longestRally, s.rally);
    for (final p in s.players) {
      p.armed = 0;
      _charge(p, p.team == team ? 0.2 : 0.12);
    }
    final srvTeam = s.servingTeam;
    var text = reason;
    if (config.rallyScoring) {
      s.score[team]++;
      for (final p in s.teamPlayers(team)) {
        s.stats[p.index].points++;
      }
      if (team == srvTeam) {
        _swapLanes(team);
      } else if (s.doubles) {
        // the new serving team serves from the side that matches its score
        final lane = s.score[team].isEven ? 1 : -1;
        s.server = s.teamPlayers(team).firstWhere((p) => p.lane == lane).index;
      } else {
        s.server = team;
      }
    } else if (team == srvTeam) {
      s.score[team]++;
      for (final p in s.teamPlayers(team)) {
        s.stats[p.index].points++;
      }
      _swapLanes(team);
    } else if (s.doubles && s.serverNumber == 1) {
      s.serverNumber = 2;
      s.server = s.partnerOf(s.server)!.index;
      text = '$reason  2ND SERVER';
    } else {
      s.serverNumber = 1;
      s.server = s.doubles ? s.teamPlayers(team).firstWhere((p) => p.lane == 1).index : team;
      text = '$reason  SIDE OUT';
    }
    final lead = s.score[team] - s.score[1 - team];
    if (s.score[team] >= config.pointsToWin && lead >= 2) s.winner = team;
    s.banner = text;
    s.bannerTime = 1.7;
    _emit('point', player: team, text: text);
  }

  /// Doubles: partners switch sides when their team scores on its own serve.
  void _swapLanes(int team) {
    if (!s.doubles) return;
    for (final p in s.teamPlayers(team)) {
      p.lane = -p.lane;
    }
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
    s.ball.clearFx();
    _deadTime = 0;
    for (final p in s.players) {
      p
        ..vx = 0
        ..vy = 0
        ..armed = 0
        ..frozen = 0
        ..burned = false;
    }
    final srv = s.players[s.server];
    if (!s.doubles) {
      srv.lane = s.score[srv.team].isEven ? 1 : -1;
    }
    final sx = srv.lane * 1.4 * -srv.side;
    srv
      ..x = sx
      ..y = srv.side * 6.95;
    for (final p in s.players) {
      if (p.index == srv.index) continue;
      if (p.team == srv.team) {
        // server's partner waits at the baseline (two-bounce rule)
        p
          ..x = -sx
          ..y = p.side * 6.6;
      } else if (!s.doubles || p.lane == srv.lane) {
        // receiver: diagonal box
        p
          ..x = -sx
          ..y = p.side * 6.6;
      } else {
        // receiver's partner starts at the kitchen line
        p
          ..x = sx
          ..y = p.side * 2.5;
      }
    }
    s.serveFromX = sx;
    s.banner = s.scoreCall(sideOut: !config.rallyScoring);
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
