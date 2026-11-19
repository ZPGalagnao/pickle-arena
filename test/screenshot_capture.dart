// Renders PNG screenshots of the main screens (not part of the normal test run).
//   flutter test test/screenshot_capture.dart --dart-define=OUT=<folder> --dart-define=FONTS=<material_fonts dir>
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
import 'package:pickle_arena/game/physics.dart';
import 'package:pickle_arena/game/session.dart';
import 'package:pickle_arena/main.dart';
import 'package:pickle_arena/models/profile.dart';
import 'package:pickle_arena/screens/ai_setup_screen.dart';
import 'package:pickle_arena/screens/customize_screen.dart';
import 'package:pickle_arena/screens/game_screen.dart';
import 'package:pickle_arena/screens/help_screen.dart';
import 'package:pickle_arena/screens/lobby_screen.dart';
import 'package:pickle_arena/screens/settings_screen.dart';
import 'package:pickle_arena/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const outDir = String.fromEnvironment('OUT', defaultValue: 'build/screens');
const fontDir = String.fromEnvironment('FONTS');

/// Every player driven by the AI, shown from player 0's point of view.
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
  String? get aiThought => ais.last.lastThought;
  @override
  void update(double dt, PlayerInput local) {
    final g = dt * engine.config.gameSpeed * (engine.s.slowmo > 0 ? GameEngine.slowmoScale : 1);
    engine.update(dt, [for (var i = 0; i < ais.length; i++) ais[i].update(engine.s, profiles[i], g)]);
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
          '{"name":"Zoren","look":{"jersey":4281637083,"shorts":4279969354,"paddle":4292146234,"number":23,"accessory":2,"pattern":3,"skin":4293962857,"hair":4280032016},"stats":{"speed":5,"power":4,"control":3},"special":0,"xp":620}',
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
        child: AppScope(
            state: state, child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: child)),
      );

  BotSession bots(bool doubles, int seed) {
    final profiles = doubles
        ? [state.profile, aiRoster[1].profile, aiRoster[3].profile, aiRoster[2].profile]
        : [state.profile, aiRoster[3].profile];
    final engine = GameEngine(
        config: MatchConfig(pointsToWin: 11, doubles: doubles),
        profiles: profiles,
        autoHit: List.filled(profiles.length, false),
        random: math.Random(seed),
        firstServer: doubles ? 2 : 1);
    return BotSession(
        engine, [for (var i = 0; i < profiles.length; i++) AiController(brain, AiDifficulty.hard, i)], profiles);
  }

  testWidgets('screens', (t) async {
    await t.binding.setSurfaceSize(const Size(860, 400));
    t.view.physicalSize = const Size(860, 400);
    t.view.devicePixelRatio = 1;

    await t.pumpWidget(RepaintBoundary(key: key, child: PickleArenaApp(state: state)));
    await frames(t, 200);
    await shoot(t, '1_home');

    await t.pumpWidget(wrap(const CustomizeScreen()));
    await frames(t, 40);
    await shoot(t, '2_customize');
    await t.tap(find.text('SPECIAL'));
    await frames(t, 40);
    await shoot(t, '2b_customize_special');

    await t.pumpWidget(wrap(const AiSetupScreen()));
    await frames(t, 40);
    await shoot(t, '3_ai_select');
    await t.tap(find.text('Doubles 2 vs 2'));
    await frames(t, 40);
    await shoot(t, '3b_ai_select_doubles');

    await t.pumpWidget(wrap(const LobbyScreen()));
    await frames(t, 10);
    await shoot(t, '4_lobby');

    await t.pumpWidget(wrap(const SettingsScreen()));
    await frames(t, 10);
    await shoot(t, '4b_settings');

    await t.pumpWidget(wrap(const HelpScreen(initialTab: 2)));
    await frames(t, 20);
    await shoot(t, '5_guide_specials');

    // ---------------------------------------------- singles rally
    var session = bots(false, 4);
    await t.pumpWidget(wrap(GameScreen(session: session)));
    for (var i = 0; i < 4000; i++) {
      await t.pump(const Duration(milliseconds: 16));
      final s = session.engine.s;
      if (s.phase == Phase.rally && s.rally >= 3 && s.ball.z > 0.9 && s.ball.y < -1.5 && s.hittingTeam == 1) {
        await shoot(t, '6_game_singles');
        break;
      }
    }
    await t.pumpWidget(const SizedBox());

    // ---------------------------------------------- doubles + a special attack
    session = bots(true, 9);
    await t.pumpWidget(wrap(GameScreen(session: session)));
    var shotSpecial = false;
    for (var i = 0; i < 6000 && !shotSpecial; i++) {
      final s = session.engine.s;
      // charge the far team's specials so we see one quickly
      if (i % 60 == 0) {
        for (final p in s.players) {
          if (p.team == 1) p.meter = 1;
        }
      }
      await t.pump(const Duration(milliseconds: 16));
      if (s.phase == Phase.rally && s.rally >= 2 && s.ball.y < 0 && s.ball.y > -3 && s.ball.fx != BallFx.none) {
        await frames(t, 3);
        await shoot(t, '7_game_doubles_special');
        shotSpecial = true;
      }
    }
    // ---------------------------------------------- victory cinematic + ranking
    final s = session.engine.s;
    s
      ..score[0] = 11
      ..score[1] = 8
      ..winner = 0
      ..phase = Phase.pointOver
      ..phaseTime = 1.7;
    s.stats[0]
      ..winners = 5
      ..aces = 2
      ..smashes = 3
      ..specials = 2
      ..errors = 2
      ..hits = 30;
    s.stats[1]
      ..winners = 3
      ..specials = 1
      ..errors = 3
      ..hits = 25;
    s.stats[2]
      ..winners = 2
      ..errors = 5
      ..hits = 20;
    s.stats[3]
      ..winners = 4
      ..specials = 2
      ..errors = 4
      ..kitchenFaults = 1
      ..hits = 24;
    await frames(t, 90);
    await shoot(t, '8_victory');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await frames(t, 200);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await frames(t, 80);
    await shoot(t, '9_results');
    await t.pumpWidget(const SizedBox());
  });
}
