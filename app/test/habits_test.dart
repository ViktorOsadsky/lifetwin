import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/habits/habit.dart';
import 'package:lifesim/habits/habit_store.dart';
import 'package:lifesim/habits/habit_week.dart';
import 'package:lifesim/habits/habits_client.dart';
import 'package:lifesim/habits/health_score.dart';

Habit habit(String id, {HabitStatus status = HabitStatus.active, String catalogId = 'walk_after_lunch'}) => Habit(
  id: id,
  catalogId: catalogId,
  pillar: 'move',
  anchor: 'After lunch',
  tinyAction: 'walk for 2 minutes outside',
  source: 'guideline',
  status: status,
  startedOn: status == HabitStatus.active ? '2026-10-01' : null,
  dismissedUntil: status == HabitStatus.dismissed ? '2026-11-07' : null,
);

Map<String, HabitResult> done(List<String> days) => {for (final d in days) d: HabitResult.done};

void main() {
  group('week rule', () {
    test('four distinct habit days make a good week; not today never counts', () {
      final results = {
        '2026-10-19': HabitResult.done,
        '2026-10-20': HabitResult.partly,
        '2026-10-21': HabitResult.done,
        '2026-10-22': HabitResult.notToday,
      };
      final three = habitWeekProgress(results, '2026-10-24');
      expect(three.habitDaysThisWeek, 3);
      expect(three.goodWeekThisWeek, isFalse);
      final four = habitWeekProgress({...results, '2026-10-23': HabitResult.partly}, '2026-10-24');
      expect(four.goodWeekThisWeek, isTrue);
      expect(four.goodWeeksTotal, 1);
    });

    test('Sunday belongs to the week before Monday', () {
      final results = done(['2026-10-22', '2026-10-23', '2026-10-24', '2026-10-25']);
      final sunday = habitWeekProgress(results, '2026-10-25');
      expect(sunday.weekStart, '2026-10-19');
      expect(sunday.habitDaysThisWeek, 4);
      final monday = habitWeekProgress(results, '2026-10-26');
      expect(monday.weekStart, '2026-10-26');
      expect(monday.habitDaysThisWeek, 0);
      expect(monday.goodWeeksTotal, 1, reason: 'good weeks never reset');
    });

    test('a week across the new year and across a DST change is one week', () {
      expect(weekStartOf('2030-01-06'), '2029-12-31');
      expect(habitWeekProgress(done(['2029-12-31', '2030-01-01', '2030-01-05', '2030-01-06']), '2030-01-06').goodWeekThisWeek, isTrue);
      // US clocks change on Sun 2026-11-01 and Europe's on Sun 2026-10-25.
      expect(weekStartOf('2026-11-01'), '2026-10-26');
      expect(weekStartOf('2026-10-25'), '2026-10-19');
      expect(addDays('2026-10-24', 14), '2026-11-07');
    });

    test('good weeks are counted over all time, never in a row', () {
      final results = {
        ...done(['2026-08-03', '2026-08-04', '2026-08-05', '2026-08-06']),
        ...done(['2026-09-07', '2026-09-08', '2026-09-09', '2026-09-10']),
        ...done(['2026-10-12', '2026-10-13', '2026-10-14', '2026-10-15']),
      };
      expect(habitWeekProgress(results, '2026-10-24').goodWeeksTotal, 3);
    });

    test('future days are ignored, not counted', () {
      final week = habitWeekProgress(done(['2026-10-25', '2026-10-26']), '2026-10-24');
      expect(week.habitDaysThisWeek, 0);
      expect(week.ignoredFutureDays, 2);
    });

    test('junk days are rejected', () {
      for (final day in ['2026-02-30', '2026-13-01', 'tomorrow', '2026-1-5', '']) {
        expect(() => parseDay(day), throwsFormatException, reason: day);
      }
    });

    test('localDay uses the phone day, not UTC', () {
      final late = DateTime(2026, 10, 25, 23, 30); // local Sunday night
      expect(localDay(late), '2026-10-25');
      expect(localDay(late.toUtc()), '2026-10-25');
    });

    test('matches the server fixture for the same results', () {
      final cases = jsonDecode(File('../contracts/fixtures/cases.json').readAsStringSync()) as List;
      final c = cases.firstWhere((c) => c['name'] == 'habits-week-good-week') as Map;
      final request = c['request'] as Map;
      final expected = c['response_subset'] as Map;
      final results = {
        for (final e in (request['results'] as Map).entries) e.key as String: HabitResult.parse(e.value),
      };
      final week = habitWeekProgress(results, request['local_date'] as String);
      expect(week.weekStart, expected['week_start']);
      expect(week.habitDaysThisWeek, expected['habit_days_this_week']);
      expect(week.goodWeekThisWeek, expected['good_week_this_week']);
      expect(week.goodWeeksTotal, expected['good_weeks_total']);
    });
  });

  group('habit record', () {
    test('round-trips and matches the contract field names', () {
      final h = habit('a-1').copyWith(whyWords: "I'm wiped out by 3pm");
      expect(Habit.fromJson(jsonDecode(jsonEncode(h.toJson()))), h);
      final schema = jsonDecode(File('../contracts/habits.update.request.schema.json').readAsStringSync()) as Map;
      final fields = ((schema[r'$defs'] as Map)['HabitRecord'] as Map)['properties'] as Map;
      expect(h.toJson().keys.toSet(), fields.keys.toSet());
    });

    test('junk records are rejected', () {
      expect(() => Habit.fromJson('habit'), throwsFormatException);
      expect(() => Habit.fromJson({...habit('a').toJson(), 'status': 'paused'}), throwsFormatException);
      expect(() => Habit.fromJson({...habit('a').toJson(), 'anchor': 3}), throwsFormatException);
      expect(() => HabitResult.parse('maybe'), throwsFormatException);
    });
  });

  group('store', () {
    test('keeps at most two active habits and one proposal', () {
      final store = HabitStore(habits: [habit('a-1'), habit('a-2', catalogId: 'three_breaths')]);
      expect(() => store.upsert(habit('a-3')), throwsA(isA<HabitStoreError>()));
      store.upsert(habit('p-1', status: HabitStatus.proposed));
      expect(() => store.upsert(habit('p-2', status: HabitStatus.proposed)), throwsA(isA<HabitStoreError>()));
      // Replacing an active habit by id is not a third one.
      store.upsert(habit('a-1').copyWith(anchor: 'After my tea'));
      expect(store.active.length, 2);
      expect(store.byId('a-1')!.anchor, 'After my tea');
    });

    test('a skip leaves the day unknown and a later answer replaces the earlier one', () {
      final store = HabitStore(habits: [habit('a-1')]);
      store.record('a-1', '2026-10-24', HabitResult.notToday);
      store.record('a-1', '2026-10-24', HabitResult.done);
      expect(store.resultsFor('a-1'), {'2026-10-24': HabitResult.done});
      store.record('a-1', '2026-10-24', null);
      expect(store.resultsFor('a-1'), isEmpty);
      expect(() => store.record('nope', '2026-10-24', HabitResult.done), throwsA(isA<HabitStoreError>()));
      expect(() => store.record('a-1', '2026-02-30', HabitResult.done), throwsFormatException);
    });

    test('saves and restores, and refuses a damaged save', () {
      final store = HabitStore(habits: [habit('a-1'), habit('d-1', status: HabitStatus.dismissed)]);
      for (final d in ['2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22']) {
        store.record('a-1', d, HabitResult.partly);
      }
      final restored = HabitStore.fromJson(jsonDecode(jsonEncode(store.toJson())));
      expect(restored.habits, store.habits);
      expect(restored.habitWeekProgressFor('a-1', today: '2026-10-24').goodWeekThisWeek, isTrue);
      expect(() => HabitStore.fromJson({'version': 2}), throwsFormatException);
      final three = {
        'version': 1,
        'habits': [for (final id in ['a', 'b', 'c']) habit(id).toJson()],
      };
      expect(() => HabitStore.fromJson(three), throwsA(isA<HabitStoreError>()));
    });

    test('applies proposals and accepts, and ignores refusals', () {
      final store = HabitStore();
      final proposal = habit('p-1', status: HabitStatus.proposed);
      store.apply(HabitsReply(status: 'proposed', message: 'Want a small idea?', mood: 'happy', habit: proposal));
      expect(store.proposed, proposal);
      store.apply(HabitsReply(status: 'safety', message: 'no', mood: 'concerned', habit: habit('p-1')));
      expect(store.proposed, proposal, reason: 'a refused edit changes nothing');
      store.apply(HabitsReply(status: 'active', message: 'Lovely.', mood: 'happy', habit: habit('p-1')));
      expect(store.active.single.id, 'p-1');
      expect(store.proposed, isNull);
    });
  });

  test('the health score stays a placeholder and never sees habits', () async {
    const source = PendingHealthScore();
    final adult = await source.score(const HealthScoreInput(profile: {'age': 26}, asOf: '2026-10-24'));
    expect(adult.status, HealthScoreStatus.notReady);
    expect(adult.value, isNull);
    final teen = await source.score(const HealthScoreInput(profile: {'age': 16}, asOf: '2026-10-24'));
    expect(teen.status, HealthScoreStatus.ageNotSupported);
  });
}
