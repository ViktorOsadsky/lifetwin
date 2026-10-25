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
  plain('default', 'pose_nohat'),
  calHat('cal_hat', 'pose'),
  stanfordHat('stanford_hat', 'pose_stanford');

  const TwinLook(this.slug, this.poseDir);
  final String slug;

  /// The folder under `assets/twin/{bear,human}/` holding this look's poses.
  final String poseDir;
}

/// Poses. Both twins have every pose, with and without the Cal hat.
enum TwinPose {
  stand('stand', 0.9646, 0.9705, Size(121, 180), Size(95, 180), Size(228, 339), Size(214, 407)),
  wave('wave', 0.965, 0.9712, Size(139, 180), Size(107, 180), Size(264, 343), Size(248, 417)),
  walkSide(
    'walk_side',
    0.9646,
    0.9699,
    Size(129, 180),
    Size(95, 180),
    Size(243, 339),
    Size(211, 399),
  ), // faces right; flip to walk left
  walkFront('walk_front', 0.9656, 0.9709, Size(117, 180), Size(93, 180), Size(226, 349), Size(214, 412)),
  walkBack('walk_back', 0.9641, 0.9715, Size(128, 180), Size(90, 180), Size(238, 334), Size(211, 421)),
  sit('sit', 0.9618, 0.965, Size(150, 180), Size(132, 180), Size(261, 314), Size(252, 343)),
  jump('jump', 0.9648, 0.9694, Size(146, 180), Size(132, 180), Size(276, 341), Size(287, 392)),
  think('think', 0.9644, 0.9687, Size(119, 180), Size(103, 180), Size(223, 337), Size(220, 384)),
  stretch('stretch', 0.9656, 0.9702, Size(144, 180), Size(108, 180), Size(279, 349), Size(242, 403)),
  sleep('sleep', 0.9329, 0.9459, Size(180, 120), Size(180, 104), Size(268, 179), Size(385, 222)),
  eat('eat', 0.9614, 0.9646, Size(134, 180), Size(114, 180), Size(232, 311), Size(214, 339)),
  holdBall('hold_ball', 0.961, 0.9636, Size(137, 180), Size(115, 180), Size(235, 308), Size(211, 330)),
  shrug(
    'shrug',
    0.9637,
    0.9694,
    Size(156, 180),
    Size(107, 180),
    Size(287, 331),
    Size(233, 393),
  ), // fortune still learning / unsupported
  dizzy(
    'dizzy',
    0.9638,
    0.9682,
    Size(137, 180),
    Size(112, 180),
    Size(253, 332),
    Size(235, 377),
  ), // game-health reaction only, never medical
  concerned(
    'concerned',
    0.9655,
    0.9713,
    Size(118, 180),
    Size(93, 180),
    Size(229, 348),
    Size(216, 418),
  ), // emergency: calm, attentive
  sleepy('sleepy', 0.965, 0.9724, Size(124, 180), Size(101, 180), Size(237, 343), Size(244, 435)), // short sleep
  proud(
    'proud',
    0.9641,
    0.9702,
    Size(120, 180),
    Size(96, 180),
    Size(223, 334),
    Size(214, 403),
  ), // cheerful, no specific event
  thinking(
    'thinking',
    0.9659,
    0.972,
    Size(110, 180),
    Size(88, 180),
    Size(215, 352),
    Size(210, 429),
  ), // curious: the model sees something to explore
  listening(
    'listening',
    0.9661,
    0.9722,
    Size(121, 180),
    Size(90, 180),
    Size(238, 354),
    Size(216, 433),
  ); // conversation probes only

  const TwinPose(
    this.slug,
    this.bearFeet,
    this.humanFeet,
    this.bearSize1x,
    this.humanSize1x,
    this.bearNative,
    this.humanNative,
  );
  final String slug;

  /// Feet baselines (`anchor.y` in `assets/twin/manifest.json`), shared by
  /// the hat and no-hat sprite of the pose.
  final double bearFeet;
  final double humanFeet;

  /// 1x sprite size (`size1x` in the manifest), shared by hat and no-hat.
  final Size bearSize1x;
  final Size humanSize1x;

  /// The 2.0x file's pixel size: the art at one scale for every pose of a twin (`manifest_v2.json`
  /// size plus 4 px padding on each side). The 1x file is the same art shrunk to a 180 px long side,
  /// so only these sizes keep the poses in proportion (see `TwinStateSprite`).
  final Size bearNative;
  final Size humanNative;
}

/// True when [pose] has its own art for this twin. Every twin now has every
/// pose in both looks; the room keeps its fallback chain for future looks.
bool twinHasPose(TwinType type, TwinLook look, TwinPose pose) => true;

/// The sprite for a twin: the pose in its hat, or the same pose without one.
/// Every look shares one canvas per pose, so changing hats never moves the body.
String twinAsset(TwinType type, TwinLook look, [TwinPose pose = TwinPose.stand]) =>
    'assets/twin/${type.name}/${look.poseDir}/${pose.slug}.png';

/// The Cal hat on its own (Customize tile; not an overlay for the bear,
/// whose ears go through the hat).
const String calHatAsset = 'assets/twin/accessory/hat/cal.png';

/// The Stanford hat on its own (Customize tile): the Cal hat's model in cardinal and white.
const String stanfordHatAsset = 'assets/twin/accessory/hat/stanford.png';

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
Offset twinBallCenter(TwinType type) => type == TwinType.bear ? const Offset(0.509, 0.606) : const Offset(0.499, 0.672);

/// Radius of that ball, as a fraction of the square sprite box.
double twinBallRadius(TwinType type) => type == TwinType.bear ? 0.105 : 0.084;

/// The vector crystal-ball glow (design/lottie, `ball_glow`: 2.4 s loop).
const String ballGlowLottie = 'assets/lottie/ball_glow.json';

/// Plain words for screen readers.
String twinDescription(TwinType type, TwinLook look) =>
    'Your ${type == TwinType.bear ? 'bear' : 'human'} twin${switch (look) {
      TwinLook.plain => '',
      TwinLook.calHat => ' in the Cal hat',
      TwinLook.stanfordHat => ' in the Stanford hat',
    }}';

/// Each sprite's 1x size (`size1x` in `assets/twin/manifest.json`), for
/// layouts that size the painted content itself (the room). The `base/`
/// files are the standing sprites, kept at their old paths.
final Map<String, Size> twinSpriteSize1x = {
  for (final t in TwinType.values) ...{
    for (final look in TwinLook.values) 'assets/twin/${t.name}/base/${look.slug}.png': _size(t, TwinPose.stand),
    for (final p in TwinPose.values) ...{
      for (final look in TwinLook.values) twinAsset(t, look, p): _size(t, p),
    },
  },
  calHatAsset: const Size(180, 180),
  stanfordHatAsset: const Size(180, 180),
};

Size _size(TwinType t, TwinPose p) => t == TwinType.bear ? p.bearSize1x : p.humanSize1x;

/// Where the feet are across each sprite (`anchor.x` in `assets/twin/manifest.json`), keyed
/// `type/pose`. Shared by the hat and no-hat sprite of a pose.
const Map<String, double> _feetX = {
  'bear/concerned': 0.5152,
  'bear/dizzy': 0.4941,
  'bear/eat': 0.4957,
  'bear/hold_ball': 0.5043,
  'bear/jump': 0.6558,
  'bear/listening': 0.4895,
  'bear/proud': 0.5,
  'bear/shrug': 0.4948,
  'bear/sit': 0.4981,
  'bear/sleep': 0.5522,
  'bear/sleepy': 0.4936,
  'bear/stand': 0.511,
  'bear/stretch': 0.4983,
  'bear/think': 0.5247,
  'bear/thinking': 0.5302,
  'bear/walk_back': 0.5021,
  'bear/walk_front': 0.4159,
  'bear/walk_side': 0.498,
  'bear/wave': 0.5682,
  'human/concerned': 0.514,
  'human/dizzy': 0.5213,
  'human/eat': 0.5,
  'human/hold_ball': 0.5048,
  'human/jump': 0.5227,
  'human/listening': 0.5231,
  'human/proud': 0.4953,
  'human/shrug': 0.4979,
  'human/sit': 0.4981,
  'human/sleep': 0.6221,
  'human/sleepy': 0.4631,
  'human/stand': 0.4836,
  'human/stretch': 0.4958,
  'human/think': 0.475,
  'human/thinking': 0.531,
  'human/walk_back': 0.6066,
  'human/walk_front': 0.5421,
  'human/walk_side': 0.5308,
  'human/wave': 0.5202,
};

/// The feet's x position as a fraction of the sprite's width.
double twinFeetX(TwinType type, TwinPose pose) => _feetX['${type.name}/${pose.slug}'] ?? 0.5;
