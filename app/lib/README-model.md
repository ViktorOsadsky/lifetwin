# On-device model, phone storage, experiments and twin state

This folder (`lib/twin/`) is the data and logic layer behind the forecast, "experiment with your twin", check-in history and the character's state. It has no screens. Everything runs on the phone. Nothing in it uses the network.

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
| `vigorous_recreation_min_week` | `vigorous_recreation_min_week` (new) | as is (min/week) |
| `moderate_recreation_min_week` | `moderate_recreation_min_week` (new) | as is (min/week) |
| `sedentary_min_day` | `sedentary_min_day` (new) | as is (awake sitting, min/day) |
| `sex_nhanes` | `sex` | `male` → 1, `female` → 2 |
| `smoking_status` | `smoking_status` | `never` → 0, `former` → 1, `current` → 2; `unknown` → missing |
| `diabetes_diagnosed` | `diabetes` | true → 1, false → 0 |
| `hypertension_diagnosed` | `hypertension_diagnosed` (new; `hypertension` also accepted) | true/1 → 1, false/0 → 0 |
| `general_health` | `general_health` (new) | 1–5, or `excellent` 1, `very_good` 2, `good` 3, `fair` 4, `poor` 5 |

Not mapped:

- `exercise_minutes_weekly`, today's single exercise answer, is not split into hard and moderate minutes. Splitting it would mean guessing.
- `alcohol_drinks_weekly`, `systolic_bp` and `diastolic_bp` are not model inputs. They stay in the profile.

Until `codex/d-conversation-v2` collects the new fields, every profile returns `missing_inputs`. `missing_inputs` lists these five ids, in the package's input order:

```
vigorous_recreation_min_week, moderate_recreation_min_week, sedentary_min_day, hypertension_diagnosed, general_health
```

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
| `static Future<TwinRepository> open({AssetBundle? bundle, StoreBackend? backend, DateTime Function()? clock})` | Loads the model and sensitivity ranking, opens the store |
| `TwinAssessment? current` | Assessment of the stored profile, with the history window; null before a profile |
| `Map<String, dynamic> profile` | Confirmed profile (read only) |
| `TwinStore store` | Read-only views: `profile`, `hasProfile`, `checkins`, `dailyLogs`, `weeklySummaries`, `habitNotes`, `twin`, `memoryConsent` |
| `TwinAssessment assess([Map? appProfile])` | Assesses any profile with the phone's history; writes nothing |
| `Future<TwinAssessment> saveConversationProfile(Map confirmed)` | Keeps a Mochi conversation's confirmed profile and recomputes |
| `Future<CheckinOutcome> applyCheckin(Map response)` | Applies a `/api/checkin/start` or `/turn` response (below) |
| `void clearEmergency()` | After "Continue" on an emergency pause |
| `Future<void> applyMemoryConsent(bool)` | The conversation's `memory_consent`; false deletes stored habit notes |
| `Future<bool> addHabitNote(Map note)` | Kept only with memory consent; returns false otherwise |
| `Future<void> saveTwinLook(Map look)` | Cosmetic `{type, look, name}` only |
| `List<WellnessCard> wellnessCards` | The package's guidance cards for `current` |
| `TwinState twinState()` | The character's state now |
| `TwinExperiment? experiment()` | A fresh experiment from `current` |
| `Future<void> deleteMyData()` | "Delete my data": removes the file and clears memory |

It is a `ChangeNotifier`, so bind it with `ListenableBuilder`.

### Who may write (owner ruling)

The owner's rule is: "people shouldn't be able to edit their things unless they consult with their agent first." So there is no setter for profile values or history. `TwinStore`'s write methods are private to the repository library. The only writes are:

1. `saveConversationProfile`, with values confirmed in a Mochi conversation. These come from onboarding (`main.dart` calls it on Continue) and from the "change through Mochi" conversation being built server-side. Apple Health values arrive through the conversation after their read-back confirmation (`importHealth`).
2. `applyCheckin`, for a check-in response's `profile_update` and finished check-ins.
3. `applyMemoryConsent` / `addHabitNote`, for habit notes, only with consent.
4. `saveTwinLook`, which is cosmetic.
5. `deleteMyData`.

Experiment levers are hypothetical and never write to the profile.

**Not wired yet:**

- The onboarding controller doesn't expose `memory_consent` yet. Pass it to `applyMemoryConsent` when it does.
- Nothing writes `daily_logs` yet. The windows code reads them, ready for a confirmed Apple Health daily import.

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

`applyCheckinResponse(profile, response, localDate:)` follows `contracts/checkin.schema.json` on `codex/d-twin-checkins`. It is tested against those fixtures (`test/fixtures/checkin_contract_cases.json`, copied from 92779c9).

- **Weekly, `complete: true`:** every non-null `profile_update` field is set on the profile, and null fields are left as they are. The forecast is then recomputed.
- **"Not sure":** an `unknown` / `not_sure` answer never replaces a known value. It only fills a gap. The same rule applies to `saveConversationProfile` (`keepKnownAnswers`).
- **Daily:** history only (`CheckinRecord`).
- **`emergency: true`:** sets `CheckinOutcome.emergency`. It is never stored. The twin shows `concerned` until `clearEmergency()`.
- **Weekly summary:** when a weekly check-in's confirmed answers cover all four behaviour fields (`sleep_hours`, `vigorous_recreation_min_week`, `moderate_recreation_min_week`, `sedentary_min_day`), a summary row is stored for the Monday–Sunday week that has ended by the end of the check-in day. Today's weekly script asks only `exercise_minutes_weekly`, so no row is made yet.

**History windows** (`twin_history.dart`): `assess()` tries the weekly summaries window first (1–4 completed consecutive weeks), then daily logs (28, 21, 14 or 7 days ending yesterday), then the plain profile. A window the package refuses is skipped, never patched. Keep `profile_used` and `input_provenance` (`TwinAssessment.profileUsed`, `.inputProvenance`, `.source`) visible in the UI.

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
- **Experiment screen:** binds `TwinExperiment`.
  - Show the levers in order, with sliders using `min`/`max`/`step` and the choice for smoking.
  - Show "Not counted" with `reasonText` for flagged levers, the weight caveat, and the difference under "Modeled difference between profiles" with no number unless `available`.
  - Do the rounding.
- **Twin:** pose and mood from `twinState()`. In an emergency, show the "Call 911" button the person taps themselves.
- **Wellness cards** with source links.
- **"Delete my data"** button with a confirmation, calling `deleteMyData()`.
- **Check-in screens and their HTTP client** (`/api/checkin/*`, not in this layer): pass every response to `applyCheckin`.
