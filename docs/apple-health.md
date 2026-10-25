# Apple Health (Track C)

Claimed in [issue #6](https://github.com/ViktorOsadsky/lifetwin/issues/6). Code lives in `app/lib/health/`.

## What it does

- Reads Apple Health on the phone, **read-only**. LifeTwin never writes to Health and does not request clinical records.
- Suggests profile answers. Each one is read back in plain words and the user is asked **"Is this accurate?"**
  (`Yes, that's right` / `No, let me fix it` / `Go back`). Only confirmed values may enter the profile; the rest go back to
  the mascot conversation.
- Also reads tracker data for the twin (steps, active energy, workouts, resting heart rate). Tracker data stays separate
  from the confirmed profile, quiz game health and experiments.

| Profile field | Apple Health source | Rule |
|---|---|---|
| `height_cm`, `weight_kg` | Height, Body Mass | Latest reading within 1 year |
| `exercise_minutes_weekly` | Exercise Time | Weekly average over the last 28 days, overlapping iPhone/Watch time counted once |
| `sleep_hours` | Asleep (core/deep/REM/unspecified) | Median night over the last 14 nights; needs at least 3 nights |
| `systolic_bp`, `diastolic_bp` | Blood Pressure | Average of the last 3 readings within 90 days |
| `vigorous_recreation_min_week`, `moderate_recreation_min_week` | Native workout mean-MET metadata + recorded active duration | Confirm-only estimate through `readSummary()`; group whole workouts by mean MET and average across 28 days. Missing buckets stay unknown |
| `sedentary_min_day` | No supported awake-sitting measurement | Unavailable; ask the person. Do not subtract stand hours from a day |

Age, sex, smoking, alcohol and diabetes stay as conversation questions. In onboarding v2 Mochi offers Apple Health right after age, sex and smoking (the server returns `client_action: "open_health_import"` on a yes), and the confirmed values come back with action `import`. Exercise Time is all brisk-or-harder movement, so after an import Mochi asks only how much of it is harder exercise and reads the rest back as lighter activity (`moderate_recreation_min_week = exercise_minutes_weekly - vigorous_recreation_min_week`); this split needs owner approval. US users hear feet, inches and pounds; values are
stored in the profile's metric units.

## Activity estimates (#106): data API, pending UI/device acceptance

`HealthReader.readSummary(now: ...)` combines the existing generic candidates with optional native workout
**estimates**. `summarizeWithAvailability()` exposes which model activity inputs remain unanswered and why. The
existing `read()` / `summarize()` path, Exercise Time suggestion and onboarding split are preserved; this work does
not validate that older split as recreational activity. No screens or engine code changed. The current
`HealthImportScreen` still calls the generic path; Daniel owns switching its data call to `readSummary()` and
preserving its confirmation boundary.

The app-owned channel is `lifetwin/health_activity`, method `readWorkoutAverages`, schema
`apple_health_workout_averages.v0`. Its coordination is recorded on
[#106](https://github.com/ViktorOsadsky/lifetwin/issues/106#issuecomment-6393243281). Native code uses existing read-only
workout permission, queries a fixed 28-day window, and reads `HKMetadataKeyAverageMETs` as a compatible MET quantity.
It groups each **whole workout** at a mean of 3–<6 METs or ≥6 METs and sums recorded active duration in that group,
dividing seconds by 240 to obtain weekly minutes averaged over four weeks. It does **not** measure time spent in
intensity zones, infer recreational purpose, or use workout names/heart-rate guesses to fill missing MET metadata.
Absolute MET intensity can differ from a person's relative effort and from the model's self-reported inputs.

`HealthActivityBridge` uses the recorded `HKWorkout.duration`, which already accounts for recorded pauses. It does
not subtract pauses twice. Available pause/resume timelines must agree with duration; impossible or inconsistent
durations are excluded. Unrecorded pauses and source errors cannot be detected. Duplicate UUIDs count once;
unresolved overlapping groups and window-crossing workouts are excluded rather than selecting a source or
prorating a whole-workout average. Missing/invalid metadata and light-intensity workouts are excluded explicitly.
The query caps at 2,000 workouts with a one-record overflow sentinel and a five-second timeout. Overflow suppresses
all estimates. An absent bucket is `null`, never zero, and a value rounding below one profile minute stays unanswered.

Only bounded aggregates cross the native/Dart channel:

- Fixed schema, `window_days: 28`, `method: whole_workout_mean_mets`, and `requires_recreation_confirmation: true`.
- Nullable positive `moderate_weekly_minutes` / `vigorous_weekly_minutes` (combined maximum 10,080), eligible workout
  count, bounded exclusion counts (`missing_metadata`, `duration`, `overlap`, `boundary`, `light_intensity`, `duplicate`)
  and a truncation flag.
- No individual workouts, MET samples, identifiers, source/device names, timestamps or arbitrary metadata. Nothing
  is logged, persisted or sent to a provider by the native helper. The Dart parser rejects unknown keys/versions,
  nonfinite/range-invalid values, inconsistent counts and truncation carrying estimates.

Successful positive buckets become `HealthCandidate` suggestions with `isEstimate: true`, a 28-day period and
`whole_workout_mean_mets` basis. `readBack()` explains that each whole workout is grouped by its average effort,
not measured zone time; warns that recordings may be incomplete; and explicitly asks whether these were
**recreational activities** and whether the amount represents the person's **usual weekly activity**. Only a user's
explicit confirmation can put the values into the existing confirmed import flow. Reading/summarizing does not
write a profile. Refusal leaves the question for the mascot. Native failure, unsupported platforms, timeout,
malformed results, empty reads and missing buckets preserve generic suggestions and explicit unavailable reasons.
Sitting always remains unavailable: no stand-hour subtraction or healthy default is used.

Primary sources and API checks (October 24, 2026):

- Apple's [Average METs metadata](https://developer.apple.com/documentation/healthkit/hkmetadatakeyaveragemets)
  describes an `HKQuantity` in kcal/(kg*hr) averaged over the entire workout. The local Xcode HealthKit headers mark
  the key available on iOS 13+, below the app's iOS 15 target. The pinned `health` 13.3.2 plugin omits iOS workout
  metadata, so the app-owned native helper reads this directly without a package fork.
- Apple's [workout duration](https://developer.apple.com/documentation/healthkit/hkworkout/duration) and
  [workout events](https://developer.apple.com/documentation/healthkit/hkworkoutevent) describe recorded active
  duration and pause/resume semantics. Explicit-duration constructors also exist, motivating consistency checks.
- [CDC intensity guidance](https://www.cdc.gov/physical-activity-basics/measuring/index.html) supplies the absolute
  MET bands and distinguishes them from relative effort. Applying one mean-intensity band to a whole workout is
  LifeTwin's disclosed approximation, not a CDC-validated way to measure minutes in zones or a validated model input.
- Apple's [Stand Hour](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifierapplestandhour)
  counts hours with at least **one minute** standing/moving (or rolling). It is not standing duration. Even actual
  Stand Time cannot identify awake sitting among sleep, lying, movement and non-wear in the remaining time.

**Acceptance limits:** real device availability of optional workout MET metadata remains unverified. Simulator
`HKWorkout` fixtures exercise the real native extraction/aggregation API without HealthKit writes; they do not prove
that a user's Watch/workout producer populates the key. Daniel must connect the data API and verify real-source
availability and the explicit read-back/confirmation path before claiming end-to-end #106 completion. The sitting
input still needs its own supported awake-sitting source; it remains a conversation question. Only confirmed bounded
averages for these three inputs may leave the phone; no new raw activity/metadata may be added to outside-AI payloads.

## Decisions (user rulings, 2026-10-24)

- **Raw samples go to the agents.** `agentSamplesPayload()` sends every sample's type, value, unit, timestamps and
  recording method for a 30-day window. Source and device names (e.g. "Daniel's Apple Watch") are removed because they
  identify a person. The intro screen tells the user readings are sent to LifeTwin's AI assistant. Samples must reach
  agents **through the server** (keys stay server-side), which needs a Track B contract that does not exist yet.
- **Provenance stays on the phone.** `HealthCandidate` records source, measurement date or averaging period on the
  device only; `contracts/profile.schema.json` is unchanged.

The #106 rule above is specific to its three activity inputs. It does not reverse the earlier separately scoped raw
sample ruling for existing Health metrics; the existing `agentSamplesPayload()` shape is unchanged. This change adds
no server route, provider request, HealthKit permission or raw-data retention.

## Not done yet

- Server contract and route for `apple_health_samples.v0` (Track B).
- Switching the existing `HealthImportScreen` generic data call to `readSummary()` and checking the stronger
  recreational-activity estimate read-back. Daniel owns this UI integration.
- On-device run: needs Developer Mode on the test iPhone. A signed generic iOS build with the HealthKit entitlement
  succeeded on team `A5C3J42JT3`.

## Checks

```sh
cd app && flutter analyze && flutter test
```
