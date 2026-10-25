import '../twin/twin_history.dart' show CheckinRecord;
import '../twin/twin_model.dart' show isoDate;
import '../twin/twin_repository.dart';
import 'checkin_client.dart';

/// Which check-in is due now. The daily one is the core loop: it is due until a daily check-in has
/// been finished (and accepted at its read-back) today. The weekly one is due on Sundays until one is
/// finished that week (Monday to Sunday). Nothing is due before there is a saved profile: the intake
/// comes first.
class CheckinScheduler {
  CheckinScheduler(this.repository, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final TwinRepository repository;
  final DateTime Function() _now;

  /// The most prominent check-in due now, or null when nothing is due.
  CheckInKind? due() => dueKinds().firstOrNull;

  /// All that are due, most prominent first: daily, then weekly.
  List<CheckInKind> dueKinds() {
    if (!repository.store.hasProfile) return const [];
    return [
      if (!doneToday(CheckInKind.daily)) CheckInKind.daily,
      if (_isWeeklyDay && !doneThisWeek) CheckInKind.weekly,
    ];
  }

  /// A daily check-in was finished today ("Checked in today").
  bool doneToday(CheckInKind kind) {
    final today = isoDate(_now());
    return repository.store.checkins.any((c) => c.kind == kind.name && c.date == today);
  }

  bool get doneThisWeek {
    final now = _now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    return repository.store.checkins.any((CheckinRecord c) {
      final d = DateTime.tryParse(c.date);
      return c.kind == 'weekly' && d != null && !d.isBefore(monday);
    });
  }

  bool get _isWeeklyDay => _now().weekday == DateTime.sunday;
}
