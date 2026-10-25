# Cox score, hazard index and rough projection: documentation handoff

Track / task: D trust and submission copy, [#108](https://github.com/ViktorOsadsky/lifetwin/issues/108). Docs only; existing owners are unchanged.

## Current implementation and selected direction

Reviewed baseline: `0417b45`. The score and age-group percentile exist in the app. The hazard index and replacement lifespan projection described in #108 are the selected product direction, pending peer-engine integration. This handoff does not claim that planned code or final device acceptance exists.

| Output | Meaning and direction | Status at the reviewed baseline |
|---|---|---|
| Health score | Cox `log_relative_hazard_score` with its sign flipped; higher is better. This is a model-derived score, not a 0–100 clinical scale. | Implemented by `healthScoreFromRaw`. |
| “Healthier than X of 100 people your age” | Percentile against same-sex, similar-age people in the unweighted NHANES reference; higher is better. It is not a national-population ranking. | Implemented by `AgeGroupReference`; retain the survey qualification. |
| Hazard index | A separate Cox comparison with a reference person of the same age and sex: 1.0 is typical for that reference, lower is better. It is a relative hazard, not a mortality probability, percentile or years remaining. | Pending app implementation; do not substitute the neural lab's fixed-profile ratio. |
| Rough lifespan guide | Repeated one-year Cox steps with age advancing and all other profile inputs fixed, assuming nothing changes. It is an unvalidated projection, not life expectancy or a personal death date. Nothing past age 79 is validated. | The root projection lab contains this recurrence; app adoption is pending. |
| Neural model | Shelved for the selected app experience. | The root research handoff still contains a frozen neural model; shelving does not mean its artifact was deleted. |

Implementation references: [app score and percentile](../../app/lib/twin/twin_model.dart), [current repository lifespan getter](../../app/lib/twin/twin_repository.dart), [current bundled package](../../app/packages/lifetwin_on_device/README.md), and [root projection lab](../../model_handoff/lifetwin_on_device/lib/src/projection.dart). The selected direction comes from [#108](https://github.com/ViktorOsadsky/lifetwin/issues/108).

## Projection boundary

The yearly recurrence starts at survival 1. Each year it multiplies by the Cox model's one-year survival for the newly advanced age, keeping BMI, smoking, diagnoses, health rating, sleep, activity and sitting fixed. This is a sequence of hypothetical snapshot assessments, not a fitted longitudinal model. The root lab also offers a five-year-block experiment; #108 selects the **yearly** path for the rough guide.

The root lab's `median_crossing_age` is the interpolated 50% crossing of that simulation, if reached. It is not a mean expected lifetime. Do not present it as a validated lifespan, guarantee a crossing when none exists, or infer causal years gained from a profile comparison. Any age/year and range shown by the app must come from the eventual engine contract; this docs change creates no conversion or range method.

The measured Cox horizons remain years 1–5 for supported assessment ages 35–79. Repeating the one-year calculation does not extend that validation to a lifetime. The full recurrence is unvalidated, including its tail and every reassessment past 79. Preserve warnings for any out-of-range starting age, missing inputs or unsupported profile; never fill a missing number by hand. [Source model card](../../model_handoff/lifetwin_on_device/MODEL_CARD.md), [projection definition](../../model_handoff/lifetwin_on_device/README.md#projection-definitions).

## Previous CDC wrapper

The app at the reviewed baseline still calls `TwinRepository.lifespanEstimate`, implemented by the [CDC 2024 life-table wrapper](../../app/lib/twin/lifespan.dart). Its expected age, expected year, age-band factors and 25th–75th-percentile range belong to that earlier method. [Its method note](../lifespan-estimate.md) records historical calculation checks; those checks do not validate the new yearly projection.

When the peer engine lands, the yearly Cox projection supersedes that wrapper for the selected product flow. Verify the implementation before changing “pending” to “implemented”; do not mix the CDC range or attenuation assumptions into the new recurrence. The older owner-override text in `AGENTS.md`, `MASTER_PLAN.md` and the CDC method note still needs coordinated reconciliation by its owners.

## Verification and next dependency

Result: source-linked submission and package documentation for the current score and pending hazard/projection transition. No app code, model artifact, inference method, shared schema or model version changes.

PR / merge state: local `codex/d-hazard-projection-docs` branch; no push, PR or merge performed by this task.

Checks actually run: all local Markdown targets in the five changed documents resolve; `git diff --check` passes. Stage logs contain 105 / 94 / 113 / 115 words, including tool/timing/rating lines and link labels. The confirmed team section is unchanged, and the model card's Development and Data/interpretation paragraphs match the source card exactly. This docs task ran no inference or device checks.

Next dependency: identify and inspect the peer-engine PR, verify the hazard reference and rough-guide API, reconcile this status and the app integration README, then run the applicable engine and UI checks before final demo/submission. Daniel retains final device/demo acceptance and stage timing/rating entry.
