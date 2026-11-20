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
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final results = await Future.wait([AppState.load(), PickleBrain.load()]);
  final state = results[0] as AppState;
  final s = state.settings;
  Sound.I
    ..sfxOn = s.sound
    ..musicOn = s.music
    ..voiceOn = s.announcer
    ..applyVolumes(master: s.masterVolume, music: s.musicVolume, sfx: s.sfxVolume, crowd: s.crowdVolume);
  runApp(PickleArenaApp(state: state));
  unawaited(Sound.I.init().then((_) => Sound.I.music('music_menu')));
}

class PickleArenaApp extends StatefulWidget {
  final AppState state;
  const PickleArenaApp({super.key, required this.state});

  @override
  State<PickleArenaApp> createState() => _PickleArenaAppState();
}

class _PickleArenaAppState extends State<PickleArenaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // keep the game full screen after the keyboard, dialogs or app switches
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: MaterialApp(
        title: 'Pickle Arena',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeScreen(),
      ),
    );
  }
}
