// The merged flow: onboarding (conversation v2) → profile and habit notes, quick
// check-ins (frequent check-ins) → daily_logs → the on-device model, weekly check-ins →
// profile_update, history, corrections and Delete my data.
//
// Inputs are real server responses (test/fixtures/merged_flow.json, written by
// server/tests/make_app_fixtures.py). Expected values come from the rules and from what
// the person said in those conversations, never from the app's output.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/twin/twin_checkin_store.dart';
import 'package:lifesim/twin/twin_history.dart' show candidateWindows;
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';

final Map<String, dynamic> flow =
    jsonDecode(File('test/fixtures/merged_flow.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> copy(Object? j) => Map<String, dynamic>.from(jsonDecode(jsonEncode(j)) as Map);
Map<String, dynamic> get ready => copy(flow['onboarding_ready']);
Map<String, dynamic> get noMemory => copy(flow['onboarding_no_memory']);
Map<String, dynamic> get weekly => copy(flow['weekly']);
Map<String, dynamic> get daily => copy(flow['daily']);
List<Map<String, dynamic>> get quickWeek => [for (final q in flow['quick_week'] as List) copy(q)];
String dateOf(Map<String, dynamic> r) => (r['state'] as Map)['local_date'] as String;

class FakePort implements NotificationPort {
  int cancels = 0;
  final scheduled = <int>[];
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime localWallTime,
    required String title,
    required String body,
  }) async => scheduled.add(id);
  @override
  Future<void> cancelAll() async {
    cancels++;
    scheduled.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());

  // Monday 26 October 2026, morning.
  var now = DateTime(2026, 10, 26, 9, 30);
  late MemoryBackend backend;
  late FakePort port;
  late TwinRepository repo;
  late TwinCheckinStore checkinStore;

  setUp(() async {
    now = DateTime(2026, 10, 26, 9, 30);
    backend = MemoryBackend();
    port = FakePort();
    repo = TwinRepository(
      model: model,
      store: await TwinStore.open(backend),
      reminders: CheckinReminders(port),
      clock: () => now,
    );
    checkinStore = TwinCheckinStore(repo);
  });

  Future<void> onboard({Map<String, dynamic>? turn}) async {
    final t = turn ?? ready;
    await repo.saveOnboarding(
      Map<String, dynamic>.from(t['state'] as Map),
      modelInputs: Map<String, dynamic>.from(t['model_inputs'] as Map),
      fromHealth: const {'height_cm', 'weight_kg', 'sleep_hours'},
    );
  }

  /// Each quick check-in in the evening of its own day, as the person would.
  Future<void> quickDays(Iterable<Map<String, dynamic>> responses) async {
    for (final r in responses) {
      final d = parseDay(dateOf(r));
      now = DateTime(d.year, d.month, d.day, 20, 15);
      await checkinStore.applyFinishedCheckin(r, localDate: dateOf(r));
    }
    now = DateTime(2026, 10, 26, 9, 30);
    repo.refresh(); // the app opens on Monday
  }

  group('onboarding result', () {
    test('the confirmed answers become the profile, with the package names and codes', () async {
      await onboard();
      // "I'm 72, female, never smoked"; Apple Health 162.6 cm, 68 kg, 6.5 h; "Good", "No",
      // "No", "About 7 hours, mostly TV", "None" harder, "About 90 minutes of walking".
      expect(repo.profile, {
        'age': 72,
        'sex': 'female',
        'smoking_status': 'never',
        'height_cm': 162.6,
        'weight_kg': 68.0,
        'sleep_hours': 6.5,
        'general_health': 'good',
        'hypertension_diagnosed': false,
        'diabetes': false,
        'sedentary_min_day': 420,
        'vigorous_recreation_min_week': 0,
        'moderate_recreation_min_week': 90,
      });
      // status ready: the model reads model_inputs.profile, all eleven inputs known.
      final a = repo.current!;
      expect(a.status, 'available');
      expect(a.missingInputs, isEmpty);
      expect(a.profileUsed['sex_nhanes'], 2);
      expect(a.profileUsed['general_health'], 3); // "good"
      expect(a.profileUsed['smoking_status'], 0); // never
      expect(a.source, 'profile_snapshot');
    });

    test('habit notes are kept only with memory consent', () async {
      await onboard();
      final said = (ready['state'] as Map)['habit_notes'] as List;
      expect(said, isNotEmpty);
      expect(repo.store.memoryConsent, isTrue);
      expect([for (final n in repo.store.habitNotes) n['note']], said);
      // Saving the same conversation again keeps each note once.
      await onboard();
      expect(repo.store.habitNotes, hasLength(said.length));

      // A later conversation without consent: the notes are deleted, the profile stays.
      await onboard(turn: noMemory);
      expect(repo.store.memoryConsent, isFalse);
      expect(repo.store.habitNotes, isEmpty);
      expect(repo.profile['age'], 72);
    });

    test('no consent from the start: nothing is remembered', () async {
      final t = noMemory;
      // Even notes sent by mistake are not kept without consent.
      (t['state'] as Map)['habit_notes'] = [
        {'topic': 'exercise', 'kind': 'walking', 'source': 'said'},
      ];
      await onboard(turn: t);
      expect(repo.store.habitNotes, isEmpty);
      expect(await repo.addHabitNote({'topic': 'sleep'}), isFalse);
    });

    test('model_inputs is used only when ready', () {
      final mi = Map<String, dynamic>.from(ready['model_inputs'] as Map);
      final confirmed = Map<String, dynamic>.from((ready['state'] as Map)['confirmed_profile'] as Map);
      // A ready model profile is what the model reads (here a different health rating).
      final ratedExcellent = {
        ...mi,
        'profile': {...mi['profile'] as Map, 'general_health': 1},
      };
      expect(repo.assess(confirmed, ratedExcellent).profileUsed['general_health'], 1);
      // Still learning: ignored; the app maps the confirmed answers itself.
      final learning = {...ratedExcellent, 'status': 'still_learning'};
      expect(repo.assess(confirmed, learning).profileUsed['general_health'], 3);
    });
  });

  group('quick check-ins → daily_logs → the on-device model', () {
    test('seven complete days ending yesterday make a daily window the forecast uses', () async {
      await onboard();
      await quickDays(quickWeek);
      final a = repo.current!;
      expect(a.status, 'available');
      expect(a.source, 'daily_logs');
      expect(a.inputProvenance['window_start'], '2026-10-19');
      expect(a.inputProvenance['window_end'], '2026-10-25');
      // Each day: 7 h sleep, 20 min out of breath, 30 min easy, 6 h sitting.
      expect(a.profileUsed['sleep_hours'], 7);
      expect(a.profileUsed['vigorous_recreation_min_week'], 140);
      expect(a.profileUsed['moderate_recreation_min_week'], 210);
      expect(a.profileUsed['sedentary_min_day'], 360);
      // Quick check-ins never touch the profile.
      expect(repo.profile['sleep_hours'], 6.5);
      expect(repo.profile['sedentary_min_day'], 420);
      // Workday is Monday to Friday.
      final window = const DailyLogsWindowProbe().window(repo);
      expect([for (final r in window) r['workday']], [true, true, true, true, true, false, false]);
      // Every quick entry fed the forecast through the daily-log window.
      final quick = repo.history().where((e) => e.kind == HistoryKind.quick).toList();
      expect(quick, hasLength(7));
      expect(quick.every((e) => e.fedForecast == 'daily_logs'), isTrue);
      expect(repo.goodWeeks(), 1);
    });

    test('a missed day: no window, and the calendar shows a blank, never 0', () async {
      await onboard();
      await quickDays(quickWeek.where((r) => dateOf(r) != '2026-10-22'));
      final a = repo.current!;
      expect(a.source, 'profile_snapshot'); // the run ending yesterday is only 3 days
      expect(a.profileUsed['sleep_hours'], 6.5);
      final days = repo.dayLogs(from: DateTime(2026, 10, 19), to: DateTime(2026, 10, 25));
      expect(days.map((d) => d.date), [
        '2026-10-19',
        '2026-10-20',
        '2026-10-21',
        '2026-10-22',
        '2026-10-23',
        '2026-10-24',
        '2026-10-25',
      ]);
      final blank = days[3];
      expect([blank.sleepHours, blank.vigorousMin, blank.moderateMin, blank.sedentaryMin], [null, null, null, null]);
      expect(days[2].complete && days[4].complete, isTrue);
      expect(repo.history(from: DateTime(2026, 10, 22), to: DateTime(2026, 10, 22)), isEmpty);
      expect(repo.history().any((e) => e.fedForecast != null), isFalse);
    });

    test('a later confirmed answer for the same day wins; nothing is written as 0', () async {
      final first = quickWeek.last;
      final again = copy(first);
      (again['daily_logs'] as List).first = {'date': '2026-10-25', 'sleep_hours': 8.0};
      await checkinStore.applyFinishedCheckin(first, localDate: '2026-10-25');
      await checkinStore.applyFinishedCheckin(again, localDate: '2026-10-25');
      final row = repo.store.dayLogs.single;
      expect(row.sleepHours, 8.0);
      expect(row.vigorousMin, 20); // kept: the second check-in didn't carry it
      final entry = repo.history().first;
      expect(entry.items.single.field, 'sleep_hours');
      expect(entry.items.single.old, 7.0);
      expect(entry.items.single.text, '8 hours');
    });

    test('refused day values are left unknown', () async {
      final r = copy(quickWeek.first);
      (r['daily_logs'] as List).first = {
        'date': '2026-10-19',
        'sleep_hours': 'seven',
        'vigorous_recreation_min': -5,
        'moderate_recreation_min': 30,
        'sedentary_min_day': 2000,
      };
      await checkinStore.applyFinishedCheckin(r, localDate: '2026-10-19');
      final row = repo.store.dayLogs.single;
      expect([row.sleepHours, row.vigorousMin, row.moderateMin, row.sedentaryMin], [null, null, 30, null]);
    });
  });

  group('weekly check-in', () {
    test('profile_update is applied under the write rules', () async {
      await onboard();
      final r = weekly;
      // What the contract allows the server to send, beyond the real answers.
      (r['profile_update'] as Map)
        ..['smoking_status'] =
            'unknown' // unknown never replaces "never"
        ..['height_cm'] =
            null // null never erases
        ..['wellbeing'] =
            'good' // not a profile field
        ..['diabetes'] = 'no'; // wrong type
      now = DateTime(2026, 10, 25, 18);
      // Through the repository directly, to see the refused fields.
      final o = await repo.applyCheckin(r, localDate: '2026-10-25');
      expect(o.refusedFields, unorderedEquals(['wellbeing', 'diabetes']));
      // "6 hours", "60 minutes of brisk walking uphill and 90 minutes of gardening",
      // "about 6 hours", "2 drinks", "158 pounds", "128 over 78".
      expect(repo.profile['sleep_hours'], 6.0);
      expect(repo.profile['vigorous_recreation_min_week'], 60);
      expect(repo.profile['moderate_recreation_min_week'], 90);
      expect(repo.profile['sedentary_min_day'], 360);
      expect((repo.profile['weight_kg'] as num).toDouble(), closeTo(158 * 0.45359237, 0.01));
      expect(repo.profile['smoking_status'], 'never');
      expect(repo.profile['height_cm'], 162.6);
      expect(repo.profile['diabetes'], false);
      expect(repo.profile.containsKey('wellbeing'), isFalse);

      // On Monday the week just ended (19–25 October) is a weekly window, preferred.
      now = DateTime(2026, 10, 26, 9, 30);
      final a = repo.refresh()!;
      expect(a.source, 'weekly_summaries');
      expect(a.inputProvenance['window_start'], '2026-10-19');
      final entry = repo.history().firstWhere((e) => e.kind == HistoryKind.weekly);
      expect(entry.weekStart, '2026-10-19');
      expect(entry.fedForecast, 'weekly_summaries');
      final sleep = entry.items.firstWhere((i) => i.field == 'sleep_hours');
      expect((sleep.old, sleep.value, sleep.isChange), (6.5, 6.0, true));
    });

    test('a weekly check-in beats a daily window; without one, the daily window is used', () async {
      await onboard();
      await quickDays(quickWeek);
      expect(repo.current!.source, 'daily_logs');
      now = DateTime(2026, 10, 25, 21);
      await checkinStore.applyFinishedCheckin(weekly, localDate: '2026-10-25');
      now = DateTime(2026, 10, 26, 9, 30);
      expect(repo.refresh()!.source, 'weekly_summaries');
      expect(repo.history().where((e) => e.fedForecast == 'daily_logs'), isEmpty);
    });
  });

  test('daily and quick check-ins never touch the profile', () async {
    await onboard();
    final before = repo.profile;
    final d = daily;
    d['profile_update'] = {'sleep_hours': 3.0, 'age': 30};
    await checkinStore.applyFinishedCheckin(d, localDate: '2026-10-23');
    final q = quickWeek.first;
    q['profile_update'] = {'sleep_hours': 3.0};
    await checkinStore.applyFinishedCheckin(q, localDate: '2026-10-19');
    expect(repo.profile, before);
  });

  test('Delete my data: everything is gone and the reminders are cancelled', () async {
    await onboard();
    await quickDays(quickWeek);
    await checkinStore.applyFinishedCheckin(weekly, localDate: '2026-10-25');
    await repo.recordHealthImport({'sleep_hours': 6.5});
    await checkinStore.saveSettings(const CheckinSettings(reminderHour: 8, remindersOn: true, reminderOffered: true));
    await CheckinReminders(port).reschedule(repo.checkinSettings, localNow: now, history: repo.store.checkins);
    expect(port.scheduled, isNotEmpty);
    await repo.saveTwinLook({'type': 'bear', 'look': 'cal_hat', 'name': 'Mochi'});

    await repo.deleteMyData();

    expect(port.cancels, greaterThan(0));
    expect(port.scheduled, isEmpty);
    expect(backend.text, isNull);
    expect(repo.profile, isEmpty);
    expect(repo.store.checkins, isEmpty);
    expect(repo.store.dayLogs, isEmpty);
    expect(repo.history(), isEmpty);
    expect(repo.readings(), isEmpty);
    expect(repo.store.habitNotes, isEmpty);
    expect(repo.store.memoryConsent, isFalse);
    expect(repo.store.twin, isNull);
    expect(repo.checkinSettings.toJson(), const CheckinSettings().toJson());
    expect(repo.current, isNull);
    expect(repo.goodWeeks(), 0);
    // Reopening the phone's store finds nothing either.
    final reopened = await TwinStore.open(backend);
    expect(reopened.hasProfile || reopened.historyEntries.isNotEmpty || reopened.dayLogs.isNotEmpty, isFalse);
  });

  group('history', () {
    test('every event kind is recorded with its source and items', () async {
      // Apple Health import confirmed on the Health screen.
      now = DateTime(2026, 10, 18, 10);
      await repo.recordHealthImport({'height_cm': 162.6, 'weight_kg': 68, 'sleep_hours': 6.5});
      // Onboarding.
      now = DateTime(2026, 10, 18, 10, 5);
      await onboard();
      // A quick check-in, a daily one, a weekly one.
      await quickDays(quickWeek.take(1));
      now = DateTime(2026, 10, 23, 19);
      await checkinStore.applyFinishedCheckin(daily, localDate: '2026-10-23');
      now = DateTime(2026, 10, 25, 18);
      await checkinStore.applyFinishedCheckin(weekly, localDate: '2026-10-25');
      // A change through Mochi.
      now = DateTime(2026, 10, 26, 11);
      await repo.saveConversationProfile({'general_health': 'very_good', 'age': 72}, kind: HistoryKind.mochiChange);
      // A day correction.
      await repo.applyDayCorrection(DateTime(2026, 10, 23), 'wellbeing', 'okay');

      final h = repo.history();
      expect(h.map((e) => e.kind), [
        HistoryKind.correction,
        HistoryKind.mochiChange,
        HistoryKind.reading,
        HistoryKind.weekly,
        HistoryKind.daily,
        HistoryKind.quick,
        HistoryKind.onboarding,
        HistoryKind.healthImport,
      ]); // newest first
      HistoryEntry of(String kind) => h.firstWhere((e) => e.kind == kind);
      expect(h.map((e) => e.id).toSet(), hasLength(h.length));

      final health = of(HistoryKind.healthImport);
      expect(health.source, HistorySource.appleHealth);
      expect(health.sourceLabel, 'Apple Health');
      expect(health.items.map((i) => i.text), ['162.6 cm', '68 kg', '6.5 hours a night']);

      final onboarding = of(HistoryKind.onboarding);
      expect(onboarding.source, HistorySource.said);
      expect((onboarding.date, onboarding.time), ('2026-10-18', '10:05'));
      final items = {for (final i in onboarding.items) i.field: i};
      expect(items['height_cm']!.source, HistorySource.appleHealth);
      expect(items['age']!.source, isNull); // the entry's own source: "You said"
      expect(items['age']!.text, '72 years');
      expect(items['general_health']!.text, 'good');
      expect(items['hypertension_diagnosed']!.label, 'told you have high blood pressure');
      expect(items['hypertension_diagnosed']!.text, 'no');
      expect(items['sedentary_min_day']!.text, '420 minutes a day');
      expect(items.length, 12);

      final quick = of(HistoryKind.quick);
      expect(quick.source, HistorySource.said);
      expect(quick.days, ['2026-10-19']);
      expect(
        {for (final i in quick.items) i.field: (i.date, i.text)},
        {
          'sleep_hours': ('2026-10-19', '7 hours'),
          'vigorous_recreation_min': ('2026-10-19', '20 minutes'),
          'moderate_recreation_min': ('2026-10-19', '30 minutes'),
          'sedentary_min_day': ('2026-10-19', '360 minutes'),
        },
      );

      final dailyEntry = of(HistoryKind.daily);
      expect(
        {for (final i in dailyEntry.items) i.field: i.text},
        {'sleep_hours_last_night': '6 hours', 'exercise_minutes_today': '30 minutes', 'wellbeing': 'not great'},
      );
      expect(dailyEntry.fedForecast, isNull); // history only
      expect(dailyEntry.corrected, isTrue);

      final week = of(HistoryKind.weekly);
      expect(week.source, HistorySource.said);
      expect(week.items.firstWhere((i) => i.field == 'vigorous_recreation_min_week').isChange, isTrue);

      final reading = of(HistoryKind.reading);
      expect(reading.source, HistorySource.said);
      expect(reading.items.map((i) => i.text), ['128 mmHg', '78 mmHg']);
      expect(repo.readings().single.id, reading.id);

      final change = of(HistoryKind.mochiChange);
      expect(change.source, HistorySource.mochiChange);
      expect(change.sourceLabel, 'Mochi change');
      // Only what changed is listed, old → new; the unchanged age is not.
      expect(change.items.single.field, 'general_health');
      expect((change.items.single.oldText, change.items.single.text), ('good', 'very good'));

      final correction = of(HistoryKind.correction);
      expect(correction.corrects, dailyEntry.id);
      expect(correction.source, HistorySource.mochiChange);
      expect((correction.items.single.oldText, correction.items.single.text), ('not great', 'okay'));

      // From and to are local dates, inclusive.
      expect(repo.history(from: DateTime(2026, 10, 23), to: DateTime(2026, 10, 25)).map((e) => e.kind), [
        HistoryKind.reading,
        HistoryKind.weekly,
        HistoryKind.daily,
      ]);
      // The history survives a restart: it is in the phone's store.
      final reopened = TwinRepository(model: model, store: await TwinStore.open(backend), clock: () => now);
      expect(reopened.history().map((e) => e.toJson()), h.map((e) => e.toJson()));
    });

    test('good weeks count different days with a finished check-in, any kind', () async {
      Map<String, dynamic> on(String date) {
        final r = copy(quickWeek.first);
        (r['state'] as Map)['local_date'] = date;
        r['daily_logs'] = [
          {'date': date, 'sleep_hours': 7.0},
        ];
        return r;
      }

      // Week of 5 Oct: Mon twice (one day), Tue, Thu: three days.
      for (final d in ['2026-10-05', '2026-10-05', '2026-10-06', '2026-10-08']) {
        await checkinStore.applyFinishedCheckin(on(d), localDate: d);
      }
      expect(repo.goodWeeks(), 0);
      // A weekly check-in on Sunday is the fourth day.
      final w = weekly..['state'] = {...(weekly['state'] as Map), 'local_date': '2026-10-11'};
      await checkinStore.applyFinishedCheckin(w, localDate: '2026-10-11');
      expect(repo.goodWeeks(), 1);
      // A later week with four days counts too; the empty week between costs nothing.
      for (final d in ['2026-10-19', '2026-10-20', '2026-10-22', '2026-10-25']) {
        await checkinStore.applyFinishedCheckin(on(d), localDate: d);
      }
      expect(repo.goodWeeks(), 2);
    });
  });

  group('day corrections', () {
    test('a daily-log value is corrected append-only and the window recomputes', () async {
      await onboard();
      await quickDays(quickWeek);
      final original = repo.history().firstWhere((e) => e.kind == HistoryKind.quick && e.days.contains('2026-10-20'));
      final c = await repo.applyDayCorrection(DateTime(2026, 10, 20), 'sleep_hours', 9.0);
      expect(c, isNotNull);
      expect(c!.kind, HistoryKind.correction);
      expect(c.corrects, original.id);
      expect(c.items.single.old, 7.0);
      // The original is kept, marked corrected.
      final h = repo.history();
      final kept = h.firstWhere((e) => e.id == original.id);
      expect(kept.corrected, isTrue);
      expect(kept.correctedBy, c.id);
      expect(kept.items.firstWhere((i) => i.field == 'sleep_hours').value, 7.0);
      // The day's row uses the corrected value; the workday sleep average moves:
      // Monday to Friday nights 7, 9, 7, 7, 7 → 7.4.
      expect(repo.store.dayLogs.firstWhere((d) => d.date == '2026-10-20').sleepHours, 9.0);
      expect(repo.current!.source, 'daily_logs');
      expect(repo.current!.profileUsed['sleep_hours'], closeTo(7.4, 1e-9));
      expect(c.fedForecast, isNull); // only once read back through history()
      expect(h.first.fedForecast, 'daily_logs');
      // A second correction still points at the original.
      final c2 = await repo.applyDayCorrection(DateTime(2026, 10, 20), 'sleep_hours', 8.0);
      expect(c2!.corrects, original.id);
      expect(c2.items.single.old, 9.0);
    });

    test('feeling is history only', () async {
      await onboard();
      await checkinStore.applyFinishedCheckin(daily, localDate: '2026-10-23');
      final before = repo.profile;
      final c = await repo.applyDayCorrection(DateTime(2026, 10, 23), 'wellbeing', 'good');
      expect(c, isNotNull);
      expect(repo.store.dayLogs, isEmpty);
      expect(repo.profile, before);
      expect(repo.store.checkins.single.answers['wellbeing'], 'not_great'); // the record stays
    });

    test('refused: wrong type, unknown over known, future, nothing to correct, unchanged', () async {
      await quickDays(quickWeek);
      final writes = backend.writes;
      Future<HistoryEntry?> fix(DateTime d, String f, Object? v) => repo.applyDayCorrection(d, f, v);
      final tue = DateTime(2026, 10, 20);
      expect(await fix(tue, 'sleep_hours', 'nine'), isNull);
      expect(await fix(tue, 'sleep_hours', 30), isNull); // out of range
      expect(await fix(tue, 'vigorous_recreation_min', 12.5), isNull); // not whole minutes
      expect(await fix(tue, 'sleep_hours', 'unknown'), isNull);
      expect(await fix(tue, 'sleep_hours', null), isNull);
      expect(await fix(tue, 'wellbeing', 'great'), isNull); // not on the scale
      expect(await fix(tue, 'age', 40), isNull); // not a day answer
      expect(await fix(DateTime(2026, 10, 27), 'sleep_hours', 8), isNull); // the future
      expect(await fix(DateTime(2026, 10, 12), 'sleep_hours', 8), isNull); // no answer that day
      expect(await fix(tue, 'wellbeing', 'good'), isNull); // no feeling was given that day
      expect(await fix(tue, 'sleep_hours', 7.0), isNull); // the same value
      expect(await repo.applyDayCorrection(tue, 'sleep_hours', 8, 'mail'), isNull); // unknown source
      expect(backend.writes, writes);
      expect(repo.history().where((e) => e.kind == HistoryKind.correction), isEmpty);
    });
  });

  test('an older saved store (before the new fields and history) still loads', () async {
    final old = MemoryBackend()
      ..text = jsonEncode({
        'version': 1,
        'profile': {
          'age': 70,
          'sex': 'male',
          'height_cm': 175,
          'weight_kg': 80,
          'sleep_hours': 7,
          'exercise_minutes_weekly': 150,
          'smoking_status': 'former',
          'diabetes': false,
          'hypertension': true,
        },
        'checkins': [
          {
            'kind': 'daily',
            'date': '2026-10-20',
            'answers': {'sleep_hours_last_night': 6, 'wellbeing': 'good'},
          },
        ],
        'daily_logs': [
          {
            'date': '2026-10-20',
            'workday': true,
            'sleep_hours': 6,
            'vigorous_recreation_min': 0,
            'moderate_recreation_min': 20,
            'sedentary_min_day': 300,
          },
        ],
        'weekly_summaries': [
          {'week_start': '2026-10-12', 'sleep_hours': 7},
        ],
        'habit_notes': [],
        'memory_consent': false,
      });
    final r = TwinRepository(model: model, store: await TwinStore.open(old), clock: () => now);
    expect(r.profile['age'], 70);
    expect(r.store.checkins.single.kind, 'daily');
    expect(r.store.dayLogs.single.sedentaryMin, 300);
    expect(r.history(), isEmpty);
    expect(r.checkinSettings.reminderHour, 10);
    // The model inputs it never had are reported missing; nothing is filled in.
    expect(r.current!.status, 'missing_inputs');
    expect(
      r.current!.missingInputs,
      containsAll([
        'vigorous_recreation_min_week',
        'moderate_recreation_min_week',
        'sedentary_min_day',
        'general_health',
      ]),
    );
    expect(r.current!.missingInputs, isNot(contains('hypertension_diagnosed'))); // the old key still maps
  });
}

/// The daily window the forecast reads, through the same assembler.
class DailyLogsWindowProbe {
  const DailyLogsWindowProbe();
  List<Map<String, dynamic>> window(TwinRepository repo) =>
      (candidateWindows(
                checkins: repo.store.checkins,
                dayLogs: repo.store.dayLogs,
                asOf: DateTime(2026, 10, 26),
              ).firstWhere((w) => w.containsKey('daily_logs'))['daily_logs']
              as List)
          .cast<Map<String, dynamic>>();
}
