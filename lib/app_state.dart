import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/profile.dart';

enum ControlMode { joystick, tilt }

class GameSettings {
  ControlMode control;
  bool autoHit; // swing automatically when the ball is in reach
  bool showMarker; // show where the incoming ball will land
  double gameSpeed;
  bool haptics;
  bool leftHanded; // joystick on the right, buttons on the left
  bool showAiThoughts;

  GameSettings({
    this.control = ControlMode.joystick,
    this.autoHit = true,
    this.showMarker = true,
    this.gameSpeed = 0.9,
    this.haptics = true,
    this.leftHanded = false,
    this.showAiThoughts = false,
  });

  Map<String, dynamic> toJson() => {
        'control': control.index,
        'autoHit': autoHit,
        'showMarker': showMarker,
        'gameSpeed': gameSpeed,
        'haptics': haptics,
        'leftHanded': leftHanded,
        'showAiThoughts': showAiThoughts,
      };

  factory GameSettings.fromJson(Map<String, dynamic> j) => GameSettings(
        control: ControlMode.values[((j['control'] as int?) ?? 0).clamp(0, 1)],
        autoHit: j['autoHit'] as bool? ?? true,
        showMarker: j['showMarker'] as bool? ?? true,
        gameSpeed: (j['gameSpeed'] as num?)?.toDouble() ?? 0.9,
        haptics: j['haptics'] as bool? ?? true,
        leftHanded: j['leftHanded'] as bool? ?? false,
        showAiThoughts: j['showAiThoughts'] as bool? ?? false,
      );
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
