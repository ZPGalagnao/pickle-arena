import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

enum Accessory { none, cap, headband, visor, shades, crown }

enum PaddlePattern { solid, stripes, dots, flame }

extension AccessoryLabel on Accessory {
  String get label => switch (this) {
        Accessory.none => 'None',
        Accessory.cap => 'Cap',
        Accessory.headband => 'Headband',
        Accessory.visor => 'Visor',
        Accessory.shades => 'Shades',
        Accessory.crown => 'Crown',
      };
}

extension PaddlePatternLabel on PaddlePattern {
  String get label => switch (this) {
        PaddlePattern.solid => 'Solid',
        PaddlePattern.stripes => 'Stripes',
        PaddlePattern.dots => 'Dots',
        PaddlePattern.flame => 'Flame',
      };
}

class CharacterLook {
  int jersey;
  int shorts;
  int shoes;
  int paddle;
  int skin;
  int hair;
  int number;
  PaddlePattern pattern;
  Accessory accessory;

  CharacterLook({
    this.jersey = 0xFF2D9CDB,
    this.shorts = 0xFF1B2A4A,
    this.shoes = 0xFFFFFFFF,
    this.paddle = 0xFFD4F33A,
    this.skin = 0xFFE0AC69,
    this.hair = 0xFF2B1B10,
    this.number = 7,
    this.pattern = PaddlePattern.solid,
    this.accessory = Accessory.none,
  });

  CharacterLook copy() => CharacterLook.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'jersey': jersey,
        'shorts': shorts,
        'shoes': shoes,
        'paddle': paddle,
        'skin': skin,
        'hair': hair,
        'number': number,
        'pattern': pattern.index,
        'accessory': accessory.index,
      };

  factory CharacterLook.fromJson(Map<String, dynamic> j) => CharacterLook(
        jersey: j['jersey'] as int? ?? 0xFF2D9CDB,
        shorts: j['shorts'] as int? ?? 0xFF1B2A4A,
        shoes: j['shoes'] as int? ?? 0xFFFFFFFF,
        paddle: j['paddle'] as int? ?? 0xFFD4F33A,
        skin: j['skin'] as int? ?? 0xFFE0AC69,
        hair: j['hair'] as int? ?? 0xFF2B1B10,
        number: j['number'] as int? ?? 7,
        pattern: PaddlePattern.values[
            ((j['pattern'] as int?) ?? 0).clamp(0, PaddlePattern.values.length - 1)],
        accessory: Accessory.values[
            ((j['accessory'] as int?) ?? 0).clamp(0, Accessory.values.length - 1)],
      );
}

/// Character attributes. Each stat is 1..6 and the total is [budget].
class PlayerStats {
  static const int budget = 12;
  static const int minStat = 1;
  static const int maxStat = 6;

  int speed;
  int power;
  int control;

  PlayerStats({this.speed = 4, this.power = 4, this.control = 4});

  int get total => speed + power + control;

  /// Movement speed in m/s.
  double get runSpeed => 3.6 + 0.22 * speed;

  PlayerStats copy() => PlayerStats(speed: speed, power: power, control: control);

  Map<String, dynamic> toJson() =>
      {'speed': speed, 'power': power, 'control': control};

  factory PlayerStats.fromJson(Map<String, dynamic> j) => PlayerStats(
        speed: ((j['speed'] as int?) ?? 4).clamp(minStat, maxStat),
        power: ((j['power'] as int?) ?? 4).clamp(minStat, maxStat),
        control: ((j['control'] as int?) ?? 4).clamp(minStat, maxStat),
      );
}

class PlayerProfile {
  String name;
  CharacterLook look;
  PlayerStats stats;
  Uint8List? face; // small square JPEG of the player's face

  PlayerProfile({
    required this.name,
    CharacterLook? look,
    PlayerStats? stats,
    this.face,
  })  : look = look ?? CharacterLook(),
        stats = stats ?? PlayerStats();

  factory PlayerProfile.defaultPlayer() {
    final r = math.Random();
    return PlayerProfile(
      name: 'Player ${100 + r.nextInt(900)}',
      look: CharacterLook(number: 1 + r.nextInt(99)),
    );
  }

  PlayerProfile copy() => PlayerProfile(
      name: name, look: look.copy(), stats: stats.copy(), face: face);

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Map<String, dynamic> toJson({bool includeFace = true}) => {
        'name': name,
        'look': look.toJson(),
        'stats': stats.toJson(),
        if (includeFace && face != null) 'face': base64Encode(face!),
      };

  factory PlayerProfile.fromJson(Map<String, dynamic> j) {
    Uint8List? face;
    final f = j['face'];
    if (f is String && f.isNotEmpty) {
      try {
        face = base64Decode(f);
      } catch (_) {
        face = null;
      }
    }
    return PlayerProfile(
      name: (j['name'] as String?)?.trim().isNotEmpty == true
          ? (j['name'] as String).trim()
          : 'Player',
      look: CharacterLook.fromJson(
          (j['look'] as Map?)?.cast<String, dynamic>() ?? const {}),
      stats: PlayerStats.fromJson(
          (j['stats'] as Map?)?.cast<String, dynamic>() ?? const {}),
      face: face,
    );
  }
}
