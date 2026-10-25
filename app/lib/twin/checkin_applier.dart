/// Applies a finished check-in (`POST /api/checkin/turn`, contracts/checkin.schema.json)
/// to the phone's profile and history.
///
/// Contract: when `complete` is true and the check-in is weekly, the app sets each non-null
/// field of `profile_update` on the confirmed profile (under [mergeConfirmed]) and reruns
/// the forecast. Quick check-ins add their `daily_logs` parts to the day rows. Daily and
/// quick check-ins never touch the profile.
library;

import '../checkin/checkin_models.dart' show CheckinEntry, DayLog, shiftDay;
import '../checkin/checkin_store.dart' show readFinishedCheckin;
import '../checkin/daily_logs.dart' show DailyLogsAssembler;

/// The profile's fields and what each accepts: the contract's HealthProfile
/// (`server/lifetwin/core/models.py`, same ranges) and the model inputs the conversation
/// is gaining (same names as the package). Nothing else may be written to the profile.
final Map<String, bool Function(Object)> profileSchema = {
  'age': (v) => _whole(v, 0, 120),
  'sex': (v) => v == 'female' || v == 'male',
  'height_cm': (v) => _number(v, 50, 280),
  'weight_kg': (v) => _number(v, 10, 700),
  'sleep_hours': (v) => _number(v, 0, 24),
  'exercise_minutes_weekly': (v) => _whole(v, 0, 10080),
  'smoking_status': (v) => const {'never', 'former', 'current', 'unknown'}.contains(v),
  'alcohol_drinks_weekly': (v) => _number(v, 0, 200),
  'diabetes': (v) => v is bool,
  'systolic_bp': (v) => _whole(v, 40, 300),
  'diastolic_bp': (v) => _whole(v, 20, 200),
  'general_health': (v) =>
      _whole(v, 1, 5) || const {'excellent', 'very_good', 'good', 'fair', 'poor', 'unknown'}.contains(v),
  'hypertension_diagnosed': (v) => v is bool,
  'sedentary_min_day': (v) => _number(v, 0, 1440),
  'vigorous_recreation_min_week': (v) => _number(v, 0, 10080),
  'moderate_recreation_min_week': (v) => _number(v, 0, 10080),
};

/// One day's `daily_logs` values and what each accepts (the server's DailyLogPart ranges).
final Map<String, bool Function(Object)> dayLogSchema = {
  'sleep_hours': (v) => _number(v, 0, 24),
  'vigorous_recreation_min': (v) => _whole(v, 0, 1440),
  'moderate_recreation_min': (v) => _whole(v, 0, 1440),
  'sedentary_min_day': (v) => _whole(v, 0, 1439),
};

/// A day's answers that are history only (not model inputs) and what each accepts.
final Map<String, bool Function(Object)> dayNoteSchema = {
  'wellbeing': (v) => const {'good', 'okay', 'not_great'}.contains(v),
  'sleep_hours_last_night': (v) => _number(v, 0, 24),
  'sleep_hours_night_before': (v) => _number(v, 0, 24),
  'exercise_minutes_today': (v) => _whole(v, 0, 1440),
  'alcohol_drinks_yesterday': (v) => _number(v, 0, 50),
};

/// The fields a conversation or a weekly `profile_update` may set.
Set<String> get updatableProfileFields => profileSchema.keys.toSet();

bool _number(Object v, num lo, num hi) => v is num && v.isFinite && v >= lo && v <= hi;
bool _whole(Object v, num lo, num hi) => _number(v, lo, hi) && (v as num) == v.roundToDouble();

/// An answer that says "I don't know" (`unknown`, `not_sure`), not a value.
bool isUnknownAnswer(Object? v) =>
    v is String && const {'unknown', 'not_sure', 'not sure'}.contains(v.trim().toLowerCase());

bool isKnownAnswer(Object? v) => v != null && !isUnknownAnswer(v);

/// The result of laying confirmed values over the stored profile.
typedef ProfileMerge = ({Map<String, dynamic> profile, List<String> changed, List<String> refused});

/// The one rule for writing confirmed values (conversation saves and weekly check-ins):
/// - a field changes only when [incoming] carries it with a value; null or absent never
///   erases (erasing is Delete my data, or a confirmed change to another value);
/// - an unknown ("not sure") answer never replaces a known value; it only fills a gap,
///   even when the server confirmed it (owner ruling);
/// - a field outside [profileSchema], or a value of the wrong type or range, is refused.
ProfileMerge mergeConfirmed(Map<String, dynamic> stored, Map<String, dynamic> incoming) {
  final next = Map<String, dynamic>.from(stored);
  final changed = <String>[], refused = <String>[];
  for (final e in incoming.entries) {
    final v = e.value;
    if (v == null) continue;
    final valid = profileSchema[e.key];
    if (valid == null || !valid(v)) {
      refused.add(e.key);
      continue;
    }
    if (isUnknownAnswer(v) && isKnownAnswer(next[e.key])) continue;
    if (next[e.key] != v) changed.add(e.key);
    next[e.key] = v;
  }
  return (profile: next, changed: changed, refused: refused);
}

class CheckinOutcome {
  const CheckinOutcome({
    required this.profile,
    required this.changedFields,
    required this.emergency,
    this.refusedFields = const [],
    this.record,
    this.dayLogParts = const [],
    this.weeklySummary,
  });

  /// `profile_update` fields refused: not profile fields (e.g. `wellbeing`), or of the
  /// wrong type or range (e.g. `sleep_hours: "I don't know"`).
  final List<String> refusedFields;

  /// The profile after the update (unchanged unless a weekly check-in completed).
  final Map<String, dynamic> profile;

  /// Fields whose value changed; when non-empty the forecast must be recomputed.
  final List<String> changedFields;

  /// The reply said something urgent is happening (the check-in is paused). The twin shows
  /// its calm, concerned state and the UI its "Call 911" button. Never stored.
  final bool emergency;

  /// The finished check-in to keep in history; null while it is still going.
  final CheckinEntry? record;

  /// A quick check-in's `daily_logs` parts (known values only), to merge into the day rows.
  final List<DayLog> dayLogParts;

  /// The weekly summary row this check-in makes (the package's shape), when its answers
  /// cover all four behaviour fields within the package's limits; null otherwise.
  final Map<String, dynamic>? weeklySummary;
}

/// Reads one check-in response. [localDate] is the phone's date (YYYY-MM-DD) the check-in
/// started on (the one sent as `local_date`).
CheckinOutcome applyCheckinResponse(
  Map<String, dynamic> profile,
  Map<String, dynamic> response, {
  required String localDate,
}) {
  final emergency = response['emergency'] == true;
  final finished = readFinishedCheckin(response, localDate: localDate);
  final kind = finished?.record.kind;
  if (finished == null || (kind != 'quick' && kind != 'daily' && kind != 'weekly')) {
    return CheckinOutcome(profile: profile, changedFields: const [], emergency: emergency);
  }
  final record = finished.record;
  // Daily and quick check-ins never touch the profile, even with a profile_update.
  if (kind != 'weekly') {
    return CheckinOutcome(
      profile: profile,
      changedFields: const [],
      emergency: emergency,
      record: record,
      dayLogParts: kind == 'quick' ? _checkedParts(response, localDate) : const [],
    );
  }
  final update = Map<String, dynamic>.from(response['profile_update'] as Map? ?? const {});
  final merge = mergeConfirmed(profile, update);
  final summaries = const DailyLogsAssembler().weeklySummaries([record]);
  return CheckinOutcome(
    profile: merge.profile,
    changedFields: merge.changed,
    refusedFields: merge.refused,
    emergency: emergency,
    record: record,
    weeklySummary: summaries.isEmpty ? null : summaries.single,
  );
}

/// The quick check-in's `daily_logs` parts with every value type- and range-checked;
/// a refused value is left unknown. A quick check-in describes only its own day and the
/// day before ([localDate] and the day before it); a part for any other date is refused.
List<DayLog> _checkedParts(Map<String, dynamic> response, String localDate) => [
  for (final row in response['daily_logs'] as List? ?? const [])
    if (row is Map && (row['date'] == localDate || row['date'] == shiftDay(localDate, -1)))
      DayLog.fromJson({
        'date': row['date'],
        for (final e in dayLogSchema.entries)
          if (row[e.key] != null && e.value(row[e.key] as Object)) e.key: row[e.key],
      }),
]..removeWhere((d) => d.empty);
