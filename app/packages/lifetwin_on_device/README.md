# LifeTwin on-device Flutter package

This package runs the trained LifeTwin Cox model **inside the Flutter app on iOS**. The app bundle contains `model.json` (learned coefficients and baseline survival) and `support_reference.f64.gz` (encoded training reference vectors for the model's input-support check). Inference uses Dart only. There is no Python interpreter, HTTP request, backend process, internet connection, TensorFlow, Core ML, or TFLite at runtime.

## Current app and conditional PR #126 proposal

The current bundled app snapshot exposes a Cox score equal to `−log_relative_hazard_score` (higher is better), plus the same-sex, nearby-age survey percentile. Main still uses the CDC life-table reveal. The root research package has a separate experimental API; adopting it is an explicit adapter change, not an automatic package copy. [Current integration](../../lib/README-model.md).

[PR #126](https://github.com/ViktorOsadsky/lifetwin/pull/126), reviewed at `02f5716`, is **open and held for owner confirmation**. If approved and merged, its latest proposal would:

- Replace the displayed score with `exp(median band s − s(profile))`, where `s` excludes the Cox age/sex terms and the reference is the same-sex, nearby-age survey band. **1.0 is the median; higher is better.** The percentile remains “Healthier than X of 100 people your age,” qualified as people like you in the survey. There is no separate lower-is-better hazard-index getter.
- Use repeated one-year Cox steps for the rough guide at ages 35–79, advancing age with other inputs fixed: **assuming nothing changes**. `expectedAge` would be the 50% crossing, with the 75%/25% crossings defining the age range. This is not mean life expectancy. An unreached threshold at the 110 simulation limit would use 110 plus `p25OpenEnded`, `openEnded` or `p75OpenEnded`; the headline would show **110+**, not a measured crossing.
- Retain the CDC life-table fallback at ages 18–34 and 80–85 with extrapolated status; under 18, over 85 and unsupported/missing profiles remain unavailable. Large jumps at the method boundaries are acknowledged and unresolved. The CDC method would remain a fallback, rather than becoming wholly historical.
- Keep displayed score/reveal outputs Cox-based. The shared projection lab would still load and compute a neural output that the app does not read; neural execution/artifacts are not removed by that product choice.

The measured Cox scope remains supported assessment ages 35–79 and years 1–5. Neither repeated lifetime projection, fallback switching nor open-ended display extends that validation; nothing past 79 is validated in the rough guide. No exact date, clinical prediction or causal years gained is supported. [Source model card](../../../model_handoff/lifetwin_on_device/MODEL_CARD.md), [current/proposed contract handoff](../../../docs/handoffs/hazard-projection-docs.md).

## Add it to the iOS Flutter app

Copy the whole `lifetwin_on_device` folder into your Flutter repository, for example `packages/lifetwin_on_device/`. In the app's `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  lifetwin_on_device:
    path: packages/lifetwin_on_device
```

Then run `flutter pub get`. The package's own `pubspec.yaml` declares the two model assets, so Flutter embeds them automatically in the built application. No iOS permissions or network entitlement are needed for model inference. See [Flutter's package asset documentation](https://docs.flutter.dev/ui/assets/assets-and-images#assets-in-package-dependencies).

Load the model **once**, such as during app startup or on first opening the LifeTwin screen:

```dart
import 'package:lifetwin_on_device/lifetwin_on_device.dart';

final model = await loadLifeTwinModel();
final twin = LifeTwinEngine(model);

final assessment = twin.assess({
  'profile': {
    'age': 45,
    'sex_nhanes': 1,
    'height_cm': 175,
    'weight_kg': 76.6,
    'smoking_status': 0,
    'diabetes_diagnosed': 0,
    'hypertension_diagnosed': 0,
    'general_health': 2,
    'sleep_hours': 7,
    'vigorous_recreation_min_week': 60,
    'moderate_recreation_min_week': 120,
    'sedentary_min_day': 360,
  },
});

final survival = assessment['survival'] as Map<String, dynamic>;
if (survival['status'] == 'available') {
  final percentages = survival['survival_percent_by_year'] as Map<String, double>;
  // Show cumulative survival through each year, labeled
  // "Modeled survival of similar people".
  final yearFive = percentages['5'];
}
final cards = assessment['wellness_cards'] as List;
final avatar = assessment['avatar'] as Map<String, dynamic>;
```

The API intentionally uses JSON-shaped maps so existing form and local storage data can be passed directly. `LifeTwinModel.predict(profile)` is available if the screen needs only the survival curve. `LifeTwinEngine.compare({'current_profile': ..., 'alternative_profile': ...})` returns an observational difference in percentage points, with `causal_interpretation: false`.

## Daily and weekly updates

For daily logs, call `twin.assess` with `profile`, `as_of_date` (`YYYY-MM-DD`), and `daily_logs`. Provide 7, 14, 21, or 28 complete consecutive days ending the day before `as_of_date`. Each row needs `date`, `workday`, `sleep_hours`, `vigorous_recreation_min`, `moderate_recreation_min`, and `sedentary_min_day`. See [daily fixture](test/fixtures/daily_request.json).

For weekly summaries, use `weekly_summaries` instead: 1–4 completed, consecutive Monday–Sunday weeks, each with `week_start` and the four behavior fields. See [weekly fixture](test/fixtures/weekly_request.json). Recent logs replace the sleep, recreation, and awake sitting values in `profile`; onboarding and medical-history answers still come from the person. Reassess when a complete window is available and preserve `profile_used` and `input_provenance` in the app UI.

## UI rules

- Show the annual percentages only when `survival.status == 'available'`. Ages 35–79 and complete, supported profiles are required. For `missing_inputs`, `unsupported_age`, or `unsupported_profile`, show the status message and no number.
- Use `avatar.strengths` and `avatar.opportunities` for avatar state. Show `wellness_cards` with their `source_url` beside the avatar. These cards are public-health guidance; they are not derived from the mortality model's coefficients.
- Label the curve **"Modeled survival of similar people"** and a comparison **"Modeled difference between profiles"**. Do not turn a five-year curve into a date of death or a number of years gained.
- Catch `FormatException` from malformed logs or values and ask the user to correct the input. Do not fill missing fields with healthy defaults.
- Keep user health records in the app's chosen local storage. This package does not save, transmit, or synchronize them.

This is a snapshot model from one survey assessment per person. Daily or weekly updates change the summary profile supplied to that model; the model was not trained as a longitudinal wearable model and does not estimate the causal benefit of a lifestyle change. The [model card](MODEL_CARD.md) describes validation, calibration, and limits.

## Verify

From this package directory:

```powershell
flutter pub get
flutter test
dart tool/check.dart
```

The Flutter test checks real package asset loading. The pure Dart checker compares three exported golden profiles against the original Python model and exercises daily/weekly mapping and support checks. `flutter test` passes on the available Windows Flutter SDK; a physical iOS build requires a macOS/Xcode environment.
