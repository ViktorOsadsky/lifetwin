import 'package:flutter/foundation.dart';

import 'band_file.dart';

/// Upstream posture classification; no posture is inferred from steps or MVPA.
enum BandPosture { unknown, sitting, standing, moving, lying, sittingOrLying }

/// Independent wake context. Thigh orientation alone does not establish sleep.
enum BandWakeState { unknown, awake, asleep }

/// One classified minute from the activity band. Only these minute aggregates
/// live in phone memory; the transient raw adapter retains no samples.
/// Every number is a sensor estimate.
@immutable
class BandMinute {
  const BandMinute({
    required this.at,
    this.steps = 0,
    this.moderate = false,
    this.worn = true,
    this.posture = BandPosture.unknown,
    this.wakeState = BandWakeState.unknown,
  });

  /// The start of the minute (local time).
  final DateTime at;
  final int steps;

  /// Moderate-to-vigorous movement this minute (approximate cut-points; Hildebrand 2014 values, to be verified).
  final bool moderate;
  final bool worn;
  final BandPosture posture;
  final BandWakeState wakeState;
}

/// A day counts at 10 or more hours worn (Troiano 2008 convention).
const validDayMinutes = 10 * 60;

/// Four or more valid days in the last seven are needed for a weekly number.
const validDaysNeeded = 4;

/// One day of minute records, added up on the phone.
class BandDay {
  BandDay(this.date, this.minutes) : report = null;
  BandDay.fromReport(BandDayReport value)
    : date = DateTime(value.date.year, value.date.month, value.date.day),
      minutes = const [],
      report = value;

  final BandDayReport? report;
  final DateTime date;
  final List<BandMinute> minutes;

  int get steps =>
      report?.steps ?? minutes.fold(0, (a, m) => a + (m.worn ? m.steps : 0));
  int get moderateMinutes =>
      report?.observedMvpaMinutes ??
      minutes.where((m) => m.worn && m.moderate).length;
  int get wornMinutes =>
      report?.wearMinutes ?? minutes.where((m) => m.worn).length;
  bool get isValid => wornMinutes >= validDayMinutes;

  /// Steps by hour (0-23), for the hour chart. Hours with no worn minute are null ("Not worn").
  List<int?> get stepsByHour => report == null
      ? [
          for (var h = 0; h < 24; h++)
            () {
              final inHour = minutes
                  .where((m) => m.at.hour == h && m.worn)
                  .toList();
              return inHour.isEmpty
                  ? null
                  : inHour.fold<int>(0, (a, m) => a + m.steps);
            }(),
        ]
      : [
          for (final hour in report!.hourly)
            if (hour['steps']! > 0 ||
                [
                  'sitting_lying_min',
                  'standing_min',
                  'walking_min',
                  'running_min',
                  'other_min',
                ].any((key) => hour[key]! > 0))
              hour['steps']
            else
              null,
        ];
}

/// The weekly moderate-minutes estimate from the band.
class BandWeek {
  BandWeek(this.days);

  /// The last seven days, oldest first.
  final List<BandDay> days;

  List<BandDay> get validDays => [
    for (final d in days)
      if (d.isValid) d,
  ];
  int get validCount => validDays.length;

  /// Wear can be known while posture/activity records were not saved. Those
  /// minutes cannot be treated as zero movement in a weekly model suggestion.
  bool get hasUnknownActivityCoverage => validDays.any(
    (day) => (day.report?.postures['positions_not_saved'] ?? 0) > 0,
  );

  /// Four valid days plus complete activity classification for the used days.
  bool get hasEstimate =>
      validCount >= validDaysNeeded && !hasUnknownActivityCoverage;

  /// Moderate-to-vigorous minutes on the valid days.
  int get validModerate => validDays.fold(0, (a, d) => a + d.moderateMinutes);

  /// Scaled to 7 days and rounded to 10 ("23 minutes on 4 days" -> 40.2 -> about 40). Null under 4 valid days.
  int? get estimateMinutesPerWeek {
    if (!hasEstimate) return null;
    final scaled = validModerate * 7 / validCount;
    return ((scaled / 10).round()) * 10;
  }

  static BandWeek from(Iterable<BandMinute> minutes, DateTime today) {
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 6));
    final byDay = <int, List<BandMinute>>{for (var i = 0; i < 7; i++) i: []};
    for (final m in minutes) {
      final d = DateTime(m.at.year, m.at.month, m.at.day);
      final i = d.difference(start).inDays;
      if (i >= 0 && i < 7) byDay[i]!.add(m);
    }
    return BandWeek([
      for (var i = 0; i < 7; i++)
        BandDay(start.add(Duration(days: i)), byDay[i]!),
    ]);
  }
}
