import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../game/ai/brain.dart';
import '../game/ai/roster.dart';
import '../game/engine.dart';
import '../game/session.dart';
import '../ui/avatar.dart';
import '../ui/theme.dart';
import 'game_screen.dart';

class AiSetupScreen extends StatefulWidget {
  const AiSetupScreen({super.key});

  @override
  State<AiSetupScreen> createState() => _AiSetupScreenState();
}

class _AiSetupScreenState extends State<AiSetupScreen> {
  int _selected = 1;
  int _points = 11;
  bool _rally = true;
  late final PageController _page = PageController(viewportFraction: 0.78, initialPage: 1);

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final app = AppScope.read(context);
    final opp = aiRoster[_selected];
    final brain = await PickleBrain.load();
    if (!mounted) return;
    final session = AiSession(
      human: app.profile,
      aiProfile: opp.profile,
      difficulty: opp.difficulty,
      style: opp.style,
      brain: brain,
      config: MatchConfig(pointsToWin: _points, rallyScoring: _rally, gameSpeed: app.settings.gameSpeed),
      autoHit: app.settings.autoHit,
    );
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(session: session)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('CHOOSE YOUR OPPONENT')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 4),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: aiRoster.length,
                  onPageChanged: (i) => setState(() => _selected = i),
                  itemBuilder: (context, i) {
                    final o = aiRoster[i];
                    final sel = i == _selected;
                    final key = 'ai_${o.difficulty.id}';
                    return AnimatedScale(
                      scale: sel ? 1 : 0.9,
                      duration: const Duration(milliseconds: 200),
                      child: AnimatedOpacity(
                        opacity: sel ? 1 : 0.6,
                        duration: const Duration(milliseconds: 200),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          child: GlassCard(
                            onTap: () => _page.animateToPage(i,
                                duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(o.profile.look.jersey).withValues(alpha: 0.55),
                                AppColors.card.withValues(alpha: 0.95),
                              ],
                            ),
                            borderColor: sel ? AppColors.lime : null,
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var s = 0; s < 4; s++)
                                      Icon(s < o.difficulty.stars ? Icons.star_rounded : Icons.star_border_rounded,
                                          color: AppColors.lime, size: 22),
                                  ],
                                ),
                                Text(o.difficulty.label.toUpperCase(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900, letterSpacing: 2, color: AppColors.lime)),
                                Expanded(child: CharacterPreview(profile: o.profile, height: 200)),
                                Text(o.profile.name,
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                                Text(o.styleName.toUpperCase(),
                                    style: const TextStyle(
                                        color: AppColors.muted, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                                const SizedBox(height: 6),
                                Text(o.tagline,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: AppColors.text, fontSize: 13)),
                                const SizedBox(height: 10),
                                _statBar('SPD', o.profile.stats.speed, AppColors.blue),
                                _statBar('PWR', o.profile.stats.power, AppColors.orange),
                                _statBar('CTL', o.profile.stats.control, AppColors.mint),
                                const SizedBox(height: 8),
                                Text('Your record: ${app.wins(key)}W - ${app.losses(key)}L',
                                    style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Points to win'),
                      ChoiceChipRow<int>(
                        values: const [7, 11, 15, 21],
                        selected: _points,
                        label: (v) => '$v',
                        onSelected: (v) => setState(() => _points = v),
                      ),
                      const SizedBox(height: 10),
                      const SectionLabel('Scoring'),
                      ChoiceChipRow<bool>(
                        values: const [true, false],
                        selected: _rally,
                        label: (v) => v ? 'Rally scoring' : 'Traditional (side-out)',
                        onSelected: (v) => setState(() => _rally = v),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: BigButton(
                  label: 'PLAY',
                  subtitle: 'vs ${aiRoster[_selected].profile.name}',
                  icon: Icons.sports_tennis_rounded,
                  colors: const [AppColors.lime, Color(0xFF9CFF57)],
                  onTap: _play,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statBar(String label, int v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
                width: 36,
                child: Text(label,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.muted))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: v / 6,
                  minHeight: 7,
                  color: c,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
          ],
        ),
      );
}
