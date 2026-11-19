import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pickle_arena/game/engine.dart';
import 'package:pickle_arena/game/game_state.dart';
import 'package:pickle_arena/game/session.dart';
import 'package:pickle_arena/game/shot_planner.dart';
import 'package:pickle_arena/models/profile.dart';
import 'package:pickle_arena/net/lan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('host and client connect, handshake and play over TCP', () async {
    final host = LanHost();
    final client = LanClient();
    final hello = Completer<Map<String, dynamic>>();
    final welcome = Completer<Map<String, dynamic>>();
    host.onMessage = (m) {
      if (m['t'] == 'hello' && !hello.isCompleted) hello.complete(m);
    };
    client.onMessage = (m) {
      if (m['t'] == 'welcome' && !welcome.isCompleted) welcome.complete(m);
    };
    await host.start('Test Court');
    await client.connect('127.0.0.1', host.port);

    final guest = PlayerProfile(name: 'Guest');
    client.send({'t': 'hello', 'profile': guest.toJson(), 'assist': true});
    final h = await hello.future.timeout(const Duration(seconds: 5));
    expect(PlayerProfile.fromJson((h['profile'] as Map).cast<String, dynamic>()).name, 'Guest');

    final me = PlayerProfile(name: 'Host');
    host.send({'t': 'welcome', 'profile': me.toJson(), 'config': MatchConfig().toJson()});
    final w = await welcome.future.timeout(const Duration(seconds: 5));
    expect((w['profile'] as Map)['name'], 'Host');

    // start real sessions on both ends
    final cfg = MatchConfig(pointsToWin: 11);
    final hs = HostSession(host: host, me: me, guest: guest, config: cfg, myAutoHit: true, guestAutoHit: true);
    final cs = ClientSession(client: client, me: guest, hostProfile: me, config: cfg);

    // the guest walks toward the net; the host simulates and streams snapshots back
    final startY = hs.state.players[1].y;
    for (var i = 0; i < 90; i++) {
      cs.update(1 / 60, PlayerInput(my: 1));
      hs.update(1 / 60, PlayerInput());
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(hs.state.players[1].y, lessThan(startY - 0.5), reason: 'host received the guest\'s joystick');
    expect(cs.state.players[1].y, closeTo(hs.state.players[1].y, 0.6), reason: 'client prediction stays close');

    // a serve from the host shows up on the client
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
}
