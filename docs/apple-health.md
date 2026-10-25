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
| `vigorous_recreation_min_week`, `moderate_recreation_min_week` | No supported mapping in the pinned iOS reader | Unavailable; ask the person. Exercise Time and workout type do not establish recreational intensity minutes |
| `sedentary_min_day` | No supported awake-sitting measurement | Unavailable; ask the person. Do not subtract stand hours from a day |

Age, sex, smoking, alcohol and diabetes stay as conversation questions. In onboarding v2 Mochi offers Apple Health right after age, sex and smoking (the server returns `client_action: "open_health_import"` on a yes), and the confirmed values come back with action `import`. Exercise Time is all brisk-or-harder movement, so after an import Mochi asks only how much of it is harder exercise and reads the rest back as lighter activity (`moderate_recreation_min_week = exercise_minutes_weekly - vigorous_recreation_min_week`); this split needs owner approval. US users hear feet, inches and pounds; values are
stored in the profile's metric units.

## Activity mapping follow-up (#106): partial implementation

The app's `HealthField`/profile-key and read-back vocabulary now include the three separate model inputs above.
`summarizeWithAvailability(samples, now)` returns the existing `HealthCandidate` suggestions plus an on-phone
`unavailableActivity` map. `HealthReader.readSummary(now: ...)` runs that same summary on the real reader's results.
No returned candidate supplies these three fields yet: their absence sends them to the existing conversation path,
without a zero or healthy default. The existing Exercise Time suggestion and onboarding split are preserved as the
older flow; this work does **not** validate that split as recreational activity.

Availability uses a 28-day lookback and distinguishes no returned data (also consistent with denied HealthKit reads),
missing recreational/intensity evidence, and unmeasured awake sitting. The three new read-backs name Apple Health,
recreational versus awake-sitting context, minutes per week/day, a four-week average and explicit confirmation. This
is vocabulary for a future supported candidate, **not** a claim that a numeric estimator has been implemented.

The native data limits were checked against Apple and the pinned `health` **13.3.2** package on October 24, 2026:

- Apple's [Exercise Time](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/1615696-appleexercisetime)
  counts full minutes at least as intense as a brisk walk. It does not distinguish moderate from vigorous recreation.
- [Stand Hour](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifierapplestandhour)
  counts hours with at least **one minute** standing/moving (or rolling for a wheelchair user). It is not standing
  duration. Actual Stand Time also cannot distinguish sitting from sleep, lying, movement or non-wear in the remaining
  time. Neither supports `24 hours - standing = awake sitting`.
- The package's [workout value](https://pub.dev/documentation/health/latest/health/WorkoutHealthValue-class.html)
  contains workout type, energy, distance and steps. In the installed 13.3.2 iOS `HealthDataReader.swift`, the
  `HKWorkout` branches omit `metadata` even though quantity/category branches include it; `HealthDataPoint.metadata`
  therefore does not provide native workout intensity evidence through this path. No arbitrary metadata is retained
  or serialized by this change.
- Apple's [Average METs metadata](https://developer.apple.com/documentation/healthkit/hkmetadatakeyaveragemets)
  represents intensity averaged over the entire workout. Even with a native bridge, that average would not supply
  time within intensity zones, paused versus active duration, or recreational context. Workout names and heart rate
  alone are not a validated replacement for these model inputs.

**Numeric mapping remains unimplemented; do not close #106 on this partial work.** A positive path needs explicit
recreational context, supported active minutes at each intensity (including coverage/deduplication rules), and an
owner-approved relationship to the model's self-reported recreational inputs. Sitting additionally needs a supported
awake-sitting measure with sleep/non-wear/unknown time separated. A native bridge or package fix alone does not settle
those estimator decisions. Once agreed, weekly values must be four-week averages and sitting a daily average across
that window; only the confirmed bounded averages for these three inputs may leave the phone. New raw activity or
metadata must not be added to outside-AI payloads.

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
- Hooking `HealthImportScreen` into the mascot conversation once the game shell exists. For now `main.dart` hosts it alone.
- On-device run: needs Developer Mode on the test iPhone. A signed generic iOS build with the HealthKit entitlement
  succeeded on team `A5C3J42JT3`.

## Checks

```sh
cd app && flutter analyze && flutter test
```
