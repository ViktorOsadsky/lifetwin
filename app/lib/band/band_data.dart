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

extension BandDayDetail on BandDay {
  static bool _sits(BandPosture p) =>
      p == BandPosture.sitting ||
      p == BandPosture.lying ||
      p == BandPosture.sittingOrLying;

  bool get _hasPostures =>
      report != null || minutes.any((m) => m.worn && m.posture != BandPosture.unknown);

  /// Sitting or lying minutes in the day (the sensor does not tell them apart). Null when unknown.
  int? get sittingMinutes {
    if (report case final r?) return r.observedSittingOrLyingMinutes;
    if (!_hasPostures) return null;
    return minutes.where((m) => m.worn && _sits(m.posture)).length;
  }

  /// Longest unbroken sitting or lying stretch, in minutes. Null when unknown.
  int? get longestSittingMinutes {
    if (report case final r?) return r.longestSittingMinutes;
    if (!_hasPostures) return null;
    var best = 0, run = 0;
    for (final m in minutes) {
      run = m.worn && _sits(m.posture) ? run + 1 : 0;
      if (run > best) best = run;
    }
    return best;
  }

  /// Times the band saw a change from sitting to upright. Null when unknown.
  int? get standUps {
    if (report case final r?) return r.transitions;
    if (!_hasPostures) return null;
    var n = 0;
    for (var i = 1; i < minutes.length; i++) {
      if (_sits(minutes[i - 1].posture) &&
          (minutes[i].posture == BandPosture.standing || minutes[i].posture == BandPosture.moving)) {
        n++;
      }
    }
    return n;
  }

  int? get standingMinutes {
    if (report case final r?) return r.postures['standing'];
    if (!_hasPostures) return null;
    return minutes.where((m) => m.worn && m.posture == BandPosture.standing).length;
  }

  int? get lightWalkingMinutes => report?.postures['walking_light'];
  int? get moderateWalkingMinutes => report?.postures['walking_moderate'];

  /// Part-worn day: some wear, not enough to count.
  bool get isPartial => wornMinutes > 0 && !isValid;

  /// Sitting or lying minutes by hour (0-23); null when the band was not worn that hour.
  List<int?> get sittingByHour {
    final steps = stepsByHour;
    if (report case final r?) {
      return [
        for (var h = 0; h < 24; h++) steps[h] == null ? null : r.hourly[h]['sitting_lying_min'],
      ];
    }
    return [
      for (var h = 0; h < 24; h++)
        steps[h] == null
            ? null
            : minutes.where((m) => m.at.hour == h && m.worn && _sits(m.posture)).length,
    ];
  }
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
