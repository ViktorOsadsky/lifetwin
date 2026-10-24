import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetwin/features/activity/activity_math.dart';
import 'package:lifetwin/features/activity/activity_models.dart';
import 'package:lifetwin/features/activity/activity_providers.dart';
import 'package:lifetwin/state/confirmed_baseline.dart';

void main() {
  final now = DateTime(2026, 10, 23, 15);

  TimedMinutes at(int daysAgo, double m) =>
      TimedMinutes(DateTime(2026, 10, 23 - daysAgo, 9), m);

  group('weeklyBuckets', () {
    test('empty input gives four zero weeks and a zero average', () {
      final w = weeklyBuckets(const [], now);
      expect(w, [0, 0, 0, 0]);
      expect(weeklyAverage(w), 0);
    });

    test('splits the 28 days into four 7-day weeks, oldest first', () {
      final w = weeklyBuckets([
        at(0, 30), // this week
        at(6, 30), // this week (last day of bucket)
        at(7, 40), // last week
        at(14, 50), // 2 wks ago
        at(27, 60), // 3 wks ago (last day of window)
      ], now);
      expect(w, [60, 50, 40, 60]);
    });

    test('ignores entries older than 28 days and in the future', () {
      final w = weeklyBuckets([at(28, 100), at(-1, 100), at(1, 20)], now);
      expect(w, [0, 0, 0, 20]);
    });

    test('average is total over four weeks, rounded', () {
      final w = weeklyBuckets([at(0, 100), at(8, 50), at(15, 25)], now);
      expect(weeklyAverage(w), 44); // 175 / 4 = 43.75
    });

    test('time of day does not move an entry between days', () {
      final late = TimedMinutes(DateTime(2026, 10, 23, 23, 59), 10);
      final early = TimedMinutes(DateTime(2026, 10, 16, 0, 1), 10); // 7 days
      expect(weeklyBuckets([late, early], now), [0, 0, 10, 10]);
    });
  });

  group('workout state', () {
    test('adds newest first, removes by id, and feeds the manual average', () {
      final c = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(c.dispose);
      final log = c.read(workoutLogProvider.notifier);
      log.add(
        type: WorkoutType.run,
        minutes: 40,
        intensity: Intensity.vigorous,
        date: DateTime(2026, 10, 20),
      );
      log.add(
        type: WorkoutType.walk,
        minutes: 30,
        intensity: Intensity.light,
        date: DateTime(2026, 10, 22),
      );
      final list = c.read(workoutLogProvider);
      expect(list.map((w) => w.type), [WorkoutType.walk, WorkoutType.run]);
      expect(c.read(manualSummaryProvider).average, 18); // 70 / 4 = 17.5

      log.remove(list.first.id);
      expect(c.read(workoutLogProvider), hasLength(1));
      expect(c.read(manualSummaryProvider).average, 10);
    });

    test('logging workouts never changes the confirmed baseline', () {
      final c = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(c.dispose);
      c
          .read(workoutLogProvider.notifier)
          .add(
            type: WorkoutType.swim,
            minutes: 60,
            intensity: Intensity.moderate,
            date: now,
          );
      expect(c.read(confirmedBaselineProvider).hasActivity, isFalse);

      c
          .read(confirmedBaselineProvider.notifier)
          .confirmActivity(minutesPerWeek: 15, source: ActivitySource.manual);
      expect(c.read(confirmedBaselineProvider).activityMinutesPerWeek, 15);
    });
  });
}
