import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pickle_arena/app_state.dart';
import 'package:pickle_arena/game/ai/brain.dart';
import 'package:pickle_arena/game/ai/roster.dart';
import 'package:pickle_arena/game/engine.dart';
import 'package:pickle_arena/game/session.dart';
import 'package:pickle_arena/main.dart';
import 'package:pickle_arena/screens/ai_setup_screen.dart';
import 'package:pickle_arena/screens/customize_screen.dart';
import 'package:pickle_arena/screens/game_screen.dart';
import 'package:pickle_arena/screens/help_screen.dart';
import 'package:pickle_arena/screens/lobby_screen.dart';
import 'package:pickle_arena/screens/settings_screen.dart';
import 'package:pickle_arena/ui/controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppState state;
  late PickleBrain brain;
  const phone = Size(860, 400); // landscape phone

  setUp(() async {
    SharedPreferences.setMockInitialValues({'profile': '{"name":"Tester"}'});
    state = await AppState.load();
    brain = await PickleBrain.load();
  });

  Widget wrap(Widget child) => AppScope(state: state, child: MaterialApp(home: child));

  Future<void> pumpFrames(WidgetTester t, [int n = 30]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('home screen shows the main menu with a live AI demo', (t) async {
    await t.binding.setSurfaceSize(phone);
    await t.pumpWidget(PickleArenaApp(state: state));
    await pumpFrames(t);
    expect(find.text('VS AI'), findsOneWidget);
    expect(find.text('MULTIPLAYER'), findsOneWidget);
    expect(find.text('Tester'), findsOneWidget);
  });

  testWidgets('every menu screen builds in landscape', (t) async {
    await t.binding.setSurfaceSize(phone);
    for (final screen in <Widget>[
      const CustomizeScreen(),
      const AiSetupScreen(),
      const LobbyScreen(),
      const SettingsScreen(),
      const HelpScreen(initialTab: 2),
      const HelpScreen(initialTab: 3),
    ]) {
      await t.pumpWidget(wrap(screen));
      await pumpFrames(t, 10);
      expect(t.takeException(), isNull, reason: '${screen.runtimeType}');
    }
  });

  for (final doubles in [false, true]) {
    testWidgets('a VS AI ${doubles ? 'doubles' : 'singles'} match runs on the game screen', (t) async {
      await t.binding.setSurfaceSize(phone);
      final opp = aiRoster[0];
      final others = doubles ? [aiRoster[2], opp, doublesPartnerOf(0)] : [opp];
      final session = AiSession(
        human: state.profile,
        others: [for (final o in others) o.profile],
        levels: [for (final o in others) o.difficulty],
        brain: brain,
        config: MatchConfig(pointsToWin: 11, doubles: doubles),
      );
      await t.pumpWidget(wrap(GameScreen(session: session)));
      await pumpFrames(t, 240); // 4 seconds of play
      expect(find.byType(ShotButtons), findsOneWidget);
      expect(find.byType(SpecialButton), findsOneWidget);
      expect(find.byType(FloatingJoystick), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
