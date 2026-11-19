import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pickle_arena/game/ai/ai_controller.dart';
import 'package:pickle_arena/game/ai/brain.dart';
import 'package:pickle_arena/game/engine.dart';
import 'package:pickle_arena/game/game_state.dart';
import 'package:pickle_arena/game/physics.dart';
import 'package:pickle_arena/game/shot_planner.dart';
import 'package:pickle_arena/models/profile.dart';

void main() {
  late PickleBrain brain;
  late Map<String, dynamic> selftest;

  setUpAll(() {
    final j = jsonDecode(File('assets/ai/pickle_brain.json').readAsStringSync()) as Map<String, dynamic>;
    brain = PickleBrain.fromJson(j);
    selftest = j['selftest'] as Map<String, dynamic>;
  });

  group('physics matches the Python simulator', () {
    test('time to ground', () {
      for (final c in selftest['ground'] as List) {
        final t = BallPhysics.timeToGround((c['z'] as num).toDouble(), (c['vz'] as num).toDouble());
        expect(t, closeTo((c['t'] as num).toDouble(), 1e-6));
      }
    });

    test('shot planner', () {
      for (final c in selftest['planner'] as List) {
        final h = (c['hit'] as List).map((e) => (e as num).toDouble()).toList();
        final t = (c['target'] as List).map((e) => (e as num).toDouble()).toList();
        final plan = ShotPlanner.plan(ShotKind.values[c['kind'] as int], h[0], h[1], h[2], t[0], t[1],
            power: (c['power'] as num).toDouble());
        final v = (c['v'] as List).map((e) => (e as num).toDouble()).toList();
        expect(plan.vx, closeTo(v[0], 1e-4));
        expect(plan.vy, closeTo(v[1], 1e-4));
        expect(plan.vz, closeTo(v[2], 1e-4));
        expect(plan.flightTime, closeTo((c['T'] as num).toDouble(), 1e-5));
      }
    });

    test('a planned shot lands on its target and clears the net', () {
      final plan = ShotPlanner.plan(ShotKind.drive, 0.5, -6.4, 0.8, 1.5, 5.3);
      final b = Ball(x: 0.5, y: -6.4, z: 0.8, vx: plan.vx, vy: plan.vy, vz: plan.vz);
      final events = <BallEvent>[];
      for (var i = 0; i < 400 && events.isEmpty; i++) {
        events.addAll(BallPhysics.step(b, 1 / 120));
      }
      expect(events.first.type, BallEventType.bounce);
      expect(events.first.x, closeTo(1.5, 1e-3));
      expect(events.first.y, closeTo(5.3, 1e-3));
    });

    test('a low ball hits the net', () {
      final b = Ball(x: 0, y: -3, z: 0.3, vx: 0, vy: 12, vz: 0.5);
      final events = <BallEvent>[];
      for (var i = 0; i < 120 && events.isEmpty; i++) {
        events.addAll(BallPhysics.step(b, 1 / 120));
      }
      expect(events.first.type, BallEventType.net);
    });
  });

  group('neural networks match Keras', () {
    test('trajectory predictor', () {
      for (final c in selftest['predictor'] as List) {
        final x = (c['x'] as List).map((e) => (e as num).toDouble()).toList();
        final p = brain.predict(x[0], x[1], x[2], x[3], x[4], x[5], x[6]);
        final plane = (c['plane'] as List).map((e) => (e as num).toDouble()).toList();
        final bounce = (c['bounce'] as List).map((e) => (e as num).toDouble()).toList();
        expect(p.x, closeTo(plane[0], 1e-3));
        expect(p.z, closeTo(plane[1], 1e-3));
        expect(p.t, closeTo(plane[2], 1e-3));
        expect(p.reach, closeTo((c['reach'] as num).toDouble(), 1e-4));
        expect(p.bounceX, closeTo(bounce[0], 1e-3));
        expect(p.bounceY, closeTo(bounce[1], 1e-3));
      }
    });

    test('shot selector', () {
      for (final c in selftest['selector'] as List) {
        final x = (c['x'] as List).map((e) => (e as num).toDouble()).toList();
        final probs = brain.shotProbabilities(x);
        final want = (c['p'] as List).map((e) => (e as num).toDouble()).toList();
        for (var i = 0; i < 9; i++) {
          expect(probs[i], closeTo(want[i], 1e-4));
        }
      }
    });

    test('predictor is accurate against the real physics', () {
      final rng = math.Random(3);
      var errX = 0.0, n = 0;
      for (var k = 0; k < 200; k++) {
        final hx = rng.nextDouble() * 4 - 2, hy = 3 + rng.nextDouble() * 3;
        final plan = ShotPlanner.plan(ShotKind.drive, hx, hy, 0.9, rng.nextDouble() * 4 - 2, -5);
        final b = Ball(x: hx, y: hy, z: 0.9, vx: plan.vx, vy: plan.vy, vz: plan.vz);
        const yp = -6.0;
        final pred = brain.predict(b.x, b.y, b.z, b.vx, b.vy, b.vz, yp);
        // simulate until the ball crosses y = -6
        for (var i = 0; i < 600 && b.y > yp; i++) {
          BallPhysics.step(b, 1 / 240);
        }
        if (b.y <= yp && pred.reach > 0.5) {
          errX += (b.x - pred.x).abs();
          n++;
        }
      }
      expect(n, greaterThan(100));
      expect(errX / n, lessThan(0.2));
    });
  });

  group('rules', () {
    GameEngine engine() => GameEngine(
          config: MatchConfig(pointsToWin: 11),
          profiles: [PlayerProfile(name: 'A'), PlayerProfile(name: 'B')],
          firstServer: 0,
          random: math.Random(1),
          autoHit: [false, false],
        );

    void run(GameEngine e, double seconds, List<PlayerInput> inputs) {
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        e.update(1 / 60, inputs);
        for (final i in inputs) {
          i.clearEdge();
        }
      }
    }

    test('serve lands and an unreturned ball is a point for the server', () {
      final e = engine();
      final idle = [PlayerInput(), PlayerInput()];
      run(e, 0.6, idle);
      expect(e.s.phase, Phase.serve);
      run(e, 0.1, [PlayerInput(shot: ShotKind.soft), PlayerInput()]);
      expect(e.s.phase, Phase.rally);
      run(e, 4, idle);
      expect(e.s.phase, isNot(Phase.rally));
      // receiver never moved and never swung -> server wins (ace) unless it was a fault
      expect(e.s.score[0] + e.s.score[1], 1);
    });

    test('volleying from the kitchen is a fault', () {
      final e = engine();
      final s = e.s;
      s.phase = Phase.rally;
      s.ballHeld = false;
      s.lastHitter = 0;
      s.shotCount = 5; // volleys allowed
      s.bouncesOnReceiver = 0;
      final rcv = s.players[1];
      rcv
        ..x = 0
        ..y = 1.0; // inside the far kitchen
      s.ball
        ..x = 0.3
        ..y = 1.4
        ..z = 1.0
        ..vx = 0
        ..vy = -1
        ..vz = 0;
      run(e, 0.05, [PlayerInput(), PlayerInput(shot: ShotKind.drive)]);
      expect(s.phase, Phase.pointOver);
      expect(s.score[0], 1);
      expect(s.stats[1].kitchenFaults, 1);
    });

    test('two-bounce rule: return of serve cannot be volleyed', () {
      final e = engine();
      final s = e.s;
      s.phase = Phase.rally;
      s.ballHeld = false;
      s.lastHitter = 0;
      s.shotCount = 1; // just served
      s.bouncesOnReceiver = 0;
      s.players[1]
        ..x = 0
        ..y = 5.0;
      s.ball
        ..x = 0.3
        ..y = 5.2
        ..z = 1.0
        ..vx = 0
        ..vy = 0.1
        ..vz = 0;
      run(e, 0.03, [PlayerInput(), PlayerInput(shot: ShotKind.drive)]);
      expect(s.lastHitter, 0, reason: 'receiver must not be able to volley the serve');
    });
  });

  test('AI vs AI plays a complete, legal match', () {
    final profiles = [PlayerProfile(name: 'Bot A'), PlayerProfile(name: 'Bot B')];
    final e = GameEngine(
      config: MatchConfig(pointsToWin: 11, gameSpeed: 1),
      profiles: profiles,
      autoHit: [false, false],
      random: math.Random(7),
    );
    final ais = [
      AiController(brain, AiDifficulty.hard, 0, random: math.Random(1)),
      AiController(brain, AiDifficulty.medium, 1, random: math.Random(2)),
    ];
    var hits = 0, maxRally = 0;
    for (var frame = 0; frame < 60 * 60 * 30 && e.s.phase != Phase.gameOver; frame++) {
      e.update(1 / 60, [
        ais[0].update(e.s, profiles[0], 1 / 60),
        ais[1].update(e.s, profiles[1], 1 / 60),
      ]);
      for (final ev in e.drainEvents()) {
        if (ev.type == 'hit' || ev.type == 'smash') hits++;
      }
      maxRally = math.max(maxRally, e.s.rally);
    }
    expect(e.s.phase, Phase.gameOver);
    final w = e.s.winner;
    expect(e.s.score[w], greaterThanOrEqualTo(11));
    expect(e.s.score[w] - e.s.score[1 - w], greaterThanOrEqualTo(2));
    // the AI must actually rally, not just lose every serve
    expect(hits, greaterThan(30));
    expect(maxRally, greaterThanOrEqualTo(5));
    // ignore: avoid_print
    print('AI match: ${e.s.score}  hits=$hits  longest rally=$maxRally  '
        'errors=${e.s.stats.map((s) => s.errors).toList()} '
        'winners=${e.s.stats.map((s) => s.winners).toList()}');
  });

  test('snapshot round-trips through JSON', () {
    final e = GameEngine(
      config: MatchConfig(),
      profiles: [PlayerProfile(name: 'A'), PlayerProfile(name: 'B')],
      firstServer: 1,
    );
    e.update(0.5, [PlayerInput(), PlayerInput()]);
    final json = jsonDecode(jsonEncode(e.s.toJson())) as Map<String, dynamic>;
    final copy = GameState()..applyJson(json);
    expect(copy.server, 1);
    expect(copy.players[1].y, closeTo(e.s.players[1].y, 1e-3));
    expect(copy.phase, e.s.phase);
  });
}
