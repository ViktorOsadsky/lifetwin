/// Apple Health values the quick check-in can offer for a one-tap "Looks right?".
///
/// Nothing here is saved: the values go to the server as `suggested`, are read back
/// once, and reach history only after the person says yes (the read-back rule).
library;

import '../health/health_sample.dart';
import '../health/health_summary.dart';
import 'checkin_models.dart';

class HealthDay {
  const HealthDay({this.sleepByNight = const {}, this.exerciseByDay = const {}});

  /// Hours asleep, by the date the person woke up (the night before that date).
  final Map<String, double> sleepByNight;

  /// Apple Exercise minutes ("brisk or harder"; it can't say which were out of breath).
  final Map<String, int> exerciseByDay;
}

/// Reads sleep and exercise minutes per day from Apple Health samples. A night is
/// labelled by the date 12 hours after it starts, as in health_summary.dart, so 11 pm and
/// 2 am belong to the same night. Implausible nights (under 2 or over 14 hours) are left
/// out so Mochi asks instead.
HealthDay healthDay(List<HealthSample> samples) {
  final nights = <String, List<HealthSample>>{};
  final days = <String, List<HealthSample>>{};
  for (final s in samples) {
    if (sleepTypes.contains(s.type)) {
      nights.putIfAbsent(isoDay(dayOf(s.start.toLocal().add(const Duration(hours: 12)))), () => []).add(s);
    } else if (s.type == 'EXERCISE_TIME') {
      days.putIfAbsent(isoDay(dayOf(s.start.toLocal())), () => []).add(s);
    }
  }
  return HealthDay(
    sleepByNight: {
      for (final e in nights.entries)
        if (coveredMinutes(e.value) case final m when m >= 120 && m <= 14 * 60) e.key: (m / 6).round() / 10,
    },
    exerciseByDay: {
      for (final e in days.entries)
        if (coveredMinutes(e.value).round() case final m when m >= 1 && m <= 1440) e.key: m,
    },
  );
}
