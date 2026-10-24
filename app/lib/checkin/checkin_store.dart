/// Where check-in history lives: on the phone only (owner ruling).
///
/// The only write for answers is [CheckinStore.applyFinishedCheckin], with a finished
/// `/api/checkin` response: answers reach history only through Mochi's confirmed
/// read-backs ("people can't edit saved answers directly"). See README.md for how this
/// is kept by `TwinRepository` (lib/twin/twin_checkin_store.dart).
library;

import 'checkin_models.dart';

abstract class CheckinStore {
  /// Finished check-ins, oldest first.
  Future<List<CheckinEntry>> checkins();

  /// Stored day rows, possibly partial, oldest first.
  Future<List<DayLog>> dayLogs();

  /// Keeps a finished check-in: the record (`state.confirmed`), and for a quick one
  /// each non-null `daily_logs` value merged into its date's row. [response] is the
  /// server's JSON; anything not `complete: true` is ignored.
  Future<void> applyFinishedCheckin(Map<String, dynamic> response, {required String localDate});

  Future<CheckinSettings> settings();

  /// Preferences only (reminder time, weekly day); never health answers.
  Future<void> saveSettings(CheckinSettings settings);
}

/// The record and the day-row parts a finished response carries; shared by every store.
({CheckinEntry record, List<DayLog> parts})? readFinishedCheckin(
  Map<String, dynamic> response, {
  required String localDate,
}) {
  final state = response['state'];
  if (response['complete'] != true || state is! Map) return null;
  final kind = state['kind'];
  if (kind is! String) return null;
  final confirmed = {
    for (final e in Map<String, dynamic>.from(state['confirmed'] as Map? ?? const {}).entries)
      if (e.value != null) e.key: e.value,
  };
  final parts = [
    for (final row in response['daily_logs'] as List? ?? const [])
      if (row is Map) DayLog.fromJson(Map<String, dynamic>.from(row)),
  ]..removeWhere((d) => d.empty);
  return (record: CheckinEntry(kind: kind, date: localDate, answers: confirmed), parts: parts);
}

/// Merges [parts] into [rows] by date, oldest first.
List<DayLog> mergeDayLogs(List<DayLog> rows, List<DayLog> parts) {
  final byDate = {for (final r in rows) r.date: r};
  for (final p in parts) {
    byDate[p.date] = (byDate[p.date] ?? DayLog(date: p.date)).merge(p);
  }
  return byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
}

/// For tests and previews. Nothing leaves memory.
class InMemoryCheckinStore implements CheckinStore {
  InMemoryCheckinStore({List<CheckinEntry>? checkins, List<DayLog>? dayLogs, CheckinSettings? settings})
    : _checkins = [...?checkins],
      _days = [...?dayLogs],
      _settings = settings ?? const CheckinSettings();

  final List<CheckinEntry> _checkins;
  List<DayLog> _days;
  CheckinSettings _settings;
  int writes = 0;

  @override
  Future<List<CheckinEntry>> checkins() async => List.unmodifiable(_checkins);

  @override
  Future<List<DayLog>> dayLogs() async => List.unmodifiable(_days);

  @override
  Future<void> applyFinishedCheckin(Map<String, dynamic> response, {required String localDate}) async {
    final finished = readFinishedCheckin(response, localDate: localDate);
    if (finished == null) return;
    _checkins.add(finished.record);
    _days = mergeDayLogs(_days, finished.parts);
    writes++;
  }

  @override
  Future<CheckinSettings> settings() async => _settings;

  @override
  Future<void> saveSettings(CheckinSettings settings) async => _settings = settings;
}
