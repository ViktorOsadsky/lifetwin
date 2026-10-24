import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;

import 'checkin_applier.dart';
import 'twin_experiment.dart';
import 'twin_history.dart';
import 'twin_model.dart';
import 'twin_state.dart';
import 'twin_store.dart';

/// The one object the UI talks to: the model (loaded once), the phone's store, the
/// current assessment, check-ins, the twin's state, experiments, and "Delete my data".
/// Everything runs on the phone; nothing here uses the network.
class TwinRepository extends ChangeNotifier {
  TwinRepository({
    required this.model,
    required this.store,
    this.leverRanking = const LeverRanking({}),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (store.hasProfile) _current = assess();
  }

  /// Loads the model and opens the store (call once, at startup).
  static Future<TwinRepository> open({AssetBundle? bundle, StoreBackend? backend, DateTime Function()? clock}) async {
    final loaded = await Future.wait<Object>([
      TwinModelService.load(bundle: bundle),
      TwinStore.open(backend),
      loadLeverRanking(bundle: bundle),
    ]);
    return TwinRepository(
      model: loaded[0] as TwinModelService,
      store: loaded[1] as TwinStore,
      leverRanking: loaded[2] as LeverRanking,
      clock: clock,
    );
  }

  final TwinModelService model;
  final TwinStore store;
  final LeverRanking leverRanking;
  final DateTime Function() _clock;
  TwinAssessment? _current;
  bool _emergency = false;

  /// The assessment of the stored profile with its history window; null before a profile.
  TwinAssessment? get current => _current;

  /// The confirmed profile on the phone.
  Map<String, dynamic> get profile => store.profile;

  /// The package's guidance cards for the current assessment, with `source_url`.
  List<WellnessCard> get wellnessCards => _current?.wellnessCards ?? const [];

  /// Assesses [appProfile] (the stored profile by default) with the phone's history.
  TwinAssessment assess([Map<String, dynamic>? appProfile]) => assessWithHistory(
    model,
    appProfile ?? store.profile,
    weeklySummaries: store.weeklySummaries,
    dailyLogs: store.dailyLogs,
    asOf: _clock(),
  );

  /// Saves the confirmed answers (end of the conversation) and recomputes.
  Future<TwinAssessment> saveConfirmedProfile(Map<String, dynamic> p) async {
    await store.saveProfile(p);
    return _refresh();
  }

  /// Applies a check-in response (`/api/checkin/start` or `/turn`): records a finished
  /// check-in, applies a weekly `profile_update`, stores a weekly summary when complete,
  /// and recomputes the forecast. Also tracks the emergency flag for [twinState].
  Future<CheckinOutcome> applyCheckin(Map<String, dynamic> response) async {
    final outcome = applyCheckinResponse(store.profile, response, localDate: _clock());
    _emergency = outcome.emergency;
    if (outcome.record != null) await store.addCheckin(outcome.record!);
    if (outcome.changedFields.isNotEmpty) await store.saveProfile(outcome.profile);
    if (outcome.weeklySummary != null) await store.putWeeklySummary(outcome.weeklySummary!);
    if (outcome.record != null || outcome.changedFields.isNotEmpty) {
      _refresh();
    } else {
      notifyListeners();
    }
    return outcome;
  }

  /// Clears the emergency state (the person tapped Continue, or the pause ended).
  void clearEmergency() {
    if (!_emergency) return;
    _emergency = false;
    notifyListeners();
  }

  Future<void> addHabitNote(Map<String, dynamic> note) => store.addHabitNote(note);

  /// The character's state now.
  TwinState twinState() =>
      TwinState.derive(assessment: _current, checkins: store.checkins, emergency: _emergency, now: _clock());

  /// A fresh experiment from the current assessment; null before a profile.
  TwinExperiment? experiment() {
    final a = _current;
    if (a == null) return null;
    final used = a.profileUsed;
    return TwinExperiment(
      engine: model.engine,
      current: a,
      appProfile: store.profile,
      order: leverRanking.orderFor(age: used['age'] as num?, sexNhanes: used['sex_nhanes'] as num?),
    );
  }

  /// "Delete my data": the profile, history, notes and twin look, on the phone.
  Future<void> deleteMyData() async {
    await store.deleteAll();
    _current = null;
    _emergency = false;
    notifyListeners();
  }

  TwinAssessment _refresh() {
    final a = assess();
    _current = a;
    notifyListeners();
    return a;
  }
}
