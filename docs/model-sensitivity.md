# Model sensitivity: which inputs move the 5-year estimate

Model `personal-cox-v2-20261024T182404Z` (`model_handoff/lifetwin_on_device`). Horizon: **5-year modeled survival only**. Every number below is an **observational difference between two model profiles**, the same quantity `compare()` returns with `causal_interpretation: false`. None of it is the benefit of changing a habit, and none of it may be shown as years of life gained.

Machine-readable results: [`model-sensitivity.json`](model-sensitivity.json). Reproduce with `dart tool/sensitivity.dart` from `model_handoff/lifetwin_on_device/` (pure Dart, about 40 s, deterministic).

## Plain-language summary

- **Of the inputs a person can change, smoking moves the estimate most.** Going from current to former smoker raises modeled 5-year survival by a median of 0.55 pp at 35–49, 1.66 pp at 50–64 and 4.74 pp at 65–79. Only about one profile in five smokes.
- **For everyone else, recreational activity is the top lever.** It matters mainly for people who currently do none. Adding 60 min/week vigorous or 90 min/week moderate activity is the largest lever for about 73% of profiles. For someone already doing 150+ min/week of moderate activity, another 90 minutes changes almost nothing (median 0.03–0.05 pp).
- **Sitting less and fixing short sleep are real but small.** Each is about a quarter of the activity effect.
- **Weight is not a lever in this model.** Losing weight never raises modeled survival for any profile: BMI −1 was favourable for 0% of profiles. Above BMI 27 the slope is near zero and slightly inverse, and below 23 lower BMI is fitted as worse. Do not offer weight as an experiment that "improves" the twin, and never suggest gaining weight.
- **The same change is worth more percentage points to older and higher-risk people.** The model's ranking of levers is the same for every age band and sex, but the size scales with baseline risk. For +60 min/week vigorous activity, the median runs from 0.13 pp in the lowest-risk fifth of profiles to 2.85 pp in the highest-risk fifth.
- **Changes don't add up.** Doing all the applicable changes together gives a median of 1.27 pp. Adding the separate effects gives 1.49 pp. The combined profile has to be evaluated again (ratio 0.86).

## 1. Is the effect of each input readable from the model?

**Mostly yes, analytically.** The model is an additive Cox model:

```
score = Σ_j β_j (x_j − c_j)          x = encoded inputs (17 columns), c = feature_center
S(t)  = S0(t) ^ exp(score)           S0 = baseline_survival, t = 1..5 years
```

An input change Δ moves the log hazard by the same amount for everyone with the same starting value of that input: `Δscore = β_j · Δx_j`. Exact reading:

- **Linear and categorical terms** have the same hazard ratio for every person. These are age, sitting, sex, smoking, diabetes, hypertension and general health.
- **Hinge and log terms** have a hazard ratio that depends only on that input's own starting value. The hinges are BMI below 23 and above 27, and sleep below 7 h and above 8 h. Vigorous and moderate activity enter as `log(1+minutes)`.
- **There are no interaction terms in the log hazard.** "Smoking × age" is not in the model. All interaction on the percentage-point scale comes from the survival transform.

Converting to percentage points: `ΔS5 = S0(5)^exp(score+Δscore) − S5`. To first order, `∂S5/∂score = S5 · ln S5`. That is about −1.0 pp per unit of log hazard at S5 = 99%, −3.0 pp at 97%, −9.5 pp at 90% and −13.8 pp at 85%. So **the Jacobian with respect to raw inputs is rank-one**:

```
∂S5/∂input_j = 100 · S5 · ln S5 · β_j · ∂x_j/∂input_j        (pp per input unit)
```

The ordering of levers in log-hazard terms is fixed by the coefficients and the person's own starting values. Age, sex and diagnoses only rescale the percentage-point size through `S5 · ln S5`. A good rule of thumb is that pp effect ≈ 5-year risk × (1 − HR).

| Step | Δ log hazard | HR | Notes |
|---|---|---|---|
| Age +1 year | +0.064 | 1.066 | 1.90 per decade |
| Female vs male | −0.363 | 0.695 | |
| Current → former smoker | −0.332 | 0.718 | the reachable smoking change |
| Former → never smoker | −0.231 | 0.793 | not reachable; descriptive only |
| No diabetes vs diabetes | −0.438 | 0.645 | diagnosis, not a lever |
| No hypertension vs hypertension | −0.295 | 0.745 | diagnosis, not a lever |
| General health 5→4 / 4→3 / 3→2 | −0.327 / −0.313 / −0.261 | 0.72 / 0.73 / 0.77 | self-rating, not a lever |
| General health 2→1 (very good → excellent) | **+0.192** | **1.21** | non-monotonic: "very good" is fitted lowest-hazard |
| Vigorous 0→30 / 0→60 / 60→120 min/week | −0.214 / −0.257 / −0.043 | 0.81 / 0.77 / 0.96 | log term: the first 30 min carry most of the effect |
| Moderate 0→30 / 0→90 / 60→150 / 150→240 | −0.216 / −0.284 / −0.057 / −0.029 | 0.81 / 0.75 / 0.95 / 0.97 | same shape |
| Sitting −60 min/day | −0.052 | 0.950 | linear |
| Sleep +1 h when below 7 h | −0.053 | 0.948 | flat from 7 to 8 h |
| Sleep −1 h when above 8 h | −0.200 | 0.818 | association; likely reflects illness |
| BMI −1 when below 23 | **+0.130** | **1.139** | lower BMI fitted as worse |
| BMI −1 when above 27 | **+0.004** | 1.004 | near zero, slightly inverse; flat from 23 to 27 |

**Brute force agrees with the analytic Jacobian.** `tool/sensitivity.dart` loads the packaged assets and calls the package's own `LifeTwinModel.predict()`, with the same validation and support check the app uses. No port was needed, and the script checks the three golden vectors first (max error 2.2e−16). It then compares central finite differences (h = 1e−4) of the six continuous inputs against the analytic formula above at every profile: 7,281 points agreed within 2.0e−10 pp per unit. The 3,897 skipped points sit exactly on a hinge (sleep at 7 or 8 h) or have a neighbour outside support. **So yes, this is checkable through the existing model.** The scan below is still needed for discrete steps, hinge crossings, support drops and the percentage-point scale.

## 2. Method

**Profiles.** The package ships `support_reference.f64.gz`, the 2,000 encoded NHANES training profiles used by the support check. The script decodes each one back to raw inputs, which gives the training data's real joint distribution of age, sex, BMI, sleep, smoking, diagnoses, health rating and activity. There are no invented combinations. The encoding is exactly invertible except in two flat regions:

- BMI from 23 to 27 is imputed uniformly at random.
- Sleep from 7 to 8 h is imputed as 7 or 8, since NHANES 2007–2012 sleep is whole hours.

Both imputations use seed 20261024. The baseline estimate does not depend on either imputed value, since both regions are flat in the model. Steps that cross a hinge do depend on it. Of the 2,000, **137 fall outside support at baseline** and are excluded. In 136 of them one input lies in the 1%-tails that the 1st–99th percentile check removes by design (BMI, sleep, sitting or activity); one fails the neighbour check. That leaves **1,863**: 932 men and 931 women. By age band: 716 aged 35–49, 649 aged 50–64 and 498 aged 65–79. Coverage: 21% current and 28% former smokers, 16% with diabetes and 42% with hypertension. 41% sleep under 7 h, 38% have BMI ≥ 30, 13% have BMI < 23 and 24% rate their health fair or poor. 63% report no moderate and 85% no vigorous recreation.

**Steps.** Each lever is applied to one input with all others held fixed, and the effect is `S5(alt) − S5(base)` in percentage points (positive = higher modeled survival).

- **Unit steps** (finite-difference sensitivities): +1 h sleep, +30 min/week moderate, +30 min/week vigorous, −60 min/day sitting, BMI ±1, smoking current→former and former→never, general health one level better, age +1 year.
- **Two-sided flags:** diabetes, hypertension and sex are evaluated both ways on each profile.
- **Realistic changes** (reachable in a few months):
  - quit smoking (current → former; a current smoker cannot become "never");
  - +90 min/week moderate (three 30-minute walks);
  - +60 min/week vigorous;
  - −60 min/day sitting, if sitting is at least 90;
  - short sleepers +1 h, up to 7 h;
  - long sleepers −1 h, down to 8 h;
  - BMI ≥ 27: lose 5% of body weight (height fixed, BMI × 0.95).
- **Combined:** all applicable recommendable changes applied together and evaluated again.

**Support.** A perturbed profile counts only if `predict()` returns `available`. Profiles outside the 1st–99th percentile range or with too few training neighbours are **dropped and counted** ("support"). Profiles that `predict()` rejects as invalid, such as negative sitting, are also dropped and counted ("invalid"). Drops are small except for the unit sitting step: 135 profiles already sit under 90 min/day. The realistic sitting change skips those people.

**Statistics.** Median, 25th–75th percentile (IQR) and share favourable, among profiles where the lever applies and both sides are supported. The JSON also carries `population_mean_pp`, with non-applicable profiles counted as 0, and `share_applicable`.

## 3. Results

### All profiles

"Applies" is the number of profiles evaluated.

| Lever | Modifiable | Applies | Median pp | IQR (q25 to q75) | Favourable | Dropped (support/invalid) |
|---|---|---|---|---|---|---|
| No diabetes vs diabetes | no | 1860 | 1.61 | 0.71 to 3.34 | 100% | 3/0 |
| All applicable recommendable realistic changes together | yes | 1848 | 1.27 | 0.49 to 2.99 | 100% | 15/0 |
| Female vs male (same other inputs) | no | 1861 | 1.12 | 0.49 to 2.51 | 100% | 2/0 |
| Smoking former -> never | no | 521 | 1.06 | 0.47 to 2.04 | 100% | 0/0 |
| Long sleepers (>8 h): -1 h, min 8 h | yes | 117 | 1.02 | 0.44 to 2.05 | 100% | 0/0 |
| Smoking current -> former | yes | 387 | 1.02 | 0.56 to 2.37 | 100% | 1/0 |
| Quit smoking (current -> former) | yes | 387 | 1.02 | 0.56 to 2.37 | 100% | 1/0 |
| No hypertension vs hypertension | no | 1863 | 0.91 | 0.43 to 1.97 | 100% | 0/0 |
| +60 min/week vigorous (2 x 30 min) | yes | 1858 | 0.64 | 0.22 to 1.53 | 100% | 5/0 |
| +30 min/week vigorous | yes | 1859 | 0.55 | 0.19 to 1.30 | 100% | 4/0 |
| General health one level better | no | 1728 | 0.53 | -0.08 to 1.56 | 74% | 1/0 |
| +90 min/week moderate (3 x 30 min walks) | yes | 1851 | 0.42 | 0.11 to 1.37 | 100% | 12/0 |
| +30 min/week moderate | yes | 1861 | 0.30 | 0.05 to 1.07 | 100% | 2/0 |
| Short sleepers (<7 h): +1 h, max 7 h | yes | 772 | 0.16 | 0.07 to 0.36 | 100% | 0/0 |
| -60 min/day sitting | yes | 1728 | 0.16 | 0.07 to 0.36 | 100% | 103/32 |
| -60 min/day awake sitting (if sitting >= 90) | yes | 1728 | 0.16 | 0.07 to 0.36 | 100% | 0/0 |
| BMI +1 | yes | 1856 | 0.01 | 0.00 to 0.04 | 81% | 7/0 |
| +1 h sleep | yes | 1839 | 0.00 | -0.22 to 0.12 | 42% | 24/0 |
| BMI -1 | yes | 1843 | -0.01 | -0.04 to -0.00 | 0% | 20/0 |
| BMI >= 27: lose 5% of body weight | yes | 1130 | -0.02 | -0.04 to -0.01 | 0% | 0/0 |
| Age +1 year | no | 1841 | -0.20 | -0.44 to -0.09 | 0% | 22/0 |

### By age band and sex

Median pp [25th, 75th percentile].

| Lever | age:35-49 | age:50-64 | age:65-79 | sex:male | sex:female |
|---|---|---|---|---|---|
| No diabetes vs diabetes | 0.60 [0.38, 0.96] | 1.85 [1.26, 2.73] | 4.48 [3.19, 6.75] | 1.92 [0.88, 4.12] | 1.31 [0.59, 2.64] |
| All applicable recommendable realistic changes together | 0.45 [0.23, 0.92] | 1.57 [0.86, 2.84] | 4.08 [2.24, 7.02] | 1.56 [0.60, 3.63] | 1.03 [0.40, 2.45] |
| Female vs male (same other inputs) | 0.41 [0.27, 0.63] | 1.36 [0.93, 2.10] | 3.37 [2.28, 5.01] | 1.16 [0.49, 2.62] | 1.08 [0.47, 2.38] |
| Smoking former -> never | 0.24 [0.19, 0.40] | 0.79 [0.56, 1.24] | 2.11 [1.48, 3.06] | 1.29 [0.63, 2.28] | 0.74 [0.35, 1.46] |
| Long sleepers (>8 h): -1 h, min 8 h | 0.27 [0.19, 0.45] | 1.02 [0.58, 1.65] | 2.40 [1.44, 3.44] | 1.74 [0.66, 2.50] | 0.71 [0.31, 1.40] |
| Smoking current -> former | 0.55 [0.41, 0.80] | 1.66 [1.08, 2.43] | 4.74 [3.79, 6.58] | 1.15 [0.60, 2.76] | 0.94 [0.50, 1.86] |
| Quit smoking (current -> former) | 0.55 [0.41, 0.80] | 1.66 [1.08, 2.43] | 4.74 [3.79, 6.58] | 1.15 [0.60, 2.76] | 0.94 [0.50, 1.86] |
| No hypertension vs hypertension | 0.36 [0.23, 0.56] | 1.10 [0.72, 1.70] | 2.73 [1.81, 4.10] | 1.15 [0.52, 2.43] | 0.76 [0.35, 1.59] |
| +60 min/week vigorous (2 x 30 min) | 0.22 [0.09, 0.40] | 0.80 [0.48, 1.34] | 2.11 [1.35, 3.31] | 0.77 [0.26, 1.89] | 0.54 [0.20, 1.25] |
| +30 min/week vigorous | 0.19 [0.08, 0.34] | 0.68 [0.41, 1.15] | 1.79 [1.15, 2.82] | 0.65 [0.22, 1.61] | 0.46 [0.17, 1.06] |
| General health one level better | 0.23 [-0.08, 0.44] | 0.82 [0.31, 1.50] | 2.08 [-0.61, 3.66] | 0.65 [-0.09, 1.89] | 0.42 [-0.07, 1.30] |
| +90 min/week moderate (3 x 30 min walks) | 0.19 [0.04, 0.40] | 0.71 [0.13, 1.37] | 2.02 [0.30, 3.49] | 0.50 [0.14, 1.69] | 0.33 [0.08, 1.17] |
| +30 min/week moderate | 0.15 [0.02, 0.31] | 0.55 [0.05, 1.07] | 1.58 [0.13, 2.73] | 0.38 [0.05, 1.32] | 0.24 [0.03, 0.91] |
| Short sleepers (<7 h): +1 h, max 7 h | 0.07 [0.05, 0.10] | 0.21 [0.14, 0.34] | 0.52 [0.34, 0.83] | 0.19 [0.08, 0.44] | 0.13 [0.06, 0.29] |
| -60 min/day sitting | 0.06 [0.04, 0.09] | 0.18 [0.12, 0.30] | 0.48 [0.31, 0.73] | 0.19 [0.08, 0.43] | 0.13 [0.06, 0.28] |
| -60 min/day awake sitting (if sitting >= 90) | 0.06 [0.04, 0.09] | 0.18 [0.12, 0.30] | 0.48 [0.31, 0.73] | 0.19 [0.08, 0.43] | 0.13 [0.06, 0.28] |
| BMI +1 | 0.00 [0.00, 0.01] | 0.01 [0.01, 0.03] | 0.04 [0.02, 0.06] | 0.01 [0.00, 0.04] | 0.01 [0.00, 0.03] |
| +1 h sleep | 0.00 [-0.12, 0.06] | 0.00 [-0.43, 0.18] | 0.00 [-1.48, 0.37] | 0.00 [-0.27, 0.15] | 0.00 [-0.17, 0.09] |
| BMI -1 | -0.00 [-0.01, -0.00] | -0.01 [-0.03, -0.00] | -0.04 [-0.07, -0.01] | -0.01 [-0.05, -0.00] | -0.01 [-0.04, -0.00] |
| BMI >= 27: lose 5% of body weight | -0.01 [-0.01, -0.00] | -0.02 [-0.04, -0.01] | -0.06 [-0.09, -0.04] | -0.02 [-0.05, -0.01] | -0.02 [-0.04, -0.01] |
| Age +1 year | -0.07 [-0.12, -0.05] | -0.24 [-0.39, -0.16] | -0.60 [-0.92, -0.40] | -0.24 [-0.55, -0.11] | -0.16 [-0.35, -0.07] |

### Ranking of recommendable levers, by age band × sex

Each lever is ranked by its median among the people it applies to. **The order is identical in every group.** The analytic structure predicts this: groups differ only in magnitude.

| Group | n | Median 5-y survival | 1st | 2nd | 3rd | 4th | 5th |
|---|---|---|---|---|---|---|---|
| all | 1863 | 96.8% | Quit smoking (current -> former) (1.02) | +60 min/week vigorous (2 x 30 min) (0.64) | +90 min/week moderate (3 x 30 min walks) (0.42) | Short sleepers (<7 h): +1 h, max 7 h (0.16) | -60 min/day awake sitting (if sitting >= 90) (0.16) |
| age:35-49 | 716 | 98.9% | Quit smoking (current -> former) (0.55) | +60 min/week vigorous (2 x 30 min) (0.22) | +90 min/week moderate (3 x 30 min walks) (0.19) | Short sleepers (<7 h): +1 h, max 7 h (0.07) | -60 min/day awake sitting (if sitting >= 90) (0.06) |
| age:50-64 | 649 | 96.3% | Quit smoking (current -> former) (1.66) | +60 min/week vigorous (2 x 30 min) (0.80) | +90 min/week moderate (3 x 30 min walks) (0.71) | Short sleepers (<7 h): +1 h, max 7 h (0.21) | -60 min/day awake sitting (if sitting >= 90) (0.18) |
| age:65-79 | 498 | 90.0% | Quit smoking (current -> former) (4.74) | +60 min/week vigorous (2 x 30 min) (2.11) | +90 min/week moderate (3 x 30 min walks) (2.02) | Short sleepers (<7 h): +1 h, max 7 h (0.52) | -60 min/day awake sitting (if sitting >= 90) (0.48) |
| sex:male | 932 | 96.2% | Quit smoking (current -> former) (1.15) | +60 min/week vigorous (2 x 30 min) (0.77) | +90 min/week moderate (3 x 30 min walks) (0.50) | Short sleepers (<7 h): +1 h, max 7 h (0.19) | -60 min/day awake sitting (if sitting >= 90) (0.19) |
| sex:female | 931 | 97.5% | Quit smoking (current -> former) (0.94) | +60 min/week vigorous (2 x 30 min) (0.54) | +90 min/week moderate (3 x 30 min walks) (0.33) | Short sleepers (<7 h): +1 h, max 7 h (0.13) | -60 min/day awake sitting (if sitting >= 90) (0.13) |
| 35-49|male | 355 | 98.6% | Quit smoking (current -> former) (0.61) | +60 min/week vigorous (2 x 30 min) (0.28) | +90 min/week moderate (3 x 30 min walks) (0.26) | Short sleepers (<7 h): +1 h, max 7 h (0.08) | -60 min/day awake sitting (if sitting >= 90) (0.07) |
| 35-49|female | 361 | 99.1% | Quit smoking (current -> former) (0.50) | +60 min/week vigorous (2 x 30 min) (0.19) | +90 min/week moderate (3 x 30 min walks) (0.15) | Short sleepers (<7 h): +1 h, max 7 h (0.05) | -60 min/day awake sitting (if sitting >= 90) (0.05) |
| 50-64|male | 307 | 95.4% | Quit smoking (current -> former) (1.90) | +60 min/week vigorous (2 x 30 min) (0.97) | +90 min/week moderate (3 x 30 min walks) (0.87) | Short sleepers (<7 h): +1 h, max 7 h (0.24) | -60 min/day awake sitting (if sitting >= 90) (0.22) |
| 50-64|female | 342 | 96.8% | Quit smoking (current -> former) (1.34) | +60 min/week vigorous (2 x 30 min) (0.70) | +90 min/week moderate (3 x 30 min walks) (0.61) | Short sleepers (<7 h): +1 h, max 7 h (0.17) | -60 min/day awake sitting (if sitting >= 90) (0.16) |
| 65-79|male | 270 | 88.2% | Quit smoking (current -> former) (5.05) | +60 min/week vigorous (2 x 30 min) (2.49) | +90 min/week moderate (3 x 30 min walks) (2.28) | Short sleepers (<7 h): +1 h, max 7 h (0.65) | -60 min/day awake sitting (if sitting >= 90) (0.56) |
| 65-79|female | 228 | 91.9% | Quit smoking (current -> former) (4.39) | +60 min/week vigorous (2 x 30 min) (1.76) | +90 min/week moderate (3 x 30 min walks) (1.67) | Short sleepers (<7 h): +1 h, max 7 h (0.42) | -60 min/day awake sitting (if sitting >= 90) (0.39) |

Medians alone overstate smoking for a population, because it only applies to smokers. For choosing what to offer a specific person, this table shows each person's own largest recommendable lever:

| Group | Quit smoking (current -> former) | +90 min/week moderate (3 x 30 min walks) | +60 min/week vigorous (2 x 30 min) | -60 min/day awake sitting (if sitting >= 90) | Short sleepers (<7 h): +1 h, max 7 h | none |
|---|---|---|---|---|---|---|
| all | 21% | 50% | 23% | 4% | 2% | 0% |
| age:35-49 | 26% | 46% | 19% | 5% | 4% | 0% |
| age:50-64 | 22% | 49% | 24% | 4% | 1% | 0% |
| age:65-79 | 13% | 56% | 28% | 2% | 1% | 0% |
| sex:male | 23% | 48% | 22% | 5% | 3% | 0% |
| sex:female | 18% | 52% | 25% | 4% | 1% | 0% |
| 35-49|male | 30% | 44% | 16% | 5% | 5% | 0% |
| 35-49|female | 21% | 48% | 22% | 6% | 2% | 0% |
| 50-64|male | 24% | 48% | 22% | 6% | 1% | 0% |
| 50-64|female | 19% | 51% | 26% | 3% | 1% | 0% |
| 65-79|male | 14% | 53% | 29% | 3% | 1% | 0% |
| 65-79|female | 12% | 59% | 27% | 1% | 1% | 0% |

Essentially every current smoker's largest lever is quitting. Almost every non-smoker's largest lever is adding activity: moderate when they do none, vigorous when they already walk. Sitting or sleep comes first for only about 6%.

### Modifiable vs non-modifiable

Median pp effect, among people it applies to.

| Age band | Modifiable: top three | Non-modifiable (descriptive only) |
|---|---|---|
| 35–49 | quit smoking 0.55; +60 vigorous 0.22; +90 moderate 0.19 | no diabetes 0.60; female 0.41; no hypertension 0.36; +1 year of age −0.07 |
| 50–64 | quit smoking 1.66; +60 vigorous 0.80; +90 moderate 0.71 | no diabetes 1.85; female 1.36; no hypertension 1.10; +1 year −0.24 |
| 65–79 | quit smoking 4.74; +60 vigorous 2.11; +90 moderate 2.02 | no diabetes 4.48; female 3.37; no hypertension 2.73; +1 year −0.60 |

Quitting smoking is about as large as the diabetes contrast. Five years of ageing (5 × 0.06 log hazard) is roughly the size of the quitting contrast in log-hazard terms.

### Interactions

There is no interaction in the log hazard. On the pp scale, effects grow with baseline risk.

**Smoking × age**, on a fixed archetype: BMI 26, 7 h sleep, no diagnoses, "good" health, no vigorous activity, 60 min/week moderate, 7 h/day sitting, current smoker. Only age and sex vary:

| Sex | Age | Baseline 5-y % | Quit (pp) | Moderate 60->150 (pp) |
|---|---|---|---|---|
| male | 35 | 98.84 | 0.33 | 0.06 |
| male | 45 | 97.81 | 0.61 | 0.12 |
| male | 55 | 95.88 | 1.15 | 0.22 |
| male | 65 | 92.32 | 2.11 | 0.41 |
| male | 75 | 85.92 | 3.76 | 0.73 |
| male | 79 | 82.20 | 4.68 | 0.90 |
| female | 35 | 99.19 | 0.23 | 0.04 |
| female | 45 | 98.47 | 0.43 | 0.08 |
| female | 55 | 97.12 | 0.81 | 0.16 |
| female | 65 | 94.60 | 1.50 | 0.29 |
| female | 75 | 89.99 | 2.72 | 0.53 |
| female | 79 | 87.26 | 3.43 | 0.66 |

**Quit smoking among current smokers in the profile set:**

| Group | n | Median pp | IQR |
|---|---|---|---|
| 35-49 male | 106 | 0.61 | 0.44 to 0.90 |
| 35-49 female | 77 | 0.50 | 0.37 to 0.67 |
| 50-64 male | 74 | 1.90 | 1.30 to 2.75 |
| 50-64 female | 66 | 1.34 | 0.96 to 1.91 |
| 65-79 male | 37 | 5.05 | 4.00 to 7.42 |
| 65-79 female | 27 | 4.39 | 3.00 to 5.26 |

**Diminishing returns for activity.** The effect of +90 min/week moderate depends on current minutes:

| Current min/week | n | Median pp | IQR |
|---|---|---|---|
| 0 | 1178 | 0.99 | 0.44 to 2.17 |
| 1-59 | 75 | 0.16 | 0.07 to 0.33 |
| 60-149 | 279 | 0.08 | 0.04 to 0.19 |
| 150-299 | 204 | 0.05 | 0.02 to 0.10 |
| 300+ | 115 | 0.03 | 0.01 to 0.05 |

**Baseline risk.** For +60 min/week vigorous activity, by fifths of baseline 5-year risk (Q1 = lowest risk): +60 min/week vigorous by baseline 5-year risk quintile: Q1 median 0.13 pp; Q2 median 0.33 pp; Q3 median 0.69 pp; Q4 median 1.33 pp; Q5 median 2.85 pp

**Combined vs separate.** Combined vs sum (n=1848): median combined 1.27 pp, median sum 1.49 pp, median ratio 0.859. The pp scale is sub-additive because hazard ratios multiply: 1 − HR₁·HR₂ < (1 − HR₁) + (1 − HR₂). Always evaluate the combined profile again.

## 4. Non-monotonic and counter-intuitive responses (do not present as advice)

| Step | Starting value | n | Median pp | IQR | Favourable |
|---|---|---|---|---|---|
| BMI -1 | 24-26 | 236 | 0.00 | 0.00 to 0.00 | 0% |
| BMI -1 | 26-28 | 263 | 0.00 | -0.01 to 0.00 | 0% |
| BMI -1 | <24 | 341 | -0.30 | -0.73 to -0.11 | 0% |
| BMI -1 | >=28 | 1003 | -0.01 | -0.03 to -0.01 | 0% |
| BMI +1 | 24-26 | 236 | 0.00 | 0.00 to 0.00 | 0% |
| BMI +1 | 26-28 | 263 | 0.01 | 0.00 to 0.02 | 100% |
| BMI +1 | <24 | 361 | 0.13 | 0.00 to 0.44 | 69% |
| BMI +1 | >=28 | 996 | 0.01 | 0.01 to 0.03 | 100% |
| +1 h sleep | 7 | 500 | 0.00 | 0.00 to 0.00 | 0% |
| +1 h sleep | 8 | 474 | -0.66 | -1.38 to -0.26 | 0% |
| +1 h sleep | <=6 | 772 | 0.16 | 0.07 to 0.36 | 100% |
| +1 h sleep | >=9 | 93 | -1.16 | -2.15 to -0.47 | 0% |
| General health one level better | 2->1 | 446 | -0.39 | -0.95 to -0.19 | 0% |
| General health one level better | 3->2 | 837 | 0.65 | 0.30 to 1.45 | 100% |
| General health one level better | 4->3 | 375 | 1.50 | 0.75 to 2.94 | 100% |
| General health one level better | 5->4 | 70 | 2.88 | 1.57 to 4.80 | 100% |

- **BMI.** Weight loss never improves the modeled estimate. Below about 23, losing weight is fitted as clearly worse, which likely reflects illness-related weight loss (reverse causation). Above 27 the slope is slightly inverse, so gaining weight raises the estimate by about 0.01 pp per BMI unit. The model card states this is **not** evidence that gaining weight helps. Treat weight as **unmodeled** for recommendations, and keep BMI-change experiments behind the existing `compare()` warning.
- **Sleep +1 h** helps only below 7 h. It is flat from 7 to 8 h and harmful above 8 h (the long-sleep term is about 4× the short-sleep term per hour). Long sleep is a known marker of existing illness, so "sleep less" is not offered as a recommendation. The `long_sleep_minus_1h` lever is marked `recommendable: false`.
- **General health 2→1** ("very good" → "excellent") lowers the estimate (−0.39 pp median). The fitted coefficient for "very good" is lower than for "excellent". Self-rated health is not a lever anyway.
- **Activity enters as log(1 + minutes).** Going from none to any is most of the effect: 15 min/week vigorous already gives 64% of the 75-minute log-hazard change. This likely captures "does any recreation" as a marker of general health. Do not imply that tiny amounts of exercise carry most of a real benefit.
- **Former → never smoker** is descriptive only, since it is not a reachable change.

## 5. How the app should use the JSON

`docs/model-sensitivity.json` → `groups["<band>|<sex>"]` (also `age:<band>`, `sex:<sex>`, `all`) contains:

- `recommendable_levers_ranked`: quit smoking, +90 moderate, +60 vigorous, −60 sitting, short sleep +1 h. Each entry has `median_pp`, `q25_pp`, `q75_pp`, `iqr_pp`, `share_applicable`, `share_favorable`, `population_mean_pp`, `median_delta_log_hazard` and drop counts.
- `all_modifiable_ranked`: also includes the BMI and long-sleep steps, flagged with `recommendable: false` and a `caution`.
- `non_modifiable_ranked`: age, sex, diagnoses, general health and former → never smoker. These are never offered as experiments.
- `share_whose_largest_recommendable_lever_is`.
- `levers` gives the label, kind, modifiable, recommendable and caution for each lever. `interactions` holds the tables above.

The ranking is a **prior for ordering** what to offer. For each person:

1. Skip levers that don't apply to them, such as quitting for a non-smoker or sleep changes for someone already at 7–8 h.
2. Compute their own number with `LifeTwinEngine.compare()` before showing anything.
3. Re-run `compare()` on the combined profile for multi-change experiments.

Show the result as "Modeled difference between profiles", never as years gained.

## 6. Caveats

- **Observational, not causal.** These are differences between modeled profiles of NHANES survey participants, including any confounding and reverse causation in the data. They are not the effect of an intervention (`causal_interpretation: false`).
- **5-year horizon only.** Effects at years 1–4 are smaller; for any one person the lever ordering is the same at every horizon. Nothing here extends beyond 5 years, and no result may be turned into life expectancy, a death date or "years gained".
  - **Owner override (2026-10-24):** A rough expected year and age range may be shown once as a proof of concept, labelled as an estimate, never as a specific date. Method: [lifespan-estimate.md](lifespan-estimate.md) (the CDC 2024 life table plus the model owner's Cox relative risk, adjusted by age band). Scope: this one-time reveal only; the rule still applies everywhere else.
- **The model is a snapshot.** It was fit on one survey assessment per person and was not trained on changes over time.
- **BMI caveat** as above: there is no favourable weight direction in this model, and weight is not offered.
- **Profile set.** The profiles are the model's own 2,000-row support reference: fitting participants, not survey-weighted to the US population. BMI in 23–27 and sleep in 7–8 h are imputed, though the model is flat in both regions.
- **No uncertainty.** Coefficient uncertainty is not propagated, and the IQRs describe spread across people, not statistical uncertainty. The 35–49 band had only 25 deaths by year five in the test cycle.
- **Realistic steps are a choice.** Sizes such as +90 moderate and +60 vigorous are assumptions. A step that the model accepts is not automatically a safe or evidence-backed goal; that requires a separate evidence review (MASTER_PLAN, "Sensitivity search").
