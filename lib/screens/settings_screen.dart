import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
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

    Widget toggle(String title, String sub, IconData icon, bool v, ValueChanged<bool> on) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: AppColors.lime),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                Switch(value: v, onChanged: on),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('SETTINGS')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionLabel('Controls'),
              ChoiceChipRow<ControlMode>(
                values: ControlMode.values,
                selected: s.control,
                label: (v) => v == ControlMode.joystick ? 'Touch joystick' : 'Tilt the phone',
                onSelected: (v) => set(() => s.control = v),
              ),
              const SizedBox(height: 14),
              toggle('Auto-swing assist', 'Swing automatically when the ball is in reach. Buttons still choose the shot.',
                  Icons.auto_fix_high_rounded, s.autoHit, (v) => set(() => s.autoHit = v)),
              toggle('Landing marker', 'Show where the incoming ball will bounce', Icons.my_location_rounded,
                  s.showMarker, (v) => set(() => s.showMarker = v)),
              toggle('Left-handed layout', 'Joystick on the right, shot buttons on the left', Icons.swap_horiz_rounded,
                  s.leftHanded, (v) => set(() => s.leftHanded = v)),
              toggle('Vibration', 'Haptic feedback on hits and points', Icons.vibration_rounded, s.haptics,
                  (v) => set(() => s.haptics = v)),
              toggle('Show AI thoughts', 'See what the neural network decides during VS AI', Icons.psychology_alt_rounded,
                  s.showAiThoughts, (v) => set(() => s.showAiThoughts = v)),
              const SizedBox(height: 8),
              const SectionLabel('Game speed'),
              ChoiceChipRow<double>(
                values: const [0.75, 0.9, 1.05],
                selected: s.gameSpeed,
                label: (v) => v == 0.75 ? 'Relaxed' : (v == 0.9 ? 'Normal' : 'Fast'),
                onSelected: (v) => set(() => s.gameSpeed = v),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text('Pickle Arena v1.0  •  Intelligent Systems Project',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
