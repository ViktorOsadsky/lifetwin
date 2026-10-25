import 'package:flutter/foundation.dart';

enum ReminderKind { daily, weekly }

/// Local reminders. The notification never mentions health details on the lock screen and never uses
/// guilt ("You missed ..."). Permission is asked in context, the first time one is turned on.
const reminderNotificationText = 'Mochi: Time for a quick check-in? About a minute.';

abstract class ReminderScheduler {
  /// Asks the person for notification permission (iOS asks once). False if they say no.
  Future<bool> requestPermission();

  /// [weekday] 1 (Monday) to 7 (Sunday) for the weekly reminder.
  Future<void> schedule(ReminderKind kind, {required int hour, required int minute, int? weekday});
  Future<void> cancel(ReminderKind kind);

  /// "Delete my data" cancels every scheduled reminder.
  Future<void> cancelAll();
}

/// STUB: no notification plugin is in the app yet, so this keeps the schedule in memory only and
/// nothing is delivered. Swap in a `flutter_local_notifications` scheduler behind [ReminderScheduler].
class InMemoryReminderScheduler implements ReminderScheduler {
  final scheduled = <ReminderKind, ({int hour, int minute, int? weekday})>{};
  bool permission = true;
  int permissionAsks = 0;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return permission;
  }

  @override
  Future<void> schedule(ReminderKind kind, {required int hour, required int minute, int? weekday}) async =>
      scheduled[kind] = (hour: hour, minute: minute, weekday: weekday);

  @override
  Future<void> cancel(ReminderKind kind) async => scheduled.remove(kind);

  @override
  Future<void> cancelAll() async => scheduled.clear();
}

/// The reminder choices on the phone: off until turned on.
class ReminderPrefs extends ChangeNotifier {
  ReminderPrefs(this.scheduler);
  final ReminderScheduler scheduler;

  bool dailyOn = false;
  bool weeklyOn = false;

  /// Morning 9:00 or evening 7:30 by default choices; any time can be picked.
  int dailyHour = 9, dailyMinute = 0;

  /// Sundays at 6:00 PM.
  static const weeklyHour = 18, weeklyMinute = 0, weeklyWeekday = DateTime.sunday;

  Future<void> setDaily(bool on) async {
    if (on && !await scheduler.requestPermission()) return;
    dailyOn = on;
    on
        ? await scheduler.schedule(ReminderKind.daily, hour: dailyHour, minute: dailyMinute)
        : await scheduler.cancel(ReminderKind.daily);
    notifyListeners();
  }

  Future<void> setDailyTime(int hour, int minute) async {
    dailyHour = hour;
    dailyMinute = minute;
    if (dailyOn) await scheduler.schedule(ReminderKind.daily, hour: hour, minute: minute);
    notifyListeners();
  }

  Future<void> setWeekly(bool on) async {
    if (on && !await scheduler.requestPermission()) return;
    weeklyOn = on;
    on
        ? await scheduler.schedule(ReminderKind.weekly, hour: weeklyHour, minute: weeklyMinute, weekday: weeklyWeekday)
        : await scheduler.cancel(ReminderKind.weekly);
    notifyListeners();
  }

  Future<void> clear() async {
    dailyOn = weeklyOn = false;
    await scheduler.cancelAll();
    notifyListeners();
  }
}
