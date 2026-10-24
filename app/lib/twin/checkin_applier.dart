/// Applies a finished check-in (`POST /api/checkin/turn`, contracts/checkin.schema.json on
/// branch codex/d-twin-checkins) to the phone's profile and history.
///
/// Contract: when `complete` is true and the check-in is weekly, the app sets each non-null
/// field of `profile_update` on the confirmed profile and reruns the forecast; null fields
/// are left as they are. Daily check-ins are history only.
library;

import 'twin_history.dart';
import 'twin_model.dart' show isoDate;

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
  final CheckinRecord? record;

  /// A weekly summary row in the package's shape, when the weekly answers covered all four
  /// behaviour fields; null otherwise (nothing is filled in).
  final Map<String, dynamic>? weeklySummary;
}

/// Reads one check-in response. [localDate] is the phone's date (the one sent as
/// `local_date` when the check-in started).
CheckinOutcome applyCheckinResponse(
  Map<String, dynamic> profile,
  Map<String, dynamic> response, {
  required DateTime localDate,
}) {
  final emergency = response['emergency'] == true;
  final state = response['state'] is Map ? Map<String, dynamic>.from(response['state'] as Map) : const {};
  final kind = state['kind'];
  if (response['complete'] != true || (kind != 'daily' && kind != 'weekly')) {
    return CheckinOutcome(profile: profile, changedFields: const [], emergency: emergency);
  }
  final confirmed = {
    for (final e in Map<String, dynamic>.from(state['confirmed'] as Map? ?? const {}).entries)
      if (e.value != null) e.key: e.value,
  };
  final record = CheckinRecord(kind: '$kind', date: isoDate(localDate), answers: confirmed);
  // Daily check-ins are history only: their profile_update is never applied.
  if (kind != 'weekly') {
    return CheckinOutcome(profile: profile, changedFields: const [], emergency: emergency, record: record);
  }
  final update = Map<String, dynamic>.from(response['profile_update'] as Map? ?? const {});
  final merge = mergeConfirmed(profile, update);
  Map<String, dynamic>? summary;
  if (weeklySummaryFields.every((f) => confirmed[f] is num)) {
    summary = {
      // The week the answers describe: the Monday–Sunday week that has ended by the end
      // of [localDate] (a Sunday check-in counts the week ending that day).
      'week_start': isoDate(latestCompletedMonday(localDate.add(const Duration(days: 1)))),
      for (final f in weeklySummaryFields) f: confirmed[f],
    };
  }
  return CheckinOutcome(
    profile: merge.profile,
    changedFields: merge.changed,
    refusedFields: merge.refused,
    emergency: emergency,
    record: record,
    weeklySummary: summary,
  );
}
