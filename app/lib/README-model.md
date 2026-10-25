# On-device model, phone storage, experiments and twin state

This folder (`lib/twin/`) is the data and logic layer behind the forecast, "experiment with your twin", check-in history, the person's history view and the character's state. It has no screens. Everything runs on the phone. Nothing in it uses the network.

## The model package

`packages/lifetwin_on_device/` is a copy of `model_handoff/lifetwin_on_device/` (model `personal-cox-v2-20261024T182404Z`). The app's `pubspec.yaml` depends on it by path.

- **Why a copy:** the package README says to copy it. The copy also pins the model the app was tested with, so a new export in `model_handoff/` can't silently change app results. To update, copy the new folder over and rerun the checks below.
- **Checks** (run in `packages/lifetwin_on_device/`): `flutter test` and `dart tool/check.dart`. Both pass on macOS. `flutter analyze` in `app/` excludes `packages/**` because the vendored code uses its own style.
- **Loading:** `TwinRepository.open()` loads the model once at startup (`main.dart`, `_twin`).
- **Server route:** `POST /api/predict` (`server/lifetwin/prediction/`) still works but the app no longer calls it. It should be removed later.

## UI rules (from the package README, enforced here)

- Show numbers only when `survival.status == 'available'`. `TwinAssessment.available`, `Forecast.supported` and `ExperimentResult.available` all mean this.
- Otherwise show `message` and no number. The statuses are `missing_inputs`, `unsupported_age`, `unsupported_profile`, and the app's own `invalid_input`, used when the package refused a value (a `FormatException`). In that case, ask the person to correct the value.
- Label the curve `TwinAssessment.survivalTitle` ("Modeled survival of similar people").
- Label comparisons `ExperimentResult.title` ("Modeled difference between profiles"). `causalInterpretation` is always false.
- Never show a death date, an age at death or years gained.
- Nothing is filled in. A missing answer is never replaced by a typical or healthy value. The "We assumed" section is gone.

## Ages 30–34 and 80–85 (extrapolated)

Owner ruling: "it is okay to extrapolate a bit below and above the age ranges". The package itself supports only ages 35–79, and its files are not edited. `TwinModelService` (`twin_model.dart`) wraps it for these two bands:

1. **Run the package at the nearest checked age.** For an age of 30–34 the package runs at 35; for 80–85 it runs at 79. So every other check still applies unchanged: missing inputs, entry ranges, the 1st–99th percentile support, and the nearest-neighbour support.
2. **Move only the age term to the real age**, using the model's own coefficient: `score += coefficient[age_decade] × (age − anchor) / 10`, then `S(t) = baseline(t)^exp(score)`.
3. **The age is never clamped.** An 84-year-old gets lower survival than the same profile at 79. A test checks the formula against the package inside 35–79.

What the UI sees for these ages:

- `TwinAssessment.extrapolated`, `Forecast.extrapolated` and `ExperimentResult.extrapolated` are true. The raw results also carry `extrapolated: true` and `extrapolation_caveat`.
- Show `extrapolationCaveat` with any number: "Your age is outside the ages this model was checked on (35–79), so treat this as a rough guide." The forecast screen and Why? already do.
- `profile_used.age` is the person's real age.

Under 30 or over 85 there is no number: `unsupported_age` with "Annual estimates support ages 30–85 only." The wellness cards don't change, because the package's guidance only changes at ages 18, 61 and 65, which neither anchor crosses.

## Profile mapping (`profile_mapping.dart`)

The app keeps the confirmed profile under the field names of `server/lifetwin/core/models.py`. `toModelProfile()` maps it to the package's 11 inputs.

| Package input | App field | Mapping |
|---|---|---|
| `age` | `age` | as is (years) |
| `bmi` | `height_cm` + `weight_kg` | passed as the pair; the package derives BMI. If either is missing, `bmi` is missing |
| `sleep_hours` | `sleep_hours` | as is (hours per night) |
| `vigorous_recreation_min_week` | `vigorous_recreation_min_week` | as is (min/week) |
| `moderate_recreation_min_week` | `moderate_recreation_min_week` | as is (min/week) |
| `sedentary_min_day` | `sedentary_min_day` | as is (awake sitting, min/day) |
| `sex_nhanes` | `sex` | `male` → 1, `female` → 2 |
| `smoking_status` | `smoking_status` | `never` → 0, `former` → 1, `current` → 2; `unknown` → missing |
| `diabetes_diagnosed` | `diabetes` | true → 1, false → 0 |
| `hypertension_diagnosed` | `hypertension_diagnosed` (`hypertension`, from older saves, also accepted) | true/1 → 1, false/0 → 0 |
| `general_health` | `general_health` | 1–5, or `excellent` 1, `very_good` 2, `good` 3, `fair` 4, `poor` 5 |

Not mapped:

- `exercise_minutes_weekly`, today's single exercise answer, is not split into hard and moderate minutes. Splitting it would mean guessing.
- `alcohol_drinks_weekly`, `systolic_bp` and `diastolic_bp` are not model inputs. They stay in the profile.

**One vocabulary.** The conversation (v2) collects these fields under the same names, and its `model_inputs.profile` uses the package's codes. A profile saved before the five new fields (`general_health`, `hypertension_diagnosed`, `sedentary_min_day`, `moderate_recreation_min_week`, `vigorous_recreation_min_week`) still loads; the model then reports those inputs in `missing_inputs` until they are answered. Nothing is filled in.

**`model_inputs` from onboarding.** When a conversation turn's `model_inputs.status` is `ready`, the model reads its `profile` (`repo.assess(profile, modelInputs)`, `saveOnboarding(..., modelInputs:)`, and the forecast client through `OnDeviceForecastClient(modelInputs:)`), with the app's own mapping filling only keys it lacks. Otherwise (`still_learning`, `unsupported_age`) the app maps the confirmed answers itself, which gives `missing_inputs` or `unsupported_age`. At save time a disagreement between the two mappings is logged by key, never by value. Later reads (after a check-in or on app open) use the stored profile.

**How unknown or missing inputs are reported:** by the package's input names, never by app field names. A missing height or weight is reported as `bmi`.

| Where | Field |
|---|---|
| Assessment | `TwinAssessment.missingInputs` |
| Forecast | `Forecast.missingInputs`, with plain words in `missingLabels` (from `modelInputLabels`) |
| Experiment result | `ExperimentResult.missingInputs` |
| Unavailable lever | `ExperimentLever.missingInput`, with reason `missing_input` |
| Refused value | `TwinAssessment.invalidInput` (status `invalid_input`) |

## The repository: `TwinRepository` (`twin_repository.dart`)

This is the one object the UI and the check-in controller (`lib/checkin/`) should use. Treat the interface below as stable.

| Member | What it does |
|---|---|
| `static Future<TwinRepository> open({AssetBundle? bundle, StoreBackend? backend, CheckinReminders? reminders, DateTime Function()? clock})` | Loads the model and sensitivity ranking, opens the store. `main.dart` passes `CheckinReminders(LocalNotificationPort())` |
| `TwinAssessment? current` / `TwinAssessment? refresh()` | Assessment of the stored profile, with the history window; null before a profile. Call `refresh()` on app open (a daily window ends yesterday) |
| `Map<String, dynamic> profile` | Confirmed profile (read only) |
| `TwinStore store` | Read-only views: `profile`, `hasProfile`, `checkins`, `dayLogs`, `historyEntries`, `habitNotes`, `twin`, `checkinSettings`, `memoryConsent` |
| `TwinAssessment assess([Map? appProfile, Map? modelInputs])` | Assesses any profile with the phone's history; writes nothing |
| `Future<TwinAssessment> saveOnboarding(Map state, {Map? modelInputs, Map<String, String> sources})` | A finished conversation: memory consent, habit notes (only with consent), then the confirmed profile. The first one is recorded as `onboarding`, later ones as `mochi_change` |
| `Future<TwinAssessment> saveConversationProfile(Map confirmed, {String kind, Map? modelInputs, Map<String, String> sources, Set<String> estimated})` | Keeps a Mochi conversation's confirmed profile and recomputes. `kind` is `onboarding` (default) or `mochi_change` |
| `Future<void> recordHealthImport(Map values)` / `recordImport(Map values, {required String source, bool estimated})` | Apple Health (or wristband) values confirmed after their read-back; history only |
| `FieldProvenance? provenance(String field)` | Where the stored value came from (`source`, `estimated`, `at`, `sourceLabel`, `estimateText`); null for a value saved before provenance was kept ("You said") |
| `Map<String, dynamic> outsideAiProfile([Map? profile])` | The profile without wristband values, for anything sent with `outside_ai_consent` |
| `bool outsideAiConsent` / `String? outsideAiProvider` / `Future<void> setOutsideAiConsent(bool consent, {String provider = 'muse'})` | The person's yes to outside-AI wording, stored on the phone, off by default and after Delete my data. Ask with the name from `/api/capabilities` `personalize.display_name` ("Muse by Meta") |
| `Map<String, bool> outsideAiConsentFor(String provider)` | The request's `outside_ai_consent` value: `{provider: true}` only with a yes for that same provider, else `{}` |
| `Future<CheckinOutcome> applyCheckin(Map response, {String? localDate})` | Applies a `/api/checkin/start` or `/turn` response (below) |
| `Future<HistoryEntry?> applyDayCorrection(DateTime date, String field, Object? value, [String source])` | A past day's answer corrected through a confirmed Mochi read-back (below) |
| `List<HistoryEntry> history({DateTime? from, DateTime? to})` | The person's history, newest first (below) |
| `List<HistoryEntry> readings()` | Confirmed readings over time, oldest first: the `reading` entries of `history()`. Items: `systolic_bp`, `diastolic_bp` (mmHg), `hba1c` (%, 3–20), `ldl_cholesterol` (mg/dL, 20–400). Item `date` = the document's own date; none means the confirmation date in `entry.at` (`dateNotOnDocument`, show "date not on the document"). Never a model, forecast or health score input |
| `Future<void> recordDocumentReadings(Iterable<DocumentCandidate> kept)` | Records the kept ("Keep") blood pressure, A1c and LDL candidates as `reading` entries, source `document`. Out-of-range values (`readingSchema`, not `profileSchema`) are rejected, never clamped; an LDL in mmol/L is converted to mg/dL. "Skip" and "Change with Mochi" record nothing |
| `List<DayLog> dayLogs({required DateTime from, required DateTime to})` | One row per day for a calendar; a day without an answer has null values |
| `int goodWeeks()` | Monday–Sunday weeks with at least 4 different days with a finished check-in of any kind |
| `CheckinSettings checkinSettings` / `saveCheckinSettings(s)` | Reminder time and weekly day; not health data |
| `void clearEmergency()` | After "Continue" on an emergency pause |
| `Future<void> applyMemoryConsent(bool)` | The conversation's `memory_consent`; false deletes stored habit notes |
| `Future<bool> addHabitNote(Map note)` | Kept only with memory consent; returns false otherwise |
| `Future<void> saveTwinLook(Map look)` | Cosmetic `{type, look, name}` only |
| `List<WellnessCard> wellnessCards` | The package's guidance cards for `current` |
| `TwinState twinState()` | The character's state now |
| `TwinExperiment? experiment()` | A fresh experiment from `current` |
| `Future<void> deleteMyData()` | "Delete my data": cancels the reminders, removes the file (profile, provenance, history, day logs, notes, settings, outside-AI consent, twin look) and clears memory |

`TwinCheckinStore(repo)` (`twin_checkin_store.dart`) is the check-in controller's `CheckinStore`: `CheckinController(store: TwinCheckinStore(repo), reminders: repo.reminders, ...)`. It saves the finished check-in through `applyCheckin`, so don't also pass the finished turn to `applyCheckin` from `onFinished`. To keep the twin's emergency state, pass each turn that is not complete to `applyCheckin` (it is never recorded).

It is a `ChangeNotifier`, so bind it with `ListenableBuilder`.

### Who may write (owner ruling)

The owner's rule is: "people shouldn't be able to edit their things unless they consult with their agent first." So there is no setter for profile values or history. `TwinStore`'s write methods are private to the repository library. The only writes are:

1. `saveOnboarding` / `saveConversationProfile`, with values confirmed in a Mochi conversation: onboarding (`main.dart` calls `saveOnboarding` on Continue) and the "change through Mochi" conversation (`kind: HistoryKind.mochiChange`). Apple Health values arrive through the conversation after their read-back (`importHealth`).
2. `recordHealthImport` / `recordImport`, history only, for values confirmed after their read-back (the Health screen, the wristband).
3. `applyCheckin`, for a finished check-in: a weekly `profile_update`, a quick check-in's `daily_logs`.
4. `applyDayCorrection`, for a past day's answer, from a confirmed Mochi read-back.
5. `applyMemoryConsent` / `addHabitNote`, for habit notes, only with consent.
6. `saveTwinLook` and `saveCheckinSettings`, which are preferences.
7. `deleteMyData`.

Every health write appends its history entry at the same time, in one write to the file: if the write fails, nothing of that event is kept (memory is put back), so a retry never records a check-in twice. Experiment levers are hypothetical and never write to the profile.

**Write rules** (`mergeConfirmed` / `profileSchema`, shared by every profile write):

- Null or absent never erases.
- Wrong types, out-of-range values and non-profile keys are refused (`CheckinOutcome.refusedFields`).
- "Unknown" never replaces a known value; it only fills a gap.
- Daily and quick check-ins never touch the profile.
- Day values (`dayLogSchema`, `dayNoteSchema`) are type- and range-checked the same way; a refused value is left unknown.
- A missed day is unknown, never 0.

## Storage choice

The store is one JSON document, written by the iOS runner (`ios/Runner/AppDelegate.swift`, channel `lifetwin/protected_store`) to `Application Support/LifeTwin/twin_store.json`:

- with `NSFileProtectionComplete`, so the file is unreadable while the phone is locked;
- excluded from iCloud and computer backups, so it is never synced;
- with no network involved.

**Why not `flutter_secure_storage` plus an encrypted file:** that means two new dependencies, a crypto package, and key management, for no gain on iOS. The file is already encrypted at rest by Data Protection under the passcode key. The Keychain is meant for secrets, not growing history.

**Tradeoff:** the app can't read the file while the phone is locked, for example from a background task. That's acceptable because LifeTwin reads it in the foreground and keeps it in memory.

**Checks:**

- `integration_test/store_protection_test.dart` round-trips through the real channel on the simulator.
- The simulator has no protection classes, so the channel reports `simulator`. The protection class itself needs one check on a physical phone.
- Under `flutter test` or on macOS, the backend keeps data in memory only and never writes it unprotected.

## Check-ins (`checkin_applier.dart`)

`applyCheckinResponse(profile, response, localDate:)` follows `contracts/checkin.schema.json`. Its contract cases are in `test/fixtures/checkin_contract_cases.json`; real server responses for the merged flow are in `test/fixtures/merged_flow.json` (written by `server/tests/make_app_fixtures.py`).

- **Quick, `complete: true`:** recorded as a `CheckinEntry`. Its `daily_logs` parts are type-checked and merged into the stored day rows (`readFinishedCheckin` + `mergeDayLogs`): each known value goes into its date's row and a later confirmed answer wins. A missing value is never written. `workday` is worked out when the window is built: Monday to Friday.
- **Daily, `complete: true`:** history only.
- **Weekly, `complete: true`:** every non-null `profile_update` field is set on the profile under the write rules, then the forecast is recomputed. When the confirmed answers cover all four behaviour fields within the package's limits, the check-in makes a weekly summary (`DailyLogsAssembler.weeklySummaries`, worked out from the stored check-ins; a later check-in for the same week wins). A weekly check-in describes the past seven days, so it is filed under the Monday–Sunday week holding most of them (`weekDescribedBy`): from Thursday to Sunday its own week, from Monday to Wednesday the week before. Whatever weekly day the person picks, a completed week is then there for the forecast every day until the next check-in.
- **Quick day values** are accepted only for the check-in's own date and the day before.
- **"Not sure" vs the server.** The server may confirm `smoking_status: "unknown"` for a person whose stored answer is `former`. The app keeps `former` (owner ruling).
- **`emergency: true`:** sets `CheckinOutcome.emergency`. It is never stored. The twin shows `concerned` until `clearEmergency()` or the next ordinary response.

**History windows** (one assembler: `DailyLogsAssembler` in `lib/checkin/daily_logs.dart`, used by `candidateWindows` / `assessWithHistory` in `twin_history.dart`): `assess()` tries complete weekly summaries first (1–4 consecutive completed weeks ending with the latest one), then complete daily logs (the longest of 28, 21, 14 or 7 consecutive days ending yesterday, with three workday nights a week), then the profile snapshot. A window the package refuses is skipped, never patched. One day's answers never change the forecast by themselves. Keep `profile_used` and `input_provenance` (`TwinAssessment.profileUsed`, `.inputProvenance`, `.source`) visible in the UI.

## History for the person (`history_log.dart`)

Owner: "Make sure the daily check ins and optional other check ins are logged and recorded and available to users." The store appends one entry per event as it happens, in the same protected file as everything else. Entries are never edited; only Delete my data removes them.

```dart
final entries = repo.history(from: DateTime(2026, 10, 1), to: DateTime.now()); // newest first
final days = repo.dayLogs(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
final weeks = repo.goodWeeks();
final bp = repo.readings();
```

**`HistoryEntry`:**

| Field | Meaning |
|---|---|
| `id` | Stable id (`h1`, `h2`, ...) |
| `kind` | `HistoryKind`: `quick`, `daily`, `weekly`, `onboarding`, `mochi_change`, `health_import`, `correction`, `reading`; `document` is reserved for document-upload confirmations |
| `at`, `date`, `time` | The phone's local date and time it happened (`YYYY-MM-DD`, `HH:MM`) |
| `source`, `sourceLabel` | `HistorySource`: `you_said` "You said", `apple_health` "Apple Health", `document` "Document", `mochi_change` "Mochi change", `wristband` "From your band" |
| `items` | `HistoryItem`s, below |
| `days` | Quick check-ins and corrections: the days whose day-log row this wrote |
| `weekStart` | Weekly check-ins whose answers made a weekly summary: that week's Monday |
| `fedForecast` | `weekly_summaries` or `daily_logs` when this entry's values are in the window the current forecast used; null otherwise (worked out when read) |
| `corrects` / `correctedBy` / `corrected` | A correction's original entry; the original's latest correction |

**`HistoryItem`:** `field`, `label` (plain words, e.g. "time sitting"), `value`, `unit`, `text` (the value with units in plain words: "7.5 hours", "very good", "no"), `old` / `oldText` (for a change: the value before), `isChange`, `date` (the day a day value describes), `source` / `sourceLabel` (every item has one; an onboarding entry can mix "You said" and Apple Health), and `estimated` / `estimateText` ("≈ Sensor estimate" for a band value, "≈ Rough estimate" for an answer to Mochi's simpler question; null otherwise).

### Provenance per value (owner ruling on the wristband)

Owner: "We are calibrating it. For this demo and this scope, we need it as a confirmation." A wristband estimate (for example moderate minutes a week after at least 4 worn days of 10 or more hours) that the person confirmed after a read-back is saved as their answer, and may change the outlook.

- **Sources:** `you_said`, `apple_health`, `document`, `mochi_change`, `wristband` (`HistorySource`). Any other value passed in `sources` is treated as `you_said`.
- **Where it's kept:** for each profile value, `store.profileMeta[field]` / `repo.provenance(field)` (`FieldProvenance{source, estimated, at}`), and on every `HistoryItem`.
- **`estimated: true`:** every wristband value, and the fields in the conversation's `state.estimated_fields` (proxy answers). Show `estimateText` beside the value: "From your band · ≈ Sensor estimate".
- **When it changes:** a conversation save sets provenance for the values it changed (an unchanged value keeps its old provenance). A weekly answer is the person's own word, so every value it confirms becomes `you_said`, even when unchanged. `main.dart` labels an Apple Health value `apple_health` only while the confirmed answer still equals the imported one.
- **Server side:** the document branch adds `import_source: apple_health | document` to the onboarding `TurnRequest`. Plan `wristband` as a third value there; this branch has no server change for it. Until then the app passes the source itself: `saveOnboarding(state, sources: {'moderate_recreation_min_week': HistorySource.wristband})`, `recordImport(values, source: HistorySource.wristband)`.
- **Outside AI:** band values are never sent to an outside AI until the owner rules. Anything the app sends with `outside_ai_consent` (today nothing does; the recommendations request and personalized turns will) must take its profile from `repo.outsideAiProfile()` or `withoutWristbandValues(profile, store.profileMeta)`. Note that an onboarding turn sends the whole conversation `state`, so a turn with `outside_ai_consent` must not carry band values in `confirmed_profile` either.

What each kind holds:

- **onboarding:** every confirmed value; Apple Health ones carry `source: apple_health`. Old → new where a stored value changed.
- **mochi_change:** only the values that changed, old → new.
- **health_import:** the values confirmed on the Health screen ("Is this accurate?").
- **quick:** each day-log value with its `date` (sleep is the night before that date), then the feeling. Old → new when it replaced an earlier answer for that day.
- **daily / weekly:** the confirmed answers; weekly ones show old → new for each profile field they changed.
- **reading:** a confirmed blood pressure reading (`systolic_bp`, `diastolic_bp`, mmHg) from a weekly check-in, a Mochi change or a document, and `hba1c` (%) and `ldl_cholesterol` (mg/dL) from a kept document value (`source` `document`; item `date` is the document's date, absent when it had none). Information for the person and the coach, never a model input; also listed in `history()`. A reading said in passing during onboarding stays a habit note (`reading`), since it was not read back.
- **correction:** below.

**Calendar:** `dayLogs({from, to})` returns one `DayLog` per day. A day with no answer has `sleepHours`, `vigorousMin`, `moderateMin` and `sedentaryMin` all null: show a blank, never 0, and never the word "missed". `DayLog.complete` says whether the day can count for the model.

**Good weeks, never streaks:** `goodWeeks()` counts Monday–Sunday weeks with at least 4 different days with a finished check-in of any kind (quick, daily or weekly), over all time, not in a row. It counts days, not check-ins.

**Past-day corrections:** `applyDayCorrection(date, field, value, [source = mochi_change])`, only after Mochi read the correction back and the person said yes.

- Records are append-only: the correction is a new `correction` entry with `corrects` set to the original entry's id (the first record of that answer, also for a second correction). The original is kept; `history()` shows it as `corrected` with `correctedBy`.
- `field` is a day-log input (`sleep_hours` for the night before `date`, `vigorous_recreation_min`, `moderate_recreation_min`, `sedentary_min_day`): that day's row takes the value and the windows recompute. Or it is a history-only answer (`wellbeing`, a daily check-in's `sleep_hours_last_night`, `exercise_minutes_today`, `alcohol_drinks_yesterday`): nothing else changes.
- Refused (returns null, writes nothing): a future date, an unknown field or source, a wrong type or range, "unknown" (never replaces a known answer), the same value, or a day with no earlier answer for that field.

## Experiment with your twin (`twin_experiment.dart`)

```dart
final e = repo.experiment();   // null before a profile
e.current;                     // TwinAssessment of the person
e.levers;                      // List<ExperimentLever>, ranked, unsupported last
e.set(LeverId.vigorous, 60);   // snaps to step, clamps to range, notifies
e.result;                      // ExperimentResult
e.reset();                     // or e.reset(LeverId.vigorous)
```

**Lever order:** from `assets/model/model-sensitivity.json`, a copy of `docs/model-sensitivity.json` (codex/d-model-sensitivity, 65acf39). It uses `groups["<age band>|<sex>"].recommendable_levers_ranked`, which is the same for every group: quit smoking, vigorous, moderate, short-sleep +1 h, less sitting. Weight comes last.

| id | unit | range | step | offered when |
|---|---|---|---|---|
| `smoking_status` | `choice` | options 2 "Smokes now", 1 "Quit" | – | current smoker (2) only |
| `vigorous_recreation_min_week` | `min/week` | current – 300 | 15 | current < 300 |
| `moderate_recreation_min_week` | `min/week` | current – 600 | 15 | current < 600 |
| `sleep_hours` | `h/night` | current – 8 | 0.5 | current < 7 h; never above 8 h (the model lowers the estimate there) |
| `sedentary_min_day` | `min/day` | 60 – current | 30 | current ≥ 90 |
| `weight_kg` | `kg` | – | – | never (`weight_not_a_lever`), with the model card BMI caveat |

Levers only move the way guidance points. Less exercise, more sitting, and weight gain are never offered.

**`ExperimentLever` fields:** `id`, `label`, `unit`, `min`, `max`, `step`, `current` (null when unknown), `value`, `options`, `supported`, `reason` / `reasonText`, `caveat`, `missingInput`, `changed`.

**`ExperimentResult` fields:**

- `status`, one of:
  - `available`
  - `no_change`
  - `not_counted`: every moved lever is "Not counted"
  - `current_unavailable`: the person's own result has no number
  - `alternative_unavailable`: the tried profile is outside the model's support; show `message` and no number
  - `invalid_input`: the tried values add up to more than 24 hours a day
- `message`
- `differenceByYear`: years 1–5 → percentage points, alternative minus current, raw and unrounded
- `difference5`
- `currentPercentByYear`, `alternativePercentByYear`
- `levers`: one `LeverFlag {id, counted, reason, reasonText}` per moved lever; `notCounted` lists the uncounted ones
- `warnings`: from the package
- `missingInputs`, `supportIssues`
- `interpretation`
- `causalInterpretation`: always false
- `extrapolated` / `caveat`: age 30–34 or 80–85; show the caveat with any number
- `title`

**Rules:**

- The result is always one `LifeTwinEngine.compare()` of the full alternative profile. Single-lever effects are never summed.
- A moved lever is "Not counted" (`counted: false`, no number for it, and it is left out of the alternative) when its own contrast lowers modeled survival even though the move follows guidance (`counter_intuitive`).
- **Rounding is the UI's job.** For example, "less than 1 in 100" plus one decimal when |pp| < 1. Activity is log-scaled, so small additions matter most for inactive people, and the raw pp shows this.

**Lever reasons:** `missing_input`, `not_current_smoker`, `not_short_sleeper`, `already_high`, `already_low`, `weight_not_a_lever`, `counter_intuitive`.

## Twin state (`twin_state.dart`)

`repo.twinState()` returns a `TwinState`:

- `mood`, `pose` and `reason`;
- `wellbeing`, `recentSleepHours` and `recentActiveMinutes`;
- `strengths` / `opportunities` (the package's `avatar`, as wellness card ids);
- `emergency`.

The first matching row wins:

| Input | `mood` | `pose` (existing sprite) | `reason` |
|---|---|---|---|
| check-in `emergency: true` | `concerned` | `stand` | `emergency` |
| latest wellbeing `not_great` | `cozy` | `sit` | `notFeelingGreat` |
| recent sleep < 6 h | `sleepy` | `stretch` | `shortSleep` |
| exercise today ≥ 30 min | `cheerful` | `jump` | `active` |
| latest wellbeing `good` | `cheerful` | `wave` | `feelingGood` |
| no result yet, or `needs_input` | `content` | `wave` | `needsInput` |
| `avatar.opportunities` not empty | `curious` | `think` | `exploring` |
| otherwise | `content` | `stand` | `steady` |

**Enums:**

- `TwinMood { cheerful, content, curious, sleepy, cozy, concerned }`
- `TwinStateReason { emergency, notFeelingGreat, shortSleep, active, feelingGood, exploring, needsInput, steady }`
- Poses used: `stand`, `sit`, `stretch`, `jump`, `wave`, `think`. These come from `TwinPose`; asset paths are unchanged.

**Recency:** daily answers count for today and yesterday, weekly answers for 7 days.

**Kindness:**

- There is no sad mood.
- Diagnoses and general health are never read, so they can't change the bear's mood.
- `dizzy` (game health) and `shrug` (forecast unsupported) are never chosen.

## Wellness cards

`repo.wellnessCards` (or `TwinAssessment.wellnessCards`) gives `WellnessCard {id, level, title, message, sourceUrl}`, where `level` is `strength`, `opportunity` or `info`. Show each card beside the twin with its `sourceUrl`. They are public-health guidance, not survival-model output.

## What the UI session builds

- **Forecast screens:** they keep working on `Forecast` (`supported`, `survival` 1–5, `curve` with year 0 plus years 1–5, `reason`, `missingLabels`, `assessment`).
  - Show the status message when there is no number.
  - The detail curve is labelled "Modeled survival of similar people".
  - Call `repo.refresh()` on app open.
- **Experiment screen:** binds `TwinExperiment`.
  - Show the levers in order, with sliders using `min`/`max`/`step` and the choice for smoking.
  - Show "Not counted" with `reasonText` for flagged levers, the weight caveat, and the difference under "Modeled difference between profiles" with no number unless `available`.
  - Do the rounding.
- **Twin:** pose and mood from `twinState()`. In an emergency, show the "Call 911" button the person taps themselves.
- **Wellness cards** with source links.
- **"Delete my data"** button with a confirmation, calling `deleteMyData()`.
- **Check-in screens** over `CheckinController` (see `lib/checkin/README.md`), with `store: TwinCheckinStore(repo)` and `reminders: repo.reminders`.
- **History screen:** `history()` as a timeline (date, time, source label, items with `label` and `text`, "was `oldText`" for changes, a small "used in your forecast" mark when `fedForecast` is set, "corrected" on corrected entries), a calendar over `dayLogs()` with blanks for days without answers, "N good weeks" from `goodWeeks()`, and blood pressure readings from `readings()`. No edit buttons: a correction goes through Mochi and then `applyDayCorrection`.
