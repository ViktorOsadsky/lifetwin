/// Plain data for check-ins: days, finished check-ins, the quick plan and the settings.
///
/// Dates are the phone's local calendar dates as `YYYY-MM-DD`. Day arithmetic goes
/// through UTC midnights, so a daylight-saving change never moves a date.
library;

/// A calendar day (no time, no zone).
DateTime dayOf(DateTime localWallTime) => DateTime.utc(localWallTime.year, localWallTime.month, localWallTime.day);

String isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

DateTime parseDay(String iso) {
  final d = DateTime.parse(iso);
  return DateTime.utc(d.year, d.month, d.day);
}

String shiftDay(String iso, int days) => isoDay(parseDay(iso).add(Duration(days: days)));

/// The Monday of the Monday–Sunday week that holds [iso].
String mondayOf(String iso) {
  final d = parseDay(iso);
  return isoDay(d.subtract(Duration(days: d.weekday - DateTime.monday)));
}

/// One day's `daily_logs` row, possibly partial, in the on-device package's names and
/// units. A null value is unknown: never zero, never a typical value.
class DayLog {
  const DayLog({required this.date, this.sleepHours, this.vigorousMin, this.moderateMin, this.sedentaryMin});

  /// A value of the wrong type is not read (left unknown), never guessed at.
  factory DayLog.fromJson(Map<String, dynamic> j) {
    num? n(String k) => j[k] is num && (j[k] as num).isFinite ? j[k] as num : null;
    return DayLog(
      date: '${j['date']}',
      sleepHours: n('sleep_hours')?.toDouble(),
      vigorousMin: n('vigorous_recreation_min')?.round(),
      moderateMin: n('moderate_recreation_min')?.round(),
      sedentaryMin: n('sedentary_min_day')?.round(),
    );
  }

  /// The value stored under the package's [field] name.
  num? valueOf(String field) => switch (field) {
    'sleep_hours' => sleepHours,
    'vigorous_recreation_min' => vigorousMin,
    'moderate_recreation_min' => moderateMin,
    'sedentary_min_day' => sedentaryMin,
    _ => null,
  };

  final String date;

  /// Hours slept the night before [date] (the person woke up on [date]).
  final double? sleepHours;

  /// Minutes of activity that got the person out of breath.
  final int? vigorousMin;

  /// Minutes of easy activity, like a gentle walk.
  final int? moderateMin;

  /// Awake minutes sitting.
  final int? sedentaryMin;

  bool get complete => sleepHours != null && vigorousMin != null && moderateMin != null && sedentaryMin != null;
  bool get activityKnown => vigorousMin != null && moderateMin != null;
  bool get empty => sleepHours == null && vigorousMin == null && moderateMin == null && sedentaryMin == null;

  /// This row with [other]'s known values on top (a later confirmed answer wins).
  DayLog merge(DayLog other) => DayLog(
    date: date,
    sleepHours: other.sleepHours ?? sleepHours,
    vigorousMin: other.vigorousMin ?? vigorousMin,
    moderateMin: other.moderateMin ?? moderateMin,
    sedentaryMin: other.sedentaryMin ?? sedentaryMin,
  );

  /// The known values only, under the package's names.
  Map<String, dynamic> toJson() => {
    'date': date,
    'sleep_hours': ?sleepHours,
    'vigorous_recreation_min': ?vigorousMin,
    'moderate_recreation_min': ?moderateMin,
    'sedentary_min_day': ?sedentaryMin,
  };

  @override
  bool operator ==(Object other) => other is DayLog && '${other.toJson()}' == '${toJson()}';

  @override
  int get hashCode => '${toJson()}'.hashCode;

  @override
  String toString() => 'DayLog(${toJson()})';
}

/// One finished check-in as confirmed in the conversation: the server's
/// `state.confirmed` without nulls. Same shape as `CheckinRecord` on codex/c-on-device-model.
class CheckinEntry {
  const CheckinEntry({required this.kind, required this.date, required this.answers});

  factory CheckinEntry.fromJson(Map<String, dynamic> j) => CheckinEntry(
    kind: '${j['kind']}',
    date: '${j['date']}',
    answers: Map<String, dynamic>.from(j['answers'] as Map? ?? const {}),
  );

  /// `quick`, `daily` or `weekly`.
  final String kind;

  /// The phone's local date when it started.
  final String date;
  final Map<String, dynamic> answers;

  String? get wellbeing => answers['wellbeing'] as String?;

  Map<String, dynamic> toJson() => {'kind': kind, 'date': date, 'answers': answers};
}

enum QuickTopic { sleep, activity, sitting, feeling }

/// What a quick check-in asks (the server's `QuickPlan`), chosen by [CheckinScheduler].
class QuickPlan {
  const QuickPlan({
    required this.topics,
    required this.activityDay,
    this.catchUp = false,
    this.suggestedSleepLastNight,
    this.suggestedSleepNightBefore,
    this.suggestedActivityMinutes,
  });

  /// One to three topics; the server asks them in its own fixed order.
  final List<QuickTopic> topics;

  /// `today` (evening check-ins) or `yesterday`.
  final String activityDay;

  /// "Yesterday was a bit of a blank": the night before's sleep, optional, last.
  final bool catchUp;

  /// Apple Health values to read back as "Looks right?". Never saved without a yes.
  final double? suggestedSleepLastNight;
  final double? suggestedSleepNightBefore;
  final int? suggestedActivityMinutes;

  Map<String, dynamic> toJson() => {
    'topics': [for (final t in topics) t.name],
    'activity_day': activityDay,
    'catch_up': catchUp,
    'suggested': {
      'sleep_hours_last_night': ?suggestedSleepLastNight,
      'sleep_hours_night_before': ?suggestedSleepNightBefore,
      'activity_minutes': ?suggestedActivityMinutes,
    },
  };
}

/// The person's check-in preferences. Not health data.
class CheckinSettings {
  const CheckinSettings({
    this.reminderHour = 10,
    this.reminderMinute = 0,
    this.remindersOn = false,
    this.reminderOffered = false,
    this.weeklyDay = DateTime.sunday,
  });

  factory CheckinSettings.fromJson(Map<String, dynamic> j) => CheckinSettings(
    reminderHour: (j['reminder_hour'] as num?)?.toInt() ?? 10,
    reminderMinute: (j['reminder_minute'] as num?)?.toInt() ?? 0,
    remindersOn: j['reminders_on'] == true,
    reminderOffered: j['reminder_offered'] == true,
    weeklyDay: (j['weekly_day'] as num?)?.toInt() ?? DateTime.sunday,
  );

  /// When the daily reminder comes (the person picks; 10:00 by default).
  final int reminderHour;
  final int reminderMinute;

  /// The person said yes to reminders and the phone allowed notifications.
  final bool remindersOn;

  /// Reminders were offered once (after the first finished check-in). Never asked again
  /// unprompted; the person can still turn them on from settings.
  final bool reminderOffered;

  /// The weekly check-in's day (`DateTime.monday`..`DateTime.sunday`).
  final int weeklyDay;

  CheckinSettings copyWith({
    int? reminderHour,
    int? reminderMinute,
    bool? remindersOn,
    bool? reminderOffered,
    int? weeklyDay,
  }) => CheckinSettings(
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
    remindersOn: remindersOn ?? this.remindersOn,
    reminderOffered: reminderOffered ?? this.reminderOffered,
    weeklyDay: weeklyDay ?? this.weeklyDay,
  );

  Map<String, dynamic> toJson() => {
    'reminder_hour': reminderHour,
    'reminder_minute': reminderMinute,
    'reminders_on': remindersOn,
    'reminder_offered': reminderOffered,
    'weekly_day': weeklyDay,
  };
}
