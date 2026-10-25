# Cox BMI35 refit

**Model:** `personal-cox-bmi35-v3-20261024` in `assets/cox.json`. The same evaluated Cox artifact and support reference are now in the Flutter handoff and the app's vendored package. The neural hazard model was not retrained.

## Why it changed

The old Cox model encoded BMI above 27 as `max(BMI − 27, 0) / 5` and fitted a coefficient of −0.02041. Thus moving from BMI 100 to 150 lowered modeled Cox hazard by about 18.5% and delayed the experimental 50% crossing, while the neural hazard rose. This direction came from the fitted Cox coefficient, not a website arithmetic bug.

The refit retains the same 11 inputs, cohort, fit/validation/later-cycle split, age term, other features, and Cox penalizer (0.02). It changes the high-BMI feature to `max(BMI − 35, 0) / 5`; the 23–35 interval is flat by design. The resulting coefficient is **+0.03481 per five BMI units above 35**. Low BMI below 23 retains a fitted positive hazard coefficient (+0.67319 per five units below 23). No input BMI is clipped or replaced by a display rule. This representation avoids claiming that increasing high BMI improves survival, while keeping the fitted contribution of BMI above 35 continuous.

The 35 knot was selected from exploratory validation fits for a more stable high-BMI sample than knots at 40 or 45. This was model development, not an independent proof of a correct causal relationship. Other adjustments to diagnoses and self-rated health changed the old inverse slope, consistent with the earlier `output/experiments/inverse_association_deep_dive_v3.md` analysis in the original training workspace. [Published NHANES research](https://pubmed.ncbi.nlm.nih.gov/36756765/) also discusses bias in BMI–mortality associations; it does not validate this particular fit.

## Evaluation

The refit uses 9,109 participants from NHANES 2007–2012 for fitting, 2,570 for validation, and 3,826 from 2013–2014 for a later-cycle check. The exact [evaluation JSON](evaluation.json) includes annual IPCW Brier scores and five-year calibration by age band, sex, and predicted-risk quintile. The largest later-cycle five-year survival calibration gap among those groups is 1.34 percentage points (ages 65–79). The original Cox v2 model is shown for comparison; differences are small and do not establish a statistically meaningful advantage.

| Later-cycle metric | Original Cox v2 | Website Cox BMI35 |
| --- | ---: | ---: |
| C-index | 0.7900 | 0.7914 |
| Five-year IPCW Brier (lower is better) | 0.04691 | 0.04686 |
| Mean predicted five-year survival | 94.27% | 94.28% |
| Observed five-year survival | 94.67% | 94.67% |
| Predicted five-year survival, ages 65–79 | 87.42% | 87.48% |
| Observed five-year survival, ages 65–79 | 88.82% | 88.82% |

With the site's reference non-BMI inputs and age 19, increasing BMI from 100 to 150 changes the **yearly projection's** 50% crossing from about 94.85 to 89.50. This checks the direction only; neither age nor BMI is in the trained region for that example.

## Limits

- Fitted ages are 35–79. The fitting data have a maximum BMI of 84.87, and only 1,566 fitting participants (243 deaths over available follow-up) had BMI at least 35. There are **no fitted examples at BMI 100 or 150**.
- The site permits age and BMI extrapolation for internal experiments, but those predictions have no measured calibration or discrimination in such cohorts. No model can infer the correct mortality curve at BMI 150 from this dataset alone.
- The Cox model is an observational, adjusted association model. Its direction does not quantify the effect of changing someone's weight. The BMI feature is flat from 23 through 35 by a modeling choice, not because those values are equally healthy.
- The age-stepping curves repeatedly apply a five-year model while keeping all other features fixed. Their 50% crossing is **not** a validated age of death or lifespan estimate.

The fitting dataset is excluded from the repository. Refit with [the training script](tools/train_bmi35_cox.py) and its [pinned environment](tools/requirements.txt), then run the browser model tests. Clinical use or another cohort would require independent evaluation of discrimination, calibration, and applicability as described by [TRIPOD+AI](https://www.bmj.com/content/385/bmj-2023-078378).
