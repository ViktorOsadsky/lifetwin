/// The forecast's history windows, through the one window assembler
/// (`DailyLogsAssembler`, lib/checkin/daily_logs.dart).
///
/// Order: complete weekly summaries (1–4 consecutive Monday–Sunday weeks ending with the
/// latest completed one, from weekly check-ins holding all four behaviour fields), then
/// complete daily logs (28, 21, 14 or 7 consecutive days ending yesterday), then the
/// profile snapshot. A missed day is unknown, never zero, so it ends a daily run.
library;

import '../checkin/checkin_models.dart' show CheckinEntry, DayLog;
import '../checkin/daily_logs.dart';
import 'twin_model.dart';

export '../checkin/checkin_models.dart' show CheckinEntry, DayLog;
export '../checkin/daily_logs.dart' show weeklySummaryFields;

/// The windows to try on [asOf], in order; the last is always the snapshot (`{}`).
List<Map<String, dynamic>> candidateWindows({
  required List<CheckinEntry> checkins,
  required List<DayLog> dayLogs,
  required DateTime asOf,
  DailyLogsAssembler assembler = const DailyLogsAssembler(),
}) {
  final day = isoDate(asOf);
  final weekly = assembler.weeklyWindow(checkins, day);
  final daily = assembler.dailyWindow(dayLogs, day);
  return [
    if (weekly != null) {'weekly_summaries': weekly},
    if (daily != null) {'daily_logs': daily},
    const {},
  ];
}

/// Assesses [modelProfile] (the package's input names) with the first window the package
/// accepts. A window it refuses (`invalid_input`) is skipped, never patched up.
TwinAssessment assessWithHistory(
  TwinModelService model,
  Map<String, dynamic> modelProfile, {
  List<CheckinEntry> checkins = const [],
  List<DayLog> dayLogs = const [],
  required DateTime asOf,
}) {
  late TwinAssessment result;
  for (final w in candidateWindows(checkins: checkins, dayLogs: dayLogs, asOf: asOf)) {
    result = model.assessModel(modelProfile, window: w, asOf: asOf);
    // A refused window is skipped; a refused profile value is the person's to fix.
    if (result.status != 'invalid_input' || w.isEmpty) return result;
  }
  return result;
}
