// Renders PNG screenshots of the main screens (not part of the normal test run).
//   flutter test test/screenshot_capture.dart --dart-define=OUT=<folder>
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pickle_arena/app_state.dart';
import 'package:pickle_arena/game/ai/ai_controller.dart';
import 'package:pickle_arena/game/ai/brain.dart';
import 'package:pickle_arena/game/ai/roster.dart';
import 'package:pickle_arena/game/engine.dart';
import 'package:pickle_arena/game/game_state.dart';
import 'package:pickle_arena/game/session.dart';
import 'package:pickle_arena/main.dart';
import 'package:pickle_arena/models/profile.dart';
import 'package:pickle_arena/screens/ai_setup_screen.dart';
import 'package:pickle_arena/screens/customize_screen.dart';
import 'package:pickle_arena/screens/game_screen.dart';
import 'package:pickle_arena/screens/help_screen.dart';
import 'package:pickle_arena/screens/lobby_screen.dart';
import 'package:pickle_arena/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const outDir = String.fromEnvironment('OUT', defaultValue: 'build/screens');
const fontDir = String.fromEnvironment('FONTS');

/// Both players driven by the AI, but shown from player 0's point of view.
class BotSession extends GameSession {
  final GameEngine engine;
  final List<AiController> ais;
  @override
  final List<PlayerProfile> profiles;
  BotSession(this.engine, this.ais, this.profiles);
  @override
  GameState get state => engine.s;
  @override
  int get localIndex => 0;
  @override
  MatchConfig get config => engine.config;
  @override
  bool get isMultiplayer => false;
  @override
  String get modeKey => 'shot';
  @override
  String? get aiThought => ais[1].lastThought;
  @override
  void update(double dt, PlayerInput local) {
    engine.update(dt, [
      ais[0].update(engine.s, profiles[0], dt),
      ais[1].update(engine.s, profiles[1], dt),
    ]);
  }

  @override
  List<GameEvent> takeEvents() => engine.drainEvents();
  @override
  void rematch() {}
}

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('$fontDir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family('Roboto', [
    'roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf',
    'roboto-italic.ttf', 'roboto-bolditalic.ttf', 'roboto-blackitalic.ttf',
  ]);
  await family('MaterialIcons', ['materialicons-regular.otf']);
}

void main() {
  final key = GlobalKey();
  late AppState state;
  late PickleBrain brain;

  setUpAll(() async {
    await loadFonts();
    Directory(outDir).createSync(recursive: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'profile':
          '{"name":"Zoren","look":{"jersey":4281637083,"shorts":4279969354,"paddle":4292146234,"number":23,"accessory":2,"pattern":3,"skin":4293962857,"hair":4280032016},"stats":{"speed":5,"power":4,"control":3}}',
    });
    state = await AppState.load();
    brain = await PickleBrain.load();
  });

  Future<void> shoot(WidgetTester t, String name) async {
    await t.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await boundary.toImage(pixelRatio: 1.5);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  Future<void> frames(WidgetTester t, int n) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
  }

  Widget wrap(Widget child) => RepaintBoundary(
        key: key,
        child: AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: child)),
      );

  testWidgets('screens', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 860));
    t.view.physicalSize = const Size(400, 860);
    t.view.devicePixelRatio = 1;

    await t.pumpWidget(RepaintBoundary(key: key, child: PickleArenaApp(state: state)));
    await frames(t, 200);
    await shoot(t, '1_home');

    await t.pumpWidget(wrap(const CustomizeScreen()));
    await frames(t, 40);
    await shoot(t, '2_customize');

    await t.pumpWidget(wrap(const AiSetupScreen()));
    await frames(t, 40);
    await shoot(t, '3_ai_select');

    await t.pumpWidget(wrap(const LobbyScreen()));
    await frames(t, 10);
    await shoot(t, '4_lobby');

    await t.pumpWidget(wrap(const HelpScreen(initialTab: 2)));
    await frames(t, 20);
    await shoot(t, '5_ai_brain');

    // a live rally
    final profiles = [state.profile, aiRoster[3].profile];
    final engine = GameEngine(
        config: MatchConfig(pointsToWin: 11), profiles: profiles, autoHit: [false, false],
        random: math.Random(4), firstServer: 1);
    final session = BotSession(engine,
        [AiController(brain, AiDifficulty.hard, 0), AiController(brain, AiDifficulty.hard, 1)], profiles);
    await t.pumpWidget(wrap(GameScreen(session: session)));
    var shots = 0;
    for (var i = 0; i < 4000; i++) {
      await t.pump(const Duration(milliseconds: 16));
      final s = engine.s;
      if (s.phase == Phase.rally && s.rally >= 3 && s.ball.z > 0.9 && s.ball.y < -1.5 && s.lastHitter == 1) {
        await shoot(t, '6_game_rally_${shots++}');
        if (shots >= 2) break;
        await frames(t, 120);
      }
    }
    // game over screen
    engine.s
      ..score[0] = 11
      ..score[1] = 8
      ..winner = 0
      ..phase = Phase.gameOver
      ..longestRally = 14;
    engine.s.stats[0]
      ..points = 11
      ..winners = 5
      ..aces = 2
      ..smashes = 3
      ..errors = 4;
    engine.s.stats[1]
      ..points = 8
      ..winners = 3
      ..errors = 7
      ..kitchenFaults = 1;
    await frames(t, 60);
    await shoot(t, '7_game_over');
    await t.pumpWidget(const SizedBox());
  });
}

