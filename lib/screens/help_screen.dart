import 'package:material_ui/material_ui.dart';

import '../game/ai/brain.dart';
import '../models/profile.dart';
import '../ui/theme.dart';

class HelpScreen extends StatelessWidget {
  final int initialTab;
  const HelpScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 44,
          title: const Text('GUIDE'),
          bottom: const TabBar(
            indicatorColor: AppColors.lime,
            labelColor: AppColors.lime,
            unselectedLabelColor: AppColors.muted,
            dividerColor: Colors.transparent,
            labelStyle: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
            tabs: [Tab(text: 'RULES', height: 36), Tab(text: 'CONTROLS', height: 36), Tab(text: 'SPECIALS', height: 36), Tab(text: 'AI BRAIN', height: 36)],
          ),
        ),
        body: const AppBackground(
          child: TabBarView(children: [_Rules(), _Controls(), _Specials(), _AiBrain()]),
        ),
      ),
    );
  }
}

/// Two-column grid of cards for landscape screens.
class _Grid extends StatelessWidget {
  final List<Widget> children;
  const _Grid(this.children);

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          for (var i = 0; i < children.length; i += 2)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 12),
                Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
              ],
            ),
        ],
      );
}

class _Card extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _Card(this.icon, this.color, this.title, this.body);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(body, style: const TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _Rules extends StatelessWidget {
  const _Rules();

  @override
  Widget build(BuildContext context) => const _Grid([
        _Card(Icons.sports_tennis_rounded, AppColors.lime, 'The serve',
            'Serve underhand from behind the baseline, diagonally into the box across the net. It must land past '
                'the kitchen line. Serve from the right when your score is even, from the left when it is odd.'),
        _Card(Icons.filter_2_rounded, AppColors.blue, 'Two-bounce rule',
            'The return of serve must bounce, and the serving side\'s next shot must bounce too. After that you may '
                'volley (hit it in the air).'),
        _Card(Icons.block_rounded, AppColors.pink, 'The kitchen',
            'The 7-ft zone next to the net is the non-volley zone. You can stand there, but you cannot volley while '
                'inside it. The zone glows red when you are about to commit a fault.'),
        _Card(Icons.cancel_rounded, AppColors.orange, 'Faults',
            'Hitting into the net, hitting out, letting the ball bounce twice, or volleying from the kitchen loses '
                'the rally.'),
        _Card(Icons.groups_rounded, AppColors.purple, 'Doubles',
            '2 vs 2. Partners switch sides when their team wins a point on its own serve. In traditional scoring '
                'both partners serve before a side out, except at the start (0-0-2). Either partner may hit the ball.'),
        _Card(Icons.scoreboard_rounded, AppColors.mint, 'Scoring',
            'Rally scoring: every rally gives a point. Traditional: only the serving side scores; losing the rally '
                'passes the serve. Win by 2.'),
      ]);
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) => const _Grid([
        _Card(Icons.gamepad_rounded, AppColors.lime, 'Move',
            'Touch the left side of the screen and drag. Up = toward the net. With Move assist ON your player slides '
                'toward the ball when you let go. Or steer by tilting the phone (Settings).'),
        _Card(Icons.flash_on_rounded, AppColors.orange, 'POWER',
            'Fast and low. Hit a high ball near the net for a SMASH. Best when the other side is slow to react.'),
        _Card(Icons.water_drop_rounded, AppColors.lime, 'SOFT',
            'A slow, short shot that drops near the net. Deadly when your opponent stands far back: they must run '
                'forward and hit it from low.'),
        _Card(Icons.north_east_rounded, AppColors.blue, 'HIGH',
            'A high, deep shot over an opponent who rushed the net. Risky against a fast player.'),
        _Card(Icons.open_with_rounded, AppColors.purple, 'Aim & depth (tactics)',
            'While you hit, hold the joystick LEFT/RIGHT to aim sideways, UP to hit deeper, DOWN to hit shorter. '
                'Example: opponent far back? Pull DOWN + SOFT for a short drop they cannot reach.'),
        _Card(Icons.bolt_rounded, AppColors.mint, 'Your stats',
            'SPEED = how fast you run (same rule for you and the AI). POWER = speed of POWER shots and smashes. '
                'CONTROL = accuracy. Easier AIs are slower and react later; Pro is as fast as its stats allow.'),
      ]);
}

class _Specials extends StatelessWidget {
  const _Specials();

  @override
  Widget build(BuildContext context) => _Grid([
        const _Card(Icons.battery_charging_full_rounded, AppColors.lime, 'Charging',
            'The meter under your name (and the ring on the SPECIAL button) fills when you hit the ball and when '
                'points end. When it glows, tap SPECIAL: time slows down and your next shot becomes your special.'),
        for (final sk in SpecialSkill.values)
          _Card(
            switch (sk) {
              SpecialSkill.fireSmash => Icons.local_fire_department_rounded,
              SpecialSkill.iceFreeze => Icons.ac_unit_rounded,
              SpecialSkill.thunderCurve => Icons.bolt_rounded,
              SpecialSkill.phantomDrop => Icons.blur_on_rounded,
              SpecialSkill.tornadoLob => Icons.cyclone_rounded,
            },
            Color(sk.color),
            sk.label,
            sk.description,
          ),
      ]);
}

class _AiBrain extends StatelessWidget {
  const _AiBrain();

  String _pct(dynamic v) => v is num ? '${(v * 100).toStringAsFixed(1)}%' : '-';
  String _cm(dynamic v) => v is num ? '${(v * 100).toStringAsFixed(1)} cm' : '-';
  String _ms(dynamic v) => v is num ? '${(v * 1000).toStringAsFixed(0)} ms' : '-';

  @override
  Widget build(BuildContext context) {
    final m = PickleBrain.instance?.metrics ?? const {};
    final p = (m['predictor'] as Map?) ?? const {};
    final s = (m['selector'] as Map?) ?? const {};
    Widget metric(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Card(Icons.psychology_rounded, AppColors.lime, 'PickleBrain',
            'The AI opponents are driven by two neural networks trained in Python (TensorFlow/Keras) on '
                'millions of simulated shots, then run directly on your phone.'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. Trajectory Predictor', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              const Text(
                'Neural network with layers 7-128-128-64 and 4 output heads. Given the ball\'s position and velocity, it predicts '
                'where and when the ball reaches any depth, how many bounces happen first, and where it lands. '
                'The AI uses it to choose a legal, comfortable spot to hit from.',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
              const Divider(color: Colors.white12),
              metric('Training samples', '${p['samples'] ?? '-'}'),
              metric('Position error (avg)', _cm(p['mae_plane_x_m'])),
              metric('Height error (avg)', _cm(p['mae_plane_height_m'])),
              metric('Timing error (avg)', _ms(p['mae_plane_time_s'])),
              metric('Bounce count accuracy', _pct(p['bounce_count_accuracy'])),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('2. Shot Selector', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              const Text(
                'Neural network with layers 9-96-96-9 (softmax). Picks drive / dink / lob and left / centre / right. '
                'Labels came from Monte Carlo roll-outs: each shot was simulated many times against a virtual '
                'opponent and the network learned which shots win rallies.',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
              const Divider(color: Colors.white12),
              metric('Training situations', '${s['situations'] ?? '-'}'),
              metric('Rally win rate: neural network', _pct(s['expected_win_rate_network'])),
              metric('Rally win rate: best possible', _pct(s['expected_win_rate_best_possible'])),
              metric('Rally win rate: random shots', _pct(s['expected_win_rate_random_shot'])),
              metric('Rally win rate: always drive', _pct(s['expected_win_rate_always_drive_centre'])),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _Card(Icons.tune_rounded, AppColors.blue, 'Difficulty',
            'Every opponent uses the same networks. Easier opponents react later, move slower, aim with more '
                'error and pick shots more randomly (higher softmax temperature).'),
      ],
    );
  }
}
