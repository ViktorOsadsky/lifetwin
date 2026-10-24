import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'activity_math.dart';
import 'activity_models.dart';
import 'health_importer.dart';

/// Clock seam so tests can pin "today".
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// In-memory manual workout log, newest first.
class WorkoutLog extends Notifier<List<Workout>> {
  int _nextId = 1;

  @override
  List<Workout> build() => const [];

  void add({
    required WorkoutType type,
    required int minutes,
    required Intensity intensity,
    required DateTime date,
  }) {
    final w = Workout(
      id: _nextId++,
      type: type,
      minutes: minutes,
      intensity: intensity,
      date: DateTime(date.year, date.month, date.day),
    );
    final next = [...state, w]
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
    state = next;
  }

  void remove(int id) => state = [
    for (final w in state)
      if (w.id != id) w,
  ];
}

final workoutLogProvider = NotifierProvider<WorkoutLog, List<Workout>>(
  WorkoutLog.new,
);

enum ImportStatus { idle, loading, imported, noData, denied, unavailable }

@immutable
class HealthImportState {
  const HealthImportState({this.status = ImportStatus.idle, this.weekly});

  final ImportStatus status;

  /// Weekly totals, oldest first, only when [status] is imported.
  final List<int>? weekly;

  int? get average => weekly == null ? null : weeklyAverage(weekly!);
}

class HealthImportController extends Notifier<HealthImportState> {
  @override
  HealthImportState build() => const HealthImportState();

  Future<void> run() async {
    if (state.status == ImportStatus.loading) return;
    final previous = state;
    state = const HealthImportState(status: ImportStatus.loading);
    final now = ref.read(clockProvider)();
    final result = await ref.read(healthImporterProvider).importLast28Days(now);
    state = switch (result) {
      HealthImported r => HealthImportState(
        status: ImportStatus.imported,
        weekly: r.weekly,
      ),
      HealthNoData() => const HealthImportState(status: ImportStatus.noData),
      HealthDenied() => const HealthImportState(status: ImportStatus.denied),
      HealthUnavailable() => HealthImportState(
        status: ImportStatus.unavailable,
        // A failed re-import keeps an earlier good result.
        weekly: previous.weekly,
      ),
    };
  }
}

final healthImportProvider =
    NotifierProvider<HealthImportController, HealthImportState>(
      HealthImportController.new,
    );

/// Which source the Activity summary shows. Defaults to manual and moves to
/// Apple Health after a successful import; the user can switch back.
class SummarySourceChoice extends Notifier<ActivitySource> {
  @override
  ActivitySource build() {
    ref.listen(healthImportProvider, (_, next) {
      if (next.status == ImportStatus.imported) {
        state = ActivitySource.appleHealth;
      }
    });
    return ActivitySource.manual;
  }

  void choose(ActivitySource s) => state = s;
}

final summarySourceProvider =
    NotifierProvider<SummarySourceChoice, ActivitySource>(
      SummarySourceChoice.new,
    );

@immutable
class ActivitySummary {
  const ActivitySummary({required this.source, required this.weekly});

  final ActivitySource source;
  final List<int> weekly;

  int get average => weeklyAverage(weekly);
  bool get isEmpty => weekly.every((m) => m == 0);
}

List<int> _manualWeekly(Ref ref) =>
    manualWeekly(ref.watch(workoutLogProvider), ref.watch(clockProvider)());

final manualSummaryProvider = Provider<ActivitySummary>(
  (ref) => ActivitySummary(
    source: ActivitySource.manual,
    weekly: _manualWeekly(ref),
  ),
);

/// Apple Health summary, or null until an import has succeeded.
final healthSummaryProvider = Provider<ActivitySummary?>((ref) {
  final weekly = ref.watch(healthImportProvider).weekly;
  if (weekly == null) return null;
  return ActivitySummary(source: ActivitySource.appleHealth, weekly: weekly);
});

/// The summary the Activity tab shows.
final activitySummaryProvider = Provider<ActivitySummary>((ref) {
  final choice = ref.watch(summarySourceProvider);
  final health = ref.watch(healthSummaryProvider);
  if (choice == ActivitySource.appleHealth && health != null) return health;
  return ref.watch(manualSummaryProvider);
});
