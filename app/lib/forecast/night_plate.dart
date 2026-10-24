import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart';

/// The shared night plate for every fortune screen, with the chosen twin
/// (bear or human) standing on its open floor: `hold_ball` with a soft glow
/// for the ceremony and result, `shrug` for still learning and unsupported.
class NightTwinPlate extends StatelessWidget {
  const NightTwinPlate({
    super.key,
    required this.appearance,
    required this.pose,
    this.glow = 0,
    this.feetAt = const Offset(0.5, 0.9),
    this.twinHeight = 0.62,
  });

  final TwinAppearance appearance;
  final TwinPose pose;

  /// Ball glow strength, 0..1 (only drawn for `hold_ball`).
  final double glow;

  /// Where the feet land in the window (fractions of the box).
  final Offset feetAt;

  /// Twin height as a fraction of the window height (capped by its width).
  final double twinHeight;

  @override
  Widget build(BuildContext context) {
    return PlateScene(
      asset: ScenePlate.night.asset,
      background: LtColors.night,
      focus: ScenePlate.nightFloor,
      focusTarget: feetAt,
      semanticLabel: 'A calm night sky over a misty hill',
      twinBuilder: (feet, scale, box) => plantTwin(
        // The twin stands where it was asked to, even if the paint is panned.
        Offset(box.width * feetAt.dx, box.height * feetAt.dy),
        TwinSprite(
          appearance: appearance,
          pose: pose,
          glow: glow,
          height: math.max(60.0, math.min(box.height * twinHeight, box.width * 0.8)),
        ),
      ),
    );
  }
}
