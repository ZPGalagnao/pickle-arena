import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../game/ai/brain.dart';
import '../game/ai/roster.dart';
import '../game/render/court_view.dart';
import '../game/render/effects.dart';
import '../game/render/game_painter.dart';
import '../game/session.dart';
import '../models/profile.dart';
import '../ui/avatar.dart';
import '../ui/theme.dart';
import 'ai_setup_screen.dart';
import 'customize_screen.dart';
import 'help_screen.dart';
import 'lobby_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  DemoSession? _demo;
  GameScene? _scene;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    final brain = PickleBrain.instance;
    if (brain != null) {
      _demo = DemoSession(brain, [aiRoster[3].profile, aiRoster[1].profile, aiRoster[2].profile, aiRoster[4].profile]);
      _scene = GameScene(
        state: _demo!.engine.s,
        profiles: _demo!.profiles,
        faces: List.filled(4, null),
        view: CourtView(),
        fx: Effects(),
        localIndex: -1,
        showMarker: false,
        topInset: 30,
        bottomInset: 10,
      );
    }
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFirstRun());
  }

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.1) dt = 1 / 60;
    final demo = _demo;
    if (demo != null) {
      demo.update(dt);
      final s = demo.engine.s;
      _scene!.state = s;
      _scene!.time += dt;
      for (final e in demo.engine.s.recentEvents) {
        if (e.seq > _lastSeq) {
          _scene!.fx.onEvent(e, s);
          _lastSeq = e.seq;
        }
      }
      _scene!.fx.update(dt, s);
    }
    _frame.value++;
  }

  int _lastSeq = 0;

  Future<void> _maybeFirstRun() async {
    final app = AppScope.read(context);
    if (app.isFirstRun && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomizeScreen(firstRun: true)));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _go(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.profile;
    final lvStart = PlayerLevel.xpFor(p.level), lvEnd = PlayerLevel.xpFor(p.level + 1);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _scene == null
                ? const AppBackground(child: SizedBox())
                : CustomPaint(painter: GamePainter(_scene!, repaint: _frame)),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    AppColors.bg.withValues(alpha: 0.95),
                    AppColors.bg.withValues(alpha: 0.55),
                    AppColors.bg.withValues(alpha: 0.35),
                    AppColors.bg.withValues(alpha: 0.85),
                  ],
                  stops: const [0, 0.4, 0.6, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ------------------------------------------ left: logo + player
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const GameLogo(size: 46),
                        const SizedBox(height: 4),
                        const Text('AI  •  DOUBLES  •  WI-FI MULTIPLAYER  •  SPECIAL ATTACKS',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                        const Spacer(),
                        GlassCard(
                          onTap: () => _go(const CustomizeScreen()),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              FaceAvatar(profile: p, size: 62),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                                    Text('LV ${p.level}  ${p.title.toUpperCase()}',
                                        style: const TextStyle(
                                            color: AppColors.lime, fontWeight: FontWeight.w900, fontSize: 12)),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: ((p.xp - lvStart) / (lvEnd - lvStart)).clamp(0.0, 1.0),
                                        minHeight: 6,
                                        color: AppColors.mint,
                                        backgroundColor: Colors.white12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.auto_awesome_rounded, size: 13, color: Color(p.special.color)),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(p.special.label,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: Color(p.special.color), fontWeight: FontWeight.w800, fontSize: 11)),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text('SPD ${p.stats.speed} PWR ${p.stats.power} CTL ${p.stats.control}',
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.end,
                                              style: const TextStyle(
                                                  color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 10.5)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.brush_rounded, color: AppColors.lime),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                  // ------------------------------------------ right: menu
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            onPressed: () => _go(const SettingsScreen()),
                            icon: const Icon(Icons.settings_rounded),
                          ),
                        ),
                        const Spacer(),
                        BigButton(
                          label: 'VS AI',
                          subtitle: 'Singles or doubles with an AI partner',
                          icon: Icons.smart_toy_rounded,
                          colors: const [AppColors.lime, Color(0xFF9CFF57)],
                          onTap: () => _go(const AiSetupScreen()),
                        ),
                        const SizedBox(height: 10),
                        BigButton(
                          label: 'MULTIPLAYER',
                          subtitle: 'Same Wi-Fi or hotspot, up to 4 phones',
                          icon: Icons.wifi_rounded,
                          colors: const [AppColors.blue, AppColors.purple],
                          textColor: Colors.white,
                          onTap: () => _go(const LobbyScreen()),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _SmallTile(
                                  icon: Icons.menu_book_rounded, label: 'HOW TO PLAY', onTap: () => _go(const HelpScreen())),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SmallTile(
                                  icon: Icons.psychology_rounded,
                                  label: 'AI BRAIN',
                                  onTap: () => _go(const HelpScreen(initialTab: 3))),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SmallTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.lime, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
            ],
          ),
        ),
      );
}
