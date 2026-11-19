// A GameSession hides where the game is simulated:
//  * AiSession     - engine + AI players on this phone (singles or doubles)
//  * HostSession   - engine on this phone; other players' controls arrive over
//                    Wi-Fi; empty doubles slots are played by the AI
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
  int get playerCount => profiles.length;

  void update(double dt, PlayerInput local);
  List<GameEvent> takeEvents();
  void rematch();
  void leave() {}
}

/// Runs AI controllers for the given player slots.
class _Bots {
  final Map<int, AiController> ais;
  _Bots(this.ais);

  void fill(GameState s, List<PlayerProfile> profiles, List<PlayerInput> inputs, double gameDt) {
    ais.forEach((i, ai) => inputs[i] = ai.update(s, profiles[i], gameDt));
  }
}

class AiSession extends GameSession {
  final PlayerProfile human;
  final List<PlayerProfile> others; // singles: [opponent]; doubles: [partner, opp1, opp2]
  final List<AiDifficulty> levels; // difficulty of each entry in [others]
  final List<AiStyle> styles;
  final PickleBrain brain;
  @override
  final MatchConfig config;
  final bool autoHit;
  final bool moveAssist;
  late GameEngine _engine;
  late _Bots _bots;
  late List<PlayerInput> _inputs;

  AiSession({
    required this.human,
    required this.others,
    required this.levels,
    required this.brain,
    required this.config,
    List<AiStyle>? styles,
    this.autoHit = true,
    this.moveAssist = true,
  }) : styles = styles ?? List.filled(others.length, AiStyle.balanced) {
    _newMatch();
  }

  void _newMatch() {
    final profiles = [human, ...others];
    _engine = GameEngine(
      config: config,
      profiles: profiles,
      noiseMul: [1, for (final l in levels) l.noiseMul],
      speedMul: [1, for (final l in levels) l.speedMul],
      autoHit: [autoHit, for (final _ in others) false],
      moveAssist: [moveAssist, for (final _ in others) false],
    );
    _bots = _Bots({
      for (var k = 0; k < others.length; k++)
        k + 1: AiController(brain, levels[k], k + 1, style: styles[k]),
    });
    _inputs = [for (var i = 0; i < profiles.length; i++) PlayerInput()];
  }

  @override
  GameState get state => _engine.s;
  @override
  int get localIndex => 0;
  @override
  List<PlayerProfile> get profiles => [human, ...others];
  @override
  bool get isMultiplayer => false;
  @override
  String get modeKey => '${config.doubles ? 'ai2' : 'ai'}_${levels.last.id}';
  @override
  String? get aiThought => _bots.ais[profiles.length - 1]?.lastThought;

  @override
  void update(double dt, PlayerInput local) {
    _inputs[0] = local;
    _bots.fill(_engine.s, profiles, _inputs, dt * config.gameSpeed * (_engine.s.slowmo > 0 ? 0.3 : 1));
    _engine.update(dt, _inputs);
  }

  @override
  List<GameEvent> takeEvents() => _engine.drainEvents();

  @override
  void rematch() {
    _newMatch();
    notifyListeners();
  }
}

/// Demo match on the home screen: AI vs AI doubles.
class DemoSession {
  final PickleBrain brain;
  final List<PlayerProfile> profiles;
  late GameEngine engine;
  late _Bots _bots;
  final List<PlayerInput> _inputs;

  DemoSession(this.brain, this.profiles) : _inputs = [for (final _ in profiles) PlayerInput()] {
    _start();
  }

  void _start() {
    engine = GameEngine(
      config: MatchConfig(pointsToWin: 99, gameSpeed: 0.85, doubles: profiles.length == 4),
      profiles: profiles,
      noiseMul: List.filled(profiles.length, 1.2),
      autoHit: List.filled(profiles.length, false),
    );
    _bots = _Bots({
      for (var i = 0; i < profiles.length; i++) i: AiController(brain, AiDifficulty.hard, i),
    });
  }

  void update(double dt) {
    _bots.fill(engine.s, profiles, _inputs, dt * engine.config.gameSpeed * (engine.s.slowmo > 0 ? 0.3 : 1));
    engine.update(dt, _inputs);
    engine.drainEvents();
    if (engine.s.score[0] + engine.s.score[1] > 40) _start();
  }
}

class HostSession extends GameSession {
  final LanHost host;
  final List<PlayerProfile> slots; // every player in the match
  final Map<int, LanPeer> slotPeers; // slots played by other phones
  final PickleBrain brain;
  @override
  final MatchConfig config;
  final bool myAutoHit;
  final bool myMoveAssist;
  late GameEngine _engine;
  late _Bots _bots;
  late List<PlayerInput> _inputs;
  double _snapTimer = 0;
  bool _disconnected = false;
  final Set<int> _wantsRematch = {};
  final List<String> _notices = [];

  HostSession({
    required this.host,
    required this.slots,
    required this.slotPeers,
    required this.brain,
    required this.config,
    required this.myAutoHit,
    this.myMoveAssist = true,
  }) {
    host.accepting = false;
    host.onMessage = _onMessage;
    host.onPeerLeft = (peer) {
      final slot = slotPeers.entries.where((e) => identical(e.value, peer)).map((e) => e.key).firstOrNull;
      if (slot == null) return;
      slotPeers.remove(slot);
      if (slotPeers.isEmpty && !config.doubles) {
        _disconnected = true;
      } else {
        // an AI takes over the empty slot so the match can go on
        _bots.ais[slot] = AiController(brain, AiDifficulty.byId(config.botLevel), slot);
        _notices.add('${slots[slot].name} left - AI took over');
      }
      notifyListeners();
    };
    _newMatch();
  }

  void _newMatch() {
    final n = slots.length;
    _engine = GameEngine(
      config: config,
      profiles: slots,
      noiseMul: [
        for (var i = 0; i < n; i++)
          i == 0 || slotPeers.containsKey(i) ? 1.0 : AiDifficulty.byId(config.botLevel).noiseMul
      ],
      speedMul: [
        for (var i = 0; i < n; i++)
          i == 0 || slotPeers.containsKey(i) ? 1.0 : AiDifficulty.byId(config.botLevel).speedMul
      ],
      autoHit: [
        for (var i = 0; i < n; i++) i == 0 ? myAutoHit : (slotPeers[i]?.assist ?? false)
      ],
      moveAssist: [
        for (var i = 0; i < n; i++) i == 0 ? myMoveAssist : (slotPeers[i]?.assist ?? false)
      ],
    );
    _bots = _Bots({
      for (var i = 1; i < n; i++)
        if (!slotPeers.containsKey(i)) i: AiController(brain, AiDifficulty.byId(config.botLevel), i),
    });
    _inputs = [for (var i = 0; i < n; i++) PlayerInput()];
    _wantsRematch.clear();
  }

  void _onMessage(LanPeer peer, Map<String, dynamic> m) {
    final slot = peer.slot;
    if (slot <= 0 || slot >= _inputs.length) return;
    switch (m['t']) {
      case 'in':
        final inp = _inputs[slot];
        inp.mx = ((m['mx'] as num?) ?? 0).toDouble().clamp(-1.0, 1.0);
        inp.my = ((m['my'] as num?) ?? 0).toDouble().clamp(-1.0, 1.0);
        inp.aim = ((m['a'] as num?) ?? 0).toDouble().clamp(-1.25, 1.25);
        inp.depth = ((m['d'] as num?) ?? 0).toDouble().clamp(-1.0, 1.0);
        final s = (m['s'] as int?) ?? -1;
        if (s >= 0 && s < ShotKind.values.length) inp.shot = ShotKind.values[s];
        if (m['x'] == 1) inp.special = true;
      case 'rematch':
        _wantsRematch.add(slot);
        notifyListeners();
      case 'ping':
        host.send(peer, {'t': 'pong', 'ts': m['ts']});
    }
  }

  @override
  GameState get state => _engine.s;
  @override
  int get localIndex => 0;
  @override
  List<PlayerProfile> get profiles => slots;
  @override
  bool get isMultiplayer => true;
  @override
  bool get disconnected => _disconnected;
  @override
  bool get opponentWantsRematch => _wantsRematch.isNotEmpty;
  @override
  String get modeKey => config.doubles ? 'lan2' : 'lan';
  @override
  String? get aiThought => _notices.isEmpty ? null : _notices.last;

  @override
  void update(double dt, PlayerInput local) {
    _inputs[0] = local;
    _bots.fill(_engine.s, slots, _inputs, dt * config.gameSpeed * (_engine.s.slowmo > 0 ? 0.3 : 1));
    _engine.update(dt, _inputs);
    for (final i in slotPeers.keys) {
      _inputs[i].clearEdge();
    }
    _snapTimer += dt;
    if (_snapTimer >= 1 / 30) {
      _snapTimer = 0;
      host.broadcast(_engine.s.toJson());
    }
  }

  @override
  List<GameEvent> takeEvents() => _engine.drainEvents();

  @override
  void rematch() {
    _newMatch();
    host.broadcast({'t': 'restart'});
    host.broadcast(_engine.s.toJson());
    notifyListeners();
  }

  @override
  void leave() {
    host.stop();
  }
}

class ClientSession extends GameSession {
  final LanClient client;
  final List<PlayerProfile> slots;
  @override
  final int localIndex;
  @override
  final MatchConfig config;
  final GameState _state;
  final List<GameEvent> _events = [];
  int _lastSeq = 0;
  bool _gotSnapshot = false;
  double _authX = 0, _authY = 0;
  final List<double> _tx, _ty, _tvx, _tvy; // targets for other players
  double _sendTimer = 0;
  bool _disconnected = false;
  bool _restartPending = false;
  int pingMs = 0;
  double _pingTimer = 0;

  ClientSession({
    required this.client,
    required this.slots,
    required this.localIndex,
    required this.config,
  })  : _state = GameState(playerCount: slots.length),
        _tx = List.filled(slots.length, 0),
        _ty = List.filled(slots.length, 0),
        _tvx = List.filled(slots.length, 0),
        _tvy = List.filled(slots.length, 0) {
    client.onMessage = _onMessage;
    client.onDisconnected = () {
      _disconnected = true;
      notifyListeners();
    };
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
    final n = _state.players.length;
    final keepX = [for (final p in _state.players) p.x];
    final keepY = [for (final p in _state.players) p.y];
    final keepRun = [for (final p in _state.players) p.runPhase];
    final mine = _state.players[localIndex];
    final keepVx = mine.vx, keepVy = mine.vy;
    final prevPhase = _state.phase;
    _state.applyJson(m);
    for (var i = 0; i < n; i++) {
      final p = _state.players[i];
      _tx[i] = p.x;
      _ty[i] = p.y;
      _tvx[i] = p.vx;
      _tvy[i] = p.vy;
    }
    _authX = mine.x;
    _authY = mine.y;
    final teleport = !_gotSnapshot ||
        (prevPhase != Phase.serve && _state.phase == Phase.serve) ||
        _restartPending;
    for (var i = 0; i < n; i++) {
      final p = _state.players[i];
      p.runPhase = keepRun[i];
      if (!teleport) {
        p.x = keepX[i];
        p.y = keepY[i];
      }
    }
    if (!teleport) {
      mine
        ..vx = keepVx
        ..vy = keepVy;
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
  List<PlayerProfile> get profiles => slots;
  @override
  bool get isMultiplayer => true;
  @override
  bool get disconnected => _disconnected;
  @override
  String get modeKey => config.doubles ? 'lan2' : 'lan';

  @override
  void update(double dt, PlayerInput local) {
    final slow = _state.slowmo > 0 ? GameEngine.slowmoScale : 1.0;
    if (_state.slowmo > 0) _state.slowmo = math.max(0, _state.slowmo - dt);
    final g = math.min(dt, 0.05) * config.gameSpeed * slow;
    _sendTimer += dt;
    if (local.shot != null || local.special || _sendTimer >= 1 / 30) {
      _sendTimer = 0;
      client.send({
        't': 'in',
        'mx': (local.mx * 1000).round() / 1000,
        'my': (local.my * 1000).round() / 1000,
        'a': (local.aim * 1000).round() / 1000,
        'd': (local.depth * 1000).round() / 1000,
        's': local.shot?.index ?? -1,
        if (local.special) 'x': 1,
      });
    }
    _pingTimer += dt;
    if (_pingTimer > 2) {
      _pingTimer = 0;
      client.send({'t': 'ping', 'ts': DateTime.now().millisecondsSinceEpoch});
    }
    if (!_gotSnapshot) return;

    for (var i = 0; i < _state.players.length; i++) {
      final p = _state.players[i];
      if (i == localIndex) {
        // predict my own movement, then ease toward the host's authority
        final locked = _state.phase == Phase.gameOver || (_state.phase == Phase.serve && _state.server == i);
        final speed = slots[i].stats.runSpeed * (p.frozen > 0 ? 0.35 : 1.0);
        GameEngine.movePlayer(p, local, speed, g, locked: locked);
        final k = math.min(1.0, dt * 6);
        p.x += (_authX - p.x) * k;
        p.y += (_authY - p.y) * k;
        _authX += p.vx * g;
        _authY += p.vy * g;
      } else {
        _tx[i] += _tvx[i] * g;
        _ty[i] += _tvy[i] * g;
        p.x += (_tx[i] - p.x) * math.min(1.0, dt * 14);
        p.y += (_ty[i] - p.y) * math.min(1.0, dt * 14);
        p.runPhase += math.sqrt(_tvx[i] * _tvx[i] + _tvy[i] * _tvy[i]) * g * 2.2;
      }
      if (p.swing > 0) p.swing = math.max(0, p.swing - g);
    }

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
