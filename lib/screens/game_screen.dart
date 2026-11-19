import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../game/game_state.dart';
import '../game/render/court_view.dart';
import '../game/render/effects.dart';
import '../game/render/game_painter.dart';
import '../game/session.dart';
import '../game/shot_planner.dart';
import '../models/profile.dart';
import '../services/sound_service.dart';
import '../ui/avatar.dart';
import '../ui/controls.dart';
import '../ui/theme.dart';

class GameScreen extends StatefulWidget {
  final GameSession session;
  const GameScreen({super.key, required this.session});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _MatchReward {
  final int xp;
  final int levelBefore, levelAfter;
  const _MatchReward(this.xp, this.levelBefore, this.levelAfter);
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final PlayerInput _input = PlayerInput();
  final Effects _fx = Effects();
  late final GameScene _scene;
  TiltController? _tilt;
  Duration _last = Duration.zero;
  bool _paused = false;
  bool _askedRematch = false;
  _MatchReward? _reward;
  bool _rewardPending = false;
  late List<int> _stepCount;
  double _crowdTimer = 0;

  GameSession get _s => widget.session;
  int get _me => _s.localIndex;

  @override
  void initState() {
    super.initState();
    final settings = AppScope.read(context).settings;
    final myTeam = _s.state.players[_me].team;
    _scene = GameScene(
      state: _s.state,
      profiles: _s.profiles,
      faces: List.filled(_s.profiles.length, null),
      view: CourtView(flip: myTeam == 1),
      fx: _fx,
      localIndex: _me,
      showMarker: settings.showMarker,
    );
    for (var i = 0; i < _s.profiles.length; i++) {
      FaceCache.get(_s.profiles[i].face).then((img) {
        if (mounted) _scene.faces[i] = img;
      });
    }
    _stepCount = List.filled(_s.profiles.length, 0);
    if (settings.control == ControlMode.tilt) _tilt = TiltController()..start();
    _s.addListener(_onSessionChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Sound.I.music('music_game', volume: 0.22);
    Sound.I.crowd(0.3);
    _ticker = createTicker(_onTick)..start();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _scene.state = _s.state;
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tilt?.dispose();
    _s.removeListener(_onSessionChanged);
    _frame.dispose();
    Sound.I.crowd(0);
    Sound.I.music('music_menu');
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.1) dt = 1 / 60;
    if (_tilt != null) {
      _input.mx = _tilt!.mx;
      _input.my = _tilt!.my;
    }
    _input.aim = (_input.mx * 1.25).clamp(-1.25, 1.25);
    _input.depth = _input.my.clamp(-1.0, 1.0);
    if (!_paused || _s.isMultiplayer) {
      _s.update(dt, _input);
      _input.clearEdge();
      final st = _s.state;
      _scene.state = st;
      for (final e in _s.takeEvents()) {
        _handleEvent(e);
      }
      final over = st.phase == Phase.gameOver;
      _fx.update(dt, st, gameOver: over);
      _scene.time += dt * (st.slowmo > 0 && !over ? 0.5 : 1);
      _scene.victoryTime = over ? _scene.victoryTime + dt : 0;
      _footsteps(st);
      _crowdTimer += dt;
      if (_crowdTimer > 0.3) {
        _crowdTimer = 0;
        Sound.I.crowd(0.2 + 0.3 * _fx.excitement);
      }
      if (over && _scene.victoryTime > 3.2 && _reward == null && !_rewardPending) _grantReward();
    }
    _frame.value++;
  }

  void _footsteps(GameState st) {
    for (var i = 0; i < st.players.length; i++) {
      final p = st.players[i];
      final steps = (p.runPhase * 2).floor();
      if (steps != _stepCount[i]) {
        _stepCount[i] = steps;
        final speed = math.sqrt(p.vx * p.vx + p.vy * p.vy);
        if (speed > 2.2 && st.phase != Phase.gameOver) {
          final near = st.players[i].team == st.players[_me].team;
          Sound.I.play(steps.isEven ? 'step1' : 'step2', volume: i == _me ? 0.55 : (near ? 0.25 : 0.12));
        }
      }
    }
  }

  void _handleEvent(GameEvent e) {
    final app = AppScope.read(context);
    final haptics = app.settings.haptics;
    final st = _s.state;
    final myTeam = st.players[_me].team;
    if (e.type == 'restart') {
      _fx.reset();
      _reward = null;
      _askedRematch = false;
      if (mounted) setState(() {});
      return;
    }
    _fx.onEvent(e, st);
    final mine = e.player == _me;
    switch (e.type) {
      case 'hit':
        Sound.I.play(switch (ShotKind.values[e.kind]) {
          ShotKind.drive => 'hit_power',
          ShotKind.soft => 'hit_soft',
          ShotKind.lob => 'hit_high',
        }, volume: mine ? 1 : 0.75);
        if (mine) Sound.I.play('swing', volume: 0.5);
        if (mine && haptics) HapticFeedback.lightImpact();
      case 'serve':
        Sound.I.play('serve', volume: mine ? 1 : 0.7);
      case 'smash':
        Sound.I.play('hit_power');
        Sound.I.play('crowd_cheer', volume: 0.5);
        if (haptics) HapticFeedback.heavyImpact();
      case 'special':
        Sound.I.play('special_${['fire', 'ice', 'thunder', 'phantom', 'tornado'][e.kind]}');
        Sound.I.play('slowmo', volume: 0.8);
        Sound.I.play('crowd_cheer', volume: 0.7);
        if (haptics) HapticFeedback.heavyImpact();
      case 'freeze':
        if (st.players[_me].frozen > 0 && haptics) HapticFeedback.mediumImpact();
      case 'ready':
        if (mine) {
          Sound.I.play('ready', volume: 0.7);
          if (haptics) HapticFeedback.selectionClick();
        }
      case 'bounce':
        Sound.I.play('bounce', volume: 0.5);
      case 'net':
        Sound.I.play('net');
      case 'point':
        final error = e.text.contains('OUT') || e.text.contains('NET') || e.text.contains('FAULT');
        Sound.I.play(e.player == myTeam ? 'point_win' : 'point_lose', volume: 0.6);
        Sound.I.play(error ? 'crowd_aww' : 'crowd_cheer', volume: error ? 0.55 : 0.75);
        if (e.player == myTeam && haptics) HapticFeedback.mediumImpact();
      case 'game_over':
        final won = st.winner == myTeam;
        Sound.I.play('slowmo', volume: 0.8);
        Sound.I.play(won ? 'win_fanfare' : 'lose', volume: 0.9);
        Sound.I.play('applause', volume: 0.8);
        Sound.I.play('crowd_cheer', volume: 0.9);
        app.recordResult(_s.modeKey, won);
        if (mounted) setState(() {});
    }
  }

  /// XP for the local player once the victory cinematic has played.
  Future<void> _grantReward() async {
    _rewardPending = true;
    final st = _s.state;
    final ms = st.stats[_me];
    final won = st.winner == st.players[_me].team;
    final xp = (won ? 120 : 45) + ms.points * 4 + ms.winners * 6 + ms.aces * 6 + ms.specials * 10 + ms.smashes * 4;
    final (before, after) = await AppScope.read(context).addXp(xp);
    _rewardPending = false;
    if (mounted) setState(() => _reward = _MatchReward(xp, before, after));
    if (after > before) Sound.I.play('ready');
  }

  void _shot(ShotKind k) {
    if (_paused) return;
    _input.shot = k;
  }

  void _special() {
    if (_paused) return;
    _input.special = true;
    Sound.I.play('ui_click', volume: 0.6);
  }

  Future<void> _quit() async {
    _s.leave();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final left = settings.leftHanded;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_s.canPause) {
          setState(() => _paused = !_paused);
        } else {
          _confirmQuit();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: GamePainter(_scene, repaint: _frame))),
            ),
            if (_s.state.phase == Phase.gameOver)
              const SizedBox.shrink() // controls hidden during the victory scene
            else if (settings.control == ControlMode.joystick)
              Positioned(
                left: left ? null : 0,
                right: left ? 0 : null,
                bottom: 0,
                width: MediaQuery.sizeOf(context).width * 0.3,
                height: MediaQuery.sizeOf(context).height * 0.72,
                child: FloatingJoystick(onChanged: (x, y) {
                  _input.mx = x;
                  _input.my = y;
                }),
              )
            else
              Positioned(
                left: left ? null : 16,
                right: left ? 16 : null,
                bottom: 20,
                child: _TiltBadge(onCalibrate: () => _tilt?.calibrate()),
              ),
            Positioned(
              right: left ? null : 6,
              left: left ? 6 : null,
              bottom: 4,
              child: SafeArea(
                top: false,
                left: false,
                child: ValueListenableBuilder<int>(
                  valueListenable: _frame,
                  builder: (context, _, _) {
                    final st = _s.state;
                    if (st.phase == Phase.gameOver) return const SizedBox.shrink();
                    final me = st.players[_me];
                    final prof = _s.profiles[_me];
                    return ShotButtons(
                      onShot: _shot,
                      onSpecial: _special,
                      serving: st.phase == Phase.serve && st.server == _me,
                      mirrored: left,
                      meter: me.meter,
                      specialArmed: me.specialArmed,
                      specialColor: Color(prof.special.color),
                      specialName: prof.special.label,
                    );
                  },
                ),
              ),
            ),
            SafeArea(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, _, _) => _Hud(
                  session: _s,
                  onPause: () => _s.canPause ? setState(() => _paused = true) : _confirmQuit(),
                  showAi: settings.showAiThoughts,
                ),
              ),
            ),
            if (_paused) Positioned.fill(child: _pauseOverlay()),
            Positioned.fill(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, _, _) {
                  if (_s.state.phase == Phase.gameOver) {
                    return _scene.victoryTime > 3.2 ? _resultsOverlay() : const SizedBox.shrink();
                  }
                  if (_s.disconnected) return _disconnectedOverlay();
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmQuit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Leave the match?'),
        content: const Text('The other players will be disconnected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('STAY')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('LEAVE')),
        ],
      ),
    );
    if (ok == true) _quit();
  }

  Widget _scrim(Widget child) => SizedBox.expand(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            color: const Color(0xAA050B16),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      );

  Widget _pauseOverlay() {
    return _scrim(ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('PAUSED',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4)),
            const SizedBox(height: 14),
            BigButton(
                label: 'RESUME',
                icon: Icons.play_arrow_rounded,
                colors: const [AppColors.lime, Color(0xFF9CFF57)],
                onTap: () => setState(() => _paused = false)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: BigButton(
                      label: 'RESTART',
                      icon: Icons.replay_rounded,
                      colors: const [AppColors.blue, AppColors.purple],
                      textColor: Colors.white,
                      onTap: () {
                        _fx.reset();
                        _reward = null;
                        _s.rematch();
                        setState(() => _paused = false);
                      }),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BigButton(
                      label: 'QUIT',
                      icon: Icons.home_rounded,
                      colors: const [Color(0xFF37474F), Color(0xFF263238)],
                      textColor: Colors.white,
                      onTap: _quit),
                ),
              ],
            ),
          ],
        ),
      ),
    ));
  }

  Widget _resultsOverlay() {
    final st = _s.state;
    final myTeam = st.players[_me].team;
    final won = st.winner == myTeam;
    final order = [for (var i = 0; i < st.players.length; i++) i]
      ..sort((a, b) => st.stats[b].rating.compareTo(st.stats[a].rating));
    final reward = _reward;
    final me = _s.profiles[_me];
    return Container(
      color: const Color(0xD9050B16),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ------------------------------------------------ ranking
            Expanded(
              flex: 6,
              child: GlassCard(
                padding: const EdgeInsets.all(14),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [(won ? AppColors.lime : AppColors.pink).withValues(alpha: 0.3), AppColors.card.withValues(alpha: 0.95)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(won ? 'VICTORY!' : 'DEFEAT',
                            style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                fontStyle: FontStyle.italic,
                                letterSpacing: 2,
                                color: won ? AppColors.lime : AppColors.pink)),
                        const Spacer(),
                        Text('${st.score[myTeam]} - ${st.score[1 - myTeam]}',
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text('MATCH RANKING',
                        style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w900, letterSpacing: 1.6, fontSize: 12)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (var r = 0; r < order.length; r++) _rankRow(r, order[r], st),
                        ],
                      ),
                    ),
                    Text('Longest rally: ${st.longestRally} shots',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // ------------------------------------------------ XP + buttons
            Expanded(
              flex: 4,
              child: GlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    FaceAvatar(profile: me, size: 64),
                    const SizedBox(height: 4),
                    Text(me.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    Text('LV ${me.level}  ${me.title.toUpperCase()}',
                        style: const TextStyle(color: AppColors.lime, fontWeight: FontWeight.w900, fontSize: 12)),
                    const SizedBox(height: 8),
                    if (reward != null) ...[
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 900),
                        builder: (context, k, _) {
                          final lvStart = PlayerLevel.xpFor(me.level), lvEnd = PlayerLevel.xpFor(me.level + 1);
                          final frac = ((me.xp - lvStart) / (lvEnd - lvStart)).clamp(0.0, 1.0) * k;
                          return Column(
                            children: [
                              Text('+${(reward.xp * k).round()} XP',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.mint)),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                    value: frac, minHeight: 9, color: AppColors.mint, backgroundColor: Colors.white12),
                              ),
                            ],
                          );
                        },
                      ),
                      if (reward.levelAfter > reward.levelBefore)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('LEVEL UP!',
                              style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w900, fontSize: 18)),
                        ),
                    ] else
                      const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    const Spacer(),
                    if (_s.opponentWantsRematch)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text('Someone wants a rematch!',
                            style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                    BigButton(
                      label: _s is ClientSession ? (_askedRematch ? 'ASKED' : 'REMATCH') : 'REMATCH',
                      icon: Icons.replay_rounded,
                      colors: const [AppColors.lime, Color(0xFF9CFF57)],
                      onTap: (_s is ClientSession && _askedRematch)
                          ? null
                          : () {
                              if (_s is ClientSession) {
                                _s.rematch();
                                setState(() => _askedRematch = true);
                              } else {
                                _fx.reset();
                                _reward = null;
                                _s.rematch();
                              }
                            },
                    ),
                    const SizedBox(height: 8),
                    BigButton(
                      label: 'HOME',
                      icon: Icons.home_rounded,
                      colors: const [Color(0xFF37474F), Color(0xFF263238)],
                      textColor: Colors.white,
                      onTap: _quit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rankRow(int rank, int i, GameState st) {
    final p = _s.profiles[i];
    final ms = st.stats[i];
    final winner = st.players[i].team == st.winner;
    const medals = [Color(0xFFFFD54F), Color(0xFFCFD8DC), Color(0xFFFFAB91), Color(0xFF90A4AE)];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: i == _me ? AppColors.lime.withValues(alpha: 0.12) : const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: rank == 0 ? Border.all(color: medals[0], width: 1.5) : null,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: medals[rank],
            child: Text('${rank + 1}', style: const TextStyle(color: AppColors.bg, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          FaceAvatar(profile: p, size: 34),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                        child: Text(p.name,
                            overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
                    if (rank == 0)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: medals[0], borderRadius: BorderRadius.circular(6)),
                        child: const Text('MVP',
                            style: TextStyle(color: AppColors.bg, fontWeight: FontWeight.w900, fontSize: 10)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(winner ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded,
                          size: 15, color: winner ? AppColors.lime : AppColors.muted),
                    ),
                  ],
                ),
                Text(
                  'Winners ${ms.winners}  •  Aces ${ms.aces}  •  Specials ${ms.specials}  •  Errors ${ms.errors}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(ms.rating.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _disconnectedOverlay() {
    return _scrim(ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.orange),
            const SizedBox(height: 8),
            const Text('Connection lost', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Your opponent left or the Wi-Fi dropped.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            BigButton(
                label: 'BACK TO HOME',
                icon: Icons.home_rounded,
                colors: const [AppColors.lime, Color(0xFF9CFF57)],
                onTap: _quit),
          ],
        ),
      ),
    ));
  }
}

class _TiltBadge extends StatelessWidget {
  final VoidCallback onCalibrate;
  const _TiltBadge({required this.onCalibrate});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onCalibrate,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.screen_rotation_alt_rounded, color: AppColors.lime),
          SizedBox(height: 2),
          Text('TILT MODE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          Text('tap to re-center', style: TextStyle(color: AppColors.muted, fontSize: 10)),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  final GameSession session;
  final VoidCallback onPause;
  final bool showAi;
  const _Hud({required this.session, required this.onPause, required this.showAi});

  @override
  Widget build(BuildContext context) {
    final st = session.state;
    final me = session.localIndex;
    final myTeam = st.players[me].team;
    final incoming = st.phase == Phase.rally && st.lastHitter >= 0 && st.hittingTeam != myTeam;
    final myP = st.players[me];
    String? hint;
    Color hintColor = AppColors.lime;
    if (st.phase == Phase.serve && st.server == me && st.phaseTime > 0.5) {
      hint = 'YOUR SERVE  •  tap POWER, SOFT or HIGH  •  joystick left/right to aim';
    } else if (myP.frozen > 0) {
      hint = 'FROZEN!';
      hintColor = const Color(0xFF7FE3FF);
    } else if (incoming && st.mustBounce && st.bouncesOnReceiver == 0) {
      hint = 'LET IT BOUNCE (two-bounce rule)';
      hintColor = AppColors.blue;
    } else if (incoming && st.bouncesOnReceiver == 0 && myP.y.abs() < 2.134) {
      hint = 'IN THE KITCHEN - no volleys!';
      hintColor = AppColors.pink;
    } else if (myP.specialArmed) {
      hint = '${session.profiles[me].special.label} ARMED - hit the ball!';
      hintColor = Color(session.profiles[me].special.color);
    }
    final specialShowing = st.specialPlayer >= 0 && st.specialTime < 1.3 && st.phase != Phase.gameOver;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TeamScore(session: session, team: myTeam, alignRight: false),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xB3091427), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          Text('${st.doubles ? 'DOUBLES' : 'SINGLES'}  •  to ${session.config.pointsToWin}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800)),
                          if (st.rally > 1 && st.phase == Phase.rally)
                            Text('RALLY ${st.rally}',
                                style: const TextStyle(color: AppColors.lime, fontSize: 12, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    if (showAi && session.aiThought != null && session.aiThought!.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(8)),
                        child: Text('AI: ${session.aiThought}',
                            style: const TextStyle(fontSize: 10, color: AppColors.mint, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              _TeamScore(session: session, team: 1 - myTeam, alignRight: true),
              const SizedBox(width: 6),
              PressScale(
                onTap: onPause,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: const Color(0x99091427), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                  child: Icon(session.canPause ? Icons.pause_rounded : Icons.close_rounded, size: 20),
                ),
              ),
            ],
          ),
        ),
        if (specialShowing)
          Align(
            alignment: const Alignment(0, -0.35),
            child: _SpecialBanner(
              profile: session.profiles[st.specialPlayer],
              t: st.specialTime,
            ),
          )
        else if (st.bannerTime > 0 && st.banner.isNotEmpty && st.phase != Phase.gameOver)
          Align(
            alignment: const Alignment(0, -0.25),
            child: _Banner(text: st.banner, t: st.bannerTime, good: st.pointWinner == myTeam),
          ),
        if (st.phase == Phase.gameOver)
          Align(
            alignment: const Alignment(0, -0.6),
            child: _Banner(text: st.banner, t: 1, good: st.winner == myTeam),
          ),
        if (hint != null && st.phase != Phase.gameOver)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: hintColor.withValues(alpha: 0.18),
                  border: Border.all(color: hintColor.withValues(alpha: 0.8)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(hint,
                    style: TextStyle(color: hintColor, fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 0.5)),
              ),
            ),
          ),
      ],
    );
  }
}

class _SpecialBanner extends StatelessWidget {
  final PlayerProfile profile;
  final double t;
  const _SpecialBanner({required this.profile, required this.t});

  @override
  Widget build(BuildContext context) {
    final color = Color(profile.special.color);
    final k = Curves.easeOutBack.transform((t / 0.25).clamp(0.0, 1.0));
    final fade = (1 - ((t - 1.0) / 0.3).clamp(0.0, 1.0));
    return IgnorePointer(
      child: Opacity(
        opacity: fade,
        child: Transform.scale(
          scale: 0.5 + 0.5 * k,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 18, 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.35)]),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 24)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaceAvatar(profile: profile, size: 46),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(profile.name.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.white)),
                    Text(profile.special.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
                            shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final double t;
  final bool good;
  const _Banner({required this.text, required this.t, required this.good});

  @override
  Widget build(BuildContext context) {
    final appear = (1 - math.max(0, t - 1.4) / 0.3).clamp(0.0, 1.0);
    final fade = t.clamp(0.0, 0.35) / 0.35;
    final scale = 0.6 + 0.4 * Curves.elasticOut.transform(appear);
    final neutral = text.contains('-') && !text.contains('OUT') && !text.contains('FAULT') && !text.contains('NET');
    final color = neutral ? Colors.white : (good ? AppColors.lime : AppColors.orange);
    return IgnorePointer(
      child: Opacity(
        opacity: fade,
        child: Transform.scale(
          scale: scale,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              letterSpacing: 2,
              color: color,
              shadows: const [Shadow(color: Colors.black, blurRadius: 12), Shadow(color: Colors.black54, blurRadius: 2)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Score card for a team: one face in singles, two overlapping faces in doubles.
class _TeamScore extends StatelessWidget {
  final GameSession session;
  final int team;
  final bool alignRight;
  const _TeamScore({required this.session, required this.team, required this.alignRight});

  @override
  Widget build(BuildContext context) {
    final st = session.state;
    final members = st.teamPlayers(team);
    final serving = st.servingTeam == team;
    final first = session.profiles[members.first.index];
    final faces = SizedBox(
      width: 40.0 + (members.length - 1) * 24,
      height: 40,
      child: Stack(
        children: [
          for (var k = 0; k < members.length; k++)
            Positioned(
              left: alignRight ? null : k * 24.0,
              right: alignRight ? k * 24.0 : null,
              child: FaceAvatar(profile: session.profiles[members[k].index], size: 40),
            ),
        ],
      ),
    );
    final names = members.map((p) => session.profiles[p.index].name).join(' & ');
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Text(names, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (serving && alignRight) _serveDot(st),
            Text('${st.score[team]}',
                style: TextStyle(
                    fontSize: 26, height: 1.0, fontWeight: FontWeight.w900, color: serving ? AppColors.lime : Colors.white)),
            if (serving && !alignRight) _serveDot(st),
          ],
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0x99091427),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(first.look.jersey).withValues(alpha: 0.6), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignRight ? [info, const SizedBox(width: 8), faces] : [faces, const SizedBox(width: 8), info],
      ),
    );
  }

  Widget _serveDot(GameState st) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.circular(8)),
        child: Text(st.doubles && !session.config.rallyScoring ? 'SERVE ${st.serverNumber}' : 'SERVE',
            style: const TextStyle(color: AppColors.bg, fontSize: 9, fontWeight: FontWeight.w900)),
      );
}
