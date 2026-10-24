# Using this handoff in the LifeTwin Flutter app

This folder is self-contained. Nothing under `app/`, `server/`, or `contracts/` is modified by the handoff commit. The trained Cox model and its support-check data are under `flutter/lifetwin_on_device/assets/`; the Dart runtime and its tests are in that package.

The app team can add this local dependency in `app/pubspec.yaml`:

```yaml
dependencies:
  lifetwin_on_device:
    path: ../lifetwin_handoff/flutter/lifetwin_on_device
```

Then run `flutter pub get` and follow the [Flutter package README](flutter/lifetwin_on_device/README.md). No model server or Python runtime is needed on the iPhone. Keep this model package separate from the existing server prediction path until the confirmed app profile matches the model input contract.

## Current profile mismatch

The app's `contracts/profile.schema.json` and mascot conversation do not yet collect every required model input. The model must return `missing_inputs`, rather than guessing healthy defaults or recoding unrelated fields.

| Trained model field | Current app field | Required action |
|---|---|---|
| `age` | `age` | Use confirmed age; model supports 35–79. |
| `sex_nhanes` | `sex` | Map confirmed male/female to 1/2; other or absent values stay unsupported. |
| `bmi` | `height_cm`, `weight_kg` | Compute from confirmed, plausible measurements. |
| `sleep_hours` | `sleep_hours` / Apple Health typical nights | Confirm usual **workday** sleep or use complete workday logs. |
| `smoking_status` | `smoking_status` | Confirm the lifetime 100-cigarette definition before mapping never/former/current. |
| `diabetes_diagnosed` | `diabetes` | Map only an explicit doctor-diagnosis yes/no. |
| `hypertension_diagnosed` | Blood-pressure readings | Ask about doctor diagnosis; do not infer from readings. |
| `general_health` | Absent | Ask the five-level self-rated health question. |
| `moderate_recreation_min_week` | Total `exercise_minutes_weekly` | Ask about moderate **recreation** or use a validated log mapping. |
| `vigorous_recreation_min_week` | Absent | Ask separately about vigorous recreation. |
| `sedentary_min_day` | Absent | Ask about awake sitting time or use complete logs. |

Alcohol intake and raw blood-pressure readings are not features of this trained model. `app/lib/main.dart` currently uses `HttpForecastClient`; adding the package alone does not switch the forecast screen. The app team should update the shared profile/conversation contracts, collect and confirm the missing fields through the mascot flow, add an on-device `ForecastClient` adapter, and then switch the screen. Keep `model_version` and unsupported reasons visible. The existing server may continue to handle conversation and other provider-backed features.

The model's percentages describe observational survival associations for similar survey profiles. Scenario comparisons are not causal benefits. See [MODEL_CARD.md](MODEL_CARD.md) for validation, supported ages and limits.
