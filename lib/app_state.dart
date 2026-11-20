import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/profile.dart';

enum ControlMode { joystick, tilt }

class GameSettings {
  // controls
  ControlMode control;
  bool autoHit; // swing automatically when the ball is in reach
  bool moveAssist; // slide toward the ball when the joystick is idle
  bool showMarker; // show where the incoming ball will land
  bool leftHanded; // joystick on the right, buttons on the left
  bool fixedJoystick; // joystick stays in one place instead of following the thumb
  double joystickSize; // 0.8 .. 1.4
  double buttonSize; // 0.8 .. 1.3
  double sensitivity; // 0..1: how little you push to reach full speed
  bool haptics;
  // gameplay
  double gameSpeed;
  bool showAiThoughts;
  // audio (0..1)
  bool sound;
  bool music;
  bool announcer;
  double masterVolume;
  double musicVolume;
  double sfxVolume;
  double crowdVolume;
  // graphics
  int graphics; // 0 = low, 1 = medium, 2 = high
  bool screenShake;
  bool showFps;

  GameSettings({
    this.control = ControlMode.joystick,
    this.autoHit = true,
    this.moveAssist = true,
    this.showMarker = true,
    this.leftHanded = false,
    this.fixedJoystick = false,
    this.joystickSize = 1.0,
    this.buttonSize = 1.0,
    this.sensitivity = 0.6,
    this.haptics = true,
    this.gameSpeed = 1.0,
    this.showAiThoughts = false,
    this.sound = true,
    this.music = true,
    this.announcer = true,
    this.masterVolume = 0.9,
    this.musicVolume = 0.45,
    this.sfxVolume = 1.0,
    this.crowdVolume = 0.35,
    this.graphics = 1,
    this.screenShake = true,
    this.showFps = false,
  });

  Map<String, dynamic> toJson() => {
        'control': control.index,
        'autoHit': autoHit,
        'moveAssist': moveAssist,
        'showMarker': showMarker,
        'leftHanded': leftHanded,
        'fixedJoystick': fixedJoystick,
        'joystickSize': joystickSize,
        'buttonSize': buttonSize,
        'sensitivity': sensitivity,
        'haptics': haptics,
        'gameSpeed': gameSpeed,
        'showAiThoughts': showAiThoughts,
        'sound': sound,
        'music': music,
        'announcer': announcer,
        'masterVolume': masterVolume,
        'musicVolume': musicVolume,
        'sfxVolume': sfxVolume,
        'crowdVolume': crowdVolume,
        'graphics': graphics,
        'screenShake': screenShake,
        'showFps': showFps,
        'v': 2,
      };

  factory GameSettings.fromJson(Map<String, dynamic> j) {
    double d(String k, double def, double lo, double hi) => ((j[k] as num?)?.toDouble() ?? def).clamp(lo, hi);
    final old = j['v'] == null; // settings saved by v1.0/1.1
    return GameSettings(
      control: ControlMode.values[((j['control'] as int?) ?? 0).clamp(0, 1)],
      autoHit: j['autoHit'] as bool? ?? true,
      moveAssist: j['moveAssist'] as bool? ?? true,
      showMarker: j['showMarker'] as bool? ?? true,
      leftHanded: j['leftHanded'] as bool? ?? false,
      fixedJoystick: j['fixedJoystick'] as bool? ?? false,
      joystickSize: d('joystickSize', 1.0, 0.8, 1.4),
      buttonSize: d('buttonSize', 1.0, 0.8, 1.3),
      sensitivity: d('sensitivity', 0.6, 0.0, 1.0),
      haptics: j['haptics'] as bool? ?? true,
      gameSpeed: old ? 1.0 : d('gameSpeed', 1.0, 0.7, 1.2),
      showAiThoughts: j['showAiThoughts'] as bool? ?? false,
      sound: j['sound'] as bool? ?? true,
      music: j['music'] as bool? ?? true,
      announcer: j['announcer'] as bool? ?? true,
      masterVolume: d('masterVolume', 0.9, 0, 1),
      musicVolume: d('musicVolume', 0.45, 0, 1),
      sfxVolume: d('sfxVolume', 1.0, 0, 1),
      crowdVolume: d('crowdVolume', 0.35, 0, 1),
      graphics: ((j['graphics'] as int?) ?? 1).clamp(0, 2),
      screenShake: j['screenShake'] as bool? ?? true,
      showFps: j['showFps'] as bool? ?? false,
    );
  }
}

/// App-wide state: the player's profile, settings and match record.
class AppState extends ChangeNotifier {
  final SharedPreferences _prefs;
  PlayerProfile profile;
  GameSettings settings;
  Map<String, int> record; // e.g. "ai_hard_win": 3

  AppState._(this._prefs, this.profile, this.settings, this.record);

  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();
    PlayerProfile profile;
    GameSettings settings;
    Map<String, int> record;
    try {
      final p = prefs.getString('profile');
      profile = p == null
          ? PlayerProfile.defaultPlayer()
          : PlayerProfile.fromJson(jsonDecode(p) as Map<String, dynamic>);
    } catch (_) {
      profile = PlayerProfile.defaultPlayer();
    }
    try {
      final s = prefs.getString('settings');
      settings = s == null
          ? GameSettings()
          : GameSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      settings = GameSettings();
    }
    try {
      final r = prefs.getString('record');
      record = r == null
          ? {}
          : (jsonDecode(r) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
    } catch (_) {
      record = {};
    }
    return AppState._(prefs, profile, settings, record);
  }

  bool get isFirstRun => !_prefs.containsKey('profile');

  Future<void> saveProfile(PlayerProfile p) async {
    profile = p;
    notifyListeners();
    await _prefs.setString('profile', jsonEncode(p.toJson()));
  }

  Future<void> saveSettings() async {
    notifyListeners();
    await _prefs.setString('settings', jsonEncode(settings.toJson()));
  }

  /// Adds match XP to the profile. Returns (oldLevel, newLevel).
  Future<(int, int)> addXp(int amount) async {
    final before = profile.level;
    profile.xp += amount;
    await saveProfile(profile);
    return (before, profile.level);
  }

  Future<void> recordResult(String key, bool won) async {
    final k = '${key}_${won ? 'win' : 'loss'}';
    record[k] = (record[k] ?? 0) + 1;
    notifyListeners();
    await _prefs.setString('record', jsonEncode(record));
  }

  int wins(String key) => record['${key}_win'] ?? 0;
  int losses(String key) => record['${key}_loss'] ?? 0;
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
