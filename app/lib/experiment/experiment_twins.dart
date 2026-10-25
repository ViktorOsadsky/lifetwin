import '../twin/twin_state.dart';
import '../ui/twin_assets.dart';
import 'result_display.dart';

/// Today's twin is the repository's state; the what-if twin is `cheerful` (the proud sprite)
/// when the what-if shows a gain, and just like today's otherwise.
TwinState whatIfTwinState(TwinState today, ResultDisplay d) {
  final gain = d.kind == ResultKind.big || d.kind == ResultKind.tiny;
  return gain
      ? const TwinState(mood: TwinMood.cheerful, pose: TwinPose.stand, reason: TwinStateReason.feelingGood)
      : today;
}

/// "Mochi is curious": the state for the screens that ask for answers.
const curiousTwin = TwinState(mood: TwinMood.curious, pose: TwinPose.think, reason: TwinStateReason.exploring);

/// A calm, waving twin for the screens with nothing to explore.
const steadyTwin = TwinState(mood: TwinMood.content, pose: TwinPose.stand, reason: TwinStateReason.steady);
