import 'dart:convert';

import '../twin/twin_repository.dart';

/// Read-only bridge to the stateless coach. No game state or experiment enters
/// this request, and wristband-derived profile values stay on the phone.
Map<String, dynamic> coachContext(TwinRepository repo, {DateTime? now}) {
  final time = now ?? DateTime.now();
  final today = DateTime(time.year, time.month, time.day);
  final date = today.toIso8601String().substring(0, 10);
  final days = repo.dayLogs(
    from: today.subtract(const Duration(days: 27)),
    to: today,
  );
  final wellbeing = <String, String>{};
  for (final entry in repo.history()) {
    for (final item in entry.items) {
      final when = item.date ?? entry.date;
      if (item.field == 'wellbeing' &&
          ['good', 'okay', 'not_great'].contains(item.value) &&
          item.source != HistorySource.wristband &&
          when.compareTo(date) <= 0) {
        wellbeing.putIfAbsent(when, () => item.value as String);
      }
    }
  }
  final readings = <Map<String, dynamic>>[];
  for (final entry in repo.readings()) {
    for (final item in entry.items) {
      if (!['systolic_bp', 'diastolic_bp'].contains(item.field) ||
          item.value is! num) {
        continue;
      }
      final when = item.date ?? entry.date;
      if (when.compareTo(date) > 0 || item.source == HistorySource.wristband) {
        continue;
      }
      readings.add({
        'field': item.field,
        'value': item.value,
        'unit': 'mmHg',
        'date': when,
        'source': switch (item.source) {
          HistorySource.document => 'document',
          HistorySource.appleHealth => 'apple_health',
          _ => 'checkin',
        },
      });
    }
  }
  // Long-term context from health documents (owner ruling 2026-10-25): kept on the phone
  // with no expiry until Delete my data, and sent only with memory consent, like habit
  // notes. Informational: never a model input.
  final documentContext = repo.store.memoryConsent ? _documentContext(repo, date) : null;
  const noteKeys = {
    'topic',
    'kind',
    'with',
    'time_of_day',
    'frequency',
    'barrier',
    'bedtime',
    'wake_time',
    'wakes_for',
    'naps',
    'smoked_years',
    'tried_quitting',
    'quit_aid',
    'quit_ago',
    'feeling',
    'concern',
    'reading',
    'estimate_for',
    'estimate',
    'source',
    'name',
  };
  final notes = <Map<String, dynamic>>[];
  if (repo.store.memoryConsent) {
    for (final row in repo.store.habitNotes) {
      if (row['note'] is! Map) continue;
      final note = Map<String, dynamic>.from(row['note'] as Map);
      // A stable local ID; no user data appears in diagnostics or URLs.
      var hash = 0x811c9dc5;
      for (final byte in utf8.encode(jsonEncode(row))) {
        hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
      }
      final noted = DateTime.tryParse('${row['at']}');
      if (noted != null && noted.isAfter(time)) continue;
      notes.add({
        'id': 'note-${hash.toRadixString(16)}',
        for (final e in note.entries)
          if (noteKeys.contains(e.key)) e.key: e.value,
        if (noted != null) 'noted_on': noted.toIso8601String().substring(0, 10),
      });
    }
  }
  final provider = repo.outsideAiProvider;
  return {
    'profile': repo.outsideAiProfile(),
    'checkins': [
      for (final day in days)
        if ([
              day.sleepHours,
              day.moderateMin,
              day.vigorousMin,
              day.sedentaryMin,
            ].any((v) => v != null) ||
            wellbeing.containsKey(day.date))
          {
            'date': day.date,
            if (wellbeing[day.date] != null) 'wellbeing': wellbeing[day.date],
            if (day.sleepHours != null) 'sleep_hours': day.sleepHours,
            if (day.moderateMin != null)
              'moderate_recreation_min': day.moderateMin,
            if (day.vigorousMin != null)
              'vigorous_recreation_min': day.vigorousMin,
            if (day.sedentaryMin != null) 'sedentary_min_day': day.sedentaryMin,
          },
    ],
    'readings': readings
        .skip(readings.length > 60 ? readings.length - 60 : 0)
        .toList(),
    'memory_consent': repo.store.memoryConsent,
    'document_context': ?documentContext,
    if (repo.store.memoryConsent)
      'habit_notes': notes
          .skip(notes.length > 20 ? notes.length - 20 : 0)
          .toList(),
    'outside_ai_consent': provider == null
        ? <String, bool>{}
        : repo.outsideAiConsentFor(provider),
    'movement_paused': repo.twinState().emergency,
    'local_date': date,
    'local_time':
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
  };
}

/// Document readings (with date and unit) and diagnoses the person confirmed; null when
/// there are none. Dates after [today] are left out.
Map<String, dynamic>? _documentContext(TwinRepository repo, String today) {
  const readingFields = {
    'systolic_bp': ('systolic_bp', 'mmHg'),
    'diastolic_bp': ('diastolic_bp', 'mmHg'),
    'hba1c': ('a1c', '%'),
    'ldl_cholesterol': ('ldl', 'mg/dL'),
  };
  final readings = <Map<String, dynamic>>[];
  for (final entry in repo.readings().reversed) {
    for (final item in entry.items) {
      final field = readingFields[item.field];
      final when = item.date ?? entry.date;
      if (field == null ||
          item.source != HistorySource.document ||
          item.value is! num ||
          when.compareTo(today) > 0) {
        continue;
      }
      readings.add({
        'field': field.$1,
        'value': item.value,
        'unit': field.$2,
        'date': when,
        'source': 'document',
      });
    }
  }
  final diagnoses = <String>{};
  for (final entry in repo.history()) {
    if (entry.kind != HistoryKind.document) continue;
    for (final item in entry.items) {
      if (item.value != true) continue;
      if (item.field == 'diabetes') diagnoses.add('diabetes');
      if (item.field == 'hypertension_diagnosed') diagnoses.add('hypertension');
    }
  }
  if (readings.isEmpty && diagnoses.isEmpty) return null;
  return {
    // Newest first, so the 40 most recent are kept.
    'readings': readings.take(40).toList(),
    'diagnoses': diagnoses.toList(),
  };
}
