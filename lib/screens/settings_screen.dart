import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../services/sound_service.dart';
import '../ui/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    void set(void Function() f) {
      f();
      app.saveSettings();
    }

    Widget toggle(String title, String sub, IconData icon, bool v, ValueChanged<bool> on) => GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              Switch(value: v, onChanged: on),
            ],
          ),
        );

    final toggles = [
      toggle('Auto-swing', 'Swing by itself when the ball is in reach', Icons.auto_fix_high_rounded, s.autoHit,
          (v) => set(() => s.autoHit = v)),
      toggle('Move assist', 'Slide toward the ball when you let go of the joystick', Icons.directions_run_rounded,
          s.moveAssist, (v) => set(() => s.moveAssist = v)),
      toggle('Landing marker', 'Show where the incoming ball will bounce', Icons.my_location_rounded, s.showMarker,
          (v) => set(() => s.showMarker = v)),
      toggle('Sound effects', 'Hits, footsteps, crowd and specials', Icons.volume_up_rounded, s.sound, (v) {
        set(() => s.sound = v);
        Sound.I.sfxOn = v;
      }),
      toggle('Music', 'Background music', Icons.music_note_rounded, s.music, (v) {
        set(() => s.music = v);
        Sound.I.setMusicOn(v);
      }),
      toggle('Vibration', 'Haptic feedback on hits and points', Icons.vibration_rounded, s.haptics,
          (v) => set(() => s.haptics = v)),
      toggle('Left-handed', 'Joystick right, buttons left', Icons.swap_horiz_rounded, s.leftHanded,
          (v) => set(() => s.leftHanded = v)),
      toggle('Show AI thoughts', 'See what the neural network decides', Icons.psychology_alt_rounded, s.showAiThoughts,
          (v) => set(() => s.showAiThoughts = v)),
    ];

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
            children: [
              Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                const Text('SETTINGS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4)),
              ]),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('Controls'),
                        ChoiceChipRow<ControlMode>(
                          values: ControlMode.values,
                          selected: s.control,
                          label: (v) => v == ControlMode.joystick ? 'Touch joystick' : 'Tilt the phone',
                          onSelected: (v) => set(() => s.control = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('Game speed'),
                        ChoiceChipRow<double>(
                          values: const [0.75, 0.9, 1.05],
                          selected: s.gameSpeed,
                          label: (v) => v == 0.75 ? 'Relaxed' : (v == 0.9 ? 'Normal' : 'Fast'),
                          onSelected: (v) => set(() => s.gameSpeed = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < toggles.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: toggles[i]),
                      const SizedBox(width: 10),
                      Expanded(child: i + 1 < toggles.length ? toggles[i + 1] : const SizedBox()),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Center(
                child: Text('Pickle Arena v1.1  •  Intelligent Systems Project',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
