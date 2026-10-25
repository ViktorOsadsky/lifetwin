import 'band_data.dart';

/// Safe rejection text: no accelerometer samples or recorded values in errors.
class BandSittingFailure implements Exception {
  const BandSittingFailure(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// A transient raw input, in gravitational units, never retained in BandStore.
class BandAccelerationSample {
  const BandAccelerationSample({
    required this.at,
    required this.xG,
    required this.yG,
    required this.zG,
  });
  final DateTime at;
  final double xG;
  final double yG;
  final double zG;
}

/// Ephemeral features for a hardware-owned, placement-calibrated classifier.
/// No angle threshold, axis convention or sleep classifier is supplied here.
class BandAccelerationSummary {
  const BandAccelerationSummary._(
    this.samples,
    this.meanXG,
    this.meanYG,
    this.meanZG,
    this.meanSquaredMagnitudeG2,
  );
  final int samples;
  final double meanXG;
  final double meanYG;
  final double meanZG;
  final double meanSquaredMagnitudeG2;
}

typedef BandPostureClassifier = BandPosture Function(BandAccelerationSummary);

/// Engineering capacity, not a sampling-rate or physiological threshold.
const bandMaxSamplesPerMinute = 12000;

/// Consume raw input once, retaining only a classified minute. The caller owns
/// acquisition/disposal of its source buffer. Neither raw samples nor features
/// enter the returned minute, store, logs, persistence or provider requests.
/// Without a supplied hardware classifier, posture remains unknown.
BandMinute processBandAccelerationMinute({
  required DateTime at,
  required Iterable<BandAccelerationSample> samples,
  BandPostureClassifier? classifyPosture,
  BandWakeState wakeState = BandWakeState.unknown,
  bool worn = true,
}) {
  _wholeMinute(at);
  var count = 0;
  var meanX = 0.0, meanY = 0.0, meanZ = 0.0, meanSquared = 0.0;
  final end = at.add(const Duration(minutes: 1));
  for (final sample in samples) {
    if (++count > bandMaxSamplesPerMinute) {
      throw const BandSittingFailure('Too many samples in one band minute.');
    }
    if (sample.at.isBefore(at) ||
        !sample.at.isBefore(end) ||
        !sample.xG.isFinite ||
        !sample.yG.isFinite ||
        !sample.zG.isFinite) {
      throw const BandSittingFailure('A band sample has invalid time or axes.');
    }
    final squared =
        sample.xG * sample.xG + sample.yG * sample.yG + sample.zG * sample.zG;
    if (!squared.isFinite) {
      throw const BandSittingFailure('A band sample has invalid axes.');
    }
    meanX += (sample.xG - meanX) / count;
    meanY += (sample.yG - meanY) / count;
    meanZ += (sample.zG - meanZ) / count;
    meanSquared += (squared - meanSquared) / count;
  }
  return BandMinute(
    at: at,
    worn: worn,
    wakeState: wakeState,
    posture: count == 0 || !worn || classifyPosture == null
        ? BandPosture.unknown
        : classifyPosture(
            BandAccelerationSummary._(count, meanX, meanY, meanZ, meanSquared),
          ),
  );
}

/// Aggregate of explicit posture/wake labels for one recorded calendar day.
/// It retains no minute list or raw samples. A complete waking day is an explicit
/// acquisition/diary assertion, never inferred from 10 hours of wear or low steps.
class BandSittingRecording {
  const BandSittingRecording._({
    required this.date,
    required this.recordedMinutes,
    required this.awakeMinutes,
    required this.observedSittingMinutes,
    required this.unknownMinutes,
    required this.completeWakingDay,
    required this.demo,
  });

  factory BandSittingRecording.fromMinutes({
    required DateTime date,
    required Iterable<BandMinute> minutes,
    bool completeWakingDay = false,
    bool demo = false,
  }) {
    var recorded = 0, awake = 0, sitting = 0, unknown = 0;
    final seen = <int>{};
    for (final minute in minutes) {
      if (++recorded > 1440) {
        throw const BandSittingFailure('A sitting recording exceeds one day.');
      }
      _wholeMinute(minute.at);
      if (minute.at.year != date.year ||
          minute.at.month != date.month ||
          minute.at.day != date.day ||
          !seen.add(minute.at.hour * 60 + minute.at.minute)) {
        throw const BandSittingFailure(
          'Use distinct minutes from one dated day.',
        );
      }
      if (minute.wakeState == BandWakeState.unknown) {
        unknown++;
      } else if (minute.wakeState == BandWakeState.awake) {
        awake++;
        if (!minute.worn ||
            minute.posture == BandPosture.unknown ||
            minute.posture == BandPosture.sittingOrLying) {
          unknown++;
        } else if (minute.posture == BandPosture.sitting) {
          sitting++;
        }
      }
    }
    return BandSittingRecording._(
      date: DateTime.utc(date.year, date.month, date.day),
      recordedMinutes: recorded,
      awakeMinutes: awake,
      observedSittingMinutes: sitting,
      unknownMinutes: unknown,
      completeWakingDay: completeWakingDay,
      demo: demo,
    );
  }

  final DateTime date;
  final int recordedMinutes;
  final int awakeMinutes;
  final int observedSittingMinutes;
  final int unknownMinutes;
  final bool completeWakingDay;
  final bool demo;

  /// No extrapolation or rounding. Zero is available only from a nonempty,
  /// complete waking-day recording with explicit known non-sitting postures.
  int? get sittingMinutesPerDay =>
      completeWakingDay && awakeMinutes > 0 && unknownMinutes == 0
      ? observedSittingMinutes
      : null;
}

void _wholeMinute(DateTime at) {
  if (at.second != 0 || at.millisecond != 0 || at.microsecond != 0) {
    throw const BandSittingFailure(
      'Band minute timestamps must be minute-aligned.',
    );
  }
}
