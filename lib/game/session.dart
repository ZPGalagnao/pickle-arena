// A GameSession hides where the game is simulated:
//  * AiSession     - engine + AI opponent on this phone
//  * HostSession   - engine on this phone, opponent's controls arrive over Wi-Fi
//  * ClientSession - snapshots arrive from the host; own movement is predicted
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import '../net/lan.dart';
import 'ai/ai_controller.dart';
import 'ai/brain.dart';
import 'engine.dart';
import 'game_state.dart';
import 'physics.dart';
import 'shot_planner.dart';

abstract class GameSession extends ChangeNotifier {
  GameState get state;
  int get localIndex;
  List<PlayerProfile> get profiles;
  MatchConfig get config;
  bool get isMultiplayer;
  bool get canPause => !isMultiplayer;
  bool get disconnected => false;
  bool get opponentWantsRematch => false;
  String? get aiThought => null;
  String get modeKey;

  void update(double dt, PlayerInput local);
  List<GameEvent> takeEvents();
  void rematch();
  void leave() {}
}

class AiSession extends GameSession {
  final PlayerProfile human;
  final PlayerProfile aiProfile;
  final AiDifficulty difficulty;
  final AiStyle style;
  final PickleBrain brain;
  @override
  final MatchConfig config;
  final bool autoHit;
  late GameEngine _engine;
  late AiController _ai;

  AiSession({
    required this.human,
    required this.aiProfile,
    required this.difficulty,
    required this.brain,
    required this.config,
    this.style = AiStyle.balanced,
    this.autoHit = true,
  }) {
    _newMatch();
  }

  void _newMatch() {
    _engine = GameEngine(
      config: config,
      profiles: [human, aiProfile],
      noiseMul: [1, difficulty.noiseMul],
      speedMul: [1, 1],
      autoHit: [autoHit, false],
    );
    _ai = AiController(brain, difficulty, 1, style: style);
  }

  @override
  GameState get state => _engine.s;
  @override
  int get localIndex => 0;
  @override
  List<PlayerProfile> get profiles => [human, aiProfile];
  @override
  bool get isMultiplayer => false;
  @override
  String get modeKey => 'ai_${difficulty.id}';
  @override
  String? get aiThought => _ai.lastThought;

  @override
  void update(double dt, PlayerInput local) {
    final aiIn = _ai.update(_engine.s, aiProfile, dt * config.gameSpeed);
    _engine.update(dt, [local, aiIn]);
  }

  @override
  List<GameEvent> takeEvents() => _engine.drainEvents();

  @override
  void rematch() {
    _newMatch();
    notifyListeners();
  }
}

/// Demo match on the home screen: AI vs AI.
class DemoSession {
  final PickleBrain brain;
  final List<PlayerProfile> profiles;
  late GameEngine engine;
  late List<AiController> ais;

  DemoSession(this.brain, this.profiles) {
    _start();
  }

  void _start() {
    engine = GameEngine(
      config: MatchConfig(pointsToWin: 99, gameSpeed: 0.85),
      profiles: profiles,
      noiseMul: [1.2, 1.2],
      autoHit: [false, false],
    );
    ais = [
      AiController(brain, AiDifficulty.hard, 0),
      AiController(brain, AiDifficulty.hard, 1),
    ];
  }

  void update(double dt) {
    final g = dt * engine.config.gameSpeed;
    engine.update(dt, [
      ais[0].update(engine.s, profiles[0], g),
      ais[1].update(engine.s, profiles[1], g),
    ]);
    engine.drainEvents();
    if (engine.s.score[0] + engine.s.score[1] > 40) _start();
  }
}

class HostSession extends GameSession {
  final LanHost host;
  final PlayerProfile me;
  final PlayerProfile guest;
  @override
  final MatchConfig config;
  final bool myAutoHit;
  final bool guestAutoHit;
  late GameEngine _engine;
  final PlayerInput _remote = PlayerInput();
  double _snapTimer = 0;
  bool _disconnected = false;
  bool _guestWantsRematch = false;

  HostSession({
    required this.host,
    required this.me,
    required this.guest,
    required this.config,
    required this.myAutoHit,
    required this.guestAutoHit,
  }) {
    host.onMessage = _onMessage;
    host.onDisconnected = () {
      _disconnected = true;
      notifyListeners();
    };
    _newMatch();
  }

  void _newMatch() {
    _engine = GameEngine(
      config: config,
      profiles: [me, guest],
      autoHit: [myAutoHit, guestAutoHit],
    );
    _guestWantsRematch = false;
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'in':
        _remote.mx = ((m['mx'] as num?) ?? 0).toDouble().clamp(-1.0, 1.0);
        _remote.my = ((m['my'] as num?) ?? 0).toDouble().clamp(-1.0, 1.0);
        _remote.aim = ((m['a'] as num?) ?? 0).toDouble().clamp(-1.25, 1.25);
        final s = (m['s'] as int?) ?? -1;
        if (s >= 0 && s < ShotKind.values.length) _remote.shot = ShotKind.values[s];
      case 'rematch':
        _guestWantsRematch = true;
        notifyListeners();
      case 'ping':
        host.send({'t': 'pong', 'ts': m['ts']});
      case 'bye':
        _disconnected = true;
        notifyListeners();
    }
  }

  @override
  GameState get state => _engine.s;
  @override
  int get localIndex => 0;
  @override
  List<PlayerProfile> get profiles => [me, guest];
  @override
  bool get isMultiplayer => true;
  @override
  bool get disconnected => _disconnected;
  @override
  bool get opponentWantsRematch => _guestWantsRematch;
  @override
  String get modeKey => 'lan';

  @override
  void update(double dt, PlayerInput local) {
    _engine.update(dt, [local, _remote]);
    _remote.shot = null;
    _snapTimer += dt;
    if (_snapTimer >= 1 / 30) {
      _snapTimer = 0;
      host.send(_engine.s.toJson());
    }
  }

  @override
  List<GameEvent> takeEvents() => _engine.drainEvents();

  @override
  void rematch() {
    _newMatch();
    host.send({'t': 'restart'});
    host.send(_engine.s.toJson());
    notifyListeners();
  }

  @override
  void leave() {
    host.stop();
  }
}

class ClientSession extends GameSession {
  final LanClient client;
  final PlayerProfile me;
  final PlayerProfile hostProfile;
  @override
  final MatchConfig config;
  final GameState _state = GameState();
  final List<GameEvent> _events = [];
  int _lastSeq = 0;
  bool _gotSnapshot = false;
  double _authX = 0, _authY = 0;
  double _oppX = 0, _oppY = 0, _oppVx = 0, _oppVy = 0;
  double _sendTimer = 0;
  bool _disconnected = false;
  bool _restartPending = false;
  int pingMs = 0;
  double _pingTimer = 0;

  ClientSession({
    required this.client,
    required this.me,
    required this.hostProfile,
    required this.config,
    Map<String, dynamic>? firstSnapshot,
  }) {
    client.onMessage = _onMessage;
    client.onDisconnected = () {
      _disconnected = true;
      notifyListeners();
    };
    if (firstSnapshot != null) _applySnapshot(firstSnapshot);
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 's':
        _applySnapshot(m);
      case 'restart':
        _restartPending = true;
        _lastSeq = 0;
        notifyListeners();
      case 'pong':
        final ts = (m['ts'] as num?)?.toInt();
        if (ts != null) pingMs = DateTime.now().millisecondsSinceEpoch - ts;
      case 'bye':
        _disconnected = true;
        notifyListeners();
    }
  }

  void _applySnapshot(Map<String, dynamic> m) {
    final mine = _state.players[1];
    final opp = _state.players[0];
    final keep = [mine.x, mine.y, mine.vx, mine.vy, mine.runPhase, opp.x, opp.y, opp.runPhase];
    final prevPhase = _state.phase;
    _state.applyJson(m);
    _authX = mine.x;
    _authY = mine.y;
    _oppX = opp.x;
    _oppY = opp.y;
    _oppVx = opp.vx;
    _oppVy = opp.vy;
    final teleport = !_gotSnapshot ||
        (prevPhase != Phase.serve && _state.phase == Phase.serve) ||
        _restartPending;
    if (!teleport) {
      mine
        ..x = keep[0]
        ..y = keep[1]
        ..vx = keep[2]
        ..vy = keep[3]
        ..runPhase = keep[4];
      opp
        ..x = keep[5]
        ..y = keep[6]
        ..runPhase = keep[7];
    }
    _gotSnapshot = true;
    if (_restartPending) {
      _restartPending = false;
      _events.add(const GameEvent(0, 'restart'));
    }
    for (final e in GameState.eventsFromJson(m)) {
      if (e.seq > _lastSeq) {
        _events.add(e);
        _lastSeq = e.seq;
      }
    }
  }

  @override
  GameState get state => _state;
  @override
  int get localIndex => 1;
  @override
  List<PlayerProfile> get profiles => [hostProfile, me];
  @override
  bool get isMultiplayer => true;
  @override
  bool get disconnected => _disconnected;
  @override
  String get modeKey => 'lan';

  @override
  void update(double dt, PlayerInput local) {
    final g = math.min(dt, 0.05) * config.gameSpeed;
    _sendTimer += dt;
    if (local.shot != null || _sendTimer >= 1 / 30) {
      _sendTimer = 0;
      client.send({
        't': 'in',
        'mx': (local.mx * 1000).round() / 1000,
        'my': (local.my * 1000).round() / 1000,
        'a': (local.aim * 1000).round() / 1000,
        's': local.shot?.index ?? -1,
      });
    }
    _pingTimer += dt;
    if (_pingTimer > 2) {
      _pingTimer = 0;
      client.send({'t': 'ping', 'ts': DateTime.now().millisecondsSinceEpoch});
    }
    if (!_gotSnapshot) return;

    // predict my own movement, then ease toward the host's authority
    final mine = _state.players[1];
    final locked = _state.phase == Phase.gameOver ||
        (_state.phase == Phase.serve && _state.server == 1);
    GameEngine.movePlayer(mine, local, me.stats.runSpeed, g, locked: locked);
    final k = math.min(1.0, dt * 6);
    mine.x += (_authX - mine.x) * k;
    mine.y += (_authY - mine.y) * k;
    _authX += mine.vx * g;
    _authY += mine.vy * g;

    // smooth the opponent
    final opp = _state.players[0];
    _oppX += _oppVx * g;
    _oppY += _oppVy * g;
    opp.x += (_oppX - opp.x) * math.min(1.0, dt * 14);
    opp.y += (_oppY - opp.y) * math.min(1.0, dt * 14);
    opp.runPhase += math.sqrt(_oppVx * _oppVx + _oppVy * _oppVy) * g * 2.2;
    if (opp.swing > 0) opp.swing = math.max(0, opp.swing - g);
    if (mine.swing > 0) mine.swing = math.max(0, mine.swing - g);

    // extrapolate the ball with the same physics the host uses
    if (!_state.ballHeld) {
      BallPhysics.step(_state.ball, g, netActive: _state.phase == Phase.rally);
    }
  }

  @override
  List<GameEvent> takeEvents() {
    final out = List<GameEvent>.of(_events);
    _events.clear();
    return out;
  }

  @override
  void rematch() => client.send({'t': 'rematch'});

  @override
  void leave() => client.close();
}
