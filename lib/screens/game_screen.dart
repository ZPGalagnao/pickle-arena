import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../game/game_state.dart';
import '../game/render/court_view.dart';
import '../game/render/effects.dart';
import '../game/render/game_painter.dart';
import '../game/session.dart';
import '../game/shot_planner.dart';
import '../ui/avatar.dart';
import '../ui/controls.dart';
import '../ui/theme.dart';

class GameScreen extends StatefulWidget {
  final GameSession session;
  const GameScreen({super.key, required this.session});

  @override
  State<GameScreen> createState() => _GameScreenState();
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
  bool _resultRecorded = false;
  bool _askedRematch = false;

  GameSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    final settings = AppScope.read(context).settings;
    _scene = GameScene(
      state: _s.state,
      profiles: _s.profiles,
      faces: [null, null],
      view: CourtView(flip: _s.localIndex == 1),
      fx: _fx,
      localIndex: _s.localIndex,
      showMarker: settings.showMarker,
      topInset: 104,
      bottomInset: 170,
    );
    for (var i = 0; i < 2; i++) {
      FaceCache.get(_s.profiles[i].face).then((img) {
        if (mounted) _scene.faces[i] = img;
      });
    }
    if (settings.control == ControlMode.tilt) {
      _tilt = TiltController()..start();
    }
    _s.addListener(_onSessionChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
    if (!_paused || _s.isMultiplayer) {
      _s.update(dt, _input);
      _input.clearEdge();
      _scene.state = _s.state;
      for (final e in _s.takeEvents()) {
        _handleEvent(e);
      }
      _fx.update(dt, _s.state.ball, !_s.state.ballHeld && _s.state.phase == Phase.rally);
      _scene.time += dt;
    }
    _frame.value++;
  }

  void _handleEvent(GameEvent e) {
    final app = AppScope.read(context);
    final haptics = app.settings.haptics;
    if (e.type == 'restart') {
      _fx.reset();
      _resultRecorded = false;
      _askedRematch = false;
      if (mounted) setState(() {});
      return;
    }
    _fx.onEvent(e, _s.state.ball);
    if (!haptics) {
      // no vibration
    } else if ((e.type == 'hit' || e.type == 'serve') && e.player == _s.localIndex) {
      HapticFeedback.lightImpact();
    } else if (e.type == 'smash') {
      HapticFeedback.heavyImpact();
    } else if (e.type == 'point' && e.player == _s.localIndex) {
      HapticFeedback.mediumImpact();
    }
    if (e.type == 'game_over' && !_resultRecorded) {
      _resultRecorded = true;
      app.recordResult(_s.modeKey, _s.state.winner == _s.localIndex);
      if (mounted) setState(() {});
    }
  }

  void _shot(ShotKind k) {
    if (_paused) return;
    _input.shot = k;
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
              child: RepaintBoundary(
                child: CustomPaint(painter: GamePainter(_scene, repaint: _frame)),
              ),
            ),
            // controls
            if (settings.control == ControlMode.joystick)
              Positioned(
                left: left ? null : 0,
                right: left ? 0 : null,
                bottom: 0,
                width: MediaQuery.sizeOf(context).width * 0.5,
                height: 230,
                child: FloatingJoystick(onChanged: (x, y) {
                  _input.mx = x;
                  _input.my = y;
                }),
              )
            else
              Positioned(
                left: left ? null : 16,
                right: left ? 16 : null,
                bottom: 24,
                child: _TiltBadge(onCalibrate: () => _tilt?.calibrate()),
              ),
            Positioned(
              right: left ? null : 4,
              left: left ? 4 : null,
              bottom: 8,
              child: SafeArea(
                top: false,
                child: ValueListenableBuilder<int>(
                  valueListenable: _frame,
                  builder: (context, _, _) {
                    final st = _s.state;
                    final serving = st.phase == Phase.serve && st.server == _s.localIndex;
                    return ShotButtons(onShot: _shot, serving: serving, mirrored: left);
                  },
                ),
              ),
            ),
            // HUD
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
            // overlays react to the game state every frame
            Positioned.fill(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, _, _) {
                  if (_s.state.phase == Phase.gameOver) return _gameOverOverlay();
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
        content: const Text('Your opponent will be disconnected.'),
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
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      );

  Widget _pauseOverlay() {
    return _scrim(GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('PAUSED',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4)),
          const SizedBox(height: 18),
          BigButton(
              label: 'RESUME',
              icon: Icons.play_arrow_rounded,
              colors: const [AppColors.lime, Color(0xFF9CFF57)],
              onTap: () => setState(() => _paused = false)),
          const SizedBox(height: 12),
          BigButton(
              label: 'RESTART',
              icon: Icons.replay_rounded,
              colors: const [AppColors.blue, AppColors.purple],
              textColor: Colors.white,
              onTap: () {
                _fx.reset();
                _s.rematch();
                setState(() => _paused = false);
              }),
          const SizedBox(height: 12),
          BigButton(
              label: 'QUIT',
              icon: Icons.home_rounded,
              colors: const [Color(0xFF37474F), Color(0xFF263238)],
              textColor: Colors.white,
              onTap: _quit),
        ],
      ),
    ));
  }

  Widget _gameOverOverlay() {
    final st = _s.state;
    final me = _s.localIndex;
    final won = st.winner == me;
    final winner = _s.profiles[st.winner < 0 ? 0 : st.winner];
    Widget statRow(String label, int a, int b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                  width: 36,
                  child: Text('$a', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900))),
              Expanded(
                  child: Text(label,
                      textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
              SizedBox(
                  width: 36,
                  child: Text('$b', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900))),
            ],
          ),
        );
    final a = st.stats[me], b = st.stats[1 - me];
    return SizedBox.expand(
      child: Container(
        color: const Color(0xE6050B16),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: GlassCard(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                (won ? AppColors.lime : AppColors.pink).withValues(alpha: 0.35),
                AppColors.card.withValues(alpha: 0.95),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(won ? 'VICTORY!' : 'DEFEAT',
                    style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 3,
                        color: won ? AppColors.lime : AppColors.pink)),
                const SizedBox(height: 10),
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    FaceAvatar(profile: winner, size: 96),
                    const Positioned(top: -30, child: Icon(Icons.emoji_events_rounded, color: AppColors.lime, size: 34)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${winner.name} wins', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text('${st.score[me]}  -  ${st.score[1 - me]}',
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(width: 36, child: Center(child: FaceAvatar(profile: _s.profiles[me], size: 30))),
                    const Expanded(
                        child: Text('MATCH STATS',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5))),
                    SizedBox(width: 36, child: Center(child: FaceAvatar(profile: _s.profiles[1 - me], size: 30))),
                  ],
                ),
                const Divider(color: Colors.white12),
                statRow('Points won', a.points, b.points),
                statRow('Winners', a.winners, b.winners),
                statRow('Aces', a.aces, b.aces),
                statRow('Smashes', a.smashes, b.smashes),
                statRow('Errors', a.errors, b.errors),
                statRow('Kitchen faults', a.kitchenFaults, b.kitchenFaults),
                const SizedBox(height: 4),
                Text('Longest rally: ${st.longestRally} shots',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 16),
                if (_s.opponentWantsRematch)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Your opponent wants a rematch!',
                        style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w800)),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: BigButton(
                        label: 'HOME',
                        icon: Icons.home_rounded,
                        colors: const [Color(0xFF37474F), Color(0xFF263238)],
                        textColor: Colors.white,
                        onTap: _quit,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BigButton(
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
                                  _resultRecorded = false;
                                  _s.rematch();
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _disconnectedOverlay() {
    return _scrim(GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 54, color: AppColors.orange),
          const SizedBox(height: 10),
          const Text('Connection lost', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Your opponent left or the Wi-Fi dropped.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 18),
          BigButton(
              label: 'BACK TO HOME',
              icon: Icons.home_rounded,
              colors: const [AppColors.lime, Color(0xFF9CFF57)],
              onTap: _quit),
        ],
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
    final opp = 1 - me;
    final incoming = st.phase == Phase.rally && st.lastHitter == opp;
    final myP = st.players[me];
    String? hint;
    Color hintColor = AppColors.lime;
    if (st.phase == Phase.serve && st.server == me && st.phaseTime > 0.5) {
      hint = 'YOUR SERVE  •  tap a shot, hold joystick left/right to aim';
    } else if (incoming && st.mustBounce && st.bouncesOnReceiver == 0) {
      hint = 'LET IT BOUNCE (two-bounce rule)';
      hintColor = AppColors.blue;
    } else if (incoming && st.bouncesOnReceiver == 0 && myP.y.abs() < 2.134) {
      hint = 'IN THE KITCHEN - no volleys!';
      hintColor = AppColors.pink;
    }
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _PlayerScore(session: session, index: me, alignRight: false)),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  children: [
                    Text('to ${session.config.pointsToWin}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                    if (st.rally > 1 && st.phase == Phase.rally)
                      Text('RALLY ${st.rally}',
                          style: const TextStyle(color: AppColors.lime, fontSize: 11, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              Expanded(child: _PlayerScore(session: session, index: opp, alignRight: true)),
              const SizedBox(width: 4),
              _CircleIcon(
                  icon: session.canPause ? Icons.pause_rounded : Icons.close_rounded, onTap: onPause),
            ],
          ),
        ),
        if (showAi && session.aiThought != null && session.aiThought!.isNotEmpty)
          Positioned(
            top: 76,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(10)),
                child: Text('AI: ${session.aiThought}',
                    style: const TextStyle(fontSize: 11, color: AppColors.mint, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        if (st.bannerTime > 0 && st.banner.isNotEmpty && st.phase != Phase.gameOver)
          Align(
            alignment: const Alignment(0, -0.18),
            child: _Banner(text: st.banner, t: st.bannerTime, good: st.pointWinner == me),
          ),
        if (hint != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 196,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: hintColor.withValues(alpha: 0.18),
                  border: Border.all(color: hintColor.withValues(alpha: 0.8)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(hint,
                    style: TextStyle(color: hintColor, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.6)),
              ),
            ),
          ),
      ],
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
    final color = text.contains('-') && !text.contains('OUT') && !text.contains('FAULT') && !text.contains('NET')
        ? Colors.white
        : (good ? AppColors.lime : AppColors.orange);
    return IgnorePointer(
      child: Opacity(
        opacity: fade,
        child: Transform.scale(
          scale: scale,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 40,
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

class _PlayerScore extends StatelessWidget {
  final GameSession session;
  final int index;
  final bool alignRight;
  const _PlayerScore({required this.session, required this.index, required this.alignRight});

  @override
  Widget build(BuildContext context) {
    final st = session.state;
    final p = session.profiles[index];
    final serving = st.server == index;
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        FaceAvatar(profile: p, size: 46),
        if (serving)
          Positioned(
            right: alignRight ? null : -4,
            left: alignRight ? -4 : null,
            bottom: -2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.lime,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ),
      ],
    );
    final info = Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(p.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          Text('${st.score[index]}',
              style: TextStyle(
                  fontSize: 30,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  color: serving ? AppColors.lime : Colors.white)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0x99091427),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(p.look.jersey).withValues(alpha: 0.6), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: alignRight
            ? [info, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), info],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => PressScale(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: const Color(0x99091427), shape: BoxShape.circle,
              border: Border.all(color: Colors.white24)),
          child: Icon(icon, size: 20),
        ),
      );
}
