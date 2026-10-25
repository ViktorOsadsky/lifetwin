import 'package:flutter/foundation.dart';

/// One minute from the wrist band. Raw samples never leave the band; these minute records live in
/// memory on the phone only (D1) and are added up there. Every number is a sensor estimate.
@immutable
class BandMinute {
  const BandMinute({required this.at, this.steps = 0, this.moderate = false, this.worn = true});

  /// The start of the minute (local time).
  final DateTime at;
  final int steps;

  /// Moderate-to-vigorous movement this minute (approximate cut-points; Hildebrand 2014 values, to be verified).
  final bool moderate;
  final bool worn;
}

/// A day counts at 10 or more hours worn (Troiano 2008 convention).
const validDayMinutes = 10 * 60;

/// Four or more valid days in the last seven are needed for a weekly number.
const validDaysNeeded = 4;

/// One day of minute records, added up on the phone.
class BandDay {
  BandDay(this.date, this.minutes);
  final DateTime date;
  final List<BandMinute> minutes;

  int get steps => minutes.fold(0, (a, m) => a + (m.worn ? m.steps : 0));
  int get moderateMinutes => minutes.where((m) => m.worn && m.moderate).length;
  int get wornMinutes => minutes.where((m) => m.worn).length;
  bool get isValid => wornMinutes >= validDayMinutes;

  /// Steps by hour (0-23), for the hour chart. Hours with no worn minute are null ("Not worn").
  List<int?> get stepsByHour => [
    for (var h = 0; h < 24; h++)
      () {
        final inHour = minutes.where((m) => m.at.hour == h && m.worn).toList();
        return inHour.isEmpty ? null : inHour.fold<int>(0, (a, m) => a + m.steps);
      }(),
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

  /// The suggestion needs 4 or more valid days.
  bool get hasEstimate => validCount >= validDaysNeeded;

  /// Moderate-to-vigorous minutes on the valid days.
  int get validModerate => validDays.fold(0, (a, d) => a + d.moderateMinutes);

  /// Scaled to 7 days and rounded to 10 ("23 minutes on 4 days" -> 40.2 -> about 40). Null under 4 valid days.
  int? get estimateMinutesPerWeek {
    if (!hasEstimate) return null;
    final scaled = validModerate * 7 / validCount;
    return ((scaled / 10).round()) * 10;
  }

  static BandWeek from(Iterable<BandMinute> minutes, DateTime today) {
    final start = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 6));
    final byDay = <int, List<BandMinute>>{for (var i = 0; i < 7; i++) i: []};
    for (final m in minutes) {
      final d = DateTime(m.at.year, m.at.month, m.at.day);
      final i = d.difference(start).inDays;
      if (i >= 0 && i < 7) byDay[i]!.add(m);
    }
    return BandWeek([for (var i = 0; i < 7; i++) BandDay(start.add(Duration(days: i)), byDay[i]!)]);
  }
}
