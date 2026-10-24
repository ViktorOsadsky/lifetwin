import 'package:flutter/foundation.dart';

import 'twin_assets.dart';

/// How the twin looks. Cosmetic only: it is held in memory, never written to
/// the health profile and never sent to the forecast (AGENTS.md: cosmetic
/// settings stay separate from confirmed health inputs).
@immutable
class TwinAppearance {
  const TwinAppearance({this.type = TwinType.bear, this.look = TwinLook.calHat, this.name});

  final TwinType type;
  final TwinLook look;

  /// The twin's name for the `{ Name }` banner; null reads "My twin".
  final String? name;

  TwinAppearance copyWith({TwinType? type, TwinLook? look}) =>
      TwinAppearance(type: type ?? this.type, look: look ?? this.look, name: name);

  String sprite([TwinPose pose = TwinPose.stand]) => twinAsset(type, look, pose);

  @override
  bool operator ==(Object other) =>
      other is TwinAppearance && other.type == type && other.look == look && other.name == name;

  @override
  int get hashCode => Object.hash(type, look, name);
}
