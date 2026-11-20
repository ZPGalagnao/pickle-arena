import 'dart:math' as math;

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

/// Everything the HUD shows. The HUD only rebuilds when this changes
/// (a few times per second at most), never every frame.
class _HudData {
  final int s0, s1, servingTeam, serverNumber, rally;
  final Phase phase;
  final String? hint;
  final int hintColor;
  final String? ai;
  final int bannerId;
  final bool bannerVisible;
  final int specialId;
  final bool showResults;
  final bool disconnected;
  final int fps;

  const _HudData({
    this.s0 = 0,
    this.s1 = 0,
    this.servingTeam = 0,
    this.serverNumber = 1,
    this.rally = 0,
    this.phase = Phase.serve,
    this.hint,
    this.hintColor = 0,
    this.ai,
    this.bannerId = 0,
    this.bannerVisible = false,
    this.specialId = 0,
    this.showResults = false,
    this.disconnected = false,
    this.fps = 0,
  });

  @override
  bool operator ==(Object o) =>
      o is _HudData &&
      o.s0 == s0 &&
      o.s1 == s1 &&
      o.servingTeam == servingTeam &&
      o.serverNumber == serverNumber &&
      o.rally == rally &&
      o.phase == phase &&
      o.hint == hint &&
      o.hintColor == hintColor &&
      o.ai == ai &&
      o.bannerId == bannerId &&
      o.bannerVisible == bannerVisible &&
      o.specialId == specialId &&
      o.showResults == showResults &&
      o.disconnected == disconnected &&
      o.fps == fps;

  @override
  int get hashCode => Object.hash(s0, s1, servingTeam, serverNumber, rally, phase, hint, hintColor, ai, bannerId,
      bannerVisible, specialId, showResults, disconnected, fps);
}

class _CtrlData {
  final bool serving, armed, hidden;
  final int meter; // 0..20 (5% steps)
  const _CtrlData(this.serving, this.armed, this.hidden, this.meter);

  @override
  bool operator ==(Object o) =>
      o is _CtrlData && o.serving == serving && o.armed == armed && o.hidden == hidden && o.meter == meter;

  @override
  int get hashCode => Object.hash(serving, armed, hidden, meter);
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final ValueNotifier<_HudData> _hud = ValueNotifier(const _HudData());
  final ValueNotifier<_CtrlData> _ctrl = ValueNotifier(const _CtrlData(false, false, false, 0));
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
  // banner / special tracking
  String _lastBanner = '';
  double _lastBannerTime = 0;
  int _bannerId = 0;
  double _lastSpecialTime = 99;
  int _specialId = 0;
  int _shownSpecialPlayer = -1;
  String _bannerText = '';
  bool _bannerGood = false;
  // throttled extras
  double _aiTimer = 0;
  String? _aiText;
  int _fpsFrames = 0;
  double _fpsTime = 0;
  int _fps = 0;

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
      quality: settings.graphics,
      screenShake: settings.screenShake,
    );
    _fx.maxParticles = settings.graphics == 0 ? 50 : (settings.graphics == 1 ? 110 : 180);
    for (var i = 0; i < _s.profiles.length; i++) {
      FaceCache.get(_s.profiles[i].face).then((img) {
        if (mounted) _scene.faces[i] = img;
      });
    }
    _stepCount = List.filled(_s.profiles.length, 0);
    if (settings.control == ControlMode.tilt) _tilt = TiltController()..start();
    _s.addListener(_onSessionChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Sound.I.music('music_game');
    Sound.I.crowd(0.6);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scene.dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
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
    _hud.dispose();
    _ctrl.dispose();
    Sound.I.crowd(0);
    Sound.I.music('music_menu');
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    // never slow the game down when frames are late (that felt like slow motion)
    if (dt <= 0) dt = 1 / 60;
    if (dt > 0.1) dt = 0.1;
    if (_tilt != null) {
      _input.mx = _tilt!.mx;
      _input.my = _tilt!.my;
    }
    _input.aim = (_input.mx * 1.25).clamp(-1.25, 1.25);
    _input.depth = _input.my.clamp(-1.0, 1.0);
    final st = _s.state;
    if (!_paused || _s.isMultiplayer) {
      _s.update(dt, _input);
      _input.clearEdge();
      _scene.state = _s.state;
      for (final e in _s.takeEvents()) {
        _handleEvent(e);
      }
      final over = st.phase == Phase.gameOver;
      _fx.update(dt, st, gameOver: over);
      _scene.time += dt * (st.slowmo > 0 && !over ? 0.5 : 1);
      _scene.victoryTime = over ? _scene.victoryTime + dt : 0;
      _footsteps(st);
      _crowdTimer += dt;
      if (_crowdTimer > 0.4) {
        _crowdTimer = 0;
        Sound.I.crowd(0.45 + 0.55 * _fx.excitement);
      }
      if (over && _scene.victoryTime > 3.2 && _reward == null && !_rewardPending) _grantReward();
    }
    _fpsFrames++;
    _fpsTime += dt;
    if (_fpsTime >= 0.5) {
      _fps = (_fpsFrames / _fpsTime).round();
      _fpsFrames = 0;
      _fpsTime = 0;
    }
    _aiTimer += dt;
    if (_aiTimer > 0.25) {
      _aiTimer = 0;
      _aiText = _s.aiThought;
    }
    _updateHud(st);
    _frame.value++;
  }

  void _updateHud(GameState st) {
    final myTeam = st.players[_me].team;
    final me = st.players[_me];
    final incoming = st.phase == Phase.rally && st.lastHitter >= 0 && st.hittingTeam != myTeam;
    String? hint;
    var hintColor = AppColors.lime.toARGB32();
    if (st.phase == Phase.serve && st.server == _me && st.phaseTime > 0.5) {
      hint = 'YOUR SERVE  •  tap POWER, SOFT or HIGH  •  joystick left/right to aim';
    } else if (me.frozen > 0) {
      hint = 'FROZEN!';
      hintColor = 0xFF7FE3FF;
    } else if (incoming && st.mustBounce && st.bouncesOnReceiver == 0) {
      hint = 'LET IT BOUNCE (two-bounce rule)';
      hintColor = AppColors.blue.toARGB32();
    } else if (incoming && st.bouncesOnReceiver == 0 && me.y.abs() < 2.134) {
      hint = 'IN THE KITCHEN - no volleys!';
      hintColor = AppColors.pink.toARGB32();
    } else if (me.specialArmed) {
      hint = '${_s.profiles[_me].special.label} ARMED - hit the ball!';
      hintColor = _s.profiles[_me].special.color;
    }
    // a new banner appears when the text changes or its timer restarts
    if (st.bannerTime > 0 && (st.banner != _lastBanner || st.bannerTime > _lastBannerTime + 0.05)) {
      _bannerId++;
      _bannerText = st.banner;
      _bannerGood = st.phase == Phase.gameOver ? st.winner == myTeam : st.pointWinner == myTeam;
    }
    _lastBanner = st.banner;
    _lastBannerTime = st.bannerTime;
    if (st.specialPlayer >= 0 && st.specialTime < _lastSpecialTime && st.specialTime < 0.5) {
      _specialId++;
      _shownSpecialPlayer = st.specialPlayer;
    }
    _lastSpecialTime = st.specialTime;
    final settings = AppScope.read(context).settings;
    _hud.value = _HudData(
      s0: st.score[0],
      s1: st.score[1],
      servingTeam: st.servingTeam,
      serverNumber: st.serverNumber,
      rally: st.phase == Phase.rally ? st.rally : 0,
      phase: st.phase,
      hint: st.phase == Phase.gameOver ? null : hint,
      hintColor: hintColor,
      ai: settings.showAiThoughts ? _aiText : null,
      bannerId: _bannerId,
      bannerVisible: st.bannerTime > 0 && st.phase != Phase.gameOver && st.specialTime >= 1.3,
      specialId: _specialId,
      showResults: st.phase == Phase.gameOver && _scene.victoryTime > 3.2,
      disconnected: _s.disconnected,
      fps: settings.showFps ? _fps : 0,
    );
    _ctrl.value = _CtrlData(st.phase == Phase.serve && st.server == _me, me.specialArmed,
        st.phase == Phase.gameOver, (me.meter.clamp(0.0, 1.0) * 20).floor());
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
          Sound.I.play(steps.isEven ? 'step1' : 'step2', volume: i == _me ? 0.5 : (near ? 0.22 : 0.1));
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
    final teammate = e.player >= 0 && e.player < st.players.length && st.players[e.player].team == myTeam;
    switch (e.type) {
      case 'hit':
        Sound.I.play(switch (ShotKind.values[e.kind]) {
          ShotKind.drive => 'hit_power',
          ShotKind.soft => 'hit_soft',
          ShotKind.lob => 'hit_high',
        }, volume: mine ? 1.0 : (teammate ? 0.85 : 0.7));
        Sound.I.play('swing', volume: mine ? 0.6 : 0.3);
        if (mine && haptics) HapticFeedback.lightImpact();
      case 'serve':
        Sound.I.play('serve', volume: mine ? 1.0 : 0.75);
        Sound.I.play('swing', volume: mine ? 0.5 : 0.25);
      case 'smash':
        Sound.I.play('hit_power');
        Sound.I.play('swing', volume: 0.7);
        Sound.I.play('crowd_cheer', volume: 0.45);
        if (haptics) HapticFeedback.heavyImpact();
      case 'special':
        Sound.I.play('special_${['fire', 'ice', 'thunder', 'phantom', 'tornado'][e.kind]}');
        Sound.I.play('hit_power', volume: 0.9);
        Sound.I.play('slowmo', volume: 0.7);
        Sound.I.play('crowd_cheer', volume: 0.6);
        if (haptics) HapticFeedback.heavyImpact();
      case 'freeze':
        if (st.players[_me].frozen > 0 && haptics) HapticFeedback.mediumImpact();
      case 'ready':
        if (mine) {
          Sound.I.play('ready', volume: 0.7);
          if (haptics) HapticFeedback.selectionClick();
        }
      case 'bounce':
        Sound.I.play('bounce', volume: 0.55);
      case 'net':
        Sound.I.play('net');
      case 'point':
        final error = e.text.contains('OUT') || e.text.contains('NET') || e.text.contains('FAULT');
        final ace = e.text.contains('ACE');
        final big = ace || st.rally >= 8;
        Sound.I.play(e.player == myTeam ? 'point_win' : 'point_lose', volume: 0.45);
        if (big) {
          Sound.I.play('crowd_big', volume: 0.75);
        } else {
          Sound.I.play(error ? 'crowd_aww' : 'crowd_cheer', volume: error ? 0.4 : 0.55);
        }
        if (ace) Sound.I.voice('vo_ace');
        if (st.winner < 0) _callBigPoint(st);
        if (e.player == myTeam && haptics) HapticFeedback.mediumImpact();
      case 'game_over':
        final won = st.winner == myTeam;
        Sound.I.play('slowmo', volume: 0.7);
        Sound.I.play('crowd_big', volume: 0.8);
        Sound.I.play('applause', volume: 0.7);
        Sound.I.voice(won ? 'vo_victory' : 'vo_game_over', gap: 0);
        Future.delayed(const Duration(milliseconds: 2600), () {
          if (mounted && won && _s.state.phase == Phase.gameOver) Sound.I.voice('vo_congrats', gap: 0);
        });
        app.recordResult(_s.modeKey, won);
        if (mounted) setState(() {});
    }
  }

  /// Announcer calls "match point" / "game point" when a team can win on the next rally.
  void _callBigPoint(GameState st) {
    final target = _s.config.pointsToWin;
    if (target > 30) return; // practice
    for (final t in [0, 1]) {
      final me = st.score[t], them = st.score[1 - t];
      if (me >= target - 1 && me > them) {
        Sound.I.voice(me >= target ? 'vo_game_point' : 'vo_match_point', volume: 0.85);
        return;
      }
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
    final size = MediaQuery.sizeOf(context);
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
            // ------------------------------------------------ controls
            if (_s.state.phase != Phase.gameOver)
              if (settings.control == ControlMode.joystick)
                Positioned(
                  left: left ? null : 0,
                  right: left ? 0 : null,
                  top: 56,
                  bottom: 0,
                  width: size.width * 0.42,
                  child: RepaintBoundary(
                    child: FloatingJoystick(
                      radius: 62 * settings.joystickSize,
                      fixed: settings.fixedJoystick,
                      fullSpeedAt: 0.85 - 0.45 * settings.sensitivity,
                      onChanged: (x, y) {
                        _input.mx = x;
                        _input.my = y;
                      },
                    ),
                  ),
                )
              else
                Positioned(
                  left: left ? null : 16,
                  right: left ? 16 : null,
                  bottom: 20,
                  child: _TiltBadge(onCalibrate: () => _tilt?.calibrate()),
                ),
            Positioned(
              right: left ? null : 4,
              left: left ? 4 : null,
              bottom: 2,
              child: RepaintBoundary(
                child: ValueListenableBuilder<_CtrlData>(
                  valueListenable: _ctrl,
                  builder: (context, c, _) {
                    if (c.hidden) return const SizedBox.shrink();
                    final prof = _s.profiles[_me];
                    return Transform.scale(
                      scale: settings.buttonSize,
                      alignment: left ? Alignment.bottomLeft : Alignment.bottomRight,
                      child: ShotButtons(
                        onShot: _shot,
                        onSpecial: _special,
                        serving: c.serving,
                        mirrored: left,
                        meter: c.meter / 20,
                        specialArmed: c.armed,
                        specialColor: Color(prof.special.color),
                        specialName: prof.special.label,
                      ),
                    );
                  },
                ),
              ),
            ),
            // ------------------------------------------------ HUD
            Positioned.fill(
              child: RepaintBoundary(
                child: SafeArea(
                  child: ValueListenableBuilder<_HudData>(
                    valueListenable: _hud,
                    builder: (context, h, _) => _Hud(
                      session: _s,
                      data: h,
                      bannerText: _bannerText,
                      bannerGood: _bannerGood,
                      specialPlayer: _shownSpecialPlayer,
                      onPause: () => _s.canPause ? setState(() => _paused = true) : _confirmQuit(),
                    ),
                  ),
                ),
              ),
            ),
            if (_paused) Positioned.fill(child: _pauseOverlay()),
            Positioned.fill(
              child: ValueListenableBuilder<_HudData>(
                valueListenable: _hud,
                builder: (context, h, _) {
                  if (h.showResults) return _resultsOverlay();
                  if (h.disconnected && h.phase != Phase.gameOver) return _disconnectedOverlay();
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

  Widget _scrim(Widget child) => Container(
        color: const Color(0xD9050B16),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: child,
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
                        children: [for (var r = 0; r < order.length; r++) _rankRow(r, order[r], st)],
                      ),
                    ),
                    Text('Longest rally: ${st.longestRally} shots', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
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
                          child: Text('LEVEL UP!', style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w900, fontSize: 18)),
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
                    Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
                    if (rank == 0)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: medals[0], borderRadius: BorderRadius.circular(6)),
                        child: const Text('MVP', style: TextStyle(color: AppColors.bg, fontWeight: FontWeight.w900, fontSize: 10)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(winner ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded,
                          size: 15, color: winner ? AppColors.lime : AppColors.muted),
                    ),
                  ],
                ),
                Text('Winners ${ms.winners}  •  Aces ${ms.aces}  •  Specials ${ms.specials}  •  Errors ${ms.errors}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
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
                label: 'BACK TO HOME', icon: Icons.home_rounded, colors: const [AppColors.lime, Color(0xFF9CFF57)], onTap: _quit),
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
  final _HudData data;
  final String bannerText;
  final bool bannerGood;
  final int specialPlayer;
  final VoidCallback onPause;
  const _Hud({
    required this.session,
    required this.data,
    required this.bannerText,
    required this.bannerGood,
    required this.specialPlayer,
    required this.onPause,
  });

  @override
  Widget build(BuildContext context) {
    final st = session.state;
    final myTeam = st.players[session.localIndex].team;
    final h = data;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TeamScore(session: session, team: myTeam, score: myTeam == 0 ? h.s0 : h.s1, data: h, alignRight: false),
              const Spacer(),
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xB3091427), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${st.doubles ? 'DOUBLES' : 'SINGLES'}  •  to ${session.config.pointsToWin}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800)),
                    if (h.rally > 1)
                      Text('RALLY ${h.rally}',
                          style: const TextStyle(color: AppColors.lime, fontSize: 12, fontWeight: FontWeight.w900)),
                    if (h.ai != null && h.ai!.isNotEmpty)
                      Text('AI: ${h.ai}', style: const TextStyle(fontSize: 10, color: AppColors.mint, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const Spacer(),
              _TeamScore(
                  session: session, team: 1 - myTeam, score: myTeam == 0 ? h.s1 : h.s0, data: h, alignRight: true),
              const SizedBox(width: 6),
              PressScale(
                onTap: onPause,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: const Color(0x99091427), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                  child: Icon(session.canPause ? Icons.pause_rounded : Icons.close_rounded, size: 20),
                ),
              ),
            ],
          ),
        ),
        if (h.fps > 0)
          Positioned(
            left: 10,
            bottom: 6,
            child: Text('${h.fps} FPS',
                style: TextStyle(
                    color: h.fps >= 50 ? AppColors.mint : (h.fps >= 30 ? AppColors.lime : AppColors.orange),
                    fontWeight: FontWeight.w900,
                    fontSize: 12)),
          ),
        if (specialPlayer >= 0 && h.specialId > 0 && h.phase != Phase.gameOver)
          Align(
            alignment: const Alignment(0, -0.35),
            child: _SpecialBanner(key: ValueKey('sp${h.specialId}'), profile: session.profiles[specialPlayer]),
          ),
        if (h.bannerVisible)
          Align(
            alignment: const Alignment(0, -0.25),
            child: _Banner(key: ValueKey('b${h.bannerId}'), text: bannerText, good: bannerGood, hold: false),
          ),
        if (h.phase == Phase.gameOver && !h.showResults)
          Align(
            alignment: const Alignment(0, -0.6),
            child: _Banner(key: const ValueKey('gameover'), text: st.banner, good: st.winner == myTeam, hold: true),
          ),
        if (h.hint != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Color(h.hintColor).withValues(alpha: 0.18),
                  border: Border.all(color: Color(h.hintColor).withValues(alpha: 0.8)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(h.hint!,
                    style: TextStyle(color: Color(h.hintColor), fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 0.5)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Pops in, holds, then fades out on its own (no per-frame rebuilds).
class _SpecialBanner extends StatefulWidget {
  final PlayerProfile profile;
  const _SpecialBanner({super.key, required this.profile});

  @override
  State<_SpecialBanner> createState() => _SpecialBannerState();
}

class _SpecialBannerState extends State<_SpecialBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final color = Color(profile.special.color);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value * 1.5;
          final k = Curves.easeOutBack.transform((t / 0.25).clamp(0.0, 1.0));
          final fade = 1 - ((t - 1.1) / 0.35).clamp(0.0, 1.0);
          return Opacity(opacity: fade, child: Transform.scale(scale: 0.5 + 0.5 * k, child: child));
        },
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
    );
  }
}

class _Banner extends StatefulWidget {
  final String text;
  final bool good;
  final bool hold; // stay visible (game over)
  const _Banner({super.key, required this.text, required this.good, required this.hold});

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final neutral = text.contains('-') && !text.contains('OUT') && !text.contains('FAULT') && !text.contains('NET');
    final color = neutral ? Colors.white : (widget.good ? AppColors.lime : AppColors.orange);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value * 1.7;
          final appear = (t / 0.3).clamp(0.0, 1.0);
          final fade = widget.hold ? 1.0 : 1 - ((t - 1.35) / 0.35).clamp(0.0, 1.0);
          return Opacity(
            opacity: fade,
            child: Transform.scale(scale: 0.6 + 0.4 * Curves.elasticOut.transform(appear), child: child),
          );
        },
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
    );
  }
}

/// Score card for a team: one face in singles, two overlapping faces in doubles.
class _TeamScore extends StatelessWidget {
  final GameSession session;
  final int team;
  final int score;
  final _HudData data;
  final bool alignRight;
  const _TeamScore(
      {required this.session, required this.team, required this.score, required this.data, required this.alignRight});

  @override
  Widget build(BuildContext context) {
    final st = session.state;
    final members = st.teamPlayers(team);
    final serving = data.servingTeam == team;
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
            Text('$score',
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
        child: Text(st.doubles && !session.config.rallyScoring ? 'SERVE ${data.serverNumber}' : 'SERVE',
            style: const TextStyle(color: AppColors.bg, fontSize: 9, fontWeight: FontWeight.w900)),
      );
}
