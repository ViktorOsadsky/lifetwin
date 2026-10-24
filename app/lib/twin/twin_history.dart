/// Check-in history in the package's shapes, and the windows `assess()` accepts.
///
/// - `daily_logs` rows: `date`, `workday`, `sleep_hours`, `vigorous_recreation_min`,
///   `moderate_recreation_min`, `sedentary_min_day`. A window is 7, 14, 21 or 28 complete
///   consecutive days ending the day before `as_of_date`.
/// - `weekly_summaries` rows: `week_start` (a Monday), `sleep_hours`,
///   `vigorous_recreation_min_week`, `moderate_recreation_min_week`, `sedentary_min_day`.
///   A window is 1–4 consecutive completed Monday–Sunday weeks ending with the latest one.
library;

import 'twin_model.dart';

const dailyLogFields = ['sleep_hours', 'vigorous_recreation_min', 'moderate_recreation_min', 'sedentary_min_day'];

const weeklySummaryFields = [
  'sleep_hours',
  'vigorous_recreation_min_week',
  'moderate_recreation_min_week',
  'sedentary_min_day',
];

/// One finished check-in as the person confirmed it (the server's `state.confirmed`
/// without the nulls), kept on the phone. Wellbeing is `good`, `okay` or `not_great`.
class CheckinRecord {
  const CheckinRecord({required this.kind, required this.date, required this.answers});

  factory CheckinRecord.fromJson(Map<String, dynamic> j) => CheckinRecord(
    kind: '${j['kind']}',
    date: '${j['date']}',
    answers: Map<String, dynamic>.from(j['answers'] as Map? ?? const {}),
  );

  /// `daily` or `weekly`.
  final String kind;

  /// The phone's local date, YYYY-MM-DD.
  final String date;
  final Map<String, dynamic> answers;

  String? get wellbeing => answers['wellbeing'] as String?;

  Map<String, dynamic> toJson() => {'kind': kind, 'date': date, 'answers': answers};
}

/// The Monday of the latest completed Monday–Sunday week before [asOf] (the package's rule).
DateTime latestCompletedMonday(DateTime asOf) {
  final day = dayOf(asOf);
  return day.subtract(Duration(days: day.weekday + 6));
}

bool _complete(Map<String, dynamic> row, List<String> fields) => fields.every((f) => row[f] is num);

/// The longest window of complete weekly summaries the package will accept on [asOf]
/// (newest last), or null.
List<Map<String, dynamic>>? weeklyWindow(List<Map<String, dynamic>> rows, DateTime asOf) {
  final byWeek = {
    for (final r in rows)
      if (_complete(r, weeklySummaryFields)) '${r['week_start']}': r,
  };
  final out = <Map<String, dynamic>>[];
  var week = latestCompletedMonday(asOf);
  while (out.length < 4) {
    final row = byWeek[isoDate(week)];
    if (row == null) break;
    out.insert(0, {'week_start': isoDate(week), for (final f in weeklySummaryFields) f: row[f]});
    week = week.subtract(const Duration(days: 7));
  }
  return out.isEmpty ? null : out;
}

/// Complete daily windows ending yesterday, longest first (28, 21, 14, 7 days). The
/// package checks the rest (e.g. three workday nights a week), so callers try each.
List<List<Map<String, dynamic>>> dailyWindows(List<Map<String, dynamic>> rows, DateTime asOf) {
  final byDate = {
    for (final r in rows)
      if (_complete(r, dailyLogFields) && r['workday'] is bool) '${r['date']}': r,
  };
  final run = <Map<String, dynamic>>[];
  var day = dayOf(asOf).subtract(const Duration(days: 1));
  while (run.length < 28) {
    final row = byDate[isoDate(day)];
    if (row == null) break;
    run.insert(0, {'date': isoDate(day), 'workday': row['workday'], for (final f in dailyLogFields) f: row[f]});
    day = day.subtract(const Duration(days: 1));
  }
  return [
    for (final n in const [28, 21, 14, 7])
      if (run.length >= n) run.sublist(run.length - n),
  ];
}

/// The windows to try for [asOf], in order: the weekly check-ins (the owner's "weekly
/// answers update forecast"), then daily logs, then none (the profile snapshot).
List<Map<String, dynamic>> candidateWindows({
  required List<Map<String, dynamic>> weeklySummaries,
  required List<Map<String, dynamic>> dailyLogs,
  required DateTime asOf,
}) {
  final weekly = weeklyWindow(weeklySummaries, asOf);
  return [
    if (weekly != null) {'weekly_summaries': weekly},
    for (final w in dailyWindows(dailyLogs, asOf)) {'daily_logs': w},
    const {},
  ];
}

/// Assesses with the first window the package accepts. A window it refuses
/// (`FormatException`) is skipped, never patched up.
TwinAssessment assessWithHistory(
  TwinModelService model,
  Map<String, dynamic> appProfile, {
  List<Map<String, dynamic>> weeklySummaries = const [],
  List<Map<String, dynamic>> dailyLogs = const [],
  required DateTime asOf,
}) {
  final windows = candidateWindows(weeklySummaries: weeklySummaries, dailyLogs: dailyLogs, asOf: asOf);
  late TwinAssessment result;
  for (final w in windows) {
    result = model.assess(appProfile, window: w, asOf: asOf);
    // A refused window is skipped; a refused profile value is the person's to fix.
    if (result.status != 'invalid_input' || w.isEmpty) return result;
  }
  return result;
}
