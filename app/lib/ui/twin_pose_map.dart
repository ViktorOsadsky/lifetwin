import '../twin/twin_state.dart';
import 'twin_assets.dart';

/// The sprite pose for the twin's state (README-model.md, "Twin state"; brief-agentic-v1).
///
/// concerned → concerned, sleepy → sleepy, curious → thinking, cozy → sit, content → stand
/// (wave while answers are still needed), cheerful → jump when the reason is `active`,
/// otherwise proud. The engine's own `pose` is ignored: the sprite set has its own mood poses.
/// `listening` is for the conversation's probes only and is never chosen here.
TwinPose poseForTwinState(TwinState state) => switch (state.mood) {
  TwinMood.concerned => TwinPose.concerned,
  TwinMood.sleepy => TwinPose.sleepy,
  TwinMood.curious => TwinPose.thinking,
  TwinMood.cozy => TwinPose.sit,
  TwinMood.content => state.reason == TwinStateReason.needsInput ? TwinPose.wave : TwinPose.stand,
  TwinMood.cheerful => state.reason == TwinStateReason.active ? TwinPose.jump : TwinPose.proud,
};
