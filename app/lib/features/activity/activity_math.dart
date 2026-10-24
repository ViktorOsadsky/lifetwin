import 'activity_models.dart';

/// Minutes of activity that started at [when].
class TimedMinutes {
  const TimedMinutes(this.when, this.minutes);

  final DateTime when;
  final double minutes;
}

const int activityWindowDays = 28;
const int activityWeeks = 4;

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Minutes per week for the last four weeks, oldest first. The newest week is
/// the 7 days ending today. Entries outside the 28-day window (or in the
/// future) are ignored.
List<int> weeklyBuckets(Iterable<TimedMinutes> entries, DateTime now) {
  final today = _day(now);
  final totals = List<double>.filled(activityWeeks, 0);
  for (final e in entries) {
    final ago = today.difference(_day(e.when)).inDays;
    if (ago < 0 || ago >= activityWindowDays) continue;
    totals[activityWeeks - 1 - ago ~/ 7] += e.minutes;
  }
  return totals.map((m) => m.round()).toList();
}

/// Average active minutes per week over the four-week window.
int weeklyAverage(List<int> weekly) {
  if (weekly.isEmpty) return 0;
  return (weekly.fold<int>(0, (a, b) => a + b) / weekly.length).round();
}

/// Buckets a manual workout log.
List<int> manualWeekly(Iterable<Workout> workouts, DateTime now) =>
    weeklyBuckets(
      workouts.map((w) => TimedMinutes(w.date, w.minutes.toDouble())),
      now,
    );
