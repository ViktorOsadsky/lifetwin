/// The phone's habit records and their day results. In memory; the app saves
/// [toJson] in its protected store and restores it with [HabitStore.fromJson].
/// Results reach the store only from a check-in answer; a habit result never
/// feeds a health score.
library;

import 'habit.dart';
import 'habit_week.dart';
import 'habits_client.dart';

const maxActiveHabits = 2;

/// Thrown when a change would break the store's rules (3 active habits, two
/// proposals at once, a result for a habit that is not on the phone).
class HabitStoreError extends StateError {
  HabitStoreError(super.message);
}

class HabitStore {
  HabitStore({Iterable<Habit> habits = const [], Map<String, Map<String, HabitResult>> results = const {}}) {
    for (final h in habits) {
      upsert(h);
    }
    for (final MapEntry(key: id, value: days) in results.entries) {
      for (final MapEntry(key: day, value: result) in days.entries) {
        record(id, day, result);
      }
    }
  }

  final List<Habit> _habits = [];
  final Map<String, Map<String, HabitResult>> _results = {};

  List<Habit> get habits => List.unmodifiable(_habits);
  List<Habit> get active => _habits.where((h) => h.isActive).toList();
  Habit? get proposed => _habits.where((h) => h.status == HabitStatus.proposed).firstOrNull;
  Habit? byId(String id) => _habits.where((h) => h.id == id).firstOrNull;

  /// Adds or replaces a habit by id. Keeps at most 2 active and 1 proposed.
  void upsert(Habit habit) {
    final others = _habits.where((h) => h.id != habit.id);
    if (habit.isActive && others.where((h) => h.isActive).length >= maxActiveHabits) {
      throw HabitStoreError('At most $maxActiveHabits habits can be active');
    }
    if (habit.status == HabitStatus.proposed && others.any((h) => h.status == HabitStatus.proposed)) {
      throw HabitStoreError('Only one habit can be proposed at a time');
    }
    final i = _habits.indexWhere((h) => h.id == habit.id);
    i < 0 ? _habits.add(habit) : _habits[i] = habit;
  }

  /// Saves a server reply's habit (a proposal, an accept, an edit or a dismissal).
  /// Replies without a habit, or refused ones (safety, age, limits), change nothing.
  void apply(HabitsReply reply) {
    final habit = reply.habit;
    if (habit == null || !const {'proposed', 'pending', 'active', 'dismissed'}.contains(reply.status)) return;
    upsert(habit);
  }

  /// One day's result for one habit. Null clears it back to unknown (a skip).
  /// A later answer the same day replaces the earlier one.
  void record(String habitId, String day, HabitResult? result) {
    if (byId(habitId) == null) throw HabitStoreError('No habit $habitId on this phone');
    parseDay(day);
    final days = _results.putIfAbsent(habitId, () => {});
    result == null ? days.remove(day) : days[day] = result;
  }

  Map<String, HabitResult> resultsFor(String habitId) => Map.unmodifiable(_results[habitId] ?? const {});

  /// The design's `habitWeekProgress(habitId)`, next to the check-in's `weekProgress`.
  HabitWeek habitWeekProgressFor(String habitId, {required String today}) =>
      habitWeekProgress(resultsFor(habitId), today);

  Map<String, Object?> toJson() => {
    'version': 1,
    'habits': [for (final h in _habits) h.toJson()],
    'results': {
      for (final MapEntry(key: id, value: days) in _results.entries)
        id: {for (final MapEntry(key: day, value: r) in days.entries) day: r.wire},
    },
  };

  /// Throws [FormatException] or [HabitStoreError] for a damaged save.
  static HabitStore fromJson(Object? json) {
    if (json is! Map || json['version'] != 1) throw const FormatException('unknown habit store');
    final habits = [for (final h in (json['habits'] as List? ?? const [])) Habit.fromJson(h)];
    final rawResults = json['results'] as Map? ?? const {};
    return HabitStore(
      habits: habits,
      results: {
        for (final MapEntry(key: id, value: days) in rawResults.entries)
          '$id': {
            for (final MapEntry(key: day, value: r) in (days as Map).entries) '$day': HabitResult.parse(r),
          },
      },
    );
  }
}
