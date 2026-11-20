// Frame-cost benchmark (not part of the normal test run):
//   flutter test test/perf_bench.dart
// Measures how long one game frame takes on the CPU: simulation (engine +
// AI) and recording the drawing commands of the game painter.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pickle_arena/game/ai/ai_controller.dart';
import 'package:pickle_arena/game/ai/brain.dart';
import 'package:pickle_arena/game/engine.dart';
import 'package:pickle_arena/game/game_state.dart';
import 'package:pickle_arena/game/render/court_view.dart';
import 'package:pickle_arena/game/render/effects.dart';
import 'package:pickle_arena/game/render/game_painter.dart';
import 'package:pickle_arena/models/profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('frame cost', () {
    final brain = PickleBrain.fromJson(
        jsonDecode(File('assets/ai/pickle_brain.json').readAsStringSync()) as Map<String, dynamic>);
    final profiles = [for (var i = 0; i < 4; i++) PlayerProfile(name: 'Player $i')];
    final engine = GameEngine(
        config: MatchConfig(doubles: true), profiles: profiles, autoHit: List.filled(4, false), random: math.Random(1));
    final ais = [for (var i = 0; i < 4; i++) AiController(brain, AiDifficulty.hard, i)];
    final fx = Effects();
    final scene = GameScene(
        state: engine.s, profiles: profiles, faces: List.filled(4, null), view: CourtView(), fx: fx, localIndex: 0,
        quality: const int.fromEnvironment('Q', defaultValue: 2));
    final painter = GamePainter(scene);
    const size = ui.Size(860, 400);
    final simW = Stopwatch(), paintW = Stopwatch();
    const frames = 600;
    for (var f = 0; f < frames + 60; f++) {
      if (f == 60) {
        simW.reset();
        paintW.reset();
      }
      simW.start();
      engine.update(1 / 60, [for (var i = 0; i < 4; i++) ais[i].update(engine.s, profiles[i], 0.9 / 60)]);
      for (final e in engine.drainEvents()) {
        fx.onEvent(e, engine.s);
      }
      fx.update(1 / 60, engine.s, gameOver: engine.s.phase == Phase.gameOver);
      scene.time += 1 / 60;
      simW.stop();
      paintW.start();
      final rec = ui.PictureRecorder();
      painter.paint(ui.Canvas(rec), size);
      rec.endRecording().dispose();
      paintW.stop();
    }
    // ignore: avoid_print
    print('per frame: simulation ${(simW.elapsedMicroseconds / frames / 1000).toStringAsFixed(2)} ms, '
        'paint recording ${(paintW.elapsedMicroseconds / frames / 1000).toStringAsFixed(2)} ms');
  });
}
