/// Turns check-in history into the on-device package's `daily_logs` and
/// `weekly_summaries`, exactly as `LifeTwinEngine.assess` accepts them.
///
/// Only real, complete days count: a missed day is unknown, never zero, and a window is
/// 7, 14, 21 or 28 complete consecutive days ending the day before `as_of_date`. A day
/// whose values the package would refuse (sleep under 2 or over 12 hours, more than 24
/// hours in all) is left out, not patched. One day's answers never change the forecast by
/// themselves: it is reassessed only when a supported window exists.
library;

import 'checkin_models.dart';

/// The package's `workday`: the night was before a weekday. The model's sleep input is
/// NHANES "sleep on weekdays or workdays", and a row's sleep is the night before its date,
/// so Monday to Friday rows are workdays. Someone who works weekends can pass their own.
bool weekdayNight(String date) => parseDay(date).weekday <= DateTime.friday;

const dailyWindowLengths = [28, 21, 14, 7];
const weeklySummaryFields = [
  'sleep_hours',
  'vigorous_recreation_min_week',
  'moderate_recreation_min_week',
  'sedentary_min_day',
];

class DailyLogsAssembler {
  const DailyLogsAssembler({this.workday = weekdayNight});

  final bool Function(String date) workday;

  /// The package's row for [day], or null unless it is complete and within the
  /// package's limits.
  Map<String, dynamic>? row(DayLog day) {
    if (!day.complete) return null;
    final sleep = day.sleepHours!, vig = day.vigorousMin!, mod = day.moderateMin!, sit = day.sedentaryMin!;
    if (sleep < 2 || sleep > 12 || sit < 0 || sit > 1439 || vig < 0 || vig > 1440 || mod < 0 || mod > 1440) {
      return null;
    }
    if (sleep * 60 + sit + vig + mod > 1440) return null;
    return {
      'date': day.date,
      'workday': workday(day.date),
      'sleep_hours': sleep,
      'vigorous_recreation_min': vig,
      'moderate_recreation_min': mod,
      'sedentary_min_day': sit,
    };
  }

  /// Complete consecutive days ending the day before [asOf], newest last.
  List<Map<String, dynamic>> completeRun(List<DayLog> days, String asOf) {
    final byDate = {for (final d in days) d.date: d};
    final run = <Map<String, dynamic>>[];
    var date = shiftDay(asOf, -1);
    while (run.length < dailyWindowLengths.first) {
      final day = byDate[date];
      final r = day == null ? null : row(day);
      if (r == null) break;
      run.insert(0, r);
      date = shiftDay(date, -1);
    }
    return run;
  }

  /// The longest `daily_logs` window the package accepts on [asOf], or null.
  List<Map<String, dynamic>>? dailyWindow(List<DayLog> days, String asOf) {
    final run = completeRun(days, asOf);
    for (final n in dailyWindowLengths) {
      if (run.length < n) continue;
      final window = run.sublist(run.length - n);
      // The package needs three workday nights a week.
      if (window.where((r) => r['workday'] == true).length >= 3 * (n ~/ 7)) return window;
    }
    return null;
  }

  /// Weekly summaries from weekly check-ins whose confirmed answers hold all four
  /// behaviour fields. A check-in describes the Monday–Sunday week that has ended by the
  /// end of its day (a Sunday check-in counts that week), as on codex/c-on-device-model.
  List<Map<String, dynamic>> weeklySummaries(List<CheckinEntry> checkins) {
    final byWeek = <String, Map<String, dynamic>>{};
    for (final c in checkins) {
      if (c.kind != 'weekly' || !weeklySummaryFields.every((f) => c.answers[f] is num)) continue;
      final week = shiftDay(mondayOf(shiftDay(c.date, 1)), -7);
      final summary = {'week_start': week, for (final f in weeklySummaryFields) f: c.answers[f]};
      if (_weeklyUsable(summary)) byWeek[week] = summary; // a later check-in for the week wins
    }
    return byWeek.values.toList()..sort((a, b) => '${a['week_start']}'.compareTo('${b['week_start']}'));
  }

  /// The longest `weekly_summaries` window (1–4 consecutive weeks ending with the latest
  /// completed week before [asOf]), or null.
  List<Map<String, dynamic>>? weeklyWindow(List<CheckinEntry> checkins, String asOf) {
    final byWeek = {for (final s in weeklySummaries(checkins)) '${s['week_start']}': s};
    final out = <Map<String, dynamic>>[];
    var week = shiftDay(mondayOf(asOf), -7);
    while (out.length < 4 && byWeek[week] != null) {
      out.insert(0, byWeek[week]!);
      week = shiftDay(week, -7);
    }
    return out.isEmpty ? null : out;
  }

  /// The request for `LifeTwinEngine.assess`: the profile with the weekly window if there
  /// is one, else the daily window, else the profile alone (the same order as
  /// `candidateWindows` on codex/c-on-device-model).
  Map<String, dynamic> assessRequest({
    required Map<String, dynamic> modelProfile,
    required String asOf,
    required List<DayLog> days,
    required List<CheckinEntry> checkins,
  }) {
    final weekly = weeklyWindow(checkins, asOf);
    final daily = weekly == null ? dailyWindow(days, asOf) : null;
    return {'profile': modelProfile, 'as_of_date': asOf, 'weekly_summaries': ?weekly, 'daily_logs': ?daily};
  }

  static bool _weeklyUsable(Map<String, dynamic> s) {
    final sleep = s['sleep_hours'] as num, vig = s['vigorous_recreation_min_week'] as num;
    final mod = s['moderate_recreation_min_week'] as num, sit = s['sedentary_min_day'] as num;
    if (sleep < 2 || sleep > 12 || vig < 0 || vig > 10073 || mod < 0 || mod > 10073 || sit < 0 || sit > 1439) {
      return false;
    }
    return sleep * 60 + sit + (vig + mod) / 7 <= 1440;
  }
}

/// "Good weeks", never streaks: Monday–Sunday weeks with at least [daysForGoodWeek]
/// different days with a finished check-in of any kind (quick, daily or weekly). It counts
/// days, not check-ins. A missed day costs nothing and is never mentioned.
const daysForGoodWeek = 4;

class WeekProgress {
  const WeekProgress({required this.goodWeeks, required this.daysThisWeek});

  /// Good weeks so far, all time (not in a row).
  final int goodWeeks;

  /// Check-in days so far this week, for a gentle "3 of 4" (never "you missed").
  final int daysThisWeek;
}

WeekProgress weekProgress(List<CheckinEntry> checkins, String today) {
  final daysByWeek = <String, Set<String>>{};
  for (final c in checkins) {
    daysByWeek.putIfAbsent(mondayOf(c.date), () => {}).add(c.date);
  }
  final thisWeek = mondayOf(today);
  return WeekProgress(
    goodWeeks: daysByWeek.values.where((days) => days.length >= daysForGoodWeek).length,
    daysThisWeek: daysByWeek[thisWeek]?.length ?? 0,
  );
}
