import 'health_sample.dart';
import 'workout_averages.dart';

/// Profile fields recognized at the Apple Health confirmation boundary.
/// Names match contracts/profile.schema.json; unavailable fields stay unanswered.
enum HealthField {
  heightCm,
  weightKg,
  exerciseMinutesWeekly,
  sleepHours,
  systolicBp,
  diastolicBp,
  vigorousRecreationMinWeek,
  moderateRecreationMinWeek,
  sedentaryMinDay,
}

extension HealthFieldName on HealthField {
  String get profileKey => switch (this) {
    HealthField.heightCm => 'height_cm',
    HealthField.weightKg => 'weight_kg',
    HealthField.exerciseMinutesWeekly => 'exercise_minutes_weekly',
    HealthField.sleepHours => 'sleep_hours',
    HealthField.systolicBp => 'systolic_bp',
    HealthField.diastolicBp => 'diastolic_bp',
    HealthField.vigorousRecreationMinWeek => 'vigorous_recreation_min_week',
    HealthField.moderateRecreationMinWeek => 'moderate_recreation_min_week',
    HealthField.sedentaryMinDay => 'sedentary_min_day',
  };
}

/// A suggested answer the user must confirm. Provenance lives here, on the phone only.
class HealthCandidate {
  const HealthCandidate({
    required this.field,
    required this.value,
    required this.basis,
    this.measuredAt,
    this.periodDays,
    this.isEstimate = false,
  });

  final HealthField field;

  /// Metric value in the profile schema's unit.
  final num value;

  /// Plain description of how the value was worked out, for the confirm screen.
  final String basis;

  /// For single readings (height, weight): when it was measured.
  final DateTime? measuredAt;

  /// For averages (exercise, sleep, blood pressure): how many days were looked at.
  final int? periodDays;

  /// Native mean-MET grouping estimates entire workouts, not measured zone time.
  final bool isEstimate;

  static const source = 'apple_health';
}

const sleepTypes = {'SLEEP_ASLEEP', 'SLEEP_LIGHT', 'SLEEP_DEEP', 'SLEEP_REM'};

/// The model asks about recreational activity and awake sitting, rather than
/// total movement. These fields need their own evidence; no missing value is 0.
const modelActivityFields = {
  HealthField.vigorousRecreationMinWeek,
  HealthField.moderateRecreationMinWeek,
  HealthField.sedentaryMinDay,
};
const modelActivityWindowDays = 28;

enum HealthActivityUnavailableReason {
  /// Nothing recent was returned. iOS does not distinguish no data from denial.
  noData,

  /// Exercise totals, workout names and heart rate cannot establish both the
  /// recreational context and minutes at the model's requested intensity.
  recreationAndIntensityNotEstablished,

  /// Stand hours count hours with at least one minute standing, not sitting
  /// duration. Even actual standing duration leaves sleep/non-wear unknown.
  awakeSittingNotMeasured,

  /// A native read failed, was unsupported, timed out or failed strict parsing.
  nativeEstimateUnavailable,

  /// Bounded native query returned too many workouts to produce an estimate.
  workoutQueryTruncated,

  /// No usable workout mean-MET estimate exists for this intensity bucket.
  noQualifyingWorkoutEstimate,
}

/// On-phone availability details for the import's confirmation/conversation
/// boundary. This object has no raw samples or network serialization.
class HealthSummary {
  HealthSummary({
    required List<HealthCandidate> candidates,
    required Map<HealthField, HealthActivityUnavailableReason> unavailableActivity,
  }) : candidates = List.unmodifiable(candidates),
       unavailableActivity = Map.unmodifiable(unavailableActivity);

  final List<HealthCandidate> candidates;
  final Map<HealthField, HealthActivityUnavailableReason> unavailableActivity;
}

/// Adds native whole-workout mean-MET estimates only after strict parsing. They
/// remain suggestions pending explicit recreational/context confirmation, never
/// measured minutes in zones. Generic samples never infer either bucket/sitting.
HealthSummary summarizeWithAvailability(
  List<HealthSample> samples,
  DateTime now, {
  WorkoutAverages? workoutAverages,
  bool workoutEstimateUnavailable = false,
}) {
  final recentActivity = samples.where(
    (s) =>
        const {
          'EXERCISE_TIME',
          'WORKOUT',
          'HEART_RATE',
          'ACTIVITY_INTENSITY',
          'APPLE_STAND_HOUR',
          'APPLE_STAND_TIME',
          'STEPS',
        }.contains(s.type) &&
        _within(s, now, modelActivityWindowDays) &&
        !s.start.isAfter(s.end) &&
        (s.value == null || s.value!.isFinite),
  );
  final hasActivity = recentActivity.isNotEmpty;
  final hasExercise = recentActivity.any(
    (s) => const {'EXERCISE_TIME', 'WORKOUT', 'HEART_RATE', 'ACTIVITY_INTENSITY'}.contains(s.type),
  );
  final candidates = summarize(samples, now);
  final unavailable = {
    HealthField.vigorousRecreationMinWeek: hasExercise
        ? HealthActivityUnavailableReason.recreationAndIntensityNotEstablished
        : HealthActivityUnavailableReason.noData,
    HealthField.moderateRecreationMinWeek: hasExercise
        ? HealthActivityUnavailableReason.recreationAndIntensityNotEstablished
        : HealthActivityUnavailableReason.noData,
    HealthField.sedentaryMinDay: hasActivity
        ? HealthActivityUnavailableReason.awakeSittingNotMeasured
        : HealthActivityUnavailableReason.noData,
  };
  if (workoutAverages?.hasReturnedWorkouts == true || workoutAverages?.truncated == true) {
    unavailable[HealthField.sedentaryMinDay] = HealthActivityUnavailableReason.awakeSittingNotMeasured;
  }
  for (final (field, minutes) in [
    (HealthField.moderateRecreationMinWeek, workoutAverages?.moderateWeeklyMinutes),
    (HealthField.vigorousRecreationMinWeek, workoutAverages?.vigorousWeeklyMinutes),
  ]) {
    if (workoutEstimateUnavailable) {
      unavailable[field] = HealthActivityUnavailableReason.nativeEstimateUnavailable;
    } else if (workoutAverages?.truncated == true) {
      unavailable[field] = HealthActivityUnavailableReason.workoutQueryTruncated;
    } else if (workoutAverages != null) {
      // The profile accepts whole minutes. A sub-minute average that rounds to
      // zero stays unanswered; an absent intensity is never a healthy zero.
      if (minutes != null && minutes.round() > 0) {
        candidates.add(
          HealthCandidate(
            field: field,
            value: minutes.round(),
            basis: WorkoutAverages.method,
            periodDays: modelActivityWindowDays,
            isEstimate: true,
          ),
        );
        unavailable.remove(field);
      } else {
        unavailable[field] = workoutAverages.hasReturnedWorkouts
            ? HealthActivityUnavailableReason.noQualifyingWorkoutEstimate
            : HealthActivityUnavailableReason.noData;
      }
    }
  }
  return HealthSummary(candidates: candidates, unavailableActivity: unavailable);
}

/// Turns raw samples into at most one candidate per field.
///
/// Rules (issue #6): exercise = weekly average over the last 28 days; sleep =
/// typical (median) night over the last 14 nights; height/weight = latest
/// reading within a year; blood pressure = average of the last 3 readings
/// within 90 days. Anything older produces no candidate, so the mascot asks.
List<HealthCandidate> summarize(List<HealthSample> samples, DateTime now) {
  final out = _summarize(samples, now);
  // A reading outside everyday human ranges is a unit or entry mistake: drop it,
  // so the mascot asks instead of offering (or the server rejecting) a wrong value.
  out.removeWhere((c) {
    final (lo, hi) = plausibleRange[c.field]!;
    return c.value < lo || c.value > hi;
  });
  final sys = out.where((c) => c.field == HealthField.systolicBp).firstOrNull;
  final dia = out.where((c) => c.field == HealthField.diastolicBp).firstOrNull;
  if (sys != null && dia != null && sys.value <= dia.value) {
    out.removeWhere((c) => c.field == HealthField.systolicBp || c.field == HealthField.diastolicBp);
  }
  return out;
}

/// Everyday ranges, all inside the server's validation limits.
const plausibleRange = <HealthField, (num, num)>{
  HealthField.heightCm: (100, 250),
  HealthField.weightKg: (25, 300),
  HealthField.exerciseMinutesWeekly: (0, 3000),
  HealthField.sleepHours: (2, 14),
  HealthField.systolicBp: (70, 250),
  HealthField.diastolicBp: (40, 150),
  HealthField.vigorousRecreationMinWeek: (0, 10080),
  HealthField.moderateRecreationMinWeek: (0, 10080),
  HealthField.sedentaryMinDay: (0, 1439),
};

List<HealthCandidate> _summarize(List<HealthSample> samples, DateTime now) {
  final out = <HealthCandidate>[];

  final height = _latest(samples, 'HEIGHT', now, 365);
  if (height != null) {
    out.add(
      HealthCandidate(
        field: HealthField.heightCm,
        value: _round1(height.value! * 100),
        basis: 'latest reading',
        measuredAt: height.end,
      ),
    );
  }
  final weight = _latest(samples, 'WEIGHT', now, 365);
  if (weight != null) {
    out.add(
      HealthCandidate(
        field: HealthField.weightKg,
        value: _round1(weight.value!),
        basis: 'latest reading',
        measuredAt: weight.end,
      ),
    );
  }

  final exercise = _unionMinutes(samples.where((s) => s.type == 'EXERCISE_TIME' && _within(s, now, 28)));
  if (exercise > 0) {
    out.add(
      HealthCandidate(
        field: HealthField.exerciseMinutesWeekly,
        value: (exercise / 4).round(),
        basis: 'weekly average',
        periodDays: 28,
      ),
    );
  }

  final nights = _sleepMinutesByNight(samples.where((s) => sleepTypes.contains(s.type) && _within(s, now, 14)));
  if (nights.length >= 3) {
    out.add(
      HealthCandidate(
        field: HealthField.sleepHours,
        value: _round1(_median(nights) / 60),
        basis: 'typical night',
        periodDays: 14,
      ),
    );
  }

  for (final (type, field) in [
    ('BLOOD_PRESSURE_SYSTOLIC', HealthField.systolicBp),
    ('BLOOD_PRESSURE_DIASTOLIC', HealthField.diastolicBp),
  ]) {
    final readings = samples.where((s) => s.type == type && s.value != null && _within(s, now, 90)).toList()
      ..sort((a, b) => b.end.compareTo(a.end));
    if (readings.isNotEmpty) {
      final last = readings.take(3).toList();
      final avg = last.map((s) => s.value!).reduce((a, b) => a + b) / last.length;
      out.add(HealthCandidate(field: field, value: avg.round(), basis: 'average of ${last.length}', periodDays: 90));
    }
  }
  return out;
}

bool _within(HealthSample s, DateTime now, int days) =>
    !s.end.isAfter(now) && now.difference(s.end) <= Duration(days: days);

HealthSample? _latest(List<HealthSample> samples, String type, DateTime now, int days) {
  HealthSample? best;
  for (final s in samples) {
    if (s.type == type && s.value != null && _within(s, now, days) && (best == null || s.end.isAfter(best.end))) {
      best = s;
    }
  }
  return best;
}

/// Total minutes covered, counting overlapping samples (iPhone + Watch) once.
double _unionMinutes(Iterable<HealthSample> samples) {
  final sorted = samples.where((s) => s.end.isAfter(s.start)).toList()..sort((a, b) => a.start.compareTo(b.start));
  var total = Duration.zero;
  DateTime? runStart, runEnd;
  for (final s in sorted) {
    if (runEnd == null || s.start.isAfter(runEnd)) {
      if (runEnd != null) total += runEnd.difference(runStart!);
      runStart = s.start;
      runEnd = s.end;
    } else if (s.end.isAfter(runEnd)) {
      runEnd = s.end;
    }
  }
  if (runEnd != null) total += runEnd.difference(runStart!);
  return total.inSeconds / 60;
}

/// Groups asleep time by night. A night is labelled by the date 12 hours after
/// it starts, so 11 pm and 2 am belong to the same night.
List<double> _sleepMinutesByNight(Iterable<HealthSample> samples) {
  final byNight = <String, List<HealthSample>>{};
  for (final s in samples) {
    final d = s.start.toLocal().add(const Duration(hours: 12));
    byNight.putIfAbsent('${d.year}-${d.month}-${d.day}', () => []).add(s);
  }
  return [for (final night in byNight.values) _unionMinutes(night)];
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _round1(num x) => (x * 10).round() / 10;

/// Minutes covered by [samples], counting overlaps (iPhone and Watch) once.
double coveredMinutes(Iterable<HealthSample> samples) => _unionMinutes(samples);
