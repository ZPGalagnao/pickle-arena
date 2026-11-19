import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../game/ai/ai_controller.dart';
import '../game/ai/brain.dart';
import '../game/ai/roster.dart';
import '../game/engine.dart';
import '../game/session.dart';
import '../models/profile.dart';
import '../net/lan.dart';
import '../ui/avatar.dart';
import '../ui/theme.dart';
import 'game_screen.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                        const Text('WI-FI MULTIPLAYER', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                      ]),
                      const SizedBox(height: 4),
                      const GlassCard(
                        child: Row(
                          children: [
                            Icon(Icons.wifi_tethering_rounded, color: AppColors.lime, size: 34),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Both phones on the same Wi-Fi, or one phone turns on its Hotspot and the others '
                                'connect to it. No internet needed. Singles: 2 phones. Doubles: 2 to 4 phones; '
                                'empty spots are played by the AI.',
                                style: TextStyle(color: AppColors.text, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const _Tip(Icons.wifi_rounded, 'Hotspot: the phone with the hotspot ON should HOST.'),
                      const _Tip(Icons.edit_location_alt_rounded, 'Room not showing? Type the IP shown on the host phone.'),
                      const _Tip(Icons.battery_charging_full_rounded, 'Keep all screens on. The host phone runs the game.'),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 300,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BigButton(
                        label: 'HOST A GAME',
                        subtitle: 'Create a room for your friends',
                        icon: Icons.router_rounded,
                        colors: const [AppColors.lime, Color(0xFF9CFF57)],
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HostLobby())),
                      ),
                      const SizedBox(height: 12),
                      BigButton(
                        label: 'JOIN A GAME',
                        subtitle: 'Find rooms near you',
                        icon: Icons.search_rounded,
                        colors: const [AppColors.blue, AppColors.purple],
                        textColor: Colors.white,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JoinLobby())),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tip(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(color: AppColors.text, fontSize: 12.5))),
          ],
        ),
      );
}

/// One player spot in the lobby: the host, a phone, or an AI fill-in.
class _Slot extends StatelessWidget {
  final PlayerProfile? profile;
  final String label;
  final bool isBot;
  final VoidCallback? onMove;
  const _Slot({required this.profile, required this.label, this.isBot = false, this.onMove});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return GlassCard(
      padding: const EdgeInsets.all(8),
      borderColor: p == null ? null : Color(p.look.jersey).withValues(alpha: 0.7),
      child: Row(
        children: [
          if (p == null)
            const SizedBox(
                width: 40, height: 40, child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2.5)))
          else
            FaceAvatar(profile: p, size: 40),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.2)),
                Text(p == null ? (isBot ? 'AI will play' : 'Waiting...') : p.name,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              ],
            ),
          ),
          if (isBot) const Icon(Icons.smart_toy_rounded, color: AppColors.muted, size: 18),
          if (onMove != null)
            IconButton(
              tooltip: 'Move to the other team',
              visualDensity: VisualDensity.compact,
              onPressed: onMove,
              icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.lime),
            ),
        ],
      ),
    );
  }
}

// ===================================================================== HOST
class HostLobby extends StatefulWidget {
  const HostLobby({super.key});

  @override
  State<HostLobby> createState() => _HostLobbyState();
}

class _HostLobbyState extends State<HostLobby> {
  final LanHost _host = LanHost();
  String? _error;
  bool _starting = false;
  bool _started = false;
  bool _doubles = false;
  int _points = 11;
  bool _rally = true;
  String _botLevel = 'medium';

  int get _slotCount => _doubles ? 4 : 2;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final me = AppScope.read(context).profile;
    _host.onPeerJoined = (_) => setState(() {});
    _host.onPeerLeft = (_) {
      if (mounted && !_started) {
        setState(() {});
        _broadcastLobby();
      }
    };
    _host.onMessage = _onMessage;
    _host.maxPeers = 1;
    try {
      await _host.start("${me.name}'s Court");
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open a room: $e');
    }
  }

  MatchConfig get _config => MatchConfig(
      pointsToWin: _points,
      rallyScoring: _rally,
      gameSpeed: AppScope.read(context).settings.gameSpeed,
      doubles: _doubles,
      botLevel: _botLevel);

  LanPeer? _peerAt(int slot) {
    for (final p in _host.peers) {
      if (p.slot == slot && p.profileJson != null) return p;
    }
    return null;
  }

  int? _freeSlot({int? team}) {
    final order = _doubles ? const [2, 1, 3] : const [1];
    for (final s in order) {
      if (team != null && (s ~/ 2) != team) continue;
      if (_peerAt(s) == null) return s;
    }
    return null;
  }

  void _onMessage(LanPeer peer, Map<String, dynamic> m) {
    if (m['t'] == 'hello') {
      final slot = _freeSlot();
      if (slot == null || _started) {
        _host.kick(peer);
        return;
      }
      peer
        ..profileJson = (m['profile'] as Map).cast<String, dynamic>()
        ..assist = m['assist'] as bool? ?? true
        ..slot = slot;
      HapticFeedback.mediumImpact();
      setState(() {});
      _broadcastLobby();
    }
  }

  void _setDoubles(bool v) {
    setState(() => _doubles = v);
    _host.maxPeers = v ? 3 : 1;
    if (!v) {
      // singles: only one guest; extra phones are sent away
      final guests = _host.peers.where((p) => p.profileJson != null).toList();
      for (var k = 0; k < guests.length; k++) {
        if (k == 0) {
          guests[k].slot = 1;
        } else {
          _host.kick(guests[k]);
        }
      }
    } else {
      for (final p in _host.peers) {
        if (p.slot == 1) p.slot = 2; // first guest plays against the host
      }
    }
    _broadcastLobby();
  }

  void _move(LanPeer peer) {
    final otherTeam = 1 - peer.slot ~/ 2;
    final target = _freeSlot(team: otherTeam);
    if (target == null) return;
    setState(() => peer.slot = target);
    _broadcastLobby();
  }

  void _broadcastLobby() {
    final me = AppScope.read(context).profile;
    final slots = <Map<String, dynamic>?>[
      me.toJson(includeFace: false),
      for (var s = 1; s < _slotCount; s++) _peerAt(s)?.profileJson,
    ];
    for (final p in _host.peers) {
      if (p.profileJson == null) continue;
      _host.send(p, {
        't': 'lobby',
        'you': p.slot,
        'slots': [for (final s in slots) s == null ? null : (Map.of(s)..remove('face'))],
        'config': _config.toJson(),
      });
    }
  }

  Future<void> _startMatch() async {
    if (_starting) return;
    setState(() => _starting = true);
    final app = AppScope.read(context);
    final cfg = _config;
    final brain = await PickleBrain.load();
    // fill empty slots with AI players (different characters from the roster)
    final usedBots = <int>{};
    final slots = <PlayerProfile>[app.profile];
    final slotPeers = <int, LanPeer>{};
    for (var s = 1; s < _slotCount; s++) {
      final peer = _peerAt(s);
      if (peer != null) {
        slots.add(PlayerProfile.fromJson(peer.profileJson!));
        slotPeers[s] = peer;
      } else {
        var k = s % aiRoster.length;
        while (usedBots.contains(k)) {
          k = (k + 1) % aiRoster.length;
        }
        usedBots.add(k);
        slots.add(aiRoster[k].profile);
      }
    }
    for (final p in List.of(_host.peers)) {
      if (!slotPeers.containsValue(p)) _host.kick(p);
    }
    final session = HostSession(
      host: _host,
      slots: slots,
      slotPeers: slotPeers,
      brain: brain,
      config: cfg,
      myAutoHit: app.settings.autoHit,
      myMoveAssist: app.settings.moveAssist,
    );
    final slotJson = [for (final p in slots) p.toJson()];
    for (final e in slotPeers.entries) {
      _host.send(e.value, {'t': 'start', 'config': cfg.toJson(), 'slots': slotJson, 'you': e.key});
    }
    _host.broadcast(session.state.toJson());
    _started = true;
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(session: session)));
  }

  @override
  void dispose() {
    if (!_started) _host.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = AppScope.of(context).profile;
    final guests = _host.peers.where((p) => p.profileJson != null).length;
    final canStart = guests > 0;
    Widget slot(int s) {
      if (s == 0) return _Slot(profile: me, label: 'HOST (YOU)');
      final peer = _peerAt(s);
      return _Slot(
        profile: peer == null ? null : PlayerProfile.fromJson(peer.profileJson!),
        label: 'PLAYER ${s + 1}',
        isBot: peer == null && _doubles,
        onMove: peer != null && _doubles && _freeSlot(team: 1 - s ~/ 2) != null ? () => _move(peer) : null,
      );
    }

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ------------------------------------------- room + settings
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                        Expanded(
                          child: Text("${me.name}'s Court".toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                        ),
                      ]),
                      if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.pink)),
                      GlassCard(
                        padding: const EdgeInsets.all(10),
                        child: _host.ips.isEmpty
                            ? const Text('Turn on Wi-Fi or Hotspot', style: TextStyle(color: AppColors.orange))
                            : Row(
                                children: [
                                  const Text('Join with IP:  ', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                  Expanded(
                                    child: SelectableText(_host.ips.take(2).join('   '),
                                        style: const TextStyle(
                                            fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.lime)),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: GlassCard(
                          padding: const EdgeInsets.all(10),
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              const SectionLabel('Mode'),
                              ChoiceChipRow<bool>(
                                values: const [false, true],
                                selected: _doubles,
                                label: (v) => v ? 'Doubles' : 'Singles',
                                onSelected: _setDoubles,
                              ),
                              const SizedBox(height: 8),
                              const SectionLabel('Points to win'),
                              ChoiceChipRow<int>(
                                values: const [7, 11, 15, 21],
                                selected: _points,
                                label: (v) => '$v',
                                onSelected: (v) {
                                  setState(() => _points = v);
                                  _broadcastLobby();
                                },
                              ),
                              const SizedBox(height: 8),
                              const SectionLabel('Scoring'),
                              ChoiceChipRow<bool>(
                                values: const [true, false],
                                selected: _rally,
                                label: (v) => v ? 'Rally' : 'Traditional',
                                onSelected: (v) {
                                  setState(() => _rally = v);
                                  _broadcastLobby();
                                },
                              ),
                              if (_doubles) ...[
                                const SizedBox(height: 8),
                                const SectionLabel('AI fill-in level'),
                                ChoiceChipRow<String>(
                                  values: [for (final d in AiDifficulty.all) d.id],
                                  selected: _botLevel,
                                  label: (v) => AiDifficulty.byId(v).label,
                                  onSelected: (v) => setState(() => _botLevel = v),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // ------------------------------------------- teams
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      const Text('TEAM A', style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w900, fontSize: 12)),
                      slot(0),
                      if (_doubles) ...[const SizedBox(height: 6), slot(1)],
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Center(
                            child: Text('VS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic))),
                      ),
                      const Text('TEAM B', style: TextStyle(color: AppColors.pink, fontWeight: FontWeight.w900, fontSize: 12)),
                      slot(_doubles ? 2 : 1),
                      if (_doubles) ...[const SizedBox(height: 6), slot(3)],
                      const Spacer(),
                      BigButton(
                        label: canStart ? 'START MATCH' : 'WAITING FOR PLAYERS...',
                        icon: canStart ? Icons.play_arrow_rounded : Icons.hourglass_top_rounded,
                        colors: const [AppColors.lime, Color(0xFF9CFF57)],
                        onTap: !canStart || _starting ? null : _startMatch,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================================== JOIN
class JoinLobby extends StatefulWidget {
  const JoinLobby({super.key});

  @override
  State<JoinLobby> createState() => _JoinLobbyState();
}

class _JoinLobbyState extends State<JoinLobby> {
  final LanDiscovery _disc = LanDiscovery();
  final LanClient _client = LanClient();
  final TextEditingController _ip = TextEditingController();
  String? _status;
  bool _connecting = false;
  bool _joined = false;
  List<PlayerProfile?> _slots = [];
  int _you = -1;
  MatchConfig _config = MatchConfig();
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _disc.onChanged = () {
      if (mounted) setState(() {});
    };
    _disc.start().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _disc.stop();
    if (!_started) _client.close();
    _ip.dispose();
    super.dispose();
  }

  Future<void> _join(String ip, int port) async {
    if (_connecting) return;
    final app = AppScope.read(context);
    setState(() {
      _connecting = true;
      _status = 'Connecting to $ip ...';
    });
    _client.onMessage = _onMessage;
    _client.onDisconnected = () {
      if (mounted && !_started) {
        setState(() {
          _joined = false;
          _status = 'Disconnected (the room may be full)';
          _connecting = false;
        });
      }
    };
    try {
      await _client.connect(ip, port);
      _client.send({'t': 'hello', 'v': kProtocolVersion, 'profile': app.profile.toJson(), 'assist': app.settings.autoHit});
      setState(() => _status = 'Connected! Waiting for the host...');
    } catch (e) {
      setState(() {
        _status = 'Could not connect to $ip. Check that you are on the same Wi-Fi.';
        _connecting = false;
      });
    }
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'lobby':
        if (!_joined) HapticFeedback.mediumImpact();
        setState(() {
          _joined = true;
          _you = m['you'] as int;
          _config = MatchConfig.fromJson((m['config'] as Map).cast<String, dynamic>());
          _slots = [
            for (final s in (m['slots'] as List)) s == null ? null : PlayerProfile.fromJson((s as Map).cast<String, dynamic>())
          ];
          _status = 'In the room! Waiting for the host to start...';
        });
      case 'start':
        _started = true;
        final cfg = MatchConfig.fromJson((m['config'] as Map).cast<String, dynamic>());
        final slots = [
          for (final s in (m['slots'] as List)) PlayerProfile.fromJson((s as Map).cast<String, dynamic>())
        ];
        final session = ClientSession(client: _client, slots: slots, localIndex: m['you'] as int, config: cfg);
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(session: session)));
      case 'bye':
        setState(() {
          _joined = false;
          _status = 'The host closed the room';
          _connecting = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hosts = _disc.hosts.values.toList();
    final me = AppScope.of(context).profile;
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                        const Text('JOIN A GAME', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                      ]),
                      if (_status != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              if (_connecting && !_joined)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: SizedBox(
                                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.lime)),
                                ),
                              Expanded(child: Text(_status!, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
                            ],
                          ),
                        ),
                      if (!_joined) ...[
                        const SectionLabel('Rooms nearby'),
                        if (_disc.error != null) Text(_disc.error!, style: const TextStyle(color: AppColors.orange)),
                        Expanded(
                          child: hosts.isEmpty
                              ? const GlassCard(
                                  child: Text('Searching... make sure your friend tapped HOST A GAME.',
                                      style: TextStyle(color: AppColors.muted)),
                                )
                              : ListView(
                                  padding: EdgeInsets.zero,
                                  children: [
                                    for (final h in hosts)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: GlassCard(
                                          onTap: _connecting ? null : () => _join(h.ip, h.port),
                                          borderColor: AppColors.lime.withValues(alpha: 0.5),
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.sports_tennis_rounded, color: AppColors.lime),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(h.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                                                    Text(h.ip, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                                  ],
                                                ),
                                              ),
                                              const Text('JOIN',
                                                  style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w900)),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ] else
                        Expanded(
                          child: GlassCard(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FaceAvatar(profile: me, size: 70),
                                const SizedBox(height: 6),
                                Text('You are PLAYER ${_you + 1} on TEAM ${_you ~/ (_config.doubles ? 2 : 1) == 0 ? 'A' : 'B'}',
                                    style: const TextStyle(fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Text(
                                  '${_config.doubles ? 'Doubles' : 'Singles'}  •  first to ${_config.pointsToWin}  •  '
                                  '${_config.rallyScoring ? 'rally' : 'traditional'} scoring',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: _joined
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            for (var s = 0; s < _slots.length; s++) ...[
                              if (s == 0)
                                const Text('TEAM A',
                                    style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w900, fontSize: 12)),
                              if (s == _slots.length ~/ 2)
                                const Text('TEAM B',
                                    style: TextStyle(color: AppColors.pink, fontWeight: FontWeight.w900, fontSize: 12)),
                              _Slot(
                                profile: s == _you ? me : _slots[s],
                                label: s == 0 ? 'HOST' : (s == _you ? 'YOU' : 'PLAYER ${s + 1}'),
                                isBot: _slots[s] == null && s != _you,
                              ),
                              const SizedBox(height: 6),
                            ],
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionLabel('Or enter the host IP'),
                            TextField(
                              controller: _ip,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(hintText: 'e.g. 192.168.43.1'),
                            ),
                            const SizedBox(height: 10),
                            BigButton(
                              label: 'JOIN',
                              icon: Icons.login_rounded,
                              colors: const [AppColors.lime, Color(0xFF9CFF57)],
                              onTap: _connecting
                                  ? null
                                  : () {
                                      final ip = _ip.text.trim();
                                      if (ip.isNotEmpty) _join(ip, kGamePort);
                                    },
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
