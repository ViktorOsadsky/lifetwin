import 'package:flutter/material.dart';

import '../../twin/twin_state.dart';
import '../twin_appearance.dart';
import '../twin_assets.dart';
import '../twin_pose_map.dart';

/// The twin showing its [TwinState]: the sprite from [poseForTwinState], the bear or the
/// human, with or without the hat.
///
/// Every pose of a twin is drawn at one scale (the stand pose is [height] tall) and
/// stands on the same baseline, so changing mood never makes the character grow, shrink
/// or hop. The sizes are the 2.0x files' (`TwinPose.bearNative`), not the 1x ones, which
/// are each shrunk to the same long side.
class TwinStateSprite extends StatelessWidget {
  const TwinStateSprite({super.key, required this.state, required this.appearance, this.height = 196, this.pose});

  final TwinState state;
  final TwinAppearance appearance;

  /// A pose of its own (an idea's), instead of the one the state picks.
  final TwinPose? pose;

  /// How tall the standing pose is, in logical pixels.
  final double height;

  @override
  Widget build(BuildContext context) {
    final pose = this.pose ?? poseForTwinState(state);
    final type = appearance.type;
    Size native(TwinPose p) => type == TwinType.bear ? p.bearNative : p.humanNative;
    final scale = height / native(TwinPose.stand).height;
    final size = native(pose) * scale;
    // The stand pose's feet are the baseline; every pose's feet land on it.
    final baseline = height * twinFeetAnchor(type, appearance.look, TwinPose.stand);
    final feetX = twinFeetX(type, pose);
    final box = height;
    return Semantics(
      image: true,
      label: '${twinDescription(type, appearance.look)}, ${_mood(state.mood)}',
      child: SizedBox(
        width: box,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: box / 2 - feetX * size.width,
              top: baseline - twinFeetAnchor(type, appearance.look, pose) * size.height,
              width: size.width,
              height: size.height,
              child: ExcludeSemantics(
                child: Image.asset(appearance.sprite(pose), fit: BoxFit.fill, gaplessPlayback: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _mood(TwinMood m) => switch (m) {
    TwinMood.concerned => 'looking concerned',
    TwinMood.sleepy => 'looking sleepy',
    TwinMood.curious => 'curious',
    TwinMood.cozy => 'sitting cosily',
    TwinMood.content => 'content',
    TwinMood.cheerful => 'cheerful',
  };
}
