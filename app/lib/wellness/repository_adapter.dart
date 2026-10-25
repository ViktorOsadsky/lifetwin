import 'package:flutter/foundation.dart';

import '../twin/twin_repository.dart';
import 'models.dart';

/// Read-only presentation boundary. Health values, provenance, corrections, good
/// weeks and the health score stay owned by TwinRepository. No score is derived here.
class RepositoryWellness extends ChangeNotifier {
  RepositoryWellness(this.repository) {
    repository.addListener(_changed);
  }
  final TwinRepository repository;
  void _changed() => notifyListeners();

  /// The repository's own score values; nothing is computed here.
  WellnessSnapshot get snapshot => WellnessSnapshot(
    healthScore: repository.healthScore,
    status: repository.healthScoreStatus,
    ageGroupPercentile: repository.ageGroupPercentile,
    message: repository.healthScoreMessage,
    lifespan: _lifespan(repository.lifespanEstimate),
    lifespanRevealSeen: repository.lifespanRevealSeen,
  );

  static LifespanReveal? _lifespan(LifespanEstimate? e) => e == null
      ? null
      : LifespanReveal(
          expectedAge: _round(e.expectedAge),
          p25Age: _round(e.p25Age),
          p75Age: _round(e.p75Age),
          expectedYear: e.expectedYear,
          caveat: e.caveat,
          roughGuide: e.status == LifespanStatus.extrapolated,
        );

  static int _round(double x) => x.round();

  /// The reveal after onboarding was shown; the estimate then appears only on "See your estimate".
  void markLifespanRevealSeen() => repository.markLifespanRevealSeen().ignore();

  List<WellnessDay> historyDays({DateTime? from, DateTime? to}) {
    final byDay = <DateTime, List<HistoryValue>>{};
    for (final entry in repository.history(from: from, to: to)) {
      final values = byDay.putIfAbsent(localDay(entry.at), () => []);
      for (final item in entry.items) {
        values.add(
          HistoryValue(
            label: item.label,
            value: item.text,
            source: ValueSource.fromWire(item.source),
            estimated: item.estimated,
            previousValue: item.isChange ? item.oldText : null,
            forDay: item.date == null ? null : DateTime.tryParse(item.date!),
            recordedAt: entry.time,
            status: entry.corrected
                ? 'Later corrected'
                : entry.fedForecast != null
                ? 'Used for your outlook'
                : null,
          ),
        );
      }
    }
    return [
      for (final day in byDay.entries)
        WellnessDay(date: day.key, values: day.value),
    ];
  }

  WellnessSettings settingsFor({String? providerId}) => WellnessSettings(
    reminderMinutes:
        repository.checkinSettings.reminderHour * 60 +
        repository.checkinSettings.reminderMinute,
    memoryConsent: repository.store.memoryConsent,
    personalSuggestions:
        providerId != null &&
        repository.outsideAiConsentFor(providerId)[providerId] == true,
  );

  @override
  void dispose() {
    repository.removeListener(_changed);
    super.dispose();
  }
}
