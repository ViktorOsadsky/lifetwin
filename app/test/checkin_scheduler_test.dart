import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_scheduler.dart';
import 'package:lifesim/checkin/health_suggestions.dart';

const scheduler = CheckinScheduler();

CheckinEntry quick(String date, [Map<String, dynamic> answers = const {}]) =>
    CheckinEntry(kind: 'quick', date: date, answers: answers);
CheckinEntry weekly(String date) => CheckinEntry(kind: 'weekly', date: date, answers: const {});

DayLog full(String date) => DayLog(date: date, sleepHours: 7, vigorousMin: 10, moderateMin: 30, sedentaryMin: 360);

void main() {
  // Saturday 24 October 2026, 10:00 on the phone's clock.
  final morning = DateTime(2026, 10, 24, 10);

  group('the quick check-in', () {
    test('on a normal morning asks last night, and yesterday\'s activity and sitting', () {
      final plan = scheduler.quickPlan(localNow: morning, history: [quick('2026-10-23')], days: [])!;
      expect(plan.topics, [QuickTopic.sleep, QuickTopic.activity, QuickTopic.sitting]);
      expect(plan.activityDay, 'yesterday');
      expect(plan.catchUp, isFalse);
      expect(plan.topics.length, lessThanOrEqualTo(CheckinScheduler.maxTopics));
    });

    test('in the evening asks about today', () {
      final plan = scheduler.quickPlan(localNow: DateTime(2026, 10, 24, 18), history: [], days: [])!;
      expect(plan.activityDay, 'today');
    });

    test('asks only what is missing, and how the person feels when there is room', () {
      final plan = scheduler.quickPlan(
        localNow: morning,
        history: [quick('2026-10-23')],
        days: [const DayLog(date: '2026-10-23', vigorousMin: 0, moderateMin: 20)],
      )!;
      expect(plan.topics, [QuickTopic.sleep, QuickTopic.sitting, QuickTopic.feeling]);
    });

    test('is not due once done today, or when nothing is left to ask', () {
      final due = scheduler.due(localNow: morning, history: [quick('2026-10-24')], days: []);
      expect(due.quick, isNull);
      final known = scheduler.quickPlan(
        localNow: morning,
        history: [
          quick('2026-10-23'),
          quick('2026-10-24', {'wellbeing': 'good'}),
        ],
        days: [
          full('2026-10-23'),
          const DayLog(date: '2026-10-24', sleepHours: 7),
        ],
      );
      expect(known, isNull);
    });

    test('after a missed day offers one optional catch-up for the night before', () {
      final plan = scheduler.quickPlan(localNow: morning, history: [quick('2026-10-22')], days: [])!;
      expect(plan.catchUp, isTrue);
      // Never on the first day ever.
      expect(scheduler.quickPlan(localNow: morning, history: [], days: [])!.catchUp, isFalse);
    });

    test('several missed days still mean at most one catch-up, about yesterday only', () {
      final plan = scheduler.quickPlan(localNow: morning, history: [quick('2026-10-10')], days: [])!;
      expect(plan.catchUp, isTrue);
      expect(plan.toJson()['catch_up'], isTrue);
    });

    test('in the evening the catch-up comes only when it completes yesterday', () {
      final evening = DateTime(2026, 10, 24, 19);
      final none = scheduler.quickPlan(localNow: evening, history: [quick('2026-10-22')], days: [])!;
      expect(none.catchUp, isFalse);
      final completes = scheduler.quickPlan(
        localNow: evening,
        history: [quick('2026-10-22')],
        days: [const DayLog(date: '2026-10-23', vigorousMin: 0, moderateMin: 30, sedentaryMin: 300)],
      )!;
      expect(completes.catchUp, isTrue);
    });

    test('Apple Health values are offered for a read-back, never saved', () {
      final health = HealthDay(sleepByNight: {'2026-10-24': 7.2, '2026-10-23': 6.5}, exerciseByDay: {'2026-10-23': 35});
      final plan = scheduler.quickPlan(localNow: morning, history: [quick('2026-10-22')], days: [], health: health)!;
      expect(plan.suggestedSleepLastNight, 7.2);
      expect(plan.suggestedSleepNightBefore, 6.5);
      expect(plan.suggestedActivityMinutes, 35);
      // A read-back still counts as one of the three questions.
      expect(plan.topics, [QuickTopic.sleep, QuickTopic.activity, QuickTopic.sitting]);
      expect(plan.toJson()['suggested'], {
        'sleep_hours_last_night': 7.2,
        'sleep_hours_night_before': 6.5,
        'activity_minutes': 35,
      });
    });

    test('the plan is the server\'s QuickPlan', () {
      final plan = scheduler.quickPlan(localNow: morning, history: [], days: [])!;
      expect(plan.toJson(), {
        'topics': ['sleep', 'activity', 'sitting'],
        'activity_day': 'yesterday',
        'catch_up': false,
        'suggested': <String, dynamic>{},
      });
    });
  });

  group('dates and time zones', () {
    test('the day is the phone\'s own date, wherever the person is', () {
      // 23:30 in New York is already the next morning in London.
      final instant = DateTime.utc(2026, 10, 25, 3, 30);
      final newYork = instant.add(const Duration(hours: -4)); // EDT wall time
      final london = instant.add(const Duration(hours: 1)); // BST wall time
      DateTime wall(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute);
      expect(isoDay(dayOf(wall(newYork))), '2026-10-24');
      expect(isoDay(dayOf(wall(london))), '2026-10-25');
      final history = [quick('2026-10-24')];
      expect(scheduler.due(localNow: wall(newYork), history: history, days: []).quick, isNull);
      expect(scheduler.due(localNow: wall(london), history: history, days: []).quick, isNotNull);
    });

    test('daylight saving changes never skip or repeat a day', () {
      expect(shiftDay('2026-11-01', 1), '2026-11-02'); // US clocks go back
      expect(shiftDay('2026-03-08', 1), '2026-03-09'); // US clocks go forward
      expect(shiftDay('2026-03-29', -1), '2026-03-28'); // UK clocks go forward
      final plan = scheduler.quickPlan(
        localNow: DateTime(2026, 11, 2, 10),
        history: [quick('2026-11-01')],
        days: [const DayLog(date: '2026-11-01', vigorousMin: 0, moderateMin: 30, sedentaryMin: 300)],
      )!;
      expect(plan.topics, [QuickTopic.sleep, QuickTopic.feeling]);
    });

    test('the Monday of a week', () {
      expect(mondayOf('2026-10-24'), '2026-10-19');
      expect(mondayOf('2026-10-25'), '2026-10-19');
      expect(mondayOf('2026-10-26'), '2026-10-26');
    });
  });

  group('the weekly check-in', () {
    const settings = CheckinSettings(); // Sunday
    test('comes on the weekly day, after the first quick check-in', () {
      expect(scheduler.weeklyDue(today: '2026-10-25', history: [quick('2026-10-24')], settings: settings), isTrue);
      expect(scheduler.weeklyDue(today: '2026-10-25', history: [], settings: settings), isFalse);
      expect(scheduler.weeklyDue(today: '2026-10-24', history: [quick('2026-10-23')], settings: settings), isFalse);
    });

    test('is not due again within the week, and waits quietly when missed', () {
      final done = [quick('2026-10-24'), weekly('2026-10-25')];
      expect(scheduler.weeklyDue(today: '2026-10-28', history: done, settings: settings), isFalse);
      expect(scheduler.weeklyDue(today: '2026-11-01', history: done, settings: settings), isTrue);
      expect(scheduler.weeklyDue(today: '2026-11-03', history: done, settings: settings), isTrue); // missed Sunday
      // Done late on a Monday: back on the weekly day.
      final late = [quick('2026-10-24'), weekly('2026-10-26')];
      expect(scheduler.weeklyDue(today: '2026-11-01', history: late, settings: settings), isTrue);
    });

    test('is offered alongside the quick one, never instead of it', () {
      final due = scheduler.due(localNow: DateTime(2026, 10, 25, 10), history: [quick('2026-10-24')], days: []);
      expect(due.quick, isNotNull);
      expect(due.weekly, isTrue);
    });
  });
}
