// Sound effects, crowd and music.
//
// Short effects use Android's low-latency SoundPool through audioplayers.
// Each effect owns a few preloaded players used round-robin; a player must be
// stopped before it can replay (SoundPool keeps the finished stream id and a
// plain resume() would play nothing - that was the "no hit sound" bug).
// Every call is fire-and-forget and silently does nothing without audio
// (e.g. in widget tests).
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class _Channel {
  final List<AudioPlayer> players;
  int next = 0;
  _Channel(this.players);
}

enum SoundGroup { sfx, crowd, voice }

class Sound {
  Sound._();
  static final Sound I = Sound._();

  bool sfxOn = true;
  bool musicOn = true;
  bool voiceOn = true; // match announcer
  double master = 0.9, musicVol = 0.45, sfxVol = 1.0, crowdVol = 0.35;

  bool _ready = false;
  final Map<String, _Channel> _channels = {};
  AudioPlayer? _music;
  AudioPlayer? _crowd;
  String? _musicName;
  double _musicTrackGain = 1;
  double _crowdLevel = 0;

  /// effect name -> (file, overlapping copies, group)
  static const Map<String, (String, int, SoundGroup)> effects = {
    'hit_power': ('hit_power.ogg', 4, SoundGroup.sfx),
    'hit_soft': ('hit_soft.ogg', 4, SoundGroup.sfx),
    'hit_high': ('hit_high.ogg', 3, SoundGroup.sfx),
    'serve': ('serve.ogg', 2, SoundGroup.sfx),
    'bounce': ('bounce.ogg', 4, SoundGroup.sfx),
    'net': ('net.wav', 2, SoundGroup.sfx),
    'step1': ('step1.wav', 3, SoundGroup.sfx),
    'step2': ('step2.wav', 3, SoundGroup.sfx),
    'swing': ('swing.ogg', 3, SoundGroup.sfx),
    'ui_click': ('ui_click.wav', 3, SoundGroup.sfx),
    'ready': ('ready.wav', 2, SoundGroup.sfx),
    'point_win': ('point_win.wav', 2, SoundGroup.sfx),
    'point_lose': ('point_lose.wav', 2, SoundGroup.sfx),
    'slowmo': ('slowmo.wav', 2, SoundGroup.sfx),
    'special_fire': ('special_fire.wav', 1, SoundGroup.sfx),
    'special_ice': ('special_ice.wav', 1, SoundGroup.sfx),
    'special_thunder': ('special_thunder.wav', 1, SoundGroup.sfx),
    'special_phantom': ('special_phantom.wav', 1, SoundGroup.sfx),
    'special_tornado': ('special_tornado.wav', 1, SoundGroup.sfx),
    'crowd_cheer': ('crowd_cheer.ogg', 2, SoundGroup.crowd),
    'crowd_big': ('crowd_big.ogg', 1, SoundGroup.crowd),
    'crowd_aww': ('crowd_aww.ogg', 2, SoundGroup.crowd),
    'applause': ('applause.ogg', 1, SoundGroup.crowd),
    'vo_ace': ('vo_ace.ogg', 1, SoundGroup.voice),
    'vo_match_point': ('vo_match_point.ogg', 1, SoundGroup.voice),
    'vo_game_point': ('vo_game_point.ogg', 1, SoundGroup.voice),
    'vo_congrats': ('vo_congrats.ogg', 1, SoundGroup.voice),
    'vo_victory': ('vo_victory.ogg', 1, SoundGroup.voice),
    'vo_game_over': ('vo_game_over.ogg', 1, SoundGroup.voice),
  };

  /// music name -> (file, loudness correction)
  static const Map<String, (String, double)> tracks = {
    'music_menu': ('music_menu.ogg', 0.8),
    'music_game': ('music_game.ogg', 0.75),
  };
  static const String crowdLoop = 'crowd_ambience.ogg';

  void applyVolumes({double? master, double? music, double? sfx, double? crowd}) {
    if (master != null) this.master = master;
    if (music != null) musicVol = music;
    if (sfx != null) sfxVol = sfx;
    if (crowd != null) crowdVol = crowd;
    final m = _music;
    if (_ready && m != null) unawaited(m.setVolume(_musicLevel).catchError((_) {}));
    final c = _crowd;
    if (_ready && c != null && _crowdLevel > 0) unawaited(c.setVolume(_crowdLoopLevel).catchError((_) {}));
  }

  double get _musicLevel => (master * musicVol * _musicTrackGain).clamp(0.0, 1.0);
  double get _crowdLoopLevel => (master * crowdVol * _crowdLevel).clamp(0.0, 1.0);

  Future<void> init() async {
    if (_ready) return;
    try {
      await AudioPlayer.global
          .setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
      for (final e in effects.entries) {
        final (file, copies, _) = e.value;
        final players = <AudioPlayer>[];
        for (var i = 0; i < copies; i++) {
          final p = AudioPlayer();
          await p.setPlayerMode(PlayerMode.lowLatency);
          await p.setReleaseMode(ReleaseMode.stop);
          await p.setSource(AssetSource('audio/$file'));
          players.add(p);
        }
        _channels[e.key] = _Channel(players);
      }
      _music = AudioPlayer();
      await _music!.setReleaseMode(ReleaseMode.loop);
      _crowd = AudioPlayer();
      await _crowd!.setReleaseMode(ReleaseMode.loop);
      _ready = true;
      if (_musicName != null) unawaited(music(_musicName, force: true));
    } catch (_) {
      _ready = false;
    }
  }

  /// Plays a short effect. [volume] is relative (0..1) and is multiplied by
  /// the master and group volumes from Settings.
  void play(String name, {double volume = 1}) {
    if (!_ready || !sfxOn) return;
    final ch = _channels[name];
    final info = effects[name];
    if (ch == null || info == null) return;
    if (info.$3 == SoundGroup.voice && !voiceOn) return;
    final group = info.$3 == SoundGroup.crowd ? crowdVol : sfxVol;
    final v = (volume * master * group).clamp(0.0, 1.0);
    if (v <= 0.01) return;
    final p = ch.players[ch.next];
    ch.next = (ch.next + 1) % ch.players.length;
    unawaited(() async {
      try {
        await p.stop();
        await p.setVolume(v);
        await p.resume();
      } catch (_) {}
    }());
  }

  double _lastVoice = -10;

  /// Announcer line; skipped if another one played in the last [gap] seconds.
  void voice(String name, {double volume = 0.9, double gap = 1.6}) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    if (now - _lastVoice < gap) return;
    _lastVoice = now;
    play(name, volume: volume);
  }

  /// Switch the background music loop ('music_menu', 'music_game' or null).
  Future<void> music(String? name, {bool force = false}) async {
    if (!force && name == _musicName) return;
    _musicName = name;
    final p = _music;
    if (!_ready || p == null) return;
    try {
      await p.stop();
      final track = tracks[name];
      if (track != null && musicOn) {
        _musicTrackGain = track.$2;
        await p.play(AssetSource('audio/${track.$1}'), volume: _musicLevel);
      }
    } catch (_) {}
  }

  Future<void> setMusicOn(bool on) async {
    musicOn = on;
    await music(_musicName, force: true);
  }

  /// Background crowd murmur during matches. [level] 0..1 (0 stops it).
  Future<void> crowd(double level) async {
    final p = _crowd;
    if (!_ready || p == null) return;
    try {
      if (level <= 0 || !sfxOn) {
        if (_crowdLevel > 0) await p.stop();
        _crowdLevel = 0;
      } else if (_crowdLevel == 0) {
        _crowdLevel = level;
        await p.play(AssetSource('audio/$crowdLoop'), volume: _crowdLoopLevel);
      } else if ((level - _crowdLevel).abs() > 0.05) {
        _crowdLevel = level;
        await p.setVolume(_crowdLoopLevel);
      }
    } catch (_) {}
  }
}
