import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
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
      appBar: AppBar(title: const Text('WI-FI MULTIPLAYER')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassCard(
                child: Row(
                  children: [
                    const Icon(Icons.wifi_tethering_rounded, color: AppColors.lime, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Play on the same network',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          SizedBox(height: 4),
                          Text(
                            'Both phones must be on the same Wi-Fi, or one phone turns on its '
                            'Hotspot and the other connects to it. No internet needed.',
                            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              BigButton(
                label: 'HOST A GAME',
                subtitle: 'Create a room and wait for a friend',
                icon: Icons.router_rounded,
                colors: const [AppColors.lime, Color(0xFF9CFF57)],
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HostLobby())),
              ),
              const SizedBox(height: 14),
              BigButton(
                label: 'JOIN A GAME',
                subtitle: 'Find rooms near you',
                icon: Icons.search_rounded,
                colors: const [AppColors.blue, AppColors.purple],
                textColor: Colors.white,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JoinLobby())),
              ),
              const SizedBox(height: 22),
              const SectionLabel('Tips'),
              const _Tip(Icons.wifi_rounded, 'Hotspot: the phone with the hotspot ON should HOST.'),
              const _Tip(Icons.edit_location_alt_rounded,
                  'Room not showing? Type the IP address shown on the host phone.'),
              const _Tip(Icons.battery_charging_full_rounded,
                  'Keep both screens on. The host phone runs the game engine.'),
            ],
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
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(color: AppColors.text, fontSize: 13))),
          ],
        ),
      );
}

// ===================================================================== HOST
class HostLobby extends StatefulWidget {
  const HostLobby({super.key});

  @override
  State<HostLobby> createState() => _HostLobbyState();
}

class _HostLobbyState extends State<HostLobby> {
  final LanHost _host = LanHost();
  PlayerProfile? _guest;
  bool _guestAssist = true;
  String? _error;
  bool _starting = false;
  bool _started = false;
  int _points = 11;
  bool _rally = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final me = AppScope.read(context).profile;
    _host.onClientConnected = () => setState(() {});
    _host.onDisconnected = () {
      if (mounted && !_started) setState(() => _guest = null);
    };
    _host.onMessage = _onMessage;
    try {
      await _host.start("${me.name}'s Court");
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open a room: $e');
    }
  }

  MatchConfig get _config => MatchConfig(
      pointsToWin: _points, rallyScoring: _rally, gameSpeed: AppScope.read(context).settings.gameSpeed);

  void _onMessage(Map<String, dynamic> m) {
    if (m['t'] == 'hello') {
      final p = PlayerProfile.fromJson((m['profile'] as Map).cast<String, dynamic>());
      _guestAssist = m['assist'] as bool? ?? true;
      final me = AppScope.read(context).profile;
      _host.send({'t': 'welcome', 'profile': me.toJson(), 'config': _config.toJson(), 'v': kProtocolVersion});
      HapticFeedback.mediumImpact();
      setState(() => _guest = p);
    } else if (m['t'] == 'bye') {
      setState(() => _guest = null);
      _host.kick();
    }
  }

  void _sendConfig() => _host.send({'t': 'config', 'config': _config.toJson()});

  Future<void> _startMatch() async {
    final guest = _guest;
    if (guest == null || _starting) return;
    setState(() => _starting = true);
    final app = AppScope.read(context);
    final cfg = _config;
    final session = HostSession(
      host: _host,
      me: app.profile,
      guest: guest,
      config: cfg,
      myAutoHit: app.settings.autoHit,
      guestAutoHit: _guestAssist,
    );
    _host.send({'t': 'start', 'config': cfg.toJson()});
    _host.send(session.state.toJson());
    _started = true;
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
    return Scaffold(
      appBar: AppBar(title: const Text('HOSTING')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                GlassCard(
                  borderColor: AppColors.pink,
                  child: Text(_error!, style: const TextStyle(color: AppColors.pink)),
                ),
              GlassCard(
                child: Column(
                  children: [
                    const Text('YOUR ROOM', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    const SizedBox(height: 4),
                    Text("${me.name}'s Court", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    if (_host.ips.isEmpty)
                      const Text('Turn on Wi-Fi or Hotspot', style: TextStyle(color: AppColors.orange))
                    else ...[
                      const Text('Friends can also join with this address:',
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      const SizedBox(height: 4),
                      for (final ip in _host.ips.take(3))
                        SelectableText(ip,
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.lime, letterSpacing: 1.5)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _PlayerSlot(profile: me, label: 'HOST')),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('VS', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                  ),
                  Expanded(child: _PlayerSlot(profile: _guest, label: 'GUEST')),
                ],
              ),
              const SizedBox(height: 14),
              GlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Points to win'),
                    ChoiceChipRow<int>(
                      values: const [7, 11, 15, 21],
                      selected: _points,
                      label: (v) => '$v',
                      onSelected: (v) {
                        setState(() => _points = v);
                        _sendConfig();
                      },
                    ),
                    const SizedBox(height: 10),
                    const SectionLabel('Scoring'),
                    ChoiceChipRow<bool>(
                      values: const [true, false],
                      selected: _rally,
                      label: (v) => v ? 'Rally scoring' : 'Traditional',
                      onSelected: (v) {
                        setState(() => _rally = v);
                        _sendConfig();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              BigButton(
                label: _guest == null ? 'WAITING FOR PLAYER...' : 'START MATCH',
                icon: _guest == null ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
                colors: const [AppColors.lime, Color(0xFF9CFF57)],
                onTap: _guest == null || _starting ? null : _startMatch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerSlot extends StatelessWidget {
  final PlayerProfile? profile;
  final String label;
  const _PlayerSlot({required this.profile, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderColor: p == null ? null : Color(p.look.jersey).withValues(alpha: 0.7),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12)),
          const SizedBox(height: 6),
          if (p == null) ...[
            const SizedBox(height: 70, child: Center(child: CircularProgressIndicator(strokeWidth: 3))),
            const SizedBox(height: 6),
            const Text('Waiting...', style: TextStyle(color: AppColors.muted)),
          ] else ...[
            SizedBox(height: 120, child: CharacterPreview(profile: p, height: 120)),
            const SizedBox(height: 4),
            Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ],
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
  PlayerProfile? _hostProfile;
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
          _hostProfile = null;
          _status = 'Disconnected from host';
          _connecting = false;
        });
      }
    };
    try {
      await _client.connect(ip, port);
      _client.send({
        't': 'hello',
        'v': kProtocolVersion,
        'profile': app.profile.toJson(),
        'assist': app.settings.autoHit,
      });
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
      case 'welcome':
        HapticFeedback.mediumImpact();
        setState(() {
          _hostProfile = PlayerProfile.fromJson((m['profile'] as Map).cast<String, dynamic>());
          _config = MatchConfig.fromJson((m['config'] as Map).cast<String, dynamic>());
          _status = 'Connected! Waiting for ${_hostProfile!.name} to start...';
        });
      case 'config':
        setState(() => _config = MatchConfig.fromJson((m['config'] as Map).cast<String, dynamic>()));
      case 'start':
        final host = _hostProfile;
        if (host == null) return;
        _started = true;
        final cfg = MatchConfig.fromJson((m['config'] as Map).cast<String, dynamic>());
        final session = ClientSession(
          client: _client,
          me: AppScope.read(context).profile,
          hostProfile: host,
          config: cfg,
        );
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(session: session)));
      case 'bye':
        setState(() {
          _hostProfile = null;
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
      appBar: AppBar(title: const Text('JOIN A GAME')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_hostProfile != null) ...[
                Row(
                  children: [
                    Expanded(child: _PlayerSlot(profile: _hostProfile, label: 'HOST')),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('VS', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                    ),
                    Expanded(child: _PlayerSlot(profile: me, label: 'YOU')),
                  ],
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Text(
                    'First to ${_config.pointsToWin}  •  ${_config.rallyScoring ? 'Rally scoring' : 'Traditional scoring'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      if (_connecting)
                        const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.lime)),
                      if (_connecting) const SizedBox(width: 10),
                      Expanded(child: Text(_status!, style: const TextStyle(color: AppColors.muted))),
                    ],
                  ),
                ),
              if (_hostProfile == null) ...[
                Row(
                  children: [
                    const Expanded(child: SectionLabel('Rooms nearby')),
                    if (_disc.error == null)
                      const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.muted)),
                  ],
                ),
                if (_disc.error != null) Text(_disc.error!, style: const TextStyle(color: AppColors.orange)),
                if (hosts.isEmpty)
                  const GlassCard(
                    child: Text('Searching... make sure your friend tapped HOST A GAME.',
                        style: TextStyle(color: AppColors.muted)),
                  ),
                for (final h in hosts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      onTap: _connecting ? null : () => _join(h.ip, h.port),
                      borderColor: AppColors.lime.withValues(alpha: 0.5),
                      child: Row(
                        children: [
                          const Icon(Icons.sports_tennis_rounded, color: AppColors.lime),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(h.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                Text(h.ip, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                              ],
                            ),
                          ),
                          const Text('JOIN', style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                const SectionLabel('Or enter the host IP'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ip,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(hintText: 'e.g. 192.168.43.1'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _connecting
                          ? null
                          : () {
                              final ip = _ip.text.trim();
                              if (ip.isNotEmpty) _join(ip, kGamePort);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.lime,
                        foregroundColor: AppColors.bg,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('JOIN', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
