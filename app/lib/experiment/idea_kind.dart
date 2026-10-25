import 'package:flutter/material.dart';

import '../ui/twin_assets.dart';

/// Mochi's pose and props for an idea's `kind` (design I2N-1). The kind picks the picture only; it
/// never changes the words or the effect. A kind the app does not know stands (and is logged).
TwinPose ideaPose(String? kind) => switch (kind) {
  'walk' || 'social' => TwinPose.walkSide,
  'dance' => TwinPose.jump,
  'stand' => TwinPose.stand,
  'stretch' => TwinPose.stretch,
  'sleep' => TwinPose.sleepy,
  'eat' => TwinPose.eat,
  'breath' => TwinPose.sit,
  'craving' => TwinPose.think,
  _ => _unknown(kind),
};

TwinPose _unknown(String? kind) {
  if (kind != null) debugPrint('Unknown idea kind "$kind": Mochi stands.');
  return TwinPose.stand;
}

/// Up to two interface icons that sit around Mochi (never new character art).
List<IconData> ideaProps(String? kind) => switch (kind) {
  'walk' => const [Icons.wb_sunny_outlined, Icons.eco_outlined],
  'dance' => const [Icons.music_note_rounded, Icons.coffee_outlined],
  'stand' => const [Icons.tv_rounded],
  'stretch' => const [Icons.wb_sunny_outlined],
  'sleep' => const [Icons.nightlight_outlined],
  'eat' => const [Icons.restaurant_rounded],
  'social' => const [Icons.phone_outlined, Icons.favorite_border_rounded],
  'breath' => const [Icons.air_rounded],
  'craving' => const [Icons.schedule_rounded],
  _ => const [],
};
