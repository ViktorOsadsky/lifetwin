import 'package:flutter/foundation.dart';

import '../twin/twin_repository.dart';
import 'band_data.dart';

/// The field the band suggests, in the person's own words: "Moderate, like brisk walks".
const bandField = 'moderate_recreation_min_week';
const bandFieldLabel = 'Moderate, like brisk walks';

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
  BandService({required this.repository, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final TwinRepository repository;
  final DateTime Function() _now;

  DateTime? _dismissedAt;
  DateTime? _offeredAt;

  /// Minutes a week the person last saved through the band offer, for the panel's saved line.
  int? savedMinutes;

  /// The suggestion for [week], or null. [live] is false for the recorded demo; [demo] allows ONE labelled
  /// suggestion from it (only when nothing live or imported is in play).
  BandSuggestion? suggest(BandWeek week, {required bool live, bool demo = false}) {
    if (!(live || demo) || !week.hasEstimate) return null;
    final saved = repository.profile[bandField];
    if (saved is! num) return null;
    if (_inCooldown(_dismissedAt) || _inCooldown(_offeredAt, acceptedOnly: true)) return null;
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
