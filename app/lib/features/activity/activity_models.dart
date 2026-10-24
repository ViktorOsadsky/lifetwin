import 'package:flutter/foundation.dart';

import '../../widgets/lt_icon.dart';

/// Where an activity figure came from. Held in app state only; no contract
/// field exists for it yet.
enum ActivitySource {
  manual('Manual'),
  appleHealth('Apple Health');

  const ActivitySource(this.label);
  final String label;

  LtIcons get icon => switch (this) {
    ActivitySource.manual => LtIcons.plus,
    ActivitySource.appleHealth => LtIcons.heart,
  };
}

enum WorkoutType {
  walk('Walk', LtIcons.walk),
  run('Run', LtIcons.run),
  cycle('Cycle', LtIcons.cycle),
  swim('Swim', LtIcons.swim),
  strength('Strength', LtIcons.strength),
  other('Other', LtIcons.other);

  const WorkoutType(this.label, this.icon);
  final String label;
  final LtIcons icon;
}

enum Intensity {
  light('Light'),
  moderate('Moderate'),
  vigorous('Vigorous');

  const Intensity(this.label);
  final String label;
}

@immutable
class Workout {
  const Workout({
    required this.id,
    required this.type,
    required this.minutes,
    required this.intensity,
    required this.date,
  });

  final int id;
  final WorkoutType type;
  final int minutes;
  final Intensity intensity;

  /// Calendar day of the workout (time of day is ignored).
  final DateTime date;
}
