import '../checkin/checkin_models.dart';
import '../checkin/checkin_store.dart';
import 'twin_repository.dart';

/// The check-in controller's [CheckinStore], kept in the phone's protected store through
/// [TwinRepository]. A finished check-in goes through [TwinRepository.applyCheckin], so it
/// is recorded once with its history entry, its `daily_logs` and its weekly
/// `profile_update`. Don't also pass the finished turn to `applyCheckin` from
/// `CheckinController.onFinished`: it would be recorded twice.
class TwinCheckinStore implements CheckinStore {
  TwinCheckinStore(this.repository);

  final TwinRepository repository;

  @override
  Future<List<CheckinEntry>> checkins() async => repository.store.checkins;

  @override
  Future<List<DayLog>> dayLogs() async => repository.store.dayLogs;

  @override
  Future<void> applyFinishedCheckin(Map<String, dynamic> response, {required String localDate}) async {
    if (response['complete'] != true) return;
    await repository.applyCheckin(response, localDate: localDate);
  }

  @override
  Future<CheckinSettings> settings() async => repository.checkinSettings;

  @override
  Future<void> saveSettings(CheckinSettings settings) => repository.saveCheckinSettings(settings);
}
