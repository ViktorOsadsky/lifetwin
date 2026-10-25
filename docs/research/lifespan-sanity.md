# Lifespan sanity sweep: app summary versus SSA period means

Research for [#132](https://github.com/ViktorOsadsky/lifetwin/issues/132), retrieved/run October 24, 2026 (Pacific).
**Pinned proposed engine:** [PR126, 787e71a4c4e6283c273db05a9ca64a4f9bdbf37b](https://github.com/ViktorOsadsky/lifetwin/tree/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b).
This is host execution of the actual proposed app adapter/package, not approval or merge of that engine,
simulator/device acceptance, or clinical calibration. No engine/UI code changed.

## Finding and comparison definition

All 36 synthetic cases passed the app support gate. **18/36 headline summaries exceed the SSA attained-age mean
by more than 8 years; 28/36 differ in either direction by more than 8 years.** For the fixed lab reference at
ages 45–70, the excess is 12.40–17.15 years; for the synthetic healthy cases at those ages, 20.23–26.05 years.
The unhealthy cases at those ages are 8.59–15.29 years below it. These are descriptive differences between unlike
estimands/populations, **not measured prediction error or validated calibration bias**. Exact values, inputs,
availability, flags and hashes are in [JSON](lifespan-sanity-results.json); selected columns are in
[CSV](lifespan-sanity-results.csv).

The official SSA page currently identifies its table as the **2023 period life table, used in the 2026 Trustees
Report**. Its e(x) is **mean remaining years at exact age x**, under 2023 mortality rates maintained through the
remaining lifetime. Thus the benchmark here is x+e(x), not e(x) alone or life expectancy at birth. It concerns
the Social Security area population, which includes specified populations beyond the 50 states/DC, and is not
conditioned on these synthetic health profiles. [SSA table, definition and population note](https://www.ssa.gov/OACT/STATS/table4c6.html).

The app headline is a **projection median** at ages 45–70, a **personalized CDC-table mean** at 35/80 in this grid,
and a weighted mean/median summary between those regimes in the general API. They are not a single consistent
mean-life-expectancy estimand. The app's CDC-only comparator also contains fitted NHANES risk/reference,
age-band adjustment and attenuation; it is not the unadjusted SSA table. A difference cannot be attributed solely
to the recurrence or to median-versus-mean. [Pinned blend/summary implementation](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/app/lib/twin/lifespan.dart),
[existing CDC-method definition](../lifespan-estimate.md).

## Inputs and provenance

“Typical” below means **typical (fixed lab-artifact reference)** only. The Cox artifact has no single
`reference_profile`; this is exactly `neural_model.json.reference_profile`, used here as a transparent fixed
input pattern, with only age/sex changed for the grid. It is neither a population-average person nor the
same-sex/age-group median used for health-index 1.0. The app's lifespan uses Cox, not the neural hazard output.
[Pinned lab reference artifact](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/app/packages/lifetwin_on_device/assets/neural_model.json),
[pinned app model adapter](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/app/lib/twin/twin_model.dart).

| Input | Healthy (synthetic) | Typical (fixed lab-artifact reference) | Unhealthy (synthetic) |
| --- | ---: | ---: | ---: |
| BMI |23|27|30|
| Sleep, h/day |7.5|7|6|
| Vigorous recreation, min/week |75|0|0|
| Moderate recreation, min/week |150|150|30|
| Awake sitting, min/day |300|360|600|
| Smoking code (0 never, 2 current) |0|0|2|
| Diabetes diagnosed |0|0|1|
| Hypertension diagnosed |0|0|1|
| General health (1 excellent–5 poor) |2|3|5|

Each pattern is crossed with exact ages 35/45/55/64/70/80 and sex codes 1 male/2 female. “Healthy/unhealthy” are
scenario labels, not diagnoses or validated clinical strata. Inputs are synthetic; no actual person's data or
profile was sent to SSA or a provider. The issue's approximate Rosa 99-versus-85 example motivates this task but
is not this sweep's reference-person comparison: the seeded Rosa history can change effective inputs.

`TwinModelService.assessModel()` executes first. The sweep copies the production repository gate
(`rawLogRelativeHazard != null`) before calling `LifespanEstimate.forProfile()` on the actual `profileUsed`.
Every row preserves assessment status, effective inputs and provenance. Unsupported cases would remain null,
not zero or a forced table estimate; all 36 happened to be supported (30 available, 6 age-80 extrapolated).
[Pinned production gate](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/app/lib/twin/twin_repository.dart).

## SSA values and all 36 results

The 12 unique SSA expectancy values were extracted by age and sex from the official rendered HTML and checked
again against its visible column headings/rows. Both direct CLI download attempts returned 403; the committed
[numeric snapshot](lifespan-sanity-ssa-2023.json) records the official URL, year and retrieval method, not a claim
that raw HTML was downloaded. [SSA original](https://www.ssa.gov/OACT/STATS/table4c6.html).

| Exact age | Male remaining mean | Male attained mean | Female remaining mean | Female attained mean |
| ---: | ---: | ---: | ---: | ---: |
|35|43.02|78.02|47.34|82.34|
|45|34.21|79.21|38.01|83.01|
|55|25.73|80.73|29.01|84.01|
|64|18.83|82.83|21.46|85.46|
|70|14.66|84.66|16.76|86.76|
|80|8.50|88.50|9.82|89.82|

In the next table, **gap=app headline summary−SSA attained-age mean**; **↑** marks a positive gap >8 years,
**↓** a negative gap <−8 years. “110+” means the simulated threshold was not reached by 110, not an exact median
of 110. Its gap is a **lower bound**, shown ≥. CDC is the same accepted profile's existing app CDC-only mean,
provided to separate that baseline from the projection choice. Source: the reproducible actual-app
[sweep data](lifespan-sanity-results.json); SSA columns use the source above.

| Age | Sex | Scenario | App summary | App 25–75 range | SSA attained mean | Gap | App CDC-only mean |
| ---: | --- | --- | ---: | --- | ---: | ---: | ---: |
|35|male|healthy|83.10|76.85–91.67|78.02|+5.08|83.10|
|35|male|typical|81.00|74.03–90.34|78.02|+2.98|81.00|
|35|male|unhealthy|67.36|54.06–81.22|78.02|-10.66 ↓|67.36|
|35|female|healthy|85.72|80.21–93.65|82.34|+3.38|85.72|
|35|female|typical|83.93|78.03–92.52|82.34|+1.59|83.93|
|35|female|unhealthy|72.43|60.69–85.73|82.34|-9.91 ↓|72.43|
|45|male|healthy|103.50|90.29–110.00+|79.21|+24.29 ↑|84.67|
|45|male|typical|94.69|81.85–105.18|79.21|+15.48 ↑|82.22|
|45|male|unhealthy|63.92|55.66–72.23|79.21|-15.29 ↓|67.35|
|45|female|healthy|109.06|95.69–110.00+|83.01|+26.05 ↑|86.87|
|45|female|typical|100.16|87.07–110.00+|83.01|+17.15 ↑|84.71|
|45|female|unhealthy|68.11|58.72–77.04|83.01|-14.90 ↓|71.28|
|55|male|healthy|103.83|91.04–110.00+|80.73|+23.10 ↑|87.49|
|55|male|typical|95.26|83.12–105.47|80.73|+14.53 ↑|84.87|
|55|male|unhealthy|67.62|61.50–74.50|80.73|-13.11 ↓|70.18|
|55|female|healthy|109.28|96.23–110.00+|84.01|+25.27 ↑|89.46|
|55|female|typical|100.56|87.99–110.00+|84.01|+16.55 ↑|87.11|
|55|female|unhealthy|71.01|63.67–78.75|84.01|-13.00 ↓|73.56|
|64|male|healthy|104.35|92.20–110.00+|82.83|+21.52 ↑|90.11|
|64|male|typical|96.15|85.01–105.94|82.83|+13.32 ↑|87.34|
|64|male|unhealthy|72.27|67.97–77.66|82.83|-10.56 ↓|73.75|
|64|female|healthy|109.65|97.07–110.00+|85.46|+24.19 ↑|91.60|
|64|female|typical|101.21|89.39–110.00+|85.46|+15.75 ↑|89.01|
|64|female|unhealthy|74.86|69.44–81.20|85.46|-10.60 ↓|75.87|
|70|male|healthy|104.89|93.36–110.00+|84.66|+20.23 ↑|92.25|
|70|male|typical|97.06|86.80–106.43|84.66|+12.40 ↑|89.42|
|70|male|unhealthy|76.07|72.82–80.45|84.66|-8.59 ↓|77.18|
|70|female|healthy|110.00+|97.93–110.00+|86.76|≥+23.24 ↑|93.80|
|70|female|typical|101.87|90.76–110.00+|86.76|+15.11 ↑|91.09|
|70|female|unhealthy|78.14|73.90–83.46|86.76|-8.62 ↓|78.95|
|80|male|healthy|96.92|91.81–101.41|88.50|+8.42 ↑|96.92|
|80|male|typical|93.82|88.95–98.46|88.50|+5.32|93.82|
|80|male|unhealthy|83.92|81.49–85.66|88.50|-4.58|83.92|
|80|female|healthy|98.58|93.28–103.03|89.82|+8.76 ↑|98.58|
|80|female|typical|95.39|90.47–100.06|89.82|+5.57|95.39|
|80|female|unhealthy|84.95|82.03–87.16|89.82|-4.87|84.95|

There is 1 open-ended headline and 12 open-ended upper-range bounds. All p25 bounds are closed. The 70-year-old
healthy female row's 23.24-year flagged gap remains over 8 even as a lower bound. The JSON/CSV retain unrounded
values and flags, including app `medianCrossingExtrapolated`, assessment/status, projection weight and tail
survival; this flag is reported as implemented rather than treated as proof that the summary is a literal
curve median in the table-only regime. [Actual results](lifespan-sanity-results.json).

## Interpretation and limits

1. **The required grid samples only weights 0 and 1.** The current schedule fades 0→1 across 35→45, stays 1 through 70,
   fades 1→0 across 70→79 and is 0 from 79. Consequently 35/80 here use the pure table, 45/55/64/70 the pure projection.
   This grid does not evaluate interior fade weights, smooth aging behavior or continuity across every adjacent
   age. Seam blending alone does not reduce the 45–70 central projection values.
   [Pinned weight function and blend](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/app/lib/twin/lifespan.dart).
2. **A large gap already exists relative to the app's own personalized table.** For the eight fixed-reference
   age 45–70 cases, the app CDC-only mean is 1.70–4.76 years above SSA, while the projection median is another
   7.64–15.45 years above that CDC mean. At 64 female, for example: SSA attained mean 85.46, app CDC mean 89.01,
   app projection median 101.21. These components use different summaries and are descriptive, not an identified
   causal decomposition. [Exact paired results](lifespan-sanity-results.json).
3. **Fixed-input recurrence and tail extrapolation are plausible contributors, not proven causes of error.**
   The projection multiplies one-year conditional Cox survival while updating age and holding BMI, sleep,
   exercise, sitting, smoking, diagnoses and self-rated health fixed. It extends beyond 79 to 110 using a model
   whose supported current forecasts are ages 35–79 and years 1–5. All 16 healthy/reference age 45–70 cases have
   extrapolated median-crossing flags; the eight unhealthy cases cross before that extrapolated tail. This
   pattern is consistent with long fixed favorable profiles producing a very high tail, but this sweep does
   not isolate each assumption or establish real-world bias. The model author already labels these recurrences
   unvalidated mathematical experiments, not learned life expectancy; the model is not survey-weighted to a
   national target population. [Pinned recurrence](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/app/packages/lifetwin_on_device/lib/src/projection.dart),
   [projection handoff](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/model_handoff/SURVIVAL_PROJECTION_HANDOFF.md),
   [model card](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/model_handoff/lifetwin_on_device/MODEL_CARD.md).
4. **The table alone cannot validate a personal prediction.** The SSA comparator is an unconditional period mean;
   the app scenarios are conditional, not cohort forecasts, and health habits/diagnoses are held fixed. The two
   methods' mean/median and population differences require reconciliation before calibration claims. The large
   negative unhealthy gaps are not evidence of a defect merely because they differ from a population average.
   [SSA definition](https://www.ssa.gov/OACT/STATS/table4c6.html), [model limitations](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/model_handoff/SURVIVAL_PROJECTION_HANDOFF.md).

## Three owner decisions to consider

- **Use supported short-horizon survival/health index for the product, keep long-range age in the research lab.**
  This removes the unvalidated headline from the ordinary flow while retaining the model's supported outputs.
  It is the most conservative product choice; it does not revoke the owner's one-time proof-of-concept option.
  [Current model scope](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/model_handoff/lifetwin_on_device/MODEL_CARD.md).
- **If a one-time age summary remains necessary, use the existing personalized CDC-only mean consistently across
  the accepted ages**, with its uncertainty and limitations. That provides one estimand rather than blending
  a mean and a median and materially lowers the central reference cases in this sweep; it still requires
  validation, is not the SSA population mean, and already exceeds SSA by >8 for the two healthy age-80 cases.
  [Paired results](lifespan-sanity-results.json), [existing method](../lifespan-estimate.md).
- **Keep the experimental projection as an explicitly separate scenario and evaluate earlier/stronger table
  weighting before any chosen product change.** Compare consistent mean/median summaries, finer age steps,
  held-out profiles and tails, and agree an external calibration target with the engine owner. A sooner fade
  could mechanically reduce this gap; neither a hand-picked weight nor a “life table + N” cap becomes clinically
  validated by fitting 36 synthetic examples. This report selects no new weight, N, calibration or cap.
  [Current blend](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/app/lib/twin/lifespan.dart),
  [author's validation requirement](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/model_handoff/SURVIVAL_PROJECTION_HANDOFF.md).

## Reproduction and handoff

From this research checkout, supply `app/` from a checkout at the exact pinned engine commit (never a moving
branch). No simulator is involved. The runner copies four adapter files and the on-device package into a
temporary host Flutter package and runs the committed [Dart sweep](lifespan-sanity-sweep.dart), without modifying
the source. Its local SDK floor permits the installed Dart 3.13.0; production SDK/lockfiles remain untouched.

```sh
python3 docs/research/run-lifespan-sanity.py \
  --app /private/tmp/engine-at-787e71a/app \
  --head 787e71a4c4e6283c273db05a9ca64a4f9bdbf37b \
  --flutter /private/tmp/flutter-game-ui-sdk/bin/flutter \
  --pub-cache /private/tmp/flutter-game-ui-pub-cache \
  --out /private/tmp/lifespan-sanity-results.json
```

The exact run used a temporary source snapshot downloaded from that GitHub commit. Every executed source hash
was checked against the commit archive. Source/Sweep/SSA SHA256s and actual tool versions are embedded in JSON.
Checks: host sweep 36 cases / 1 test pass; independent repeat identical JSON/CSV; Dart format; Python syntax;
JSON/CSV cross-check, SSA selected-row/sex mapping twice, exact-source archive hash check, and `git diff --check`.
Root independently checked all 36 JSON rows for uniqueness, range order, SSA age+remaining arithmetic and gap flags, and verified all 12 SSA values against the official page. No simulator, physical device, live server or provider was used.

Track/task: D research #132. Changes confined to `docs/research/`: report, runner, actual Dart sweep, source snapshot
and result JSON/CSV. No app/engine/contracts changed. Branch `codex/d-lifespan-sanity`; local commit, no push/PR/merge
at handoff. PR126 remains separately owned/held pending its owner's decision. Next dependency: engine owner chooses
the intended summary and validates it; root reviews this research and opens the documentation PR after checks.
