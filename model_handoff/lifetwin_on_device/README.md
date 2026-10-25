# LifeTwin on-device survival models

This Flutter package bundles two frozen, separate models and runs their math locally in Dart:

1. **Dense neural Cox network:** emits a log relative hazard score and a hazard ratio versus a fixed reference profile (age 55, male NHANES category, BMI 27, seven hours sleep, 150 moderate recreational minutes, 360 sitting minutes/day, never smoker, no reported diabetes or hypertension, self-rated health "good"). A ratio of `2` means twice that reference profile's modeled instantaneous hazard; it is **not** a probability, a health score, or a time until death. Only compare ratios computed with this exact model version and reference.
2. **Penalized Cox model:** emits supported cumulative survival percentages at years 1–5 for a complete, supported profile age 35–79. It also powers two explicitly experimental age-stepping curves. Its probabilities are **not** calculated from the neural score. Keep the model names and versions visible separately.

The package no longer generates wellness guidance, habit cards, or avatar states. Its public API is `LifeTwinModel`, `NeuralHazardModel`, and `LifeTwinProjectionLab`.

## Integrate into the iOS Flutter app

From `app/pubspec.yaml`, add:

```yaml
dependencies:
  lifetwin_on_device:
    path: ../model_handoff/lifetwin_on_device
```

Then load once and call with an explicitly confirmed, complete profile:

```dart
final lab = await loadLifeTwinProjectionLab();
final result = lab.assess(confirmedProfile, includeExtrapolation: false);
if (result['status'] == 'available') {
  final neural = result['neural_hazard'] as Map;
  final cox = result['current_cox'] as Map;
  final annual = result['annual'] as Map;
  final fiveYear = result['five_year'] as Map;
  // Use neural['relative_hazard_vs_reference'] as a labeled comparison.
  // Use cox['survival_percent_by_year'] for validated 1–5 year display.
  // Show annual/fiveYear only as experimental projection views.
}
```

Required numeric fields: `age` (completed years), `bmi`, `sleep_hours`, `vigorous_recreation_min_week`, `moderate_recreation_min_week`, and `sedentary_min_day`. Required survey-coded fields: `sex_nhanes` (1 male, 2 female), `smoking_status` (0 never, 1 former, 2 current), `diabetes_diagnosed` and `hypertension_diagnosed` (0/1), and `general_health` (1 excellent through 5 poor). The package does not fill missing inputs. Height and weight can be used to calculate BMI in the app after explicit confirmation. The app's single `exercise_minutes_weekly` field cannot be split into vigorous and moderate recreational activity without asking; blood-pressure readings cannot establish a diagnosis. See [the handoff](../SURVIVAL_PROJECTION_HANDOFF.md) for the app field gap.

## Projection definitions

For both methods, begin at 100% survival at current age, hold all inputs except age fixed, and multiply conditional Cox survival values:

- **Yearly:** at assessment age `a`, use the Cox model's `S(1 | age=a)` for the next year. At age `a+1`, reassess and multiply the new one-year survival, repeating to the chosen maximum age.
- **Five-year blocks:** at age `a`, use `S(1..5 | age=a)` within the block. At age `a+5`, reassess and multiply the next block, repeating. The output has one plotted point per year.

`annual.points` and `five_year.points` contain `{age, survival_percent, extrapolated}`. `median_crossing_age` is the interpolated age where the chained curve first crosses 50%, or null if not reached. This is a **median threshold of an unvalidated simulation**, not mean life expectancy or a personal death age. `median_crossing_extrapolated` flags a crossing using an age input above 79.

`includeExtrapolation: false` stops when the next assessment age would exceed 79. The five-year method can end after age 80 because a supported age-79 baseline has a five-year horizon. With `includeExtrapolation: true`, the package mechanically extends the age term to age 110, marks every segment assessed after age 79 as `extrapolated`, and **does not claim validation there**. Neither repeated method has been evaluated as a lifelong dynamic survival model. Diagnoses, habits, and self-rated health are unrealistically fixed under the "keep this up" scenario.

The 50% crossing is *not* the mean expected lifetime. A survival model's mean lifetime requires the integral of a supported survival curve through the full tail; this artifact provides neither that horizon nor a validated tail model. Do not convert these curves into guaranteed years gained or causal benefits.

## Artifacts and checks

`assets/neural_model.json` contains the exported dense network weights and preprocessing parameters from `output/models/temporal_deepsurv_35_79` in the parent research workspace. `../export_neural.py` regenerates the JSON and `test/neural_golden.json` from the original Keras and joblib files; TensorFlow is not needed on device. The Cox `assets/model.json` and raw `support_reference.f64` contain the evaluated BMI35 v3 model and its matching input-support reference. Run `python model_handoff/sync_cox_from_lab.py` from the repository root after evaluating another Survival Lab release to refresh both package copies, then `python server/tools/lifespan_reference.py build` to regenerate the app's derived lifespan data.

From this package directory:

```powershell
flutter pub get
dart tool/check.dart
flutter test
flutter analyze
```

The checker compares frozen Cox outputs and neural outputs against Python exports, checks the first five projected points against the current Cox curve, and asserts monotonicity, extrapolation labels, and missing-input behavior. An iOS device build still requires macOS/Xcode.

## Model limits and references

The Cox model has temporal NHANES validation only at years 1–5; the neural hazard benchmark has a small discrimination advantage with an uncertainty interval spanning zero and has inverse associations for some BMI and sleep profile comparisons. See [the model card](MODEL_CARD.md). A higher neural hazard ratio means higher modeled hazard, not necessarily worse present-day health, and changing a feature is not a proven intervention benefit. The two long-range projections are for a hackathon proof of concept and need proper out-of-sample longitudinal validation before being presented as a personal lifespan estimate.

Methodological background: the [R survival package documentation](https://web.mit.edu/r/current/lib/R/library/survival/html/survfit.coxph.html) explains that a time-varying covariate path must be specified for Cox survival curves and that such predictions can be nonsensical if specified poorly. The [lifelines time-varying Cox documentation](https://lifelines.readthedocs.io/en/latest/Time%20varying%20survival%20regression.html) describes a separately fitted time-varying model; this package has not fitted one.
