/// Applies a finished check-in (`POST /api/checkin/turn`, contracts/checkin.schema.json on
/// branch codex/d-twin-checkins) to the phone's profile and history.
///
/// Contract: when `complete` is true and the check-in is weekly, the app sets each non-null
/// field of `profile_update` on the confirmed profile and reruns the forecast; null fields
/// are left as they are. Daily check-ins are history only.
library;

import 'twin_history.dart';
import 'twin_model.dart' show isoDate;

/// Profile fields a weekly `profile_update` may set: the contract's HealthProfile fields,
/// and the model inputs the conversation is gaining (same names as the package).
const updatableProfileFields = {
  'age',
  'sex',
  'height_cm',
  'weight_kg',
  'sleep_hours',
  'exercise_minutes_weekly',
  'smoking_status',
  'alcohol_drinks_weekly',
  'diabetes',
  'systolic_bp',
  'diastolic_bp',
  'general_health',
  'hypertension_diagnosed',
  'sedentary_min_day',
  'vigorous_recreation_min_week',
  'moderate_recreation_min_week',
};

class CheckinOutcome {
  const CheckinOutcome({
    required this.profile,
    required this.changedFields,
    required this.emergency,
    this.record,
    this.weeklySummary,
  });

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
  if (kind != 'weekly') {
    return CheckinOutcome(profile: profile, changedFields: const [], emergency: emergency, record: record);
  }
  final update = Map<String, dynamic>.from(response['profile_update'] as Map? ?? const {});
  final next = Map<String, dynamic>.from(profile);
  final changed = <String>[];
  for (final e in update.entries) {
    if (e.value == null || !updatableProfileFields.contains(e.key)) continue;
    if (next[e.key] != e.value) changed.add(e.key);
    next[e.key] = e.value;
  }
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
    profile: next,
    changedFields: changed,
    emergency: emergency,
    record: record,
    weeklySummary: summary,
  );
}
