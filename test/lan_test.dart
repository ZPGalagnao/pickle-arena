import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pickle_arena/game/ai/brain.dart';
import 'package:pickle_arena/game/engine.dart';
import 'package:pickle_arena/game/game_state.dart';
import 'package:pickle_arena/game/session.dart';
import 'package:pickle_arena/game/shot_planner.dart';
import 'package:pickle_arena/models/profile.dart';
import 'package:pickle_arena/net/lan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final brain = PickleBrain.fromJson(
      jsonDecode(File('assets/ai/pickle_brain.json').readAsStringSync()) as Map<String, dynamic>);

  Future<LanClient> joinAs(LanHost host, String name) async {
    final c = LanClient();
    final lobby = Completer<Map<String, dynamic>>();
    c.onMessage = (m) {
      if (m['t'] == 'lobby' && !lobby.isCompleted) lobby.complete(m);
    };
    await c.connect('127.0.0.1', host.port);
    c.send({'t': 'hello', 'profile': PlayerProfile(name: name).toJson(), 'assist': true});
    return c;
  }

  test('singles: host and client handshake and play over TCP', () async {
    final host = LanHost()..maxPeers = 1;
    final hello = Completer<LanPeer>();
    host.onMessage = (peer, m) {
      if (m['t'] == 'hello' && !hello.isCompleted) {
        peer
          ..slot = 1
          ..profileJson = (m['profile'] as Map).cast<String, dynamic>();
        hello.complete(peer);
      }
    };
    await host.start('Test Court');
    final client = await joinAs(host, 'Guest');
    final peer = await hello.future.timeout(const Duration(seconds: 5));
    expect(PlayerProfile.fromJson(peer.profileJson!).name, 'Guest');

    final cfg = MatchConfig(pointsToWin: 11);
    final slots = [PlayerProfile(name: 'Host'), PlayerProfile.fromJson(peer.profileJson!)];
    final hs = HostSession(host: host, slots: slots, slotPeers: {1: peer}, brain: brain, config: cfg, myAutoHit: true);
    final cs = ClientSession(client: client, slots: slots, localIndex: 1, config: cfg);

    // the guest walks toward the net (if receiving; servers wait in place)
    final guestServes = hs.state.server == 1;
    final startY = hs.state.players[1].y;
    for (var i = 0; i < 90; i++) {
      cs.update(1 / 60, PlayerInput(my: 1));
      hs.update(1 / 60, PlayerInput());
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (!guestServes) {
      expect(hs.state.players[1].y, lessThan(startY - 0.5), reason: 'host received the guest\'s joystick');
    }
    expect(cs.state.players[1].y, closeTo(hs.state.players[1].y, 0.6), reason: 'client prediction stays close');

    if (hs.state.server == 0) {
      hs.update(1 / 60, PlayerInput(shot: ShotKind.drive));
    } else {
      cs.update(1 / 60, PlayerInput(shot: ShotKind.drive));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      hs.update(1 / 60, PlayerInput());
    }
    for (var i = 0; i < 10; i++) {
      hs.update(1 / 60, PlayerInput());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cs.update(1 / 60, PlayerInput());
    }
    expect(hs.state.phase, Phase.rally);
    expect(cs.state.phase, Phase.rally);
    expect(cs.takeEvents().any((e) => e.type == 'serve'), isTrue);

    client.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(hs.disconnected, isTrue);
    await host.stop();
  });

  test('doubles: 3 phones join, the 4th spot is played by the AI', () async {
    final host = LanHost()..maxPeers = 3;
    final peers = <LanPeer>[];
    final allIn = Completer<void>();
    host.onMessage = (peer, m) {
      if (m['t'] == 'hello') {
        peer
          ..slot = const [2, 1, 3][peers.length]
          ..profileJson = (m['profile'] as Map).cast<String, dynamic>();
        peers.add(peer);
        if (peers.length == 2 && !allIn.isCompleted) allIn.complete();
      }
    };
    await host.start('Doubles Court');
    final c1 = await joinAs(host, 'Ana');
    final c2 = await joinAs(host, 'Ben');
    await allIn.future.timeout(const Duration(seconds: 5));

    final cfg = MatchConfig(doubles: true, botLevel: 'hard');
    final slots = <PlayerProfile>[
      PlayerProfile(name: 'Host'),
      for (var s = 1; s < 4; s++)
        peers.where((p) => p.slot == s).map((p) => PlayerProfile.fromJson(p.profileJson!)).firstOrNull ??
            PlayerProfile(name: 'Bot'),
    ];
    final hs = HostSession(
      host: host,
      slots: slots,
      slotPeers: {for (final p in peers) p.slot: p},
      brain: brain,
      config: cfg,
      myAutoHit: true,
    );
    final cs1 = ClientSession(client: c1, slots: slots, localIndex: peers[0].slot, config: cfg);
    final cs2 = ClientSession(client: c2, slots: slots, localIndex: peers[1].slot, config: cfg);
    expect(hs.state.players.length, 4);
    for (var i = 0; i < 240; i++) {
      hs.update(1 / 60, PlayerInput(shot: i % 30 == 0 ? ShotKind.soft : null));
      // every phone taps a button now and then, so whoever is serving serves
      cs1.update(1 / 60, PlayerInput(mx: 0.5, shot: i % 30 == 5 ? ShotKind.drive : null));
      cs2.update(1 / 60, PlayerInput(shot: i % 30 == 10 ? ShotKind.lob : null));
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    expect(cs1.state.players.length, 4);
    expect(cs1.state.score, hs.state.score);
    expect(hs.state.shotCount, greaterThan(0), reason: 'someone served (host or the AI)');
    c1.close();
    c2.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(hs.disconnected, isFalse, reason: 'doubles goes on with AI taking over');
    await host.stop();
  });
}
