import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import '../app_state.dart';
import '../game/ai/brain.dart';
import '../game/ai/roster.dart';
import '../game/render/court_view.dart';
import '../game/render/effects.dart';
import '../game/render/game_painter.dart';
import '../game/session.dart';
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
      _demo = DemoSession(brain, [aiRoster[3].profile, aiRoster[2].profile]);
      _scene = GameScene(
        state: _demo!.engine.s,
        profiles: _demo!.profiles,
        faces: [null, null],
        view: CourtView(),
        fx: Effects(),
        localIndex: -1,
        showMarker: false,
        topInset: 40,
        bottomInset: 40,
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
      _scene!.state = demo.engine.s;
      _scene!.time += dt;
      _scene!.fx.update(dt, demo.engine.s.ball, true);
    }
    _frame.value++;
  }

  Future<void> _maybeFirstRun() async {
    final app = AppScope.read(context);
    if (app.isFirstRun && mounted) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const CustomizeScreen(firstRun: true)));
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
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.bg.withValues(alpha: 0.88),
                    AppColors.bg.withValues(alpha: 0.35),
                    AppColors.bg.withValues(alpha: 0.75),
                    AppColors.bg.withValues(alpha: 0.97),
                  ],
                  stops: const [0, 0.35, 0.6, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        onPressed: () => _go(const SettingsScreen()),
                        icon: const Icon(Icons.settings_rounded),
                      ),
                    ],
                  ),
                  const GameLogo(size: 52),
                  const SizedBox(height: 6),
                  const Text('AI  •  WI-FI MULTIPLAYER  •  YOUR FACE IN THE GAME',
                      style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                  const Spacer(),
                  GlassCard(
                    onTap: () => _go(const CustomizeScreen()),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        FaceAvatar(profile: p, size: 58),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                              Text('SPD ${p.stats.speed}  •  PWR ${p.stats.power}  •  CTL ${p.stats.control}',
                                  style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: AppColors.lime.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                          child: const Row(
                            children: [
                              Icon(Icons.brush_rounded, size: 16, color: AppColors.lime),
                              SizedBox(width: 4),
                              Text('CUSTOMIZE',
                                  style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w900, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  BigButton(
                    label: 'VS AI',
                    subtitle: '5 opponents powered by a trained neural network',
                    icon: Icons.smart_toy_rounded,
                    colors: const [AppColors.lime, Color(0xFF9CFF57)],
                    onTap: () => _go(const AiSetupScreen()),
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    label: 'MULTIPLAYER',
                    subtitle: 'Same Wi-Fi or hotspot, phone vs phone',
                    icon: Icons.wifi_rounded,
                    colors: const [AppColors.blue, AppColors.purple],
                    textColor: Colors.white,
                    onTap: () => _go(const LobbyScreen()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SmallTile(
                            icon: Icons.menu_book_rounded,
                            label: 'HOW TO PLAY',
                            onTap: () => _go(const HelpScreen())),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SmallTile(
                            icon: Icons.psychology_rounded,
                            label: 'AI BRAIN',
                            onTap: () => _go(const HelpScreen(initialTab: 2))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
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
