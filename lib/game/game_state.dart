import 'physics.dart';
import 'shot_planner.dart';

enum Phase { serve, rally, pointOver, gameOver }

/// What a controller (touch, tilt, AI or network) wants a player to do.
/// Movement is in the player's own frame: [my] > 0 = toward the net,
/// [mx] > 0 = to the player's right.
class PlayerInput {
  double mx, my;
  ShotKind? shot; // pressed this frame
  bool special; // SPECIAL pressed this frame
  double aim; // sideways aim (-1.25..1.25) in the player's frame
  double depth; // -1 = shorter .. +1 = deeper

  PlayerInput({this.mx = 0, this.my = 0, this.shot, this.aim = 0, this.depth = 0, this.special = false});

  void clearEdge() {
    shot = null;
    special = false;
  }
}

class PlayerState {
  final int index;
  final int team; // 0 = near team (y < 0), 1 = far team (y > 0)
  int lane = 1; // doubles: +1 = right half, -1 = left half (team's own view)
  double x = 0, y = 0, vx = 0, vy = 0;
  double swing = 0; // seconds left in the swing animation
  ShotKind swingKind = ShotKind.drive;
  int swingHand = 1; // +1 forehand, -1 backhand
  double armed = 0; // seconds left in an armed (pressed) swing
  ShotKind armedKind = ShotKind.drive;
  double prevBallDist = 99;
  double runPhase = 0;
  double meter = 0; // special meter 0..1
  bool specialArmed = false;
  double frozen = 0; // ICE FREEZE: seconds of slow movement left
  bool burned = false; // FIRE SMASH: next shot is wild

  PlayerState(this.index, this.team);

  int get side => team == 0 ? -1 : 1;
  bool get specialReady => meter >= 1;
}

class MatchStats {
  int points = 0, winners = 0, errors = 0, aces = 0, kitchenFaults = 0, smashes = 0, specials = 0, hits = 0;

  List<int> toList() => [points, winners, errors, aces, kitchenFaults, smashes, specials, hits];

  void fromList(List l) {
    points = l[0] as int;
    winners = l[1] as int;
    errors = l[2] as int;
    aces = l[3] as int;
    kitchenFaults = l[4] as int;
    smashes = l[5] as int;
    specials = l.length > 6 ? l[6] as int : 0;
    hits = l.length > 7 ? l[7] as int : 0;
  }

  /// Performance score used for the post-match ranking.
  double get rating =>
      winners * 3.0 + aces * 3.0 + smashes * 2.0 + specials * 2.0 + hits * 0.4 - errors * 2.0 - kitchenFaults * 1.0;
}

/// Discrete things that happened (for sound, haptics, particles, banners).
class GameEvent {
  final int seq;
  final String type; // hit, smash, serve, bounce, net, point, special, freeze, game_over, restart
  final int player;
  final double x, y;
  final String text;
  final int kind;

  const GameEvent(this.seq, this.type,
      {this.player = -1, this.x = 0, this.y = 0, this.text = '', this.kind = 0});

  List<Object> toList() => [seq, type, player, _r(x), _r(y), text, kind];

  static GameEvent fromList(List l) => GameEvent(l[0] as int, l[1] as String,
      player: l[2] as int,
      x: (l[3] as num).toDouble(),
      y: (l[4] as num).toDouble(),
      text: l[5] as String,
      kind: l[6] as int);
}

double _r(double v) => (v * 1000).roundToDouble() / 1000;

class GameState {
  final Ball ball = Ball(z: 0.9);
  bool ballHeld = true;
  final List<PlayerState> players;
  final List<int> score = [0, 0]; // per team
  int server = 0; // player index
  int serverNumber = 1; // doubles side-out scoring: 1st or 2nd server
  double serveFromX = 1.4;
  Phase phase = Phase.serve;
  double phaseTime = 0;
  int lastHitter = -1;
  int shotCount = 0;
  int bouncesOnReceiver = 0;
  String banner = '';
  double bannerTime = 0;
  int pointWinner = -1; // team
  int winner = -1; // team
  int rally = 0;
  int longestRally = 0;
  bool hasMarker = false;
  double markerX = 0, markerY = 0;
  double slowmo = 0; // real seconds of slow motion left
  int specialPlayer = -1; // who fired the last special (for the banner)
  double specialTime = 0; // seconds since that special
  final List<MatchStats> stats;
  final List<GameEvent> recentEvents = [];

  GameState({int playerCount = 2})
      : players = [
          for (var i = 0; i < playerCount; i++) PlayerState(i, playerCount == 2 ? i : i ~/ 2)
        ],
        stats = [for (var i = 0; i < playerCount; i++) MatchStats()];

  bool get doubles => players.length == 4;
  int teamOf(int i) => players[i].team;
  List<PlayerState> teamPlayers(int t) => [for (final p in players) if (p.team == t) p];
  PlayerState? partnerOf(int i) {
    if (!doubles) return null;
    for (final p in players) {
      if (p.team == players[i].team && p.index != i) return p;
    }
    return null;
  }

  int get servingTeam => teamOf(server);
  int get hittingTeam => lastHitter < 0 ? -1 : teamOf(lastHitter);

  /// Must the team about to hit let the ball bounce first? (two-bounce rule)
  bool get mustBounce => shotCount <= 2;

  String scoreCall({bool sideOut = false}) {
    final s = score[servingTeam];
    final r = score[1 - servingTeam];
    return doubles && sideOut ? '$s - $r - $serverNumber' : '$s - $r';
  }

  Map<String, dynamic> toJson() => {
        't': 's',
        'b': [
          _r(ball.x), _r(ball.y), _r(ball.z), _r(ball.vx), _r(ball.vy), _r(ball.vz),
          ball.rolling ? 1 : 0, ballHeld ? 1 : 0, ball.fx, _r(ball.curve), _r(ball.kick), ball.fxBounces,
        ],
        'p': [
          for (final p in players)
            [
              _r(p.x), _r(p.y), _r(p.vx), _r(p.vy), _r(p.swing), p.swingKind.index, p.swingHand,
              _r(p.meter), p.specialArmed ? 1 : 0, _r(p.frozen), p.burned ? 1 : 0, p.lane,
            ]
        ],
        'sc': score,
        'sv': server,
        'sn': serverNumber,
        'sx': _r(serveFromX),
        'ph': phase.index,
        'pt': _r(phaseTime),
        'lh': lastHitter,
        'sh': shotCount,
        'bo': bouncesOnReceiver,
        'bn': banner,
        'bt': _r(bannerTime),
        'pw': pointWinner,
        'w': winner,
        'r': rally,
        'lr': longestRally,
        'm': [hasMarker ? 1 : 0, _r(markerX), _r(markerY)],
        'sm': _r(slowmo),
        'sp': [specialPlayer, _r(specialTime)],
        'st': [for (final s in stats) s.toList()],
        'ev': [for (final e in recentEvents) e.toList()],
      };

  /// Apply a host snapshot (network client).
  void applyJson(Map<String, dynamic> j) {
    final b = (j['b'] as List).map((e) => (e as num).toDouble()).toList();
    ball
      ..x = b[0]
      ..y = b[1]
      ..z = b[2]
      ..vx = b[3]
      ..vy = b[4]
      ..vz = b[5]
      ..rolling = b[6] > 0.5
      ..fx = b[8].round()
      ..curve = b[9]
      ..kick = b[10]
      ..fxBounces = b[11].round();
    ballHeld = b[7] > 0.5;
    final ps = j['p'] as List;
    for (var i = 0; i < players.length && i < ps.length; i++) {
      final l = (ps[i] as List);
      final p = players[i];
      p.x = (l[0] as num).toDouble();
      p.y = (l[1] as num).toDouble();
      p.vx = (l[2] as num).toDouble();
      p.vy = (l[3] as num).toDouble();
      p.swing = (l[4] as num).toDouble();
      p.swingKind = ShotKind.values[l[5] as int];
      p.swingHand = l[6] as int;
      p.meter = (l[7] as num).toDouble();
      p.specialArmed = (l[8] as num) > 0;
      p.frozen = (l[9] as num).toDouble();
      p.burned = (l[10] as num) > 0;
      p.lane = l[11] as int;
    }
    final sc = j['sc'] as List;
    score[0] = sc[0] as int;
    score[1] = sc[1] as int;
    server = j['sv'] as int;
    serverNumber = j['sn'] as int;
    serveFromX = (j['sx'] as num).toDouble();
    phase = Phase.values[j['ph'] as int];
    phaseTime = (j['pt'] as num).toDouble();
    lastHitter = j['lh'] as int;
    shotCount = j['sh'] as int;
    bouncesOnReceiver = j['bo'] as int;
    banner = j['bn'] as String;
    bannerTime = (j['bt'] as num).toDouble();
    pointWinner = j['pw'] as int;
    winner = j['w'] as int;
    rally = j['r'] as int;
    longestRally = j['lr'] as int;
    final m = j['m'] as List;
    hasMarker = (m[0] as num) > 0;
    markerX = (m[1] as num).toDouble();
    markerY = (m[2] as num).toDouble();
    slowmo = (j['sm'] as num).toDouble();
    final sp = j['sp'] as List;
    specialPlayer = sp[0] as int;
    specialTime = (sp[1] as num).toDouble();
    final st = j['st'] as List;
    for (var i = 0; i < stats.length && i < st.length; i++) {
      stats[i].fromList(st[i] as List);
    }
  }

  static List<GameEvent> eventsFromJson(Map<String, dynamic> j) =>
      [for (final e in (j['ev'] as List? ?? const [])) GameEvent.fromList(e as List)];
}
