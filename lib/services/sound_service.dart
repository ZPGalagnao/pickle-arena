// Sound effects, crowd and music. All files in assets/audio are generated
// by tools/make_sounds.py. Every call is fire-and-forget and silently does
// nothing if audio isn't available (e.g. in widget tests).
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class Sound {
  Sound._();
  static final Sound I = Sound._();

  bool sfxOn = true;
  bool musicOn = true;
  bool _ready = false;
  final Map<String, AudioPool> _pools = {};
  AudioPlayer? _music;
  AudioPlayer? _crowd;
  String? _musicName;
  double _crowdVolume = 0;

  /// Short sounds kept preloaded for instant playback (name -> max overlap).
  static const _sfx = {
    'hit_power': 3, 'hit_soft': 3, 'hit_high': 2, 'serve': 2, 'bounce': 3, 'net': 1,
    'step1': 3, 'step2': 3, 'swing': 3, 'ui_click': 2, 'ready': 2, 'point_win': 1,
    'point_lose': 1, 'slowmo': 1, 'special_fire': 1, 'special_ice': 1, 'special_thunder': 1,
    'special_phantom': 1, 'special_tornado': 1, 'crowd_cheer': 2, 'crowd_aww': 1, 'applause': 1,
    'win_fanfare': 1, 'lose': 1,
  };

  Future<void> init() async {
    if (_ready) return;
    try {
      await AudioPlayer.global
          .setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
      for (final e in _sfx.entries) {
        _pools[e.key] = await AudioPool.createFromAsset(
            path: 'audio/${e.key}.wav', maxPlayers: e.value, playerMode: PlayerMode.lowLatency);
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

  void play(String name, {double volume = 1}) {
    if (!_ready || !sfxOn) return;
    final pool = _pools[name];
    if (pool == null) return;
    unawaited(pool.start(volume: volume.clamp(0.0, 1.0)).then((_) {}, onError: (_) {}));
  }

  /// Switch the background music loop ('music_menu', 'music_game' or null).
  Future<void> music(String? name, {double volume = 0.42, bool force = false}) async {
    if (!force && name == _musicName) return;
    _musicName = name;
    final p = _music;
    if (!_ready || p == null) return;
    try {
      await p.stop();
      if (name != null && musicOn) {
        await p.play(AssetSource('audio/$name.wav'), volume: volume);
      }
    } catch (_) {}
  }

  Future<void> setMusicOn(bool on) async {
    musicOn = on;
    await music(_musicName, force: true);
  }

  /// Background crowd murmur during matches; [volume] 0 stops it.
  Future<void> crowd(double volume) async {
    final p = _crowd;
    if (!_ready || p == null) return;
    try {
      if (volume <= 0 || !sfxOn) {
        _crowdVolume = 0;
        await p.stop();
      } else if (_crowdVolume == 0) {
        _crowdVolume = volume;
        await p.play(AssetSource('audio/crowd_ambience.wav'), volume: volume);
      } else if ((volume - _crowdVolume).abs() > 0.05) {
        _crowdVolume = volume;
        await p.setVolume(volume);
      }
    } catch (_) {}
  }
}
