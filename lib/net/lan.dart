// Local network play over the same Wi-Fi or a phone hotspot. No internet needed.
//
//  * HOST opens a TCP server and broadcasts a small UDP "beacon" every second.
//  * JOIN listens for beacons, lists the rooms, and connects over TCP.
//  * Messages are newline-delimited JSON. The host runs the real game engine
//    and streams state snapshots; the joining phone streams its controls.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

const int kGamePort = 47820;
const int kDiscoveryPort = 47821;
const String kMagic = 'PICKLE_ARENA_1';
const int kProtocolVersion = 1;

class NetUtil {
  static const _channel = MethodChannel('pickle_arena/net');

  /// Android drops broadcast packets unless a Wi-Fi multicast lock is held.
  static Future<void> acquireMulticast() async {
    try {
      await _channel.invokeMethod('acquireMulticastLock');
    } catch (_) {}
  }

  static Future<void> releaseMulticast() async {
    try {
      await _channel.invokeMethod('releaseMulticastLock');
    } catch (_) {}
  }

  static Future<List<String>> localIPv4() async {
    try {
      final list = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      final out = <String>[];
      for (final i in list) {
        for (final a in i.addresses) {
          if (!a.isLoopback && !a.isLinkLocal) out.add(a.address);
        }
      }
      // Wi-Fi / hotspot style addresses first
      out.sort((a, b) => _rank(a).compareTo(_rank(b)));
      return out;
    } catch (_) {
      return [];
    }
  }

  static int _rank(String ip) {
    if (ip.startsWith('192.168.')) return 0;
    if (ip.startsWith('10.')) return 1;
    if (ip.startsWith('172.')) return 2;
    return 3;
  }

  /// Global broadcast plus the /24 broadcast of each interface (hotspots
  /// often ignore 255.255.255.255).
  static List<InternetAddress> broadcastTargets(List<String> ips) {
    final set = <String>{'255.255.255.255'};
    for (final ip in ips) {
      final parts = ip.split('.');
      if (parts.length == 4) set.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    return set.map(InternetAddress.new).toList();
  }
}

/// A TCP socket speaking newline-delimited JSON.
class JsonLineConnection {
  final Socket socket;
  void Function(Map<String, dynamic> msg)? onMessage;
  void Function()? onClosed;
  bool _closed = false;
  StreamSubscription<String>? _sub;

  JsonLineConnection(this.socket) {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _sub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _handleClosed, onError: (_) => _handleClosed(), cancelOnError: true);
  }

  String get remoteAddress {
    try {
      return socket.remoteAddress.address;
    } catch (_) {
      return '?';
    }
  }

  bool get isClosed => _closed;

  void _onLine(String line) {
    if (line.isEmpty) return;
    try {
      final m = jsonDecode(line);
      if (m is Map<String, dynamic>) onMessage?.call(m);
    } catch (_) {
      // ignore malformed lines
    }
  }

  void send(Map<String, dynamic> msg) {
    if (_closed) return;
    try {
      socket.write('${jsonEncode(msg)}\n');
    } catch (_) {
      _handleClosed();
    }
  }

  void _handleClosed() {
    if (_closed) return;
    _closed = true;
    _sub?.cancel();
    try {
      socket.destroy();
    } catch (_) {}
    onClosed?.call();
  }

  void close() {
    if (_closed) return;
    try {
      socket.write('${jsonEncode({'t': 'bye'})}\n');
      socket.flush().catchError((_) {}).whenComplete(() => socket.destroy());
    } catch (_) {}
    _closed = true;
    _sub?.cancel();
  }
}

class LanHost {
  ServerSocket? _server;
  RawDatagramSocket? _udp;
  Timer? _beaconTimer;
  JsonLineConnection? conn;
  int port = kGamePort;
  List<String> ips = [];
  String roomName = 'Pickle Room';

  void Function(Map<String, dynamic> msg)? onMessage;
  void Function()? onClientConnected;
  void Function()? onDisconnected;

  bool get hasClient => conn != null && !conn!.isClosed;

  Future<void> start(String roomName) async {
    this.roomName = roomName;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, kGamePort);
    } catch (_) {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    }
    port = _server!.port;
    _server!.listen((socket) {
      if (hasClient) {
        socket.destroy(); // room is full
        return;
      }
      final c = JsonLineConnection(socket);
      c.onMessage = (m) => onMessage?.call(m);
      c.onClosed = () {
        if (identical(conn, c)) conn = null;
        onDisconnected?.call();
      };
      conn = c;
      onClientConnected?.call();
    });
    ips = await NetUtil.localIPv4();
    await NetUtil.acquireMulticast();
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udp!.broadcastEnabled = true;
    } catch (_) {
      _udp = null;
    }
    _beaconTimer = Timer.periodic(const Duration(milliseconds: 900), (_) => _beacon());
    _beacon();
  }

  void _beacon() {
    if (hasClient || _udp == null) return;
    final data = utf8.encode(jsonEncode(
        {'magic': kMagic, 'v': kProtocolVersion, 'name': roomName, 'port': port}));
    for (final target in NetUtil.broadcastTargets(ips)) {
      try {
        _udp!.send(data, target, kDiscoveryPort);
      } catch (_) {}
    }
  }

  void send(Map<String, dynamic> msg) => conn?.send(msg);

  void kick() {
    conn?.close();
    conn = null;
  }

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    conn?.close();
    conn = null;
    _udp?.close();
    _udp = null;
    await _server?.close();
    _server = null;
    await NetUtil.releaseMulticast();
  }
}

class LanClient {
  JsonLineConnection? conn;
  void Function(Map<String, dynamic> msg)? onMessage;
  void Function()? onDisconnected;
  String hostIp = '';

  bool get connected => conn != null && !conn!.isClosed;

  Future<void> connect(String ip, int port) async {
    final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
    hostIp = ip;
    final c = JsonLineConnection(socket);
    c.onMessage = (m) => onMessage?.call(m);
    c.onClosed = () {
      if (identical(conn, c)) conn = null;
      onDisconnected?.call();
    };
    conn = c;
  }

  void send(Map<String, dynamic> msg) => conn?.send(msg);

  void close() {
    conn?.close();
    conn = null;
  }
}

class DiscoveredHost {
  final String name;
  final String ip;
  final int port;
  DateTime seen;
  DiscoveredHost(this.name, this.ip, this.port, this.seen);
}

class LanDiscovery {
  RawDatagramSocket? _sock;
  Timer? _prune;
  final Map<String, DiscoveredHost> hosts = {};
  void Function()? onChanged;
  String? error;

  Future<void> start() async {
    await NetUtil.acquireMulticast();
    try {
      _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kDiscoveryPort,
          reuseAddress: true);
      _sock!.broadcastEnabled = true;
      _sock!.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = _sock?.receive();
        if (d == null) return;
        try {
          final m = jsonDecode(utf8.decode(d.data));
          if (m is Map && m['magic'] == kMagic) {
            final port = m['port'] as int;
            final key = '${d.address.address}:$port';
            final isNew = !hosts.containsKey(key);
            hosts[key] = DiscoveredHost(
                (m['name'] as String?) ?? 'Pickle Room', d.address.address, port, DateTime.now());
            if (isNew) onChanged?.call();
          }
        } catch (_) {}
      });
    } catch (e) {
      error = 'Could not listen for rooms: $e';
    }
    _prune = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final before = hosts.length;
      hosts.removeWhere((_, h) => now.difference(h.seen).inMilliseconds > 4000);
      if (hosts.length != before) onChanged?.call();
    });
  }

  Future<void> stop() async {
    _prune?.cancel();
    _sock?.close();
    _sock = null;
    await NetUtil.releaseMulticast();
  }
}
