/// Gentle check-in reminders at the time the person picks (10:00 unless they choose).
///
/// The honest model: the phone shows a scheduled local notification, and the app does its
/// work when the person opens it. Nothing runs in the background. Reminders are planned
/// a week ahead and planned again on every app open and after every check-in, so a day
/// that's already done gets no reminder.
///
/// Permission is asked at a sensible moment, never on first launch: once, at the end of
/// onboarding or right after the first finished check-in, and only if the person says yes
/// to reminders. Notification permission is separate from Apple Health access and from
/// consent to process answers.
///
/// Someone who doesn't open the app for a week gets the week's reminders, and the last one
/// says, gently, that reminders pause until they're back. The next app open plans a new
/// week.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'checkin_models.dart';

/// What the app needs from the phone's notifications. Fake it in tests.
abstract class NotificationPort {
  /// Shows the system's "Allow notifications?" question the first time.
  Future<bool> requestPermission();

  /// One notification at [localWallTime] in the phone's current zone.
  Future<void> scheduleAt({
    required int id,
    required DateTime localWallTime,
    required String title,
    required String body,
  });

  Future<void> cancelAll();
}

/// Reminder lines: an invitation, never a nudge about missed days, streaks or health.
const reminderTitle = 'Mochi';
const reminderLines = [
  "I'm here when you're ready for a quick check-in.",
  'A minute with Mochi? Just a few quick words about your day.',
  'Mochi would love to hear how you slept.',
];

/// The last planned reminder: reminders pause after it until the next app open.
const reminderPauseLine = "I'll pause reminders until you're back. I'm here whenever you like.";

/// How many days ahead are planned (iOS keeps at most 64 pending).
const reminderDays = 7;

class CheckinReminders {
  CheckinReminders(this.port);

  final NotificationPort port;

  /// Offer reminders now? At the end of onboarding ([onboarded]: a profile is saved) or
  /// after the first finished check-in, and only once.
  bool shouldOffer(CheckinSettings settings, List<CheckinEntry> history, {bool onboarded = false}) =>
      !settings.reminderOffered && !settings.remindersOn && (onboarded || history.isNotEmpty);

  /// The person said yes to reminders at [hour]:[minute]: asks the phone, then plans
  /// them. Returns the new settings for the store; reminders stay off if the phone said no.
  Future<CheckinSettings> accept(
    CheckinSettings settings, {
    required DateTime localNow,
    required List<CheckinEntry> history,
    int? hour,
    int? minute,
  }) async {
    final allowed = await port.requestPermission();
    final next = settings.copyWith(
      reminderOffered: true,
      remindersOn: allowed,
      reminderHour: hour ?? settings.reminderHour,
      reminderMinute: minute ?? settings.reminderMinute,
    );
    await reschedule(next, localNow: localNow, history: history);
    return next;
  }

  /// "Not now": remembered, so the offer isn't repeated.
  CheckinSettings decline(CheckinSettings settings) => settings.copyWith(reminderOffered: true, remindersOn: false);

  /// Turns reminders off and removes the planned ones.
  Future<CheckinSettings> turnOff(CheckinSettings settings) async {
    await port.cancelAll();
    return settings.copyWith(remindersOn: false);
  }

  /// Plans the next [reminderDays] reminders. Call on app open and after each check-in.
  /// Today is skipped once its check-in is done or its time has passed. The last one is
  /// [reminderPauseLine], so a week away ends with a kind word instead of silence.
  Future<List<DateTime>> reschedule(
    CheckinSettings settings, {
    required DateTime localNow,
    required List<CheckinEntry> history,
  }) async {
    await port.cancelAll();
    if (!settings.remindersOn) return const [];
    final today = isoDay(dayOf(localNow));
    final doneToday = history.any((c) => c.kind != 'weekly' && c.date == today);
    final planned = <DateTime>[];
    for (var i = 0; i < reminderDays + 1 && planned.length < reminderDays; i++) {
      final day = parseDay(shiftDay(today, i));
      final at = DateTime(day.year, day.month, day.day, settings.reminderHour, settings.reminderMinute);
      if (i == 0 && (doneToday || !at.isAfter(localNow))) continue;
      final id = day.year * 10000 + day.month * 100 + day.day;
      await port.scheduleAt(
        id: id,
        localWallTime: at,
        title: reminderTitle,
        body: planned.length == reminderDays - 1
            ? reminderPauseLine
            : reminderLines[day.difference(DateTime.utc(2026)).inDays % reminderLines.length],
      );
      planned.add(at);
    }
    return planned;
  }
}

/// [NotificationPort] on the phone, with flutter_local_notifications. A reminder's wall
/// time is placed in the phone's current time zone, so 10:00 stays 10:00 across daylight
/// saving changes; after travel, the next app open plans them again in the new zone.
class LocalNotificationPort implements NotificationPort {
  LocalNotificationPort([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;

  Future<void> _init() => _ready ??= () async {
    tzdata.initializeTimeZones();
    // An unknown zone name throws: better no reminder than one at the wrong hour.
    tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    // No permission prompt here: it's asked only through requestPermission().
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
  }();

  @override
  Future<bool> requestPermission() async {
    await _init();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime localWallTime,
    required String title,
    required String body,
  }) async {
    await _init();
    final when = tz.TZDateTime(
      tz.local,
      localWallTime.year,
      localWallTime.month,
      localWallTime.day,
      localWallTime.hour,
      localWallTime.minute,
    );
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: when,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(iOS: DarwinNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }
}
