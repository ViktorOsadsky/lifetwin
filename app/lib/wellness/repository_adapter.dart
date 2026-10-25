import 'package:flutter/foundation.dart';

import '../twin/twin_repository.dart';
import 'models.dart';

/// Read-only presentation boundary. Health values, provenance, corrections and
/// good weeks stay owned by TwinRepository. No score is derived here.
class RepositoryWellness extends ChangeNotifier {
  RepositoryWellness(this.repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    repository.addListener(_changed);
  }
  final TwinRepository repository;
  final DateTime Function() _now;
  void _changed() => notifyListeners();

  WellnessSnapshot get snapshot {
    final today = localDay(_now());
    final from = DateTime(today.year, today.month, today.day - 6);
    final entries = repository.history(from: from, to: today);
    final checked = {
      for (final e in entries)
        if (HistoryKind.checkins.contains(e.kind)) localDay(e.at),
    };
    final days = repository.dayLogs(from: from, to: today);
    return WellnessSnapshot(
      goodWeeks: repository.goodWeeks(),
      days: [
        for (final row in days)
          WellnessDay(
            date: DateTime.parse(row.date),
            logged: checked.contains(DateTime.parse(row.date)),
            values: [
              for (final field in [
                'sleep_hours',
                'vigorous_recreation_min',
                'moderate_recreation_min',
                'sedentary_min_day',
              ])
                if (row.valueOf(field) case final value?)
                  _dayValue(field, value, row.date),
            ],
          ),
      ],
    );
  }

  HistoryValue _dayValue(String field, num value, String date) {
    HistoryItem? provenance;
    // Find the newest confirmation of this day's field, including a correction
    // confirmed later than the displayed calendar window.
    for (final entry in repository.history()) {
      for (final item in entry.items) {
        if (item.field == field && item.date == date && item.value == value) {
          provenance = item;
          break;
        }
      }
      if (provenance != null) break;
    }
    return HistoryValue(
      label: fieldLabel(field, day: true),
      value: valueText(field, value, day: true),
      source: ValueSource.fromWire(provenance?.source),
      estimated: provenance?.estimated ?? false,
    );
  }

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
