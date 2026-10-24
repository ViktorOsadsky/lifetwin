/// Asset paths for the LifeTwin twin sprites and scene plates.
///
/// The Cal-hat poses live in `assets/twin/{bear,human}/pose/` (the names
/// mirror the Figma page "Twin · Assets": the component
/// `twin/bear/pose/walk_side` is `assets/twin/bear/pose/walk_side.png`) and
/// the same poses without the hat in `assets/twin/{bear,human}/pose_nohat/`.
/// Flutter picks the `2.0x/` and `3.0x/` variants automatically. Anchors
/// live in `assets/twin/manifest.json`; the naming rule is in
/// `docs/design/painted-card-direction.md`.
///
/// The art is the v2 sprite set: each hat pose is its no-hat pose with one
/// canonical Cal hat composited on, and the two share one canvas (same size,
/// same feet anchor), so taking the hat off never moves or rescales the body.
library;

import 'dart:ui' show Offset, Size;

enum TwinType { bear, human }

/// The twin's signature look. `plain` is Figma's `look=default`.
enum TwinLook {
  plain('default'),
  calHat('cal_hat');

  const TwinLook(this.slug);
  final String slug;
}

/// Poses. Both twins have every pose, with and without the Cal hat.
enum TwinPose {
  stand('stand', 0.9646, 0.9639, Size(121, 180), Size(97, 180)),
  wave('wave', 0.9641, 0.9661, Size(132, 180), Size(111, 180)),
  walkSide('walk_side', 0.9648, 0.9652, Size(122, 180), Size(96, 180)), // faces right; flip to walk left
  walkFront('walk_front', 0.9656, 0.9644, Size(119, 180), Size(96, 180)),
  walkBack('walk_back', 0.9641, 0.965, Size(128, 180), Size(92, 180)),
  sit('sit', 0.9648, 0.9653, Size(149, 180), Size(131, 180)),
  jump('jump', 0.9661, 0.9648, Size(138, 180), Size(132, 180)),
  think('think', 0.9644, 0.9639, Size(119, 180), Size(105, 180)),
  stretch('stretch', 0.9664, 0.9657, Size(151, 180), Size(108, 180)),
  sleep('sleep', 0.9641, 0.9668, Size(180, 118), Size(180, 101)),
  eat('eat', 0.9644, 0.9649, Size(134, 180), Size(113, 180)),
  holdBall('hold_ball', 0.964, 0.964, Size(137, 180), Size(114, 180)),
  shrug('shrug', 0.9637, 0.9649, Size(156, 180), Size(107, 180)), // fortune still learning / unsupported
  dizzy('dizzy', 0.9663, 0.9656, Size(144, 180), Size(113, 180)); // game-health reaction only, never medical

  const TwinPose(this.slug, this.bearFeet, this.humanFeet, this.bearSize1x, this.humanSize1x);
  final String slug;

  /// Feet baselines (`anchor.y` in `assets/twin/manifest.json`), shared by
  /// the hat and no-hat sprite of the pose.
  final double bearFeet;
  final double humanFeet;

  /// 1x sprite size (`size1x` in the manifest), shared by hat and no-hat.
  final Size bearSize1x;
  final Size humanSize1x;
}

/// True when [pose] has its own art for this twin. Every twin now has every
/// pose in both looks; the room keeps its fallback chain for future looks.
bool twinHasPose(TwinType type, TwinLook look, TwinPose pose) => true;

/// The sprite for a twin: the Cal-hat pose, or the same pose without the hat.
String twinAsset(TwinType type, TwinLook look, [TwinPose pose = TwinPose.stand]) =>
    'assets/twin/${type.name}/${look == TwinLook.calHat ? 'pose' : 'pose_nohat'}/${pose.slug}.png';

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
double twinFeetAnchor(TwinType type, TwinLook look, [TwinPose pose = TwinPose.stand]) =>
    type == TwinType.human ? pose.humanFeet : pose.bearFeet;

/// Centre of the ball in a [TwinPose.holdBall] sprite, as fractions of the
/// square sprite box (the art is bottom-centred in it), for the glow.
Offset twinBallCenter(TwinType type) =>
    type == TwinType.bear ? const Offset(0.509, 0.606) : const Offset(0.499, 0.672);

/// Radius of that ball, as a fraction of the square sprite box.
double twinBallRadius(TwinType type) => type == TwinType.bear ? 0.105 : 0.084;

/// The vector crystal-ball glow (design/lottie, `ball_glow`: 2.4 s loop).
const String ballGlowLottie = 'assets/lottie/ball_glow.json';

/// Plain words for screen readers.
String twinDescription(TwinType type, TwinLook look) =>
    'Your ${type == TwinType.bear ? 'bear' : 'human'} twin${look == TwinLook.calHat ? ' in the Cal hat' : ''}';

/// Each sprite's 1x size (`size1x` in `assets/twin/manifest.json`), for
/// layouts that size the painted content itself (the room). The `base/`
/// files are the standing sprites, kept at their old paths.
final Map<String, Size> twinSpriteSize1x = {
  for (final t in TwinType.values) ...{
    for (final look in TwinLook.values)
      'assets/twin/${t.name}/base/${look.slug}.png': _size(t, TwinPose.stand),
    for (final p in TwinPose.values) ...{
      'assets/twin/${t.name}/pose/${p.slug}.png': _size(t, p),
      'assets/twin/${t.name}/pose_nohat/${p.slug}.png': _size(t, p),
    },
  },
  calHatAsset: const Size(180, 180),
};

Size _size(TwinType t, TwinPose p) => t == TwinType.bear ? p.bearSize1x : p.humanSize1x;
