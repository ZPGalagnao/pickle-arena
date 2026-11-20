import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../services/sound_service.dart';
import '../ui/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                    const Text('SETTINGS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: TabBar(
                        indicatorColor: AppColors.lime,
                        labelColor: AppColors.lime,
                        unselectedLabelColor: AppColors.muted,
                        dividerColor: Colors.transparent,
                        labelStyle: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 12.5),
                        tabs: [
                          Tab(icon: Icon(Icons.volume_up_rounded, size: 18), text: 'AUDIO', height: 48),
                          Tab(icon: Icon(Icons.auto_awesome_mosaic_rounded, size: 18), text: 'GRAPHICS', height: 48),
                          Tab(icon: Icon(Icons.sports_esports_rounded, size: 18), text: 'CONTROLS', height: 48),
                          Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'GAMEPLAY', height: 48),
                        ],
                      ),
                    ),
                  ],
                ),
                const Expanded(
                  child: TabBarView(children: [_Audio(), _Graphics(), _Controls(), _Gameplay()]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- building blocks
void _save(BuildContext context, void Function(GameSettings s) change) {
  final app = AppScope.read(context);
  change(app.settings);
  app.saveSettings();
}

class _Toggle extends StatelessWidget {
  final String title, sub;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle(this.title, this.sub, this.icon, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: AppColors.lime, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      );
}

class _SliderRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final double value, min, max;
  final String Function(double) label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  const _SliderRow(this.title, this.icon, this.value, this.min, this.max, this.label, this.onChanged,
      {this.onChangeEnd});

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(
          children: [
            Icon(icon, color: AppColors.lime, size: 22),
            const SizedBox(width: 10),
            SizedBox(width: 120, child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(label(value),
                  textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.lime)),
            ),
          ],
        ),
      );
}

Widget _grid(List<Widget> items) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        for (var i = 0; i < items.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: items[i]),
                const SizedBox(width: 10),
                Expanded(child: i + 1 < items.length ? items[i + 1] : const SizedBox()),
              ],
            ),
          ),
      ],
    );

String _pct(double v) => '${(v * 100).round()}%';

// ------------------------------------------------------------------ tabs
class _Audio extends StatelessWidget {
  const _Audio();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    void vol(void Function(GameSettings s) f) {
      _save(context, f);
      Sound.I.applyVolumes(master: s.masterVolume, music: s.musicVolume, sfx: s.sfxVolume, crowd: s.crowdVolume);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _SliderRow('Master', Icons.volume_up_rounded, s.masterVolume, 0, 1, _pct, (v) => vol((s) => s.masterVolume = v)),
        const SizedBox(height: 8),
        _SliderRow('Music', Icons.music_note_rounded, s.musicVolume, 0, 1, _pct, (v) => vol((s) => s.musicVolume = v)),
        const SizedBox(height: 8),
        _SliderRow('Sound effects', Icons.sports_tennis_rounded, s.sfxVolume, 0, 1, _pct,
            (v) => vol((s) => s.sfxVolume = v),
            onChangeEnd: (_) => Sound.I.play('hit_power')),
        const SizedBox(height: 8),
        _SliderRow('Crowd', Icons.groups_rounded, s.crowdVolume, 0, 1, _pct, (v) => vol((s) => s.crowdVolume = v),
            onChangeEnd: (_) => Sound.I.play('crowd_cheer', volume: 0.6)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Toggle('Music on', 'Background music', Icons.queue_music_rounded, s.music, (v) {
                _save(context, (s) => s.music = v);
                Sound.I.setMusicOn(v);
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Toggle('Sound effects on', 'Hits, footsteps, crowd, specials', Icons.graphic_eq_rounded, s.sound, (v) {
                _save(context, (s) => s.sound = v);
                Sound.I.sfxOn = v;
              }),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Toggle('Announcer', 'Calls aces, match point and the winner', Icons.campaign_rounded, s.announcer, (v) {
          _save(context, (s) => s.announcer = v);
          Sound.I.voiceOn = v;
          if (v) Sound.I.voice('vo_ace', gap: 0);
        }),
        const SizedBox(height: 14),
        const _Credits(),
      ],
    );
  }
}

class _Credits extends StatelessWidget {
  const _Credits();

  @override
  Widget build(BuildContext context) {
    const lines = [
      'Game music "Shake and Bake" by Matthew Pablo (CC-BY 3.0)',
      'Menu music "Well oiled, shiny Oscillators" by Viktor Kraus (CC-BY 3.0)',
      'Crowd cheering by Gregor Quendel (CC-BY 4.0)',
      'Announcer voice by Aimee Smith / WinterWalrus (CC-BY 4.0)',
      'Paddle, swish and applause sounds: Aj_, artisticdude, eXpl0it3r (CC0)',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AUDIO CREDITS',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5)),
            ),
        ],
      ),
    );
  }
}

class _Graphics extends StatelessWidget {
  const _Graphics();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        const SectionLabel('Graphics quality'),
        ChoiceChipRow<int>(
          values: const [0, 1, 2],
          selected: s.graphics,
          label: (v) => const ['Low (fastest)', 'Medium', 'High'][v],
          onSelected: (v) => _save(context, (s) => s.graphics = v),
        ),
        const SizedBox(height: 6),
        const Text(
          'Low: still crowd, fewer effects - best for older phones. Medium: animated crowd. High: full crowd and effects.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Toggle('Screen shake', 'Shake on smashes and specials', Icons.vibration_rounded, s.screenShake,
                  (v) => _save(context, (s) => s.screenShake = v)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Toggle('Show FPS', 'Frames per second in the corner', Icons.speed_rounded, s.showFps,
                  (v) => _save(context, (s) => s.showFps = v)),
            ),
          ],
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Move with'),
                  ChoiceChipRow<ControlMode>(
                    values: ControlMode.values,
                    selected: s.control,
                    label: (v) => v == ControlMode.joystick ? 'Joystick' : 'Tilt the phone',
                    onSelected: (v) => _save(context, (s) => s.control = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Joystick type'),
                  ChoiceChipRow<bool>(
                    values: const [false, true],
                    selected: s.fixedJoystick,
                    label: (v) => v ? 'Fixed' : 'Follows thumb',
                    onSelected: (v) => _save(context, (s) => s.fixedJoystick = v),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _SliderRow('Joystick size', Icons.radio_button_checked_rounded, s.joystickSize, 0.8, 1.4, _pct,
            (v) => _save(context, (s) => s.joystickSize = v)),
        const SizedBox(height: 8),
        _SliderRow('Sensitivity', Icons.speed_rounded, s.sensitivity, 0, 1, _pct,
            (v) => _save(context, (s) => s.sensitivity = v)),
        const SizedBox(height: 8),
        _SliderRow('Button size', Icons.touch_app_rounded, s.buttonSize, 0.8, 1.3, _pct,
            (v) => _save(context, (s) => s.buttonSize = v)),
        const SizedBox(height: 8),
        _grid([
          _Toggle('Auto-swing', 'Swing by itself when the ball is in reach', Icons.auto_fix_high_rounded, s.autoHit,
              (v) => _save(context, (s) => s.autoHit = v)),
          _Toggle('Move assist', 'Slide toward the ball when you let go', Icons.directions_run_rounded, s.moveAssist,
              (v) => _save(context, (s) => s.moveAssist = v)),
          _Toggle('Landing marker', 'Show where the ball will bounce', Icons.my_location_rounded, s.showMarker,
              (v) => _save(context, (s) => s.showMarker = v)),
          _Toggle('Left-handed', 'Joystick right, buttons left', Icons.swap_horiz_rounded, s.leftHanded,
              (v) => _save(context, (s) => s.leftHanded = v)),
          _Toggle('Vibration', 'Haptic feedback on hits and points', Icons.vibration_rounded, s.haptics,
              (v) => _save(context, (s) => s.haptics = v)),
        ]),
      ],
    );
  }
}

class _Gameplay extends StatelessWidget {
  const _Gameplay();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        const SectionLabel('Game speed'),
        ChoiceChipRow<double>(
          values: const [0.85, 1.0, 1.12],
          selected: s.gameSpeed,
          label: (v) => v < 0.9 ? 'Relaxed' : (v < 1.05 ? 'Normal' : 'Fast'),
          onSelected: (v) => _save(context, (s) => s.gameSpeed = v),
        ),
        const SizedBox(height: 12),
        _Toggle('Show AI thoughts', 'See what the neural network decides during VS AI', Icons.psychology_alt_rounded,
            s.showAiThoughts, (v) => _save(context, (s) => s.showAiThoughts = v)),
        const SizedBox(height: 16),
        const Center(
          child: Text('Pickle Arena v1.3  •  Intelligent Systems Project',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
      ],
    );
  }
}
