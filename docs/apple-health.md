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

Age, sex, smoking, alcohol and diabetes stay as conversation questions. US users hear feet, inches and pounds; values are
stored in the profile's metric units.

## Decisions (user rulings, 2026-10-24)

- **Raw samples go to the agents.** `agentSamplesPayload()` sends every sample's type, value, unit, timestamps and
  recording method for a 30-day window. Source and device names (e.g. "Daniel's Apple Watch") are removed because they
  identify a person. The intro screen tells the user readings are sent to LifeTwin's AI assistant. Samples must reach
  agents **through the server** (keys stay server-side), which needs a Track B contract that does not exist yet.
- **Provenance stays on the phone.** `HealthCandidate` records source, measurement date or averaging period on the
  device only; `contracts/profile.schema.json` is unchanged.

## Not done yet

- Server contract and route for `apple_health_samples.v0` (Track B).
- Hooking `HealthImportScreen` into the mascot conversation once the game shell exists. For now `main.dart` hosts it alone.
- On-device run: needs Developer Mode on the test iPhone. A signed generic iOS build with the HealthKit entitlement
  succeeded on team `A5C3J42JT3`.

## Checks

```sh
cd app && flutter analyze && flutter test
```
