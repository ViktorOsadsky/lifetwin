import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Habitat colours, one palette per vitality tier. Mirrors the Figma
/// **Scene** collection (modes Thriving / Good / Steady / Resting) exactly.
/// Scene colour is its own palette role: it never carries text or actions.
@immutable
class LtScene {
  const LtScene({
    required this.skyTop,
    required this.skyBottom,
    required this.ground,
    required this.foliage,
    required this.foliageDeep,
    required this.light,
    required this.contactShadow,
  });

  /// `scene/sky-top`.
  final Color skyTop;

  /// `scene/sky-bottom`.
  final Color skyBottom;

  /// `scene/ground`, the contact plane.
  final Color ground;

  /// `scene/foliage`, midground bushes.
  final Color foliage;

  /// `scene/foliage-deep`, distant hills and leaf shade.
  final Color foliageDeep;

  /// `scene/light`, the upper-left sun bloom.
  final Color light;

  /// `scene/contact-shadow`, painted at low opacity under every actor.
  final Color contactShadow;

  /// Tier 4.
  static const thriving = LtScene(
    skyTop: Color(0xFF5AA9FF),
    skyBottom: Color(0xFFCFF5E3),
    ground: Color(0xFF8FE0B4),
    foliage: Color(0xFF34D399),
    foliageDeep: Color(0xFF0E9F6E),
    light: Color(0xFFFFD66B),
    contactShadow: Color(0xFF0E9F6E),
  );

  /// Tier 3.
  static const good = LtScene(
    skyTop: Color(0xFF8EC5FF),
    skyBottom: Color(0xFFE3F7EE),
    ground: Color(0xFFBFEBD2),
    foliage: Color(0xFF6FD9A8),
    foliageDeep: Color(0xFF2FA57A),
    light: Color(0xFFFFE7A3),
    contactShadow: Color(0xFF2FA57A),
  );

  /// Tier 2.
  static const steady = LtScene(
    skyTop: Color(0xFFCFE3FF),
    skyBottom: Color(0xFFF4F8FF),
    ground: Color(0xFFDCEDE4),
    foliage: Color(0xFFA9DCC3),
    foliageDeep: Color(0xFF6DB394),
    light: Color(0xFFFFF1C9),
    contactShadow: Color(0xFF6DB394),
  );

  /// Tier 1: calm dusk, never dark or wilted.
  static const resting = LtScene(
    skyTop: Color(0xFFDCDAF5),
    skyBottom: Color(0xFFF4F8FF),
    ground: Color(0xFFE6E8F2),
    foliage: Color(0xFFC3CCE0),
    foliageDeep: Color(0xFF8E9AB8),
    light: Color(0xFFF4EFE0),
    contactShadow: Color(0xFF8E9AB8),
  );

  /// Palette for a vitality tier (1 Resting .. 4 Thriving).
  static LtScene of(int tier) => switch (tier) {
    >= 4 => thriving,
    3 => good,
    2 => steady,
    _ => resting,
  };

  static LtScene lerp(LtScene a, LtScene b, double t) => LtScene(
    skyTop: Color.lerp(a.skyTop, b.skyTop, t)!,
    skyBottom: Color.lerp(a.skyBottom, b.skyBottom, t)!,
    ground: Color.lerp(a.ground, b.ground, t)!,
    foliage: Color.lerp(a.foliage, b.foliage, t)!,
    foliageDeep: Color.lerp(a.foliageDeep, b.foliageDeep, t)!,
    light: Color.lerp(a.light, b.light, t)!,
    contactShadow: Color.lerp(a.contactShadow, b.contactShadow, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is LtScene &&
      other.skyTop == skyTop &&
      other.skyBottom == skyBottom &&
      other.ground == ground &&
      other.foliage == foliage &&
      other.foliageDeep == foliageDeep &&
      other.light == light &&
      other.contactShadow == contactShadow;

  @override
  int get hashCode => Object.hash(
    skyTop,
    skyBottom,
    ground,
    foliage,
    foliageDeep,
    light,
    contactShadow,
  );
}
