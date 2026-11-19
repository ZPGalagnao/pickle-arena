import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'game/ai/brain.dart';
import 'screens/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: AppColors.bg,
  ));
  final results = await Future.wait([AppState.load(), PickleBrain.load()]);
  runApp(PickleArenaApp(state: results[0] as AppState));
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
