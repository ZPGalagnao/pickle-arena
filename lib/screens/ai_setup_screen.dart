import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../game/ai/ai_controller.dart';
import '../game/ai/brain.dart';
import '../game/ai/roster.dart';
import '../game/engine.dart';
import '../game/session.dart';
import '../models/profile.dart';
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
  int _partner = 4;
  bool _doubles = false;
  int _points = 11;
  bool _rally = true;
  late final PageController _page = PageController(viewportFraction: 0.62, initialPage: 1);

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  List<int> get _partnerChoices {
    final opp2 = aiRoster.indexOf(doublesPartnerOf(_selected));
    return [for (var i = 0; i < aiRoster.length; i++) if (i != _selected && i != opp2) i];
  }

  Future<void> _play() async {
    final app = AppScope.read(context);
    final opp = aiRoster[_selected];
    final brain = await PickleBrain.load();
    if (!mounted) return;
    final others = <PlayerProfile>[];
    final levels = <AiDifficulty>[];
    final styles = <AiStyle>[];
    if (_doubles) {
      final partner = aiRoster[_partnerChoices.contains(_partner) ? _partner : _partnerChoices.first];
      final opp2 = doublesPartnerOf(_selected);
      for (final o in [partner, opp, opp2]) {
        others.add(o.profile);
        levels.add(o.difficulty);
        styles.add(o.style);
      }
    } else {
      others.add(opp.profile);
      levels.add(opp.difficulty);
      styles.add(opp.style);
    }
    final session = AiSession(
      human: app.profile,
      others: others,
      levels: levels,
      styles: styles,
      brain: brain,
      config: MatchConfig(
          pointsToWin: _points, rallyScoring: _rally, gameSpeed: app.settings.gameSpeed, doubles: _doubles),
      autoHit: app.settings.autoHit,
      moveAssist: app.settings.moveAssist,
    );
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(session: session)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!_partnerChoices.contains(_partner)) _partner = _partnerChoices.first;
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --------------------------------------------- opponents
              Expanded(
                flex: 6,
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                        Text(_doubles ? 'CHOOSE THE OPPONENT TEAM' : 'CHOOSE YOUR OPPONENT',
                            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 16)),
                      ],
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _page,
                        itemCount: aiRoster.length,
                        onPageChanged: (i) => setState(() => _selected = i),
                        itemBuilder: (context, i) => _opponentCard(app, i),
                      ),
                    ),
                  ],
                ),
              ),
              // --------------------------------------------- settings
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: GlassCard(
                          padding: const EdgeInsets.all(12),
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              const SectionLabel('Mode'),
                              ChoiceChipRow<bool>(
                                values: const [false, true],
                                selected: _doubles,
                                label: (v) => v ? 'Doubles 2 vs 2' : 'Singles 1 vs 1',
                                onSelected: (v) => setState(() => _doubles = v),
                              ),
                              if (_doubles) ...[
                                const SizedBox(height: 10),
                                const SectionLabel('Your AI partner'),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final k in _partnerChoices)
                                      PressScale(
                                        onTap: () => setState(() => _partner = k),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 150),
                                          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                                          decoration: BoxDecoration(
                                            color: k == _partner ? AppColors.lime : const Color(0x22FFFFFF),
                                            borderRadius: BorderRadius.circular(30),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              FaceAvatar(profile: aiRoster[k].profile, size: 28, ring: false),
                                              const SizedBox(width: 6),
                                              Text(aiRoster[k].profile.name,
                                                  style: TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 12,
                                                      color: k == _partner ? AppColors.bg : AppColors.text)),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 10),
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
                                label: (v) => v ? 'Rally' : 'Traditional',
                                onSelected: (v) => setState(() => _rally = v),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      BigButton(
                        label: 'PLAY',
                        subtitle: _doubles
                            ? 'vs ${aiRoster[_selected].profile.name} & ${doublesPartnerOf(_selected).profile.name}'
                            : 'vs ${aiRoster[_selected].profile.name}',
                        icon: Icons.sports_tennis_rounded,
                        colors: const [AppColors.lime, Color(0xFF9CFF57)],
                        onTap: _play,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _opponentCard(AppState app, int i) {
    final o = aiRoster[i];
    final sel = i == _selected;
    final key = '${_doubles ? 'ai2' : 'ai'}_${o.difficulty.id}';
    final mate = doublesPartnerOf(i);
    return AnimatedScale(
      scale: sel ? 1 : 0.88,
      duration: const Duration(milliseconds: 200),
      child: AnimatedOpacity(
        opacity: sel ? 1 : 0.55,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: GlassCard(
            onTap: () => _page.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(o.profile.look.jersey).withValues(alpha: 0.55), AppColors.card.withValues(alpha: 0.95)],
            ),
            borderColor: sel ? AppColors.lime : null,
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  flex: _doubles ? 7 : 5,
                  child: _doubles
                      ? Row(
                          children: [
                            Expanded(child: CharacterPreview(profile: o.profile, height: 999)),
                            Expanded(child: CharacterPreview(profile: mate.profile, height: 999)),
                          ],
                        )
                      : CharacterPreview(profile: o.profile, height: 999),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          for (var s = 0; s < 4; s++)
                            Icon(s < o.difficulty.stars ? Icons.star_rounded : Icons.star_border_rounded,
                                color: AppColors.lime, size: 18),
                          const SizedBox(width: 6),
                          Text(o.difficulty.label.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.lime, fontSize: 12)),
                        ],
                      ),
                      Text(_doubles ? '${o.profile.name} &\n${mate.profile.name}' : o.profile.name,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.1)),
                      Text(o.styleName.toUpperCase(),
                          style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(o.tagline, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 14, color: Color(o.profile.special.color)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(o.profile.special.label,
                                style: TextStyle(
                                    color: Color(o.profile.special.color), fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _statBar('SPD', o.profile.stats.speed, AppColors.blue),
                      _statBar('PWR', o.profile.stats.power, AppColors.orange),
                      _statBar('CTL', o.profile.stats.control, AppColors.mint),
                      const SizedBox(height: 4),
                      Text('Record: ${app.wins(key)}W - ${app.losses(key)}L',
                          style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statBar(String label, int v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          children: [
            SizedBox(
                width: 32,
                child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.muted))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: v / 6, minHeight: 6, color: c, backgroundColor: Colors.white12),
              ),
            ),
          ],
        ),
      );
}
