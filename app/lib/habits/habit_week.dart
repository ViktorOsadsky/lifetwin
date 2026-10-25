/// The good-week rule, the same as the server's `/api/habits/week`:
/// a habit day is a phone-local day marked done or sort of done; a good habit
/// week has 4+ habit days in one Monday-to-Sunday week. Good weeks are counted
/// over all time, never in a row, and nothing ever resets to zero.
library;

import 'habit.dart';

const daysForGoodWeek = 4;

/// The phone-local day of [time], as YYYY-MM-DD.
String localDay(DateTime time) {
  final t = time.toLocal();
  return _format(DateTime.utc(t.year, t.month, t.day));
}

/// Parses YYYY-MM-DD as a calendar day (UTC midnight, so no DST shifts).
/// Throws [FormatException] for anything else, including 2026-02-30.
DateTime parseDay(String day) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day);
  if (m == null) throw FormatException('not a day', day);
  final parsed = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  if (_format(parsed) != day) throw FormatException('not a real day', day);
  return parsed;
}

/// The Monday of the week [day] is in.
String weekStartOf(String day) {
  final d = parseDay(day);
  return _format(d.subtract(Duration(days: d.weekday - DateTime.monday)));
}

String addDays(String day, int days) => _format(parseDay(day).add(Duration(days: days)));

String _format(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class HabitWeek {
  const HabitWeek({
    required this.weekStart,
    required this.habitDaysThisWeek,
    required this.goodWeeksTotal,
    required this.ignoredFutureDays,
  });

  final String weekStart;
  final int habitDaysThisWeek;
  final int goodWeeksTotal;

  /// Results dated after today (a changed clock): never counted.
  final int ignoredFutureDays;

  bool get goodWeekThisWeek => habitDaysThisWeek >= daysForGoodWeek;
}

/// Habit days this week and good weeks so far, from one habit's results
/// (day to result; an absent day is unknown).
HabitWeek habitWeekProgress(Map<String, HabitResult> results, String today) {
  final todayDate = parseDay(today);
  final perWeek = <String, int>{};
  var future = 0;
  for (final MapEntry(key: day, value: result) in results.entries) {
    if (parseDay(day).isAfter(todayDate)) {
      future++;
      continue;
    }
    if (result.isHabitDay) perWeek.update(weekStartOf(day), (n) => n + 1, ifAbsent: () => 1);
  }
  final start = weekStartOf(today);
  return HabitWeek(
    weekStart: start,
    habitDaysThisWeek: perWeek[start] ?? 0,
    goodWeeksTotal: perWeek.values.where((n) => n >= daysForGoodWeek).length,
    ignoredFutureDays: future,
  );
}
