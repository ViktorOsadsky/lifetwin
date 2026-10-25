# LifeTwin neural rate and lifespan projection handoff

**Delivery:** Local Flutter package in `lifetwin_on_device/` for iOS app integration. No shared schema, server route, or app screen changed. No model was retrained. The guidance-card and avatar-state API was removed from this handoff package at the user's request.

## What the prototype calculates

| Output | Trained component | Meaning | Display |
| --- | --- | --- | --- |
| Relative hazard | Frozen dense DeepSurv Cox network | `exp(neural score − fixed reference score)` | “Modeled relative hazard: 1.4× a fixed reference profile,” with the reference available on tap. Not a mortality probability or health score. |
| Current 1–5 year outlook | Frozen penalized Cox model | `S(t | current profile)` for trained horizons | Cumulative survival percentages only for complete, supported ages 35–79. |
| Yearly age-stepping curve | Repeated one-year Cox predictions | `∏ S(1 | age=a+k, other inputs fixed)` | Experimental “if inputs stay fixed” curve. |
| Five-year block curve | Repeated Cox 1–5 year blocks | `∏ S(5 | age=a+5k, other inputs fixed)`, with within-block annual points | Experimental comparison curve. |

The last two outputs are deliberately different from the trained five-year forecast. They are recurrences over *new hypothetical assessments*, not a learned life expectancy model. The fitted NHANES model uses baseline age and follow-up time, not a longitudinal sequence of repeated personal assessments. The [R survival documentation](https://web.mit.edu/r/current/lib/R/library/survival/html/survfit.coxph.html) warns that a time-varying path must be defined carefully; the [lifelines documentation](https://lifelines.readthedocs.io/en/latest/Time%20varying%20survival%20regression.html) treats time-varying Cox data as a separate model setup.

The Dart API can enable extrapolation to age 110 to see where either curve crosses 50%. Age inputs above 79 are marked `extrapolated` and are outside the trained age range. A 50% crossing is a *median threshold in that simulation*, not mean life expectancy or a prediction of when this person dies. If extrapolation is disabled, the curves end when the next assessment would require an age above 79. This is the more defensible mode for user-facing claims.

## App integration boundary

In `app/pubspec.yaml`, add the local `lifetwin_on_device` path dependency as shown in [the package README](lifetwin_on_device/README.md). Load once with `loadLifeTwinProjectionLab()`. Call `assess(confirmedProfile, includeExtrapolation: false)` to get `neural_hazard`, `current_cox`, `annual`, and `five_year`. Handle non-`available` status by showing the returned message and collecting/correcting inputs, not by inserting healthy defaults. An explicitly labeled lab mode can enable extrapolation for the hackathon demo.

The current app intake lacks distinct moderate/vigorous recreational minutes, diagnosed hypertension, self-rated general health, and awake sitting minutes. Its generic exercise total, BP readings, and skipped answers cannot be silently converted. Track B/C must add confirmed questions and map `sex` and smoking categories to the survey codes. Calculate BMI from confirmed height and weight. The existing `app/lib/forecast/forecast_client.dart` and `app/lib/main.dart` still use the HTTP forecast path; this handoff does not switch them.

The avatar can reflect an explicit experiment choice or simple non-medical expression, but should not change shape or apparent illness based on the neural hazard ratio. The “if inputs stay fixed” control should keep hypothetical inputs separate from the confirmed profile. An edit to an experimental copy is an association test, not evidence that changing a habit causes the plotted benefit.

## Model selection and limits

- The neural network was trained on the same age-35–79 split as the Cox model and exported from the existing Keras artifact; the [model card](lifetwin_on_device/MODEL_CARD.md) records the held-out temporal metrics and adverse inverse feature associations. Its hazard ratio is relative to the frozen reference, so it cannot be compared numerically to the Cox hazard score.
- The Cox package gates current percentages on age and input support. The recurrence uses its trained 1–5-year baseline and coefficients; after age 79 it bypasses age support only for the explicitly labeled experiment. No long-range calibration or coverage study has been done.
- Repeating an age-adjusted snapshot model year by year or five years at a time assumes that diagnosis, health rating, BMI, sleep, exercise, smoking, and sitting remain fixed. Both curves require longitudinal validation. Do not call their median crossing “life expectancy” in a user-facing result. A mean life expectancy would require a validated full survival tail.
- No iOS device build, long-range validation, new cohort, or causal intervention study is included. The package runs locally; a final mobile UI integration remains for the app team.

## Validation and next dependency

Run `dart tool/check.dart`, `flutter test`, and `flutter analyze` from `lifetwin_on_device/`. The checks compare both model implementations to frozen Python vectors and verify the projection methods against the Cox five-year curve. Before adopting any 50% crossing as a product forecast, fit and validate a model with enough observed follow-up and an age range covering the intended lifespan.
