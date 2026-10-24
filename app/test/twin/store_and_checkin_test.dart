import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/checkin_applier.dart';
import 'package:lifesim/twin/twin_history.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';

/// Every model input known (golden profile 1 with height and weight).
const fullProfile = {
  'age': 45,
  'sex': 'male',
  'height_cm': 175.0,
  'weight_kg': 76.5625,
  'sleep_hours': 7,
  'smoking_status': 'never',
  'diabetes': false,
  'hypertension_diagnosed': false,
  'general_health': 2,
  'vigorous_recreation_min_week': 60,
  'moderate_recreation_min_week': 120,
  'sedentary_min_day': 360,
  'alcohol_drinks_weekly': 2,
};

/// A check-in response built from a contract case: the request's state with the response
/// subset laid over it (the subset lists only what the contract pins down).
Map<String, dynamic> responseFor(String name) {
  final cases =
      (jsonDecode(File('test/fixtures/checkin_contract_cases.json').readAsStringSync()) as Map)['cases'] as List;
  final c = cases.cast<Map<String, dynamic>>().firstWhere((c) => c['name'] == name);
  final sub = Map<String, dynamic>.from(c['response_subset'] as Map);
  final reqState = Map<String, dynamic>.from((c['request'] as Map)['state'] as Map? ?? const {});
  final subState = Map<String, dynamic>.from(sub['state'] as Map? ?? const {});
  Map<String, dynamic> merge(String k) => {
    ...?reqState[k] as Map<String, dynamic>?,
    ...?subState[k] as Map<String, dynamic>?,
  };
  return {
    'emergency': false,
    'profile_update': <String, dynamic>{},
    ...sub,
    'state': {...reqState, ...subState, 'confirmed': merge('confirmed'), 'pending': merge('pending')},
  };
}

/// A finished weekly check-in whose answers cover all four behaviour fields.
Map<String, dynamic> weeklyWithBehaviour({required double sleep}) {
  final r = responseFor('checkin-weekly-profile-update');
  (r['state'] as Map)['confirmed'] = {
    'sleep_hours': sleep,
    'vigorous_recreation_min_week': 60,
    'moderate_recreation_min_week': 165,
    'sedentary_min_day': 393,
  };
  r['profile_update'] = <String, dynamic>{};
  return r;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final monday = DateTime(2026, 10, 26);

  group('phone store (written only through TwinRepository)', () {
    late TwinModelService model;
    setUpAll(() async => model = await TwinModelService.load());
    Future<TwinRepository> repoOn(StoreBackend b) async =>
        TwinRepository(model: model, store: await TwinStore.open(b), clock: () => monday);

    test('round trip: profile, check-ins, weekly summary, habit notes, twin look', () async {
      final backend = MemoryBackend();
      final repo = await repoOn(backend);
      expect(repo.store.hasProfile, isFalse);
      await repo.saveConversationProfile({...fullProfile, 'diastolic_bp': null});
      await repo.applyCheckin(weeklyWithBehaviour(sleep: 7));
      await repo.applyCheckin(weeklyWithBehaviour(sleep: 6.5)); // same week: replaced
      await repo.applyMemoryConsent(true);
      expect(await repo.addHabitNote({'topic': 'walks', 'text': 'walks the dog twice a day'}), isTrue);
      await repo.saveTwinLook({'type': 'bear', 'look': 'cal_hat', 'name': 'Mochi'});

      final again = await TwinStore.open(backend);
      expect(again.profile, fullProfile); // nulls are not stored
      expect(again.checkins.map((c) => c.kind), ['weekly', 'weekly']);
      expect(again.weeklySummaries.single, {
        'week_start': '2026-10-19',
        'sleep_hours': 6.5,
        'vigorous_recreation_min_week': 60,
        'moderate_recreation_min_week': 165,
        'sedentary_min_day': 393,
      });
      expect(again.habitNotes.single['note'], {'topic': 'walks', 'text': 'walks the dog twice a day'});
      expect(again.memoryConsent, isTrue);
      expect(again.twin, {'type': 'bear', 'look': 'cal_hat', 'name': 'Mochi'});
    });

    test('habit notes need memory consent; turning it off deletes them', () async {
      final backend = MemoryBackend();
      final repo = await repoOn(backend);
      expect(await repo.addHabitNote({'text': 'tea at night'}), isFalse);
      expect(repo.store.habitNotes, isEmpty);
      await repo.applyMemoryConsent(true);
      await repo.addHabitNote({'text': 'tea at night'});
      await repo.saveConversationProfile(fullProfile);
      await repo.applyMemoryConsent(false);
      expect(repo.store.habitNotes, isEmpty);
      expect(repo.store.profile, fullProfile); // the profile stays: the forecast needs it
      expect((await TwinStore.open(backend)).habitNotes, isEmpty);
    });

    test('Delete my data removes the file and everything in memory', () async {
      final backend = MemoryBackend();
      final repo = await repoOn(backend);
      await repo.saveConversationProfile(fullProfile);
      await repo.saveTwinLook({'type': 'human'});
      expect(repo.wellnessCards, isNotEmpty);
      await repo.deleteMyData();
      expect(backend.text, isNull);
      expect(repo.current, isNull);
      expect(repo.store.hasProfile, isFalse);
      expect(repo.store.twin, isNull);
      expect((await TwinStore.open(backend)).profile, isEmpty);
    });

    test('an unreadable or other-version file is not guessed at', () async {
      for (final text in ['{not json', '{"version": 99, "profile": {"age": 50}}']) {
        final s = await TwinStore.open(MemoryBackend()..text = text);
        expect(s.profile, isEmpty);
      }
    });

    test('the protected backend talks only to the iOS channel; without it, memory only', () async {
      const channel = MethodChannel('lifetwin/protected_store');
      final calls = <MethodCall>[];
      String? file;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'write':
            file = call.arguments as String;
          case 'delete':
            file = null;
          case 'protection':
            return 'NSFileProtectionComplete';
        }
        return call.method == 'read' ? file : null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );
      final b = ProtectedFileBackend();
      final repo = await repoOn(b);
      await repo.saveConversationProfile({'age': 50});
      expect(jsonDecode(file!), {
        'version': 1,
        'profile': {'age': 50},
      });
      expect(await b.protection(), 'NSFileProtectionComplete');
      await repo.deleteMyData();
      expect(file, isNull);
      expect(calls.map((c) => c.method), ['read', 'write', 'protection', 'delete']);

      // No plugin (flutter test without the mock, macOS): kept in memory, never unprotected.
      final m = ProtectedFileBackend(channel: const MethodChannel('lifetwin/none'));
      await m.write('x');
      expect(await m.read(), 'x');
      await m.delete();
      expect(await m.read(), isNull);
    });
  });

  group('check-in applier (contracts on codex/d-twin-checkins)', () {
    test('weekly profile_update: each non-null field is set, nulls left alone', () {
      final r = responseFor('checkin-weekly-profile-update');
      final o = applyCheckinResponse(fullProfile, r, localDate: monday);
      expect(o.profile['sleep_hours'], 6.0);
      expect(o.profile['exercise_minutes_weekly'], 90);
      expect(o.profile['weight_kg'], 71.67);
      expect(o.profile['alcohol_drinks_weekly'], 2); // null in the update: kept
      expect(o.profile['age'], 45);
      expect(o.changedFields, unorderedEquals(['sleep_hours', 'exercise_minutes_weekly', 'weight_kg']));
      expect(o.record!.kind, 'weekly');
      expect(o.record!.date, '2026-10-26');
      expect(o.record!.answers, {
        'sleep_hours': 6,
        'exercise_minutes_weekly': 90,
        'weight_kg': 71.67,
        'wellbeing': 'good',
      });
      // The weekly answers lack the hard/moderate split and sitting: no summary row is invented.
      expect(o.weeklySummary, isNull);
      expect(o.emergency, isFalse);
    });

    test('a weekly check-in still going changes nothing', () {
      final o = applyCheckinResponse(fullProfile, responseFor('checkin-weekly-confirm'), localDate: monday);
      expect(o.profile, fullProfile);
      expect(o.record, isNull);
      expect(o.changedFields, isEmpty);
    });

    test('an emergency pause is flagged and not stored; resume clears it', () {
      final o = applyCheckinResponse(fullProfile, responseFor('checkin-emergency-pause'), localDate: monday);
      expect(o.emergency, isTrue);
      expect(o.record, isNull);
      expect(
        applyCheckinResponse(fullProfile, responseFor('checkin-resume-after-pause'), localDate: monday).emergency,
        isFalse,
      );
    });

    test('a finished daily check-in is history only', () {
      final r = {
        ...responseFor('checkin-daily-start'),
        'complete': true,
        'state': {
          'kind': 'daily',
          'phase': 'ready',
          'questions': ['sleep_hours_last_night', 'exercise_minutes_today', 'wellbeing'],
          'current_field': null,
          'confirmed': {'sleep_hours_last_night': 5.5, 'exercise_minutes_today': null, 'wellbeing': 'okay'},
        },
      };
      final o = applyCheckinResponse(fullProfile, r, localDate: monday);
      expect(o.profile, fullProfile);
      expect(o.changedFields, isEmpty);
      expect(o.record!.answers, {'sleep_hours_last_night': 5.5, 'wellbeing': 'okay'});
    });

    test('weekly answers with all four behaviour fields become a weekly summary for the week just ended', () {
      final r = responseFor('checkin-weekly-profile-update');
      (r['state'] as Map)['confirmed'] = {
        'sleep_hours': 6.5,
        'vigorous_recreation_min_week': 30,
        'moderate_recreation_min_week': 200,
        'sedentary_min_day': 420,
      };
      for (final (day, week) in [
        (DateTime(2026, 10, 25), '2026-10-19'), // Sunday: the week ending today
        (monday, '2026-10-19'),
        (DateTime(2026, 10, 28), '2026-10-19'),
      ]) {
        expect(applyCheckinResponse(fullProfile, r, localDate: day).weeklySummary, {
          'week_start': week,
          'sleep_hours': 6.5,
          'vigorous_recreation_min_week': 30,
          'moderate_recreation_min_week': 200,
          'sedentary_min_day': 420,
        });
      }
    });
  });

  group('history windows', () {
    test('weekly: consecutive weeks ending with the latest completed one, at most four', () {
      Map<String, dynamic> w(String start) => {
        'week_start': start,
        'sleep_hours': 7,
        'vigorous_recreation_min_week': 60,
        'moderate_recreation_min_week': 165,
        'sedentary_min_day': 393,
      };
      final rows = [w('2026-09-14'), w('2026-09-28'), w('2026-10-05'), w('2026-10-12'), w('2026-10-19')];
      expect(weeklyWindow(rows, monday)!.map((r) => r['week_start']), [
        '2026-09-28',
        '2026-10-05',
        '2026-10-12',
        '2026-10-19',
      ]);
      expect(weeklyWindow(rows, DateTime(2026, 10, 25)), hasLength(3)); // Sunday: latest completed is 10-12
      expect(weeklyWindow([w('2026-10-05')], monday), isNull); // the latest week is missing
      expect(
        weeklyWindow([
          {...w('2026-10-19'), 'sedentary_min_day': null},
        ], monday),
        isNull,
      );
    });

    test('daily: complete days ending yesterday, longest window first', () {
      final rows = [
        for (var i = 1; i <= 15; i++)
          {
            'date': isoDate(monday.subtract(Duration(days: i))),
            'workday': i % 7 != 1 && i % 7 != 2,
            'sleep_hours': 7,
            'vigorous_recreation_min': 0,
            'moderate_recreation_min': 30,
            'sedentary_min_day': 400,
          },
      ];
      final windows = dailyWindows(rows, monday);
      expect(windows.map((w) => w.length), [14, 7]);
      expect(windows.first.last['date'], '2026-10-25');
    });
  });

  group('TwinRepository', () {
    late TwinModelService model;
    setUpAll(() async => model = await TwinModelService.load());

    test('a weekly check-in updates the profile on the phone and recomputes the forecast', () async {
      final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => monday);
      final before = await repo.saveConversationProfile(fullProfile);
      expect(before.status, 'available');
      var notified = 0;
      repo.addListener(() => notified++);
      final o = await repo.applyCheckin(responseFor('checkin-weekly-profile-update'));
      expect(o.changedFields, isNotEmpty);
      expect(repo.profile['sleep_hours'], 6.0);
      expect(repo.store.checkins.single.kind, 'weekly');
      final after = repo.current!;
      expect(after.profileUsed['sleep_hours'], 6.0);
      expect(after.inputProvenance, {'source': 'profile_snapshot'});
      expect(after.survivalByYear[5], lessThan(before.survivalByYear[5]!)); // short sleep term
      expect(notified, greaterThan(0));
    });

    test('a stored weekly summary window replaces the behaviour values, with provenance kept', () async {
      final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => monday);
      await repo.applyCheckin(weeklyWithBehaviour(sleep: 7));
      final a = await repo.saveConversationProfile({...fullProfile, 'sedentary_min_day': null});
      expect(a.status, 'available'); // sitting came from the window
      expect(a.source, 'weekly_summaries');
      expect(a.inputProvenance['window_start'], '2026-10-19');
      expect(a.profileUsed['moderate_recreation_min_week'], 165);
    });

    test('the emergency flag shows on the twin until cleared', () async {
      final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => monday);
      await repo.applyCheckin(responseFor('checkin-emergency-pause'));
      expect(repo.twinState().emergency, isTrue);
      repo.clearEmergency();
      expect(repo.twinState().emergency, isFalse);
    });
  });
}
