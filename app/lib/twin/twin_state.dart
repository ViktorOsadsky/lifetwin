import '../ui/twin_assets.dart';
import 'twin_history.dart';
import 'twin_model.dart';

/// The twin's mood. There is no sad mood: the bear never looks sad because of a
/// diagnosis, a number or a missed habit. Diagnoses are not read here at all.
enum TwinMood {
  /// Active recently, or feeling good.
  cheerful,

  /// Nothing to react to.
  content,

  /// The model sees something to explore (`avatar.opportunities`).
  curious,

  /// Short sleep recently.
  sleepy,

  /// The person is not feeling great: the twin sits with them.
  cozy,

  /// An emergency reply: calm and attentive, beside the "Call 911" button.
  concerned,
}

/// What made the state, for the UI's copy.
enum TwinStateReason { emergency, notFeelingGreat, shortSleep, active, feelingGood, exploring, needsInput, steady }

/// The character's state, derived from the model's avatar, the latest check-in wellbeing,
/// recent sleep and activity, and the check-in emergency flag. Poses are the existing
/// sprites (assets/twin/, twin_assets.dart); `dizzy` and `shrug` are never used here.
class TwinState {
  const TwinState({
    required this.mood,
    required this.pose,
    required this.reason,
    this.wellbeing,
    this.recentSleepHours,
    this.recentActiveMinutes,
    this.strengths = const [],
    this.opportunities = const [],
    this.emergency = false,
  });

  final TwinMood mood;
  final TwinPose pose;
  final TwinStateReason reason;

  /// `good`, `okay` or `not_great`, from the latest recent check-in.
  final String? wellbeing;
  final double? recentSleepHours;
  final int? recentActiveMinutes;

  /// The package's `avatar.strengths` / `avatar.opportunities` (wellness card ids).
  final List<String> strengths;
  final List<String> opportunities;
  final bool emergency;

  static const _poses = {
    TwinMood.concerned: TwinPose.stand,
    TwinMood.cozy: TwinPose.sit,
    TwinMood.sleepy: TwinPose.stretch,
    TwinMood.curious: TwinPose.think,
  };

  /// Priority: emergency, not feeling great, short sleep, active, feeling good, something
  /// to explore, answers still needed, steady.
  static TwinState derive({
    TwinAssessment? assessment,
    List<CheckinEntry> checkins = const [],
    DayLog? today,
    bool emergency = false,
    DateTime? now,
  }) {
    final day = dayOf(now ?? DateTime.now());
    final strengths = assessment?.strengths ?? const <String>[];
    final opportunities = assessment?.opportunities ?? const <String>[];
    // Daily answers count for two days, weekly ones for eight.
    final recent = [
      for (final c in checkins)
        if (_age(c, day) case final days? when days >= 0 && days <= (c.kind == 'weekly' ? 7 : 1)) c,
    ]..sort((a, b) => b.date.compareTo(a.date));
    final wellbeing = recent.map((c) => c.wellbeing).nonNulls.firstOrNull;
    final sleep = recent
        .map((c) => (c.answers['sleep_hours_last_night'] ?? c.answers['sleep_hours']) as num?)
        .nonNulls
        .firstOrNull
        ?.toDouble();
    // Today's activity: a quick check-in's day row (both paces known), else a daily one's.
    final logged = today != null && today.activityKnown ? today.vigorousMin! + today.moderateMin! : null;
    final active =
        logged ??
        recent
            .where((c) => c.kind == 'daily' && _age(c, day) == 0)
            .map((c) => c.answers['exercise_minutes_today'] as num?)
            .nonNulls
            .firstOrNull
            ?.toInt();

    TwinState make(TwinMood mood, TwinStateReason reason, [TwinPose? pose]) => TwinState(
      mood: mood,
      pose: pose ?? _poses[mood] ?? TwinPose.stand,
      reason: reason,
      wellbeing: wellbeing,
      recentSleepHours: sleep,
      recentActiveMinutes: active,
      strengths: strengths,
      opportunities: opportunities,
      emergency: emergency,
    );

    if (emergency) return make(TwinMood.concerned, TwinStateReason.emergency);
    if (wellbeing == 'not_great') return make(TwinMood.cozy, TwinStateReason.notFeelingGreat);
    if (sleep != null && sleep < 6) return make(TwinMood.sleepy, TwinStateReason.shortSleep);
    if (active != null && active >= 30) return make(TwinMood.cheerful, TwinStateReason.active, TwinPose.jump);
    if (wellbeing == 'good') return make(TwinMood.cheerful, TwinStateReason.feelingGood, TwinPose.wave);
    if (assessment == null || assessment.wellnessState == 'needs_input') {
      return make(TwinMood.content, TwinStateReason.needsInput, TwinPose.wave);
    }
    if (opportunities.isNotEmpty) return make(TwinMood.curious, TwinStateReason.exploring);
    return make(TwinMood.content, TwinStateReason.steady);
  }

  static int? _age(CheckinEntry c, DateTime today) {
    final d = DateTime.tryParse(c.date);
    return d == null ? null : today.difference(dayOf(d)).inDays;
  }
}
