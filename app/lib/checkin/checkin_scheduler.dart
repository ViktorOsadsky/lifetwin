/// Which check-in is due, and what the quick one asks.
///
/// The quick check-in comes once a day and asks only what the stored days are missing,
/// at most three questions, so it takes under a minute: last night's sleep, the day's
/// activity (out of breath, or easy), the day's sitting, and how the person feels when
/// there is room. Before [CheckinScheduler.eveningHour] the activity and sitting
/// questions are about yesterday (a whole day); from then on, about today. A missed day
/// is never chased: the only catch-up is one optional question about the night before
/// yesterday, asked when it would complete yesterday's row.
library;

import 'checkin_models.dart';
import 'health_suggestions.dart';

class DueCheckins {
  const DueCheckins({this.quick, this.weekly = false});

  /// The quick check-in's plan, or null when it isn't due (done today, or nothing to ask).
  final QuickPlan? quick;

  /// The weekly check-in is ready. Offered after the quick one, never instead of it.
  final bool weekly;

  bool get any => quick != null || weekly;
}

class CheckinScheduler {
  const CheckinScheduler({this.eveningHour = 17});

  /// From this hour (local), "today" is nearly done, so the quick check-in asks about it.
  final int eveningHour;

  static const maxTopics = 3;

  /// [localNow] is the phone's wall-clock time in its current zone. [health] holds Apple
  /// Health values already read on the phone (none when not connected).
  DueCheckins due({
    required DateTime localNow,
    required List<CheckinEntry> history,
    required List<DayLog> days,
    CheckinSettings settings = const CheckinSettings(),
    HealthDay health = const HealthDay(),
    String? firstJoined,
  }) {
    final today = isoDay(dayOf(localNow));
    final doneToday = history.any((c) => c.kind != 'weekly' && c.date == today);
    return DueCheckins(
      quick: doneToday ? null : quickPlan(localNow: localNow, history: history, days: days, health: health),
      weekly: weeklyDue(today: today, history: history, settings: settings, firstJoined: firstJoined),
    );
  }

  QuickPlan? quickPlan({
    required DateTime localNow,
    required List<CheckinEntry> history,
    required List<DayLog> days,
    HealthDay health = const HealthDay(),
  }) {
    final today = isoDay(dayOf(localNow));
    final yesterday = shiftDay(today, -1);
    final evening = localNow.hour >= eveningHour;
    final activityDate = evening ? today : yesterday;
    final byDate = {for (final d in days) d.date: d};
    final todayRow = byDate[today] ?? DayLog(date: today);
    final activityRow = byDate[activityDate] ?? DayLog(date: activityDate);

    final sleepHint = todayRow.sleepHours == null ? health.sleepByNight[today] : null;
    final topics = <QuickTopic>[
      if (todayRow.sleepHours == null) QuickTopic.sleep,
      if (!activityRow.activityKnown) QuickTopic.activity,
      if (activityRow.sedentaryMin == null) QuickTopic.sitting,
    ];
    // How the person feels takes a free place, so the check-in stays at three questions.
    final feltToday = history.any((c) => c.date == today && c.wellbeing != null);
    if (topics.length < maxTopics && !feltToday) topics.add(QuickTopic.feeling);

    // Catch-up: yesterday had no check-in and only its sleep is missing once this one is
    // answered. It is the last question, and optional.
    final yesterdayRow = byDate[yesterday] ?? DayLog(date: yesterday);
    final quickDays = history.where((c) => c.kind != 'weekly').map((c) => c.date);
    // Not on the first day: there was no "yesterday" with Mochi yet.
    final missedYesterday = !quickDays.contains(yesterday) && quickDays.any((d) => d.compareTo(yesterday) < 0);
    final restOfYesterday = !evening || (yesterdayRow.activityKnown && yesterdayRow.sedentaryMin != null);
    final catchUp = missedYesterday && yesterdayRow.sleepHours == null && restOfYesterday;

    if (topics.isEmpty && !catchUp) return null;
    final activityHint =
        topics.contains(QuickTopic.activity) && activityRow.vigorousMin == null && activityRow.moderateMin == null
        ? health.exerciseByDay[activityDate]
        : null;
    return QuickPlan(
      topics: topics,
      activityDay: evening ? 'today' : 'yesterday',
      catchUp: catchUp,
      suggestedSleepLastNight: topics.contains(QuickTopic.sleep) ? sleepHint : null,
      suggestedSleepNightBefore: catchUp ? health.sleepByNight[yesterday] : null,
      suggestedActivityMinutes: activityHint,
    );
  }

  /// Never before 7 full days after [firstJoined]; then the first one is ready at once and
  /// stays ready, quietly, until done. After that, once a week from the person's weekly day.
  bool weeklyDue({
    required String today,
    required List<CheckinEntry> history,
    required CheckinSettings settings,
    required String? firstJoined,
  }) {
    if (!weeklyOpen(today: today, firstJoined: firstJoined)) return false;
    final weeklies = history.where((c) => c.kind == 'weekly').map((c) => c.date).toList()..sort();
    if (weeklies.isEmpty) return true;
    final since = parseDay(today).difference(parseDay(weeklies.last)).inDays;
    return since >= 7 || (since >= 6 && parseDay(today).weekday == settings.weeklyDay);
  }
}
