import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../checkin/checkin_models.dart' show CheckinSettings, DayLog, isoDay, shiftDay, weeklyOpen, weeklyOpensLine;
import '../checkin/checkin_reminders.dart' show CheckinReminders;
import '../checkin/checkin_store.dart' show mergeDayLogs;
import '../checkin/daily_logs.dart' show weekProgress;
import '../documents/document_extract.dart' show DocumentCandidate;
import 'checkin_applier.dart';
import 'history_log.dart';
import 'lifespan.dart';
import 'profile_mapping.dart' show toModelProfile;
import 'twin_experiment.dart';
import 'twin_history.dart';
import 'twin_model.dart';
import 'twin_state.dart';

export 'history_log.dart';
export 'lifespan.dart' show LifespanEstimate, LifespanStatus, LifespanPoint;

part 'twin_store.dart';

/// The one object the UI talks to: the model (loaded once), the phone's store, the
/// current assessment, check-ins, history, the twin's state, experiments, and "Delete my
/// data". Everything runs on the phone; nothing here uses the network.
///
/// Who may write (owner ruling: no edits without consulting the agent). There is no setter
/// for profile values or history. The only writes are:
/// - [saveOnboarding] / [saveConversationProfile]: values confirmed in a Mochi conversation
///   (onboarding, a Mochi change; Apple Health values arrive through it after their read-back);
/// - [recordHealthImport]: the Apple Health values the person confirmed (history only);
/// - [applyCheckin]: a finished check-in (weekly `profile_update`, quick `daily_logs`);
/// - [applyDayCorrection]: a past day's answer corrected through a confirmed Mochi read-back;
/// - [applyMemoryConsent] / [addHabitNote]: habit notes, only with `memory_consent`;
/// - [saveTwinLook], [saveCheckinSettings] and [markLifespanRevealSeen]: preferences, not
///   health data;
/// - [saveTodayPlan]: the coach's latest daily plan, so its next revision has a base after a relaunch;
/// - [deleteMyData].
/// Experiments ([experiment]) are hypothetical and never write. Every health write also
/// appends its [HistoryEntry], so [history] shows what happened as it happened.
/// A quick check-in's answers that the server returns as `daily_logs` parts.
const _quickLogAnswers = {
  'sleep_hours_last_night',
  'sleep_hours_night_before',
  'vigorous_recreation_min',
  'moderate_recreation_min',
  'sedentary_min_day',
};

class TwinRepository extends ChangeNotifier {
  TwinRepository({
    required this.model,
    required this.store,
    this.leverRanking = const LeverRanking({}),
    this.reminders,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (store.hasProfile) _current = assess();
  }

  /// Loads the model and opens the store (call once, at startup).
  static Future<TwinRepository> open({
    AssetBundle? bundle,
    StoreBackend? backend,
    CheckinReminders? reminders,
    DateTime Function()? clock,
  }) async {
    final loaded = await Future.wait<Object>([
      TwinModelService.load(bundle: bundle),
      TwinStore.open(backend),
      loadLeverRanking(bundle: bundle),
    ]);
    final repo = TwinRepository(
      model: loaded[0] as TwinModelService,
      store: loaded[1] as TwinStore,
      leverRanking: loaded[2] as LeverRanking,
      reminders: reminders,
      clock: clock,
    );
    // Older profiles get their join date now; then plan the coming week's reminders again.
    if (repo.store.hasProfile) await repo._ensureFirstJoined();
    await repo.replanReminders();
    return repo;
  }

  final TwinModelService model;
  final TwinStore store;
  final LeverRanking leverRanking;

  /// The check-in reminders; Delete my data cancels them.
  final CheckinReminders? reminders;
  final DateTime Function() _clock;
  TwinAssessment? _current;
  bool _emergency = false;

  /// The assessment of the stored profile with its history window; null before a profile.
  TwinAssessment? get current => _current;

  /// The confirmed profile on the phone.
  Map<String, dynamic> get profile => store.profile;

  /// The health score, the Cox HEALTH INDEX: 1.0 is the middle of people your age and sex
  /// in the survey (the same people as [ageGroupPercentile]), HIGHER IS BETTER, above 1
  /// exactly when the percentile is above 50. See [TwinAssessment.healthScore]. Null unless
  /// the model gave a number; see [healthScoreStatus].
  double? get healthScore => _current?.healthScore;

  /// The group [healthScore] compares with, as the band actually used, e.g. `women 59–69`.
  String? get healthGroupLabel => _current?.healthGroupLabel;

  /// The model's own `log_relative_hazard_score`, unchanged (lower is lower modelled risk;
  /// includes age and sex). For internal use; the person sees [healthScore].
  double? get rawLogRelativeHazard => _current?.rawLogRelativeHazard;

  /// Healthier than this share (0–100) of people like you in the survey (same sex, nearby
  /// ages); see [TwinAssessment.ageGroupPercentile]. Null when there is no score.
  double? get ageGroupPercentile => _current?.ageGroupPercentile;
  int? get ageGroupSize => _current?.ageGroupSize;
  String? get ageGroupBand => _current?.ageGroupBand;
  int? get ageGroupWidth => _current?.ageGroupWidth;
  bool? get ageGroupNearestBand => _current?.ageGroupNearestBand;

  /// The one-time lifespan reveal (owner override 2026-10-24): a rough, proof-of-concept
  /// age and YEAR (never a date) from the current profile: the model owner's yearly Cox
  /// projection blended with the life table at the seams (Rough guide where the life table
  /// has the larger weight); see
  /// [LifespanEstimate]. Null when there is no health score (no profile, missing inputs,
  /// unsupported profile, under 18 or over 85).
  LifespanEstimate? get lifespanEstimate {
    final a = _current;
    if (a == null || a.rawLogRelativeHazard == null) return null;
    if (a.roughMissing) {
      // Rough (1 or 2 answers missing): the same marginalised hazard as the score.
      final fill = a.raw['rough_fill'], shift = a.raw['rough_shift'];
      if (fill is! Map || shift is! double) return null;
      return LifespanEstimate.forProfile(
        {...a.profileUsed, ...Map<String, dynamic>.from(fill)},
        currentYear: _clock().year,
        lab: model.projection,
        logHazardShift: shift,
      );
    }
    return LifespanEstimate.forProfile(a.profileUsed, currentYear: _clock().year, lab: model.projection);
  }

  /// The model inputs still missing (package names, e.g. `vigorous_recreation_min_week`); empty
  /// before a profile and when nothing is missing. With 1 or 2 the score is rough
  /// ([HealthScoreStatus.roughMissing]); with more there is none.
  List<String> get missingInputs => _current?.missingInputs ?? const [];
  int get missingCount => missingInputs.length;

  /// True once the person has seen the lifespan reveal; the UI then de-emphasises it.
  /// Persisted; [deleteMyData] clears it.
  bool get lifespanRevealSeen => store.lifespanRevealSeen;

  /// Ideas for you, kept for the day (see [TwinStore.ideasState]); [deleteMyData] clears it.
  Map<String, dynamic> get ideasState => store.ideasState;

  Future<void> saveIdeasState(Map<String, dynamic> state) => store._saveIdeasState(state);

  /// Records that the lifespan reveal was shown.
  Future<void> markLifespanRevealSeen() async {
    if (store.lifespanRevealSeen) return;
    await store._setLifespanRevealSeen();
    notifyListeners();
  }

  /// The coach's latest plan given today (local date), as its JSON; null when none was given today.
  /// Persisted, so "what changed" survives a relaunch; [deleteMyData] clears it.
  Map<String, dynamic>? get todayPlan {
    final kept = store.lastPlan;
    final plan = kept?['plan'];
    return kept?['date'] == isoDay(dayOf(_clock())) && plan is Map ? Map<String, dynamic>.from(plan) : null;
  }

  /// Keeps [plan] (a `DailyPlan`'s JSON) as today's latest plan.
  Future<void> saveTodayPlan(Map<String, dynamic> plan) => store._setLastPlan(isoDay(dayOf(_clock())), plan);

  /// Why [healthScore] has or lacks a number; null before a profile.
  HealthScoreStatus? get healthScoreStatus => _current?.healthScoreStatus;

  /// The model's message when there is no number (null otherwise).
  String? get healthScoreMessage => _current?.message;

  /// The score history between [from] and [to] (local dates, inclusive; open-ended when
  /// null), oldest first. Appended whenever an assessment is made after a Mochi
  /// conversation, a check-in that feeds the forecast, a day correction or an import.
  /// Only points of [engine] (the current [healthScoreEngine] by default) are returned, so
  /// scales from different engines never mix.
  List<HealthScorePoint> healthScoreHistory({DateTime? from, DateTime? to, String engine = healthScoreEngine}) {
    final lo = from == null ? null : isoDate(from), hi = to == null ? null : isoDate(to);
    return [
      for (final p in store.healthScorePoints)
        if (p.engine == engine &&
            (lo == null || p.date.compareTo(lo) >= 0) &&
            (hi == null || p.date.compareTo(hi) <= 0))
          p,
    ];
  }

  /// The package's guidance cards for the current assessment, with `source_url`.
  List<WellnessCard> get wellnessCards => _current?.wellnessCards ?? const [];

  /// Assesses [appProfile] (the stored profile by default) with the phone's history.
  ///
  /// [modelInputs] is a conversation's `model_inputs`: when its `status` is `ready`, its
  /// `profile` (the server's mapping, in the package's codes) is what the model reads,
  /// with the app's own mapping filling only keys it lacks.
  TwinAssessment assess([Map<String, dynamic>? appProfile, Map<String, dynamic>? modelInputs]) {
    final mapped = toModelProfile(appProfile ?? store.profile);
    final ready = readyModelProfile(modelInputs);
    return assessWithHistory(
      model,
      ready == null ? mapped : {...mapped, ...ready},
      checkins: store.checkins,
      dayLogs: store.dayLogs,
      asOf: _clock(),
    );
  }

  /// A conversation's `model_inputs.profile` when `status == 'ready'` (nulls dropped);
  /// null otherwise ("still learning": the model gives no number).
  static Map<String, dynamic>? readyModelProfile(Map<String, dynamic>? modelInputs) {
    if (modelInputs == null || modelInputs['status'] != 'ready' || modelInputs['profile'] is! Map) return null;
    return {
      for (final e in (modelInputs['profile'] as Map).entries)
        if (e.value != null) '${e.key}': e.value,
    };
  }

  /// A finished onboarding conversation (its returned `state`); recorded as
  /// [HistoryKind.onboarding] the first time and as a [HistoryKind.mochiChange] (only the
  /// values that changed) once a profile exists. Memory consent first, then
  /// the habit notes (`state.habit_notes`, kept only when `memory_consent` is true), then
  /// the confirmed profile ([saveConversationProfile]). [modelInputs] is the turn's
  /// `model_inputs`; [sources] the profile keys whose values came from somewhere other
  /// than the person's own words (Apple Health, a document, the wristband). The state's
  /// `estimated_fields` (answers to Mochi's simpler questions) and [estimatedFields]
  /// (confirmed source estimates) are marked estimated.
  Future<TwinAssessment> saveOnboarding(
    Map<String, dynamic> state, {
    Map<String, dynamic>? modelInputs,
    Map<String, String> sources = const {},
    Set<String> estimatedFields = const {},
  }) => _atomically(() async {
    // The first conversation is the onboarding; a later one changes answers through Mochi.
    final kind = store.hasProfile ? HistoryKind.mochiChange : HistoryKind.onboarding;
    final consent = state['memory_consent'];
    if (consent is bool) await store._setMemoryConsent(consent);
    if (consent == true) {
      final kept = {for (final n in store.habitNotes) jsonEncode(n['note'])};
      for (final note in state['habit_notes'] as List? ?? const []) {
        if (note is! Map) continue;
        final n = Map<String, dynamic>.from(note);
        // The same note from a repeated save is kept once.
        if (kept.add(jsonEncode(n))) await store._addHabitNote(n, at: _clock());
      }
    }
    final confirmed = Map<String, dynamic>.from(state['confirmed_profile'] as Map? ?? const {});
    return saveConversationProfile(
      confirmed,
      kind: kind,
      modelInputs: modelInputs,
      sources: sources,
      estimated: {...estimatedFields, for (final f in state['estimated_fields'] as List? ?? const []) '$f'},
    );
  });

  /// Keeps the answers a Mochi conversation confirmed (the whole confirmed profile it
  /// returns) and recomputes. Call only with a conversation's confirmed values.
  /// Follows [mergeConfirmed]: only fields carried with a value change; null or absent
  /// never erases; "not sure" keeps a known value; wrong types are refused.
  ///
  /// [kind] is [HistoryKind.onboarding] or [HistoryKind.mochiChange]. An onboarding entry
  /// lists every confirmed value; a Mochi change only the values that changed (old → new).
  ///
  /// Each changed value's provenance is kept (`store.profileMeta`, [provenance]): its
  /// source from [sources] (by default "You said", or "Changed with Mochi" for a Mochi change)
  /// and `estimated` for the fields in [estimated] and every wristband value.
  Future<TwinAssessment> saveConversationProfile(
    Map<String, dynamic> confirmed, {
    String kind = HistoryKind.onboarding,
    Map<String, dynamic>? modelInputs,
    Map<String, String> sources = const {},
    Set<String> estimated = const {},
  }) => _atomically(() async {
    await _ensureFirstJoined();
    final before = store.profile;
    final merge = mergeConfirmed(before, confirmed);
    if (merge.refused.isNotEmpty) debugPrint('Refused profile fields: ${merge.refused}');
    final fallback = kind == HistoryKind.mochiChange ? HistorySource.mochiChange : HistorySource.said;
    String sourceOf(String k) => HistorySource.all.contains(sources[k]) ? sources[k]! : fallback;
    bool estimatedOf(String k) => estimated.contains(k) || sourceOf(k) == HistorySource.wristband;
    await store._saveProfile(merge.profile, {
      for (final k in merge.changed) k: FieldProvenance(source: sourceOf(k), estimated: estimatedOf(k), at: _clock()),
    });
    final ready = readyModelProfile(modelInputs);
    if (ready != null) {
      // One vocabulary: the server's mapping and the app's must agree (keys only, no values).
      final mine = toModelProfile(merge.profile);
      final differ = [
        for (final k in ready.keys)
          if (mine.containsKey(k) && mine[k] != ready[k]) k,
      ];
      if (differ.isNotEmpty) debugPrint('model_inputs and the app mapping differ on: $differ');
    }
    final fields = kind == HistoryKind.mochiChange
        ? merge.changed
        : [
            for (final k in confirmed.keys)
              if (merge.profile[k] != null && profileSchema.containsKey(k) && !merge.refused.contains(k)) k,
          ];
    await _record(
      kind: kind,
      source: kind == HistoryKind.mochiChange ? HistorySource.mochiChange : HistorySource.said,
      items: [
        for (final k in fields)
          HistoryItem(
            field: k,
            value: merge.profile[k],
            old: before[k] != merge.profile[k] ? before[k] : null,
            source: merge.changed.contains(k) ? sourceOf(k) : (store.profileMeta[k]?.source ?? sourceOf(k)),
            estimated: merge.changed.contains(k) ? estimatedOf(k) : (store.profileMeta[k]?.estimated ?? false),
          ),
      ],
    );
    // A reading only from the numbers this save changed: an unchanged stored half is not
    // a new measurement.
    await _recordReading({for (final k in merge.changed) k: merge.profile[k]}, fallback);
    final a = assess(null, modelInputs);
    _current = a;
    await _recordHealthScore(a);
    notifyListeners();
    return a;
  });

  /// The Apple Health values the person confirmed on the Health screen ("Is this
  /// accurate?"). History only: they reach the profile through the conversation.
  Future<void> recordHealthImport(Map<String, Object?> values, {Set<String> estimatedFields = const {}}) =>
      recordImport(values, source: HistorySource.appleHealth, estimatedFields: estimatedFields);

  /// Values from Apple Health or the wristband that the person confirmed after a
  /// read-back, before the conversation takes them. History only. Wristband values are
  /// always estimates ("≈ Sensor estimate").
  Future<void> recordImport(
    Map<String, Object?> values, {
    required String source,
    bool estimated = false,
    Set<String> estimatedFields = const {},
  }) => _atomically(() async {
    final band = source == HistorySource.wristband;
    await _record(
      kind: band
          ? HistoryKind.wristbandImport
          : source == HistorySource.document
          ? HistoryKind.document
          : HistoryKind.healthImport,
      source: source,
      items: [
        for (final e in values.entries)
          if (e.value != null && (profileSchema[e.key]?.call(e.value!) ?? false))
            HistoryItem(
              field: e.key,
              value: e.value,
              source: source,
              estimated: estimated || estimatedFields.contains(e.key) || band,
            ),
      ],
    );
    if (_current != null) await _recordHealthScore(_current!);
    notifyListeners();
  });

  /// Where the stored value of [field] came from; null for a value saved before
  /// provenance was kept (treat it as "You said").
  FieldProvenance? provenance(String field) => store.profileMeta[field];

  /// [profile] (the stored one by default) without the values that came from the
  /// wristband. Use it for anything sent with `outside_ai_consent` (owner ruling: band
  /// values are not shared with an outside AI until the owner rules).
  Map<String, dynamic> outsideAiProfile([Map<String, dynamic>? profile]) =>
      withoutWristbandValues(profile ?? store.profile, store.profileMeta);

  /// Applies a check-in response (`/api/checkin/start` or `/turn`). A finished check-in
  /// (`complete: true`) is recorded once with its history entry; a quick one merges its
  /// `daily_logs` into the day rows (a later confirmed answer wins, nothing is ever written
  /// as 0); a weekly one applies its `profile_update`. Daily and quick check-ins never
  /// touch the profile. Also tracks the emergency flag for [twinState].
  ///
  /// [localDate] (YYYY-MM-DD) is the date the check-in started; by default the state's
  /// `local_date`, else today.
  Future<CheckinOutcome> applyCheckin(Map<String, dynamic> response, {String? localDate}) => _atomically(() async {
    final state = response['state'] is Map ? response['state'] as Map : const {};
    final stateDate = state['local_date'];
    final date = localDate ?? (stateDate is String && stateDate.length == 10 ? stateDate : isoDate(_clock()));
    final before = store.profile;
    final outcome = applyCheckinResponse(before, response, localDate: date);
    _emergency = outcome.emergency;
    final record = outcome.record;
    if (record == null) {
      notifyListeners();
      return outcome;
    }
    await store._addCheckin(record);
    final items = <HistoryItem>[];
    if (outcome.dayLogParts.isNotEmpty) {
      final rows = store.dayLogs;
      final byDate = {for (final r in rows) r.date: r};
      for (final part in outcome.dayLogParts) {
        for (final f in dayLogSchema.keys) {
          final v = part.valueOf(f);
          if (v == null) continue;
          final old = byDate[part.date]?.valueOf(f);
          items.add(
            HistoryItem(
              field: f,
              value: v,
              old: old != null && old != v ? old : null,
              date: part.date,
              source: HistorySource.said,
            ),
          );
        }
      }
      await store._putDayLogs(mergeDayLogs(rows, outcome.dayLogParts));
    }
    // A weekly answer is the person's own word now, even when the value didn't change: each
    // value the profile took (or kept, unchanged) is theirs, no longer a band estimate.
    final update = response['profile_update'] is Map ? response['profile_update'] as Map : const {};
    final taken = [
      for (final e in update.entries)
        if (record.kind == HistoryKind.weekly && e.value != null && outcome.profile[e.key] == e.value) '${e.key}',
    ];
    if (outcome.changedFields.isNotEmpty || taken.isNotEmpty) {
      await store._saveProfile(outcome.profile, {
        for (final k in {...outcome.changedFields, ...taken})
          k: FieldProvenance(source: HistorySource.said, at: _clock()),
      });
    }
    // The rest of what the person confirmed (feeling, a daily check-in's answers, the
    // weekly answers, with old → new where the profile changed).
    for (final e in record.answers.entries) {
      // A quick check-in's day-log answers are listed above, by the day they describe.
      if (record.kind == HistoryKind.quick && _quickLogAnswers.contains(e.key)) continue;
      final weeklyChange = record.kind == HistoryKind.weekly && outcome.changedFields.contains(e.key);
      items.add(
        HistoryItem(
          field: e.key,
          value: e.value,
          old: weeklyChange ? before[e.key] : null,
          date: record.kind == HistoryKind.weekly ? null : record.date,
          source: HistorySource.said,
        ),
      );
    }
    await _record(
      kind: record.kind,
      source: HistorySource.said,
      items: items,
      days: [for (final p in outcome.dayLogParts) p.date],
      weekStart: outcome.weeklySummary?['week_start'] as String?,
    );
    if (record.kind == HistoryKind.weekly) {
      // A weekly answer is a fresh measurement even when unchanged; a refused value is not one.
      await _recordReading(record.answers, HistorySource.said);
    }
    final a = _refresh();
    // Only a check-in that feeds the forecast (day rows, a weekly summary, a profile change).
    if (outcome.dayLogParts.isNotEmpty || outcome.weeklySummary != null || outcome.changedFields.isNotEmpty) {
      await _recordHealthScore(a);
    }
    return outcome;
  });

  /// A past day's answer, corrected through a confirmed Mochi read-back ("Tuesday I felt
  /// okay, not great"). Records stay append-only: the correction is a new
  /// [HistoryKind.correction] entry linked to the entry it corrects, which is kept and
  /// reads as `corrected`. [field] is a `daily_logs` input (`sleep_hours` for the night
  /// before [date], `vigorous_recreation_min`, `moderate_recreation_min`,
  /// `sedentary_min_day`; that day's row takes the value and the windows recompute) or a
  /// history-only answer (`wellbeing`, …; nothing else changes).
  ///
  /// Refused (returns null, writes nothing): a future date, an unknown field, a wrong
  /// type or range, an "unknown" answer over a known one, a value equal to the current
  /// one, or a day with no earlier answer for [field] to correct.
  Future<HistoryEntry?> applyDayCorrection(
    DateTime date,
    String field,
    Object? value, [
    String source = HistorySource.mochiChange,
  ]) => _atomically(() async {
    final day = isoDate(date);
    if (day.compareTo(isoDate(_clock())) > 0 || !HistorySource.all.contains(source)) return null;
    final logInput = dayLogSchema.containsKey(field);
    final valid = dayLogSchema[field] ?? dayNoteSchema[field];
    if (valid == null || value == null) return null;
    if (isUnknownAnswer(value)) return null; // unknown never replaces a known answer
    if (!valid(value)) return null;
    final original = _latestAnswer(day, field);
    if (original == null) return null;
    final old = original.$2;
    if (old == value) return null;
    if (logInput) {
      await store._putDayLogs(
        mergeDayLogs(store.dayLogs, [
          DayLog.fromJson({'date': day, field: value}),
        ]),
      );
    }
    final entry = await _record(
      kind: HistoryKind.correction,
      source: source,
      items: [HistoryItem(field: field, value: value, old: old, date: day, source: source)],
      days: logInput ? [day] : const [],
      corrects: original.$1.id,
    );
    if (logInput) {
      await _recordHealthScore(_refresh());
    } else {
      notifyListeners();
    }
    return entry;
  });

  /// The entry holding the current answer for [field] on [day] (a correction, or the
  /// check-in that gave it), with that value.
  (HistoryEntry, Object?)? _latestAnswer(String day, String field) {
    final entries = store.historyEntries;
    for (final e in entries.reversed) {
      if (e.kind != HistoryKind.quick && e.kind != HistoryKind.daily && e.kind != HistoryKind.correction) continue;
      for (final i in e.items) {
        if (i.field == field && (i.date ?? e.date) == day) {
          // A correction points back at the first record, so the original reads as corrected.
          final first = e.kind == HistoryKind.correction
              ? entries.firstWhere((o) => o.id == e.corrects, orElse: () => e)
              : e;
          return (first, i.value);
        }
      }
    }
    return null;
  }

  /// Clears the emergency state (the person tapped Continue, or the pause ended).
  void clearEmergency() {
    if (!_emergency) return;
    _emergency = false;
    notifyListeners();
  }

  /// The conversation's `memory_consent`. False deletes the stored habit notes.
  Future<void> applyMemoryConsent(bool consent) async {
    await store._setMemoryConsent(consent);
    notifyListeners();
  }

  /// Keeps a free-form habit note from the conversation, only with memory consent.
  /// Returns false (and keeps nothing) without it.
  Future<bool> addHabitNote(Map<String, dynamic> note) async {
    if (!store.memoryConsent) return false;
    await store._addHabitNote(note, at: _clock());
    return true;
  }

  /// The twin's cosmetic look (`type`, `look`, `name`); never part of the health profile.
  Future<void> saveTwinLook(Map<String, dynamic> look) => store._saveTwin(look);

  /// The person's consent to outside-AI wording (owner ruling: Muse is on, but only after
  /// this yes). Stored on the phone; off by default and after Delete my data. It covers
  /// only [outsideAiProvider]: consent for one provider never covers another.
  bool get outsideAiConsent => store.outsideAiConsent;
  String? get outsideAiProvider => store.outsideAiProvider;

  /// Sets the consent for [provider], the id from `/api/capabilities` `personalize.provider`
  /// (`claude` or `muse`). Required: no caller can record a consent for a provider by default.
  Future<void> setOutsideAiConsent(bool consent, {required String provider}) async {
    await store._saveOutsideAiConsent(consent, provider);
    notifyListeners();
  }

  /// The request field `outside_ai_consent` for [provider]: `{provider: true}` only with
  /// a yes for that same provider, else empty. Send it with [outsideAiProfile].
  Map<String, bool> outsideAiConsentFor(String provider) =>
      outsideAiConsent && outsideAiProvider == provider ? {provider: true} : const {};

  // ---- reminders ------------------------------------------------------------------

  /// Plans the next week's reminders again from the saved settings and check-ins (a
  /// done day gets none). Runs at app start ([open]) and on every [refresh]; a reminder
  /// that can't be planned never blocks the app. Returns the planned times.
  Future<List<DateTime>> replanReminders() async {
    final r = reminders;
    if (r == null) return const [];
    try {
      final now = _clock();
      final later = DateTime.tryParse(store.remindLater ?? '');
      // A remind-later that has fired or passed is done; one still ahead survives the replan.
      if (store.remindLater != null && (later == null || !later.isAfter(now))) await store._setRemindLater(null);
      return await r.reschedule(
        checkinSettings,
        localNow: now,
        history: store.checkins,
        firstJoined: firstJoined,
        remindLaterAt: later,
      );
    } catch (e) {
      debugPrint('Reminders could not be planned: $e');
      return const [];
    }
  }

  /// The local date onboarding was first completed (null before a profile). A profile saved
  /// before this was kept reads as its earliest history or check-in date, else today.
  String? get firstJoined {
    final kept = store.firstJoined;
    if (kept != null || !store.hasProfile) return kept;
    final dates = [
      for (final e in store.historyEntries) isoDay(dayOf(e.at)),
      for (final c in store.checkins) c.date,
    ]..sort();
    return dates.isEmpty ? isoDay(dayOf(_clock())) : dates.first;
  }

  Future<void> _ensureFirstJoined() async {
    if (store.firstJoined != null) return;
    final joined = store.hasProfile ? firstJoined : isoDay(dayOf(_clock()));
    if (joined != null) await store._setFirstJoined(joined);
  }

  /// Is the weekly check-in available now? Not until 7 full days after joining.
  bool get weeklyAvailable => weeklyOpen(today: isoDay(dayOf(_clock())), firstJoined: firstJoined);

  /// The gentle line shown where the weekly check-in would be, or null once it is open.
  String? get weeklyGateLine {
    final joined = firstJoined;
    return joined == null || weeklyAvailable ? null : weeklyOpensLine(joined);
  }

  /// "Remind me later" on the plan: one extra reminder a couple of hours from now (reminders are on),
  /// kept out of quiet hours. Remembered in the store so a refresh doesn't wipe it.
  Future<void> remindLater() async {
    final r = reminders;
    if (r == null) return;
    try {
      final s = checkinSettings;
      final at = await r.remindLater(_clock(), hour: s.reminderHour, minute: s.reminderMinute);
      await store._setRemindLater(at.toIso8601String());
    } catch (e) {
      debugPrint('Reminder could not be planned: $e');
    }
  }

  /// Show the one-time "Would you like a gentle reminder each day?" offer: at the end of
  /// onboarding (a profile is saved) or after the first check-in, until it is answered.
  bool get shouldOfferReminders =>
      reminders?.shouldOffer(checkinSettings, store.checkins, onboarded: store.hasProfile) ?? false;

  /// Yes to the offer at [hour]:[minute] (10:00 unless picked): the phone asks to allow
  /// notifications now, then the week is planned. Reminders stay off if the phone says no.
  Future<void> acceptReminders({int? hour, int? minute}) async {
    final r = reminders;
    if (r == null) return;
    final next = await r.accept(
      checkinSettings,
      localNow: _clock(),
      history: store.checkins,
      hour: hour,
      minute: minute,
      firstJoined: firstJoined,
    );
    await saveCheckinSettings(next);
  }

  /// "Not now": remembered, so the offer isn't repeated.
  Future<void> declineReminders() async {
    final r = reminders;
    if (r == null) return;
    await saveCheckinSettings(r.decline(checkinSettings));
  }

  /// Reminder time and weekly day. Not health data.
  CheckinSettings get checkinSettings => store.checkinSettings;
  Future<void> saveCheckinSettings(CheckinSettings settings) async {
    await store._saveCheckinSettings(settings);
    notifyListeners();
  }

  // ---- history (read only) ------------------------------------------------------

  /// The person's history between [from] and [to] (local dates, inclusive; open-ended
  /// when null), newest first. Each entry says whether it fed the current forecast
  /// (`fedForecast`) and whether a later correction replaced it (`correctedBy`).
  List<HistoryEntry> history({DateTime? from, DateTime? to}) {
    final lo = from == null ? null : isoDate(from), hi = to == null ? null : isoDate(to);
    final entries = store.historyEntries;
    final correctedBy = <String, String>{
      for (final e in entries)
        if (e.corrects != null) e.corrects!: e.id,
    };
    final p = _current?.inputProvenance ?? const {};
    final source = p['source'], start = p['window_start'] as String?, end = p['window_end'] as String?;
    bool inWindow(String d) => start != null && end != null && d.compareTo(start) >= 0 && d.compareTo(end) <= 0;
    // A later weekly check-in for the same week replaces the earlier one's summary.
    final weekOwner = <String, String>{
      for (final e in entries)
        if (e.weekStart != null) e.weekStart!: e.id,
    };
    String? fed(HistoryEntry e) {
      if (source == 'weekly_summaries' && e.weekStart != null && weekOwner[e.weekStart] == e.id) {
        return inWindow(e.weekStart!) ? 'weekly_summaries' : null;
      }
      if (source == 'daily_logs' && e.days.any(inWindow)) return 'daily_logs';
      return null;
    }

    return [
      for (final e in entries.reversed)
        if ((lo == null || e.date.compareTo(lo) >= 0) && (hi == null || e.date.compareTo(hi) <= 0))
          e.withStatus(fedForecast: fed(e), correctedBy: correctedBy[e.id]),
    ];
  }

  /// Confirmed readings over time, oldest first: information for the person and the coach,
  /// never a model, forecast or health score input. They are the `reading` entries of
  /// [history], and their items are:
  /// - `systolic_bp`, `diastolic_bp` (mmHg, whole numbers) from weekly check-ins, Mochi
  ///   changes and documents;
  /// - `hba1c` (%, 3-20) and `ldl_cholesterol` (mg/dL, 20-400), from documents only.
  ///
  /// Date: an item's `date` is the document's own date (YYYY-MM-DD) when it had one; a
  /// check-in reading has no item date. Otherwise the entry's `at` is the confirmation time
  /// and, for a document, [HistoryEntry.dateNotOnDocument] is true.
  List<HistoryEntry> readings() => [
    for (final e in history().reversed)
      if (e.kind == HistoryKind.reading) e,
  ];

  /// One row per day from [from] to [to] (inclusive), oldest first, for a calendar. A
  /// day without an answer has null values: unknown, never 0.
  List<DayLog> dayLogs({required DateTime from, required DateTime to}) {
    final byDate = {for (final r in store.dayLogs) r.date: r};
    final last = isoDate(to);
    return [for (var d = isoDate(from); d.compareTo(last) <= 0; d = shiftDay(d, 1)) byDate[d] ?? DayLog(date: d)];
  }

  /// Monday–Sunday weeks with at least 4 different days with a finished check-in of any
  /// kind, all time. Never a streak: a missed week costs nothing.
  int goodWeeks() => weekProgress(store.checkins, isoDate(_clock())).goodWeeks;

  // ---- the twin ----------------------------------------------------------------

  /// The character's state now.
  TwinState twinState() => TwinState.derive(
    assessment: _current,
    checkins: store.checkins,
    today: store.dayLogs.where((d) => d.date == isoDate(_clock())).firstOrNull,
    emergency: _emergency,
    now: _clock(),
  );

  /// A fresh experiment from the current assessment; null before a profile.
  TwinExperiment? experiment() {
    final a = _current;
    if (a == null) return null;
    final used = a.profileUsed;
    return TwinExperiment(
      model: model,
      current: a,
      appProfile: store.profile,
      order: leverRanking.orderFor(age: used['age'] as num?, sexNhanes: used['sex_nhanes'] as num?),
    );
  }

  /// "Delete my data": the profile and its provenance, history, day logs, notes, settings,
  /// the outside-AI consent, the twin look and the lifespan-reveal flag, on the phone, and
  /// the planned reminders.
  Future<void> deleteMyData() async {
    try {
      await reminders?.port.cancelAll();
    } catch (e) {
      debugPrint('Reminders could not be cancelled: $e');
    }
    await store._deleteAll();
    _current = null;
    _emergency = false;
    notifyListeners();
  }

  // ---- private -----------------------------------------------------------------

  Future<HistoryEntry?> _record({
    required String kind,
    required String source,
    required List<HistoryItem> items,
    List<String> days = const [],
    String? weekStart,
    String? corrects,
  }) async {
    if (items.isEmpty) return null;
    final entry = HistoryEntry(
      id: 'h${store.historyEntries.length + 1}',
      kind: kind,
      at: _clock(),
      source: source,
      items: items,
      days: days,
      weekStart: weekStart,
      corrects: corrects,
    );
    await store._addHistory(entry);
    return entry;
  }

  /// Appends the score the model gave for [a] (also when it gave none, with its status).
  Future<void> _recordHealthScore(TwinAssessment a) => store._addHealthScore(
    HealthScorePoint(
      at: _clock(),
      rawLogRelativeHazard: a.rawLogRelativeHazard,
      score: a.healthScore,
      status: a.healthScoreStatus,
      ageGroupPercentile: a.ageGroupPercentile,
      ageGroupSize: a.ageGroupSize,
      ageGroupBand: a.ageGroupBand,
      modelVersion: a.modelVersion.isEmpty ? model.modelVersion : a.modelVersion,
    ),
  );

  /// A confirmed blood pressure reading in [values] becomes its own dated entry, with
  /// only the numbers that pass the profile's checks.
  Future<void> _recordReading(Map<String, dynamic> values, String source) async {
    await _record(
      kind: HistoryKind.reading,
      source: source,
      items: [
        for (final f in const ['systolic_bp', 'diastolic_bp'])
          if (values[f] != null && profileSchema[f]!(values[f] as Object))
            HistoryItem(field: f, value: values[f], source: source),
      ],
    );
  }

  /// The blood pressure, A1c and LDL values the person kept ("Keep") from a document,
  /// each its own `reading` entry item with its unit and the document's date (none when
  /// the document had none). Values outside the plausible range are dropped, never clamped.
  /// History only: nothing here reaches the profile, the forecast or the health score.
  Future<void> recordDocumentReadings(Iterable<DocumentCandidate> kept) => _atomically(() async {
    for (final c in kept) {
      final items = _documentReadingItems(c);
      if (items.isEmpty) continue;
      await _record(kind: HistoryKind.reading, source: HistorySource.document, items: items);
    }
    notifyListeners();
  });

  List<HistoryItem> _documentReadingItems(DocumentCandidate c) {
    final date = c.date == null ? null : isoDate(c.date!);
    HistoryItem item(String f, Object v) => HistoryItem(field: f, value: v, source: HistorySource.document, date: date);
    final v = c.value;
    switch (c.field) {
      case 'blood_pressure':
        final m = v is String ? RegExp(r'^(\d{2,3})/(\d{2,3})$').firstMatch(v) : null;
        if (m == null) return const [];
        final sys = int.parse(m.group(1)!), dia = int.parse(m.group(2)!);
        return [
          if (profileSchema['systolic_bp']!(sys)) item('systolic_bp', sys),
          if (profileSchema['diastolic_bp']!(dia)) item('diastolic_bp', dia),
        ];
      case 'hba1c':
        if (v is! num || (c.unit != null && c.unit != '%') || !readingSchema['hba1c']!(v)) return const [];
        return [item('hba1c', v)];
      case 'ldl_cholesterol':
        if (v is! num) return const [];
        // mmol/L is converted; the stored unit is always mg/dL.
        final mg = c.unit == 'mmol/L' ? (v * 38.67).roundToDouble() : v;
        if (!readingSchema['ldl_cholesterol']!(mg)) return const [];
        return [item('ldl_cholesterol', mg)];
      default:
        return const [];
    }
  }

  /// One write per event (see `TwinStore._transaction`); if it fails, memory and the
  /// forecast are put back as they were.
  Future<T> _atomically<T>(Future<T> Function() body) async {
    try {
      return await store._transaction(body);
    } catch (_) {
      _current = store.hasProfile ? assess() : null;
      notifyListeners();
      rethrow;
    }
  }

  /// Call on every app open: recomputes [current] (a daily window ends yesterday; null
  /// before a profile) and plans the coming week's reminders again ([replanReminders]).
  TwinAssessment? refresh() {
    unawaited(replanReminders());
    return store.hasProfile ? _refresh() : null;
  }

  TwinAssessment _refresh() {
    final a = assess();
    _current = a;
    notifyListeners();
    return a;
  }
}

/// [profile] without the fields whose provenance is the wristband (owner ruling: band
/// values never go to an outside AI until the owner rules).
Map<String, dynamic> withoutWristbandValues(Map<String, dynamic> profile, Map<String, FieldProvenance> meta) => {
  for (final e in profile.entries)
    if (meta[e.key]?.source != HistorySource.wristband) e.key: e.value,
};
