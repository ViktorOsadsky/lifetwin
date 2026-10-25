# LifeTwin on-device Flutter package

This package runs the trained LifeTwin Cox model **inside the Flutter app on iOS**. The app bundle contains `model.json` (learned coefficients and baseline survival), `support_reference.f64.gz` (encoded training reference vectors for the input-support check), and `neural_model.json` (the frozen research neural hazard model). Inference uses Dart only. There is no Python interpreter, HTTP request, backend process, internet connection, TensorFlow, Core ML, or TFLite at runtime.

## Current app contract

Main at `9ace866` includes [#126](https://github.com/ViktorOsadsky/lifetwin/pull/126)'s reveal and [#138](https://github.com/ViktorOsadsky/lifetwin/pull/138)'s centred score:

- `healthScore = median band s − s(profile)`, where `s` excludes Cox age/sex terms and uses the same-sex, nearby-age survey group. **0 is the middle; positive is healthier and higher is better.** This is the log of the former higher-is-better health index, not a probability. The percentile remains “Healthier than X of 100 people your age,” qualified as people like you in the survey. There is no separate lower-is-better hazard-index getter.
- The rough reveal blends CDC age summaries with repeated one-year Cox projection summaries, assuming other inputs stay fixed. Projection weight is zero through 35, rises linearly to 1 at 45, stays 1 through 70, and fades linearly to zero at 79. Projection contributes its 50% crossing and 75%/25% crossing range; CDC contributes its mean and percentile ages. This mixed summary is not mean life expectancy.
- An unreached projection threshold uses sentinel 110. Its `p25OpenEnded`, `openEnded` or `p75OpenEnded` flag survives only if the associated blended value stays at least 110; a retained flag shows **110+**, not a measured crossing or guaranteed age. Rough guide applies where CDC has the majority weight (completed ages 18–39 and 75–85). A fractional age runs projection at its floor while the weight uses the fractional age. Under 18, over 85 and unsupported/missing inputs remain unavailable.
- Blending resolves the earlier hard-switch steps but retains a known trend issue: remaining years increase at 35–45 and expected age falls at 70–79. These blends and trends remain unvalidated. CDC is still a current component, rather than wholly historical.
- Displayed score/reveal outputs use Cox. The shared lab still loads and computes neural output that the app does not read. The neural asset loads through bytes and explicit UTF-8 decoding; that loading fix changes no model values.

The measured Cox scope remains assessment ages 35–79 and years 1–5. Repeated lifetime projection, blending and open-ended display do not extend that validation; nothing past 79 is validated in the rough guide. No exact date, clinical prediction or causal years gained is supported. [Source model card](../../../model_handoff/lifetwin_on_device/MODEL_CARD.md), [current integration](../../lib/README-model.md), [contract handoff](../../../docs/handoffs/hazard-projection-docs.md).

## Add it to the iOS Flutter app

Copy the whole `lifetwin_on_device` folder into your Flutter repository, for example `packages/lifetwin_on_device/`. In the app's `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  lifetwin_on_device:
    path: packages/lifetwin_on_device
```

Then run `flutter pub get`. The package's own `pubspec.yaml` declares these model assets, so Flutter embeds them automatically in the built application. No iOS permissions or network entitlement are needed for model inference. See [Flutter's package asset documentation](https://docs.flutter.dev/ui/assets/assets-and-images#assets-in-package-dependencies).

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
