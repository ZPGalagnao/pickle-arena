import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'game/ai/brain.dart';
import 'screens/home_screen.dart';
import 'services/sound_service.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final results = await Future.wait([AppState.load(), PickleBrain.load()]);
  final state = results[0] as AppState;
  Sound.I
    ..sfxOn = state.settings.sound
    ..musicOn = state.settings.music;
  runApp(PickleArenaApp(state: state));
  unawaited(Sound.I.init().then((_) => Sound.I.music('music_menu')));
}

class PickleArenaApp extends StatelessWidget {
  final AppState state;
  const PickleArenaApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Pickle Arena',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeScreen(),
      ),
    );
  }
}
