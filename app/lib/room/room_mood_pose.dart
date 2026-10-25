import 'dart:ui' show Size;

import '../twin/twin_state.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/twin_pose_map.dart';
import 'room_sim.dart';

/// While the twin is just standing around, it shows the character's state (concerned, sleepy,
/// thinking, sitting, proud, waving or jumping); an activity or a walk keeps its own pose.
///
/// Returns the sprite pose, the room pose whose height and shadow it shares, and a correction for mood
/// poses drawn taller or shorter than the standing one (from the art's real sizes).
(TwinPose, RoomPose, double) applyMoodPose(TwinAppearance look, TwinPose pose, RoomPose shape, TwinState? mood) {
  if (mood == null || shape != RoomPose.stand) return (pose, shape, 1.0);
  final p = poseForTwinState(mood);
  if (!twinHasPose(look.type, look.look, p)) return (pose, shape, 1.0);
  Size native(TwinPose q) => look.type == TwinType.bear ? q.bearNative : q.humanNative;
  return switch (p) {
    TwinPose.wave => (p, RoomPose.wave, 1.0),
    TwinPose.jump => (p, RoomPose.jump, 1.0),
    TwinPose.sit => (p, RoomPose.sit, 1.0),
    TwinPose.stand => (p, RoomPose.stand, 1.0),
    _ => (p, RoomPose.stand, native(p).height / native(TwinPose.stand).height),
  };
}
