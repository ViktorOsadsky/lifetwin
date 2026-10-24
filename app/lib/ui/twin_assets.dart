/// Asset paths for the LifeTwin twin sprites and scene plates.
///
/// Names mirror the Figma page "Twin · Assets" one to one: the Figma
/// component `twin/bear/pose/walk_side` is the file
/// `app/assets/twin/bear/pose/walk_side.png`, loaded as
/// `assets/twin/bear/pose/walk_side.png`. Flutter picks the `2.0x/` and
/// `3.0x/` variants automatically. Anchors and suggested uses live in
/// `assets/twin/manifest.json`; the naming rule is in
/// `docs/design/painted-card-direction.md`.
library;

enum TwinType { bear, human }

/// The twin's signature look. `plain` is Figma's `look=default`.
enum TwinLook {
  plain('default'),
  calHat('cal_hat');

  const TwinLook(this.slug);
  final String slug;
}

/// Bear poses. They exist only for the bear in the Cal hat.
enum TwinPose {
  stand('stand'),
  wave('wave'),
  walkSide('walk_side'), // faces right; flip horizontally to walk left
  walkFront('walk_front'),
  walkBack('walk_back'),
  sit('sit'),
  jump('jump'),
  think('think'),
  stretch('stretch'),
  sleep('sleep'),
  eat('eat'),
  holdBall('hold_ball'),
  dizzy('dizzy'); // game-health reaction only, never medical

  const TwinPose(this.slug);
  final String slug;
}

/// The sprite for a twin. Poses other than [TwinPose.stand] exist only for
/// [TwinType.bear] with [TwinLook.calHat]; every other combination falls
/// back to its standing base sprite.
String twinAsset(TwinType type, TwinLook look,
    [TwinPose pose = TwinPose.stand]) {
  if (type == TwinType.bear && look == TwinLook.calHat) {
    return 'assets/twin/bear/pose/${pose.slug}.png';
  }
  return 'assets/twin/${type.name}/base/${look.slug}.png';
}

/// The Cal hat on its own (Customize tile; not an overlay for the bear,
/// whose ears go through the hat).
const String calHatAsset = 'assets/twin/accessory/hat/cal.png';

/// Calm scene plates (390 × 585 at 1x).
enum ScenePlate {
  room('room'),
  customize('customize'),
  fortuneReveal('fortune_reveal'),
  fortuneLearning('fortune_learning');

  const ScenePlate(this.slug);
  final String slug;

  String get asset => 'assets/scene/$slug.jpg';
}
