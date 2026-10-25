import 'package:flutter/foundation.dart';

import '../twin/twin_repository.dart';
import 'band_data.dart';
import 'band_sitting.dart';

/// The field the band suggests, in the person's own words: "Moderate, like brisk walks".
const bandField = 'moderate_recreation_min_week';
const bandFieldLabel = 'Moderate, like brisk walks';
const bandSittingField = 'sedentary_min_day';

/// An observed day's awake sitting, offered as a usual-day answer only after
/// explicit read-back. This is independent of the existing activity suggestion.
class BandSittingSuggestion {
  const BandSittingSuggestion._({
    required this.estimate,
    required this.current,
    required this.date,
    required this.awakeMinutes,
    required this.demo,
  });
  final int estimate;
  final num? current;
  final DateTime date;
  final int awakeMinutes;
  final bool demo;
  static const demoLabel = 'Demo data';
  String get sourceLabel => demo ? demoLabel : 'From your band';
  String get question =>
      '${demo ? '$demoLabel. ' : ''}The recording counted $estimate minutes sitting while awake '
      'on ${date.toIso8601String().substring(0, 10)}. '
      'Is that typical for you? Save $estimate minutes as your usual daily sitting?';
  static const how =
      'Counts only explicitly classified sitting while awake in a complete waking-day recording. '
      'Sleep, lying, unknown posture and missing wear are not assumed to be sitting. '
      'A sensor estimate; one day does not establish your usual day.';
}

/// What the band offers once a week (H-6, H-7, H-7v).
class BandSuggestion {
  const BandSuggestion({
    required this.estimate,
    required this.current,
    required this.validDays,
    required this.validMinutes,
    this.demo = false,
  });

  /// The band's estimate, minutes a week (rounded to 10).
  final int estimate;

  /// The person's saved answer, minutes a week.
  final num current;
  final int validDays;
  final int validMinutes;

  /// From the recorded demo, not measured: labelled "Demo data" everywhere, and still needs the person's yes.
  final bool demo;

  static const demoLabel = 'Demo data';

  bool get lower => estimate < current;

  /// "Moderate, like brisk walks: about 40 minutes a week, instead of 30. Right?"
  String get question => lower
      ? 'Your band saw less this week. Keep ${current.round()}, or use about $estimate?'
      : '$bandFieldLabel: about $estimate minutes a week, instead of ${current.round()}. Right?';

  /// The "How?" sheet.
  static const how =
      'Includes brisk and harder moves. The band counts minutes of moderate-to-vigorous movement on days worn 10+ hours, '
      'then scales them to 7 days. It’s a sensor estimate.';
}

/// The band's one weekly suggestion and the only way it reaches a saved answer.
///
/// - Offered at most once a week, only from live band data (never the recorded demo), and only with 4 or
///   more valid days (worn 10+ hours) in the last 7.
/// - Nothing is saved by showing it. "Use this" opens a read-back; only the person's "Yes, save" (or "Use
///   about N") writes the answer, as `moderate_recreation_min_week`, with the wristband source
///   (`repository.provenance`: "From your band", an estimate). A confirmed band estimate IS the person's answer and may change the outlook (owner
///   ruling). It goes through `TwinRepository.saveConversationProfile` like any confirmed answer.
/// - "Not now" dismisses it until next week. A band answer is never sent to an outside AI provider.
class BandService extends ChangeNotifier {
  BandService({required this.repository, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final TwinRepository repository;
  final DateTime Function() _now;

  DateTime? _dismissedAt;
  DateTime? _offeredAt;
  DateTime? _sittingDismissedAt;
  DateTime? _sittingAcceptedAt;

  /// Measured data needs [live]; the built-in labelled demo additionally needs
  /// an explicit [demo] opt-in. Imported v0 files cannot supply this recording.
  /// Showing an offer never changes the confirmed profile or model.
  BandSittingSuggestion? suggestSitting(
    BandSittingRecording recording, {
    required bool live,
    bool demo = false,
  }) {
    if (recording.demo ? (!demo || live) : (!live || demo)) return null;
    final estimate = recording.sittingMinutesPerDay;
    // Existing shared profile entry range, not a physiological threshold.
    if (estimate == null || estimate > 1439) return null;
    if (_inCooldown(_sittingDismissedAt) || _inCooldown(_sittingAcceptedAt)) {
      return null;
    }
    final saved = repository.profile[bandSittingField];
    final current = saved is num && saved.isFinite ? saved : null;
    if (estimate == current) return null;
    return BandSittingSuggestion._(
      estimate: estimate,
      current: current,
      date: recording.date,
      awakeMinutes: recording.awakeMinutes,
      demo: recording.demo,
    );
  }

  /// Uses the existing seven-day band offer cooldown, independently of activity.
  void dismissSitting() => _sittingDismissedAt = _now();
  void keepSitting() => dismissSitting();

  /// Call only after the person confirms the dated count as their usual day.
  /// A replacement number explicitly supplied by the person has Mochi provenance.
  Future<void> confirmSitting(
    BandSittingSuggestion suggestion, {
    int? minutes,
  }) async {
    final value = minutes ?? suggestion.estimate;
    if (value < 0 || value > 1439) {
      throw const BandSittingFailure(
        'Daily sitting must be between 0 and 1439 minutes.',
      );
    }
    if (repository.profile[bandSittingField] != suggestion.current) {
      throw const BandSittingFailure(
        'Your saved sitting changed. Review a new suggestion.',
      );
    }
    await repository.saveConversationProfile(
      {bandSittingField: value},
      kind: HistoryKind.mochiChange,
      sources: {if (minutes == null) bandSittingField: HistorySource.wristband},
    );
    _sittingAcceptedAt = _now();
  }

  /// Minutes a week the person last saved through the band offer, for the panel's saved line.
  int? savedMinutes;

  /// The suggestion for [week], or null. [live] is false for the recorded demo; [demo] allows ONE labelled
  /// suggestion from it (only when nothing live or imported is in play).
  BandSuggestion? suggest(
    BandWeek week, {
    required bool live,
    bool demo = false,
  }) {
    if (!(live || demo) || !week.hasEstimate) return null;
    final saved = repository.profile[bandField];
    if (saved is! num) return null;
    if (_inCooldown(_dismissedAt) ||
        _inCooldown(_offeredAt, acceptedOnly: true)) {
      return null;
    }
    final est = week.estimateMinutesPerWeek!;
    if (est == saved.round()) return null;
    return BandSuggestion(
      estimate: est,
      current: saved,
      validDays: week.validCount,
      validMinutes: week.validModerate,
      demo: !live,
    );
  }

  bool _inCooldown(DateTime? at, {bool acceptedOnly = false}) {
    if (at == null) return false;
    return _now().difference(at) < const Duration(days: 7);
  }

  /// "Not now": nothing saved, the offer returns next week.
  void dismiss() {
    _dismissedAt = _now();
    notifyListeners();
  }

  /// "Yes, save" / "Use about N" with the estimate (or a number the person gave Mochi instead).
  Future<void> confirm(BandSuggestion s, {int? minutes}) async {
    final value = minutes ?? s.estimate;
    // The band's number is saved with the wristband source ("From your band", an estimate). A number the
    // person gave Mochi instead is simply their own answer.
    await repository.saveConversationProfile(
      {bandField: value},
      kind: HistoryKind.mochiChange,
      sources: {if (minutes == null) bandField: HistorySource.wristband},
    );
    _offeredAt = _now();
    savedMinutes = value;
    notifyListeners();
  }

  /// "Keep 30" (the lower variant): nothing changes; the offer returns next week.
  void keep() => dismiss();
}
