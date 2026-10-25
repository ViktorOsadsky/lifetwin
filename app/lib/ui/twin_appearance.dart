import 'package:flutter/foundation.dart';

import 'twin_assets.dart';

/// Cosmetic lighting only; never a wellbeing, quiz or prediction signal.
enum TwinRoom { original, morning, twilight }

/// How the twin looks. Cosmetic only: it is saved in the phone's twin preferences,
/// never written to the health profile or sent to the forecast (AGENTS.md: cosmetic
/// settings stay separate from confirmed health inputs).
@immutable
class TwinAppearance {
  const TwinAppearance({
    this.type = TwinType.bear,
    this.look = TwinLook.calHat,
    this.name,
    this.room = TwinRoom.original,
  });

  final TwinType type;
  final TwinLook look;
  final TwinRoom room;

  /// The twin's name for the `{ Name }` banner; null reads "My twin".
  final String? name;

  TwinAppearance copyWith({TwinType? type, TwinLook? look, TwinRoom? room, String? name, bool clearName = false}) =>
      TwinAppearance(
        type: type ?? this.type,
        look: look ?? this.look,
        name: clearName ? null : name ?? this.name,
        room: room ?? this.room,
      );

  String sprite([TwinPose pose = TwinPose.stand]) => twinAsset(type, look, pose);

  @override
  bool operator ==(Object other) =>
      other is TwinAppearance && other.type == type && other.look == look && other.name == name && other.room == room;

  @override
  int get hashCode => Object.hash(type, look, name, room);
}
