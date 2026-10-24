import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/activity/activity_models.dart';

/// Real measurements the user explicitly confirmed. This is the only state
/// that may change the baseline. It is deliberately separate from the
/// workout log, experiments, cosmetics and quiz/game health: logging
/// workouts or importing from Apple Health does NOT change it by itself.
@immutable
class ConfirmedBaseline {
  const ConfirmedBaseline({this.activityMinutesPerWeek, this.activitySource});

  final int? activityMinutesPerWeek;
  final ActivitySource? activitySource;

  bool get hasActivity => activityMinutesPerWeek != null;
}

class ConfirmedBaselineNotifier extends Notifier<ConfirmedBaseline> {
  @override
  ConfirmedBaseline build() => const ConfirmedBaseline();

  void confirmActivity({
    required int minutesPerWeek,
    required ActivitySource source,
  }) {
    state = ConfirmedBaseline(
      activityMinutesPerWeek: minutesPerWeek,
      activitySource: source,
    );
  }
}

final confirmedBaselineProvider =
    NotifierProvider<ConfirmedBaselineNotifier, ConfirmedBaseline>(
      ConfirmedBaselineNotifier.new,
    );
