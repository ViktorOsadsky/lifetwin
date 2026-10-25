/// Opt-in demo data: "Rosa", 64, with about two weeks of history on the phone, so a judged
/// walkthrough starts from a lived-in app instead of an empty one.
///
/// Off unless the app is built with `--dart-define=DEMO_SEED=1`. With the flag absent or 0,
/// [openTwin] is exactly `TwinRepository.open` and nothing here runs. When on, it seeds only
/// an EMPTY store (so a real person's data is never touched), and only through the
/// repository's public write APIs, so every rule (provenance, history, health score points,
/// "unknown never replaces a known value") holds. Scores come from the real model; none is
/// written by hand. The seed is dated relative to the day the app first opens.
library;

import 'package:flutter/services.dart';

import '../checkin/checkin_models.dart'
    show CheckinSettings, mondayOf, shiftDay;
import '../checkin/checkin_reminders.dart' show CheckinReminders;
import '../documents/document_extract.dart' show DocumentCandidate;
import '../twin/twin_model.dart' show isoDate;
import '../twin/twin_repository.dart';

const demoSeedEnabled = String.fromEnvironment('DEMO_SEED') == '1';

/// What the app calls at startup instead of `TwinRepository.open`. [demo] is only for tests.
Future<TwinRepository> openTwin({
  CheckinReminders? reminders,
  StoreBackend? backend,
  AssetBundle? bundle,
  bool demo = demoSeedEnabled,
  DateTime Function()? now,
}) async {
  if (!demo) {
    return TwinRepository.open(
      bundle: bundle,
      backend: backend,
      reminders: reminders,
    );
  }
  // The repository keeps this clock; while seeding it reads the simulated time, afterwards the real one.
  DateTime? simulated;
  final real = now ?? DateTime.now;
  final repo = await TwinRepository.open(
    bundle: bundle,
    backend: backend,
    reminders: reminders,
    clock: () => simulated ?? real(),
  );
  if (!repo.store.hasProfile) {
    await seedDemo(repo, real(), (t) => simulated = t);
  }
  repo.refresh();
  return repo;
}

/// Rosa's confirmed profile at onboarding: the approved design persona (BMI 25.149; 5-year survival about 96.9 %).
const rosaProfile = <String, dynamic>{
  'age': 64,
  'sex': 'female',
  'height_cm': 162.6,
  'weight_kg': 66.49,
  'sleep_hours': 6.5,
  'smoking_status': 'never',
  'diabetes': false,
  'hypertension_diagnosed': false,
  'general_health': 3,
  'sedentary_min_day': 480,
  'moderate_recreation_min_week': 90,
  'vigorous_recreation_min_week': 0,
};

/// Writes the demo history into [repo] (an empty one), moving the repository's clock with
/// [setClock] so each event is dated when it "happened". [now] is the real current time.
Future<void> seedDemo(
  TwinRepository repo,
  DateTime now,
  void Function(DateTime?) setClock,
) async {
  DateTime at(int daysAgo, int hour, [int minute = 0]) {
    final d = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: daysAgo));
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  final today = isoDate(now);
  final prevMonday = shiftDay(mondayOf(today), -7);
  // The weekly check-in is the Sunday that closes last week: the week the forecast reads.
  final sunday = shiftDay(mondayOf(today), -1);
  final missed = {
    shiftDay(prevMonday, 2),
    shiftDay(prevMonday, 5),
    shiftDay(prevMonday, -2),
  };
  final dontKnow = shiftDay(prevMonday, 1);

  Future<void> event(DateTime when, Future<void> Function() run) async {
    setClock(when);
    await run();
  }

  // Everything that happens, in time order.
  final events = <(DateTime, Future<void> Function())>[];

  events.add((
    at(16, 10),
    () async {
      await repo.saveOnboarding({
        'memory_consent': true,
        'habit_notes': [
          {'topic': 'walks', 'text': 'walks the dog in the morning'},
          {'topic': 'sitting', 'text': 'sits a lot watching TV in the evening'},
        ],
        'confirmed_profile': rosaProfile,
      });
      await repo.saveCheckinSettings(
        const CheckinSettings(
          reminderHour: 10,
          reminderMinute: 0,
          remindersOn: true,
          reminderOffered: true,
        ),
      );
    },
  ));

  // About two weeks of quick check-ins. Sleep and activity improve in the second week.
  for (var ago = 14; ago >= 1; ago--) {
    final date = isoDate(
      DateTime(now.year, now.month, now.day).subtract(Duration(days: ago)),
    );
    if (missed.contains(date) || date == sunday) continue;
    final better = date.compareTo(prevMonday) >= 0;
    final k = ago % 3; // a little day-to-day variation, deterministic
    final sleep = better ? 6.8 + 0.2 * k : 6.0 + 0.2 * k;
    final moderate = better ? 18 + 2 * k : 10 + 2 * k;
    final sitting = better ? 430 - 5 * k : 490 - 5 * k;
    final unknown = date == dontKnow;
    events.add((
      at(ago, 10, 15),
      () => repo.applyCheckin({
        'complete': true,
        'emergency': false,
        'state': {
          'kind': 'quick',
          'phase': 'ready',
          'local_date': date,
          'activity_day': 'yesterday',
          'confirmed': {
            'sleep_hours_last_night': sleep,
            'vigorous_recreation_min': 0,
            'moderate_recreation_min': moderate,
            'sedentary_min_day': unknown ? 'unknown' : sitting,
            'wellbeing': k == 0 ? 'okay' : 'good',
          },
        },
        'daily_logs': [
          {
            'date': shiftDay(date, -1),
            'vigorous_recreation_min': 0,
            'moderate_recreation_min': moderate,
            if (!unknown) 'sedentary_min_day': sitting,
          },
          {'date': date, 'sleep_hours': sleep},
        ],
      }, localDate: date),
    ));
  }

  // The weekly check-in that feeds the forecast (all four behaviour fields).
  final sundayAgo = DateTime.parse(today)
      .difference(DateTime.parse(sunday))
      .inDays;
  events.add((
    at(sundayAgo, 10, 30),
    () => repo.applyCheckin({
      'complete': true,
      'emergency': false,
      'state': {
        'kind': 'weekly',
        'phase': 'ready',
        'local_date': sunday,
        'confirmed': {
          'sleep_hours': 6.9,
          'vigorous_recreation_min_week': 0,
          'moderate_recreation_min_week': 120,
          'sedentary_min_day': 420,
          'wellbeing': 'good',
        },
      },
      // Only sleep: the Mochi change and the band estimate keep their own provenance.
      'profile_update': {'sleep_hours': 6.9},
    }, localDate: sunday),
  ));

  // A document upload: blood pressure and A1c, dated ten days ago.
  final visit = at(10, 0);
  events.add((
    at(9, 11),
    () => repo.recordDocumentReadings([
      DocumentCandidate(
        field: 'blood_pressure',
        value: '138/86',
        unit: 'mmHg',
        date: visit,
        modelInput: false,
        sourceText: 'Blood pressure 138/86 mmHg',
        page: 1,
      ),
      DocumentCandidate(
        field: 'hba1c',
        value: 5.8,
        unit: '%',
        date: visit,
        modelInput: false,
        sourceText: 'HbA1c 5.8 %',
        page: 1,
      ),
    ]),
  ));

  // One Mochi change: Rosa tells Mochi she now sits less in the evening.
  events.add((
    at(sundayAgo + 3, 18),
    () => repo.saveConversationProfile({
      'sedentary_min_day': 420,
    }, kind: HistoryKind.mochiChange),
  ));

  // One wristband value she confirmed after a read-back: moderate activity, an estimate.
  // (Both come before the weekly check-in: once a week is summarised the forecast reads it.)
  events.add((
    at(sundayAgo + 1, 19),
    () => repo.saveConversationProfile(
      {'moderate_recreation_min_week': 120},
      kind: HistoryKind.mochiChange,
      sources: {'moderate_recreation_min_week': HistorySource.wristband},
    ),
  ));

  events.sort((a, b) => a.$1.compareTo(b.$1));
  try {
    for (final e in events) {
      await event(e.$1, e.$2);
    }
  } finally {
    setClock(null);
  }
}
