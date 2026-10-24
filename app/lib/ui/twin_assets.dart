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

import 'dart:ui' show Offset;

enum TwinType { bear, human }

/// The twin's signature look. `plain` is Figma's `look=default`.
enum TwinLook {
  plain('default'),
  calHat('cal_hat');

  const TwinLook(this.slug);
  final String slug;
}

/// Poses. All pose art wears the Cal hat. The bear has every pose; the
/// human has [humanPoses]. See [twinAsset] for the fallback.
enum TwinPose {
  stand('stand', 0.956, 0.954),
  wave('wave', 0.96, 0.961),
  walkSide('walk_side', 0.963, 0.963), // faces right; flip horizontally to walk left
  walkFront('walk_front', 0.966),
  walkBack('walk_back', 0.967),
  sit('sit', 0.959, 0.961),
  jump('jump', 0.963, 0.967),
  think('think', 0.965),
  stretch('stretch', 0.967),
  sleep('sleep', 0.94),
  eat('eat', 0.956),
  holdBall('hold_ball', 0.964, 0.961),
  shrug('shrug', 0.968, 0.967), // fortune still learning / unsupported
  dizzy('dizzy', 0.964); // game-health reaction only, never medical

  const TwinPose(this.slug, this.bearFeet, [this.humanFeet]);
  final String slug;

  /// Feet baselines (`anchor.y` in `assets/twin/manifest.json`).
  final double bearFeet;
  final double? humanFeet;
}

/// Poses that exist for the human (in the Cal hat).
const Set<TwinPose> humanPoses = {
  TwinPose.holdBall,
  TwinPose.shrug,
  TwinPose.wave,
  TwinPose.walkSide,
  TwinPose.sit,
  TwinPose.jump,
};

/// True when [pose] has its own art for this twin (otherwise [twinAsset]
/// falls back to the standing sprite).
bool twinHasPose(TwinType type, TwinLook look, TwinPose pose) {
  if (pose == TwinPose.stand) return true;
  if (look != TwinLook.calHat) return false; // pose art always wears the Cal hat
  return type == TwinType.bear || humanPoses.contains(pose);
}

/// The sprite for a twin. A pose the twin lacks (any pose without the Cal
/// hat, or a bear-only pose for the human) falls back to the twin's own
/// standing sprite, so the chosen look is never swapped for another.
String twinAsset(TwinType type, TwinLook look,
    [TwinPose pose = TwinPose.stand]) {
  if (look == TwinLook.calHat && twinHasPose(type, look, pose)) {
    if (type == TwinType.bear) return 'assets/twin/bear/pose/${pose.slug}.png';
    if (pose != TwinPose.stand) return 'assets/twin/human/pose/${pose.slug}.png';
  }
  return 'assets/twin/${type.name}/base/${look.slug}.png';
}

/// The Cal hat on its own (Customize tile; not an overlay for the bear,
/// whose ears go through the hat).
const String calHatAsset = 'assets/twin/accessory/hat/cal.png';

/// Calm scene plates (390 × 585 at 1x). The fortune screens composite the
/// twin on [night]; the older baked-bear plates (`fortune_reveal`,
/// `fortune_learning`) stay in assets/scene only for the static mockups.
enum ScenePlate {
  room('room'),
  customize('customize'),
  night('night');

  const ScenePlate(this.slug);
  final String slug;

  String get asset => 'assets/scene/$slug.jpg';

  /// The open floor of the night plate, where the twin stands.
  static const Offset nightFloor = Offset(0.5, 0.86);
}

/// Feet baseline as a fraction of the sprite's height (`anchor.y` in
/// `assets/twin/manifest.json`). Swapping sprites never moves the feet.
double twinFeetAnchor(TwinType type, TwinLook look, [TwinPose pose = TwinPose.stand]) {
  if (!twinHasPose(type, look, pose) || pose == TwinPose.stand) {
    if (type == TwinType.human) return look == TwinLook.calHat ? 0.954 : 0.926;
    return 0.956;
  }
  return type == TwinType.human ? pose.humanFeet! : pose.bearFeet;
}

/// Centre of the ball in a [TwinPose.holdBall] sprite, as fractions of the
/// square sprite box (the art is bottom-centred in it), for the glow.
Offset twinBallCenter(TwinType type) =>
    type == TwinType.bear ? const Offset(0.436, 0.53) : const Offset(0.42, 0.53);

/// Plain words for screen readers.
String twinDescription(TwinType type, TwinLook look) =>
    'Your ${type == TwinType.bear ? 'bear' : 'human'} twin${look == TwinLook.calHat ? ' in the Cal hat' : ''}';
