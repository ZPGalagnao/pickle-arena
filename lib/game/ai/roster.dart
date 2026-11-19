import '../../models/profile.dart';
import 'ai_controller.dart';

class AiOpponent {
  final String tagline;
  final AiDifficulty difficulty;
  final AiStyle style;
  final PlayerProfile profile;
  final String styleName;

  const AiOpponent(this.profile, this.difficulty, this.style, this.tagline, this.styleName);
}

final List<AiOpponent> aiRoster = [
  AiOpponent(
    PlayerProfile(
      name: 'Rookie Rio',
      look: CharacterLook(
          jersey: 0xFFFF7A3D, shorts: 0xFF37474F, shoes: 0xFFFFFFFF, paddle: 0xFF2D9CDB,
          skin: 0xFFE0AC69, hair: 0xFF1B1B1B, number: 3, accessory: Accessory.cap),
      stats: PlayerStats(speed: 4, power: 4, control: 4),
      special: SpecialSkill.tornadoLob,
    ),
    AiDifficulty.easy,
    AiStyle.balanced,
    'Just started playing last week. Friendly!',
    'All-rounder',
  ),
  AiOpponent(
    PlayerProfile(
      name: 'Coach Lia',
      look: CharacterLook(
          jersey: 0xFF00BFA5, shorts: 0xFFFFFFFF, shoes: 0xFF111111, paddle: 0xFFFF4D8D,
          skin: 0xFFF1C27D, hair: 0xFF4E342E, number: 12, pattern: PaddlePattern.dots,
          accessory: Accessory.visor),
      stats: PlayerStats(speed: 3, power: 3, control: 6),
      special: SpecialSkill.phantomDrop,
    ),
    AiDifficulty.medium,
    AiStyle(0.8, 1.4, 1.0),
    'Patient and precise. Loves the soft game.',
    'Dinker',
  ),
  AiOpponent(
    PlayerProfile(
      name: 'Banger Bruno',
      look: CharacterLook(
          jersey: 0xFFE53935, shorts: 0xFF111111, shoes: 0xFFFFC400, paddle: 0xFF111111,
          skin: 0xFFC68642, hair: 0xFF1B1B1B, number: 99, pattern: PaddlePattern.flame,
          accessory: Accessory.headband),
      stats: PlayerStats(speed: 3, power: 6, control: 3),
      special: SpecialSkill.fireSmash,
    ),
    AiDifficulty.hard,
    AiStyle(1.6, 0.7, 0.6),
    'Hits every ball as hard as possible.',
    'Banger',
  ),
  AiOpponent(
    PlayerProfile(
      name: 'Dink Queen Maya',
      look: CharacterLook(
          jersey: 0xFF9B6BFF, shorts: 0xFF1B2A4A, shoes: 0xFFFFFFFF, paddle: 0xFFD4F33A,
          skin: 0xFF8D5524, hair: 0xFF1B1B1B, number: 7, pattern: PaddlePattern.stripes,
          accessory: Accessory.crown),
      stats: PlayerStats(speed: 5, power: 2, control: 5),
      special: SpecialSkill.iceFreeze,
    ),
    AiDifficulty.hard,
    AiStyle(0.7, 1.7, 0.9),
    'Rules the kitchen. Good luck out-dinking her.',
    'Kitchen master',
  ),
  AiOpponent(
    PlayerProfile(
      name: 'Pro Atlas',
      look: CharacterLook(
          jersey: 0xFF111111, shorts: 0xFF111111, shoes: 0xFFFFC400, paddle: 0xFFFFC400,
          skin: 0xFFFFE0BD, hair: 0xFFE6C27A, number: 1, pattern: PaddlePattern.stripes,
          accessory: Accessory.shades),
      stats: PlayerStats(speed: 5, power: 4, control: 3),
      special: SpecialSkill.thunderCurve,
    ),
    AiDifficulty.pro,
    AiStyle.balanced,
    'Tour champion. Uses the full PickleBrain.',
    'Complete player',
  ),
];

/// In doubles, each opponent brings a teammate of a similar level.
AiOpponent doublesPartnerOf(int index) => aiRoster[const [1, 0, 3, 2, 3][index]];
