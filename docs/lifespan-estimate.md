# Expected lifespan: one-time reveal (proof of concept)

**Status: in the app engine as `TwinRepository.lifespanEstimate`, for a one-time reveal.** It is a rough, proof-of-concept estimate, and the caveat text says so.

**Owner override (2026-10-24):** A rough expected year and age range may be shown once as a proof of concept, labelled as an estimate, never as a specific date. Daniel, after talking to Viktor in person:

> "We should extrapolate an expected death year or date, but then it basically goes away as we focus on relative health score. It doesn't matter how accurate it is for this, as it will never be truly accurate if we extrapolate. it is more of a proof of concept. Age bands should be extrapolated and adjusted. higher should mean better health rating. the set is fine. He [Viktor] is okay with the extrapolation. We don't really need beyond five years."

The written rules stay in place for everything else: [AGENTS.md](../AGENTS.md) and [MASTER_PLAN.md](../MASTER_PLAN.md) scope the one-time reveal as a proof of concept. The [model card](../model_handoff/lifetwin_on_device/MODEL_CARD.md) documents the Cox model's validated five-year scope and the unvalidated long-range projection.

**Presentation ruling (owner, 2026-10-24): option 1.** The headline is an expected age rounded to a whole year, with the 25th–75th percentile ages as the range:

> You're likely to live to about {age}. Most people like you live to between {p25} and {p75}.

Add a "rough estimate" note, and put the model caveats behind a "How?" tap. Never use deterministic wording ("you will die…"), and never show exact days or dates. The override allows an expected YEAR (`expectedYear`), never a day or date.

**App API** ([app/lib/README-model.md](../app/lib/README-model.md), "Lifespan reveal"):

- `repo.lifespanEstimate` → `LifespanEstimate { expectedAge, p25Age, p75Age, expectedYear, status, caveat }`, computed from the current profile. It is null without a health score, which covers no profile, missing inputs, an unsupported profile, under 18 and over 85.
- `expectedYear` = current year + (expectedAge − current age), rounded to a whole year. There is no date output: with an SD of 8–13 years, a day would be false precision.
- `status`: `available` for ages 35–79, `extrapolated` for 18–34 and 80–85.
- `repo.lifespanRevealSeen` / `markLifespanRevealSeen()`: shown once, then de-emphasised. Persisted, and cleared by `deleteMyData()`.

Code:

- [`app/lib/twin/lifespan.dart`](../app/lib/twin/lifespan.dart): pure Dart, runs on the phone. `LifespanEstimate` is the summary the app shows; `LifespanCurve` is the full calculation. The headline is `LifespanEstimate.headline`.
- [`app/lib/twin/lifespan_data.dart`](../app/lib/twin/lifespan_data.dart): generated data.
- [`server/tools/lifespan_reference.py`](../server/tools/lifespan_reference.py): Python reference.
- [`server/tools/lifespan_validation.py`](../server/tools/lifespan_validation.py): produces the tables below.
- Golden vectors: [`app/test/twin/lifespan_golden.json`](../app/test/twin/lifespan_golden.json). Dart and Python agree to 1e-9.

Reproduce:

```sh
python server/tools/lifespan_reference.py build     # regenerate data + golden vectors
python server/tools/lifespan_reference.py validate  # print the validation tables below
```

## Why the curve can't simply be integrated

The packaged Cox model gives S(t | x) = S0(t)^exp(β·(x − c)) only for t = 1…5 years. ∫₀⁵ S(t) dt is the restricted mean survival over five years, about 4.9 years for almost everyone. It is not a lifespan, and S0 beyond year 5 is not in the artifact. A lifespan needs mortality at every later age. The standard way to get that is a relative-risk-adjusted life table.

## Method

1. **Population baseline.** The CDC/NCHS *United States Life Tables, 2024* ([NVSR vol 75 no 5, 25 Aug 2026](https://www.cdc.gov/nchs/data/nvsr/nvsr75/nvsr75-05.pdf)), Table 2 (males) and Table 3 (females), give single years of age 0–99 and an open 100+ interval. q(x), l(x), L(x), T(x) and e(x) were copied unrounded from the NCHS spreadsheets ([Table02.xlsx](https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/75-05/Table02.xlsx), [Table03.xlsx](https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/75-05/Table03.xlsx)) into [`server/tools/data/us_life_table_2024.csv`](../server/tools/data/us_life_table_2024.csv) by `lifespan_reference.py extract-cdc`.
   - Within each year of age, deaths are spread uniformly. That is the table's own convention: L(x) = l(x) − d(x)/2 holds to float32 precision for ages 1–99.
   - Above 100 the hazard is constant at 1/e(100), which reproduces the table's T(100) exactly. The curve runs to age 110.
   - Spot checks against the publication's Table A: e(65) is 18.4 for males and 20.8 for females; the spreadsheet has 18.3587 and 20.8307. e(0) is 76.5 for males and 81.4 for females.
2. **Personal hazard ratio.** log HR(x) = Σ_j β_j x_j − ref(sex, age), summed over the model's 17 encoded columns **except `age_decade` and `female`**. Age and sex are already in the sex-specific life table, so the model's age term is never extrapolated.
   - **Reference: the log-mean hazard of similar NHANES people.** ref(sex, a) = log of the Gaussian-kernel-weighted mean of exp(Σ_j β_j x_j) over the model's 2,000 encoded training profiles of that sex. The kernel is on age, with a 5-year bandwidth. These profiles are `support_reference.f64.gz`, the same source [docs/model-sensitivity.md](model-sensitivity.md) used. The reference is tabulated for ages 35–79 and held flat outside them. So HR = 1 means *the average hazard of people your age and sex*, which is what a life-table death rate is.
   - The other reading, "HR = 1 for the profile with average features", was rejected. Because of Jensen's inequality, a mean profile has HR ≈ 0.8 against the average hazard (§2). Using it would push almost everyone's estimate below the life table.
   - **Age-band calibration (owner: "age bands should be extrapolated and adjusted").** Per sex and assessment-age band (35–44, 45–54, 55–64, 65–74, 75–79), one multiplicative hazard factor k is fitted by bisection so the mean life-table 5-year survival of that band's NHANES training profiles equals the Cox model's own mean 5-year survival (§3). The adjusted log HR is log HR + log k. Ages 18–34 use the 35–44 factor and 80–85 the 75–79 factor, held **constant**. That is the simpler choice: a linear trend would extrapolate from five noisy points, and at 75–79 the trend reverses. The factor applies from the assessment age and is attenuated together with log HR after year 5. At a band boundary the expected age steps by about half a year in the examples; see §6, ages 44 and 45.
   - The reference is fixed at the assessment age. A person stays as much above or below their peers as they are today, apart from the attenuation in step 4. It does not follow peers as they acquire hypertension or diabetes.
3. **Proportional hazards on the table.** μ_person(a) = HR(t) · μ_pop(a) for a ≥ the current age. In the year starting at age y, survival from y+u to y+v is ((1 − v·q_y)/(1 − u·q_y))^HR. Integrals, moments and percentiles all have closed forms. With HR = 1 the method returns the life table exactly.
4. **Attenuation.** The model's HRs come from five years of follow-up after one baseline survey. Holding them for decades overstates differences, for three reasons:
   - Exposures change: smokers quit and inactive people start moving. This is regression dilution. Clarke et al. ([Am J Epidemiol 1999;150:341–53](https://pubmed.ncbi.nlm.nih.gov/10453810/)) found that associations with a single baseline measurement understate the true association by about one-third in the first decade of follow-up, one-half in the second and two-thirds in the third. The baseline-measurement slope therefore falls to about 0.75 of its first-decade value by year 15 and 0.5 by year 25: roughly a 20-year half-life.
   - Relative risks shrink with age. For blood pressure, proportional differences in vascular mortality are "about half as extreme at ages 80–89 as at ages 40–49" ([Prospective Studies Collaboration, Lancet 2002;360:1903–13](https://pubmed.ncbi.nlm.nih.gov/12493255/)).
   - Short-term HRs for self-rated health and inactivity are inflated by illness that is already present (reverse causation), and that effect fades with follow-up.

   **Implementation:** log HR is held at full strength for the model's validated 5 years, then multiplied by 0.5^((t − 5)/h), evaluated at the midpoint of each life-table year. Default h = **20 years**; `None` turns attenuation off.

   **Historical development check for h (Cox v2):** Li et al. ([Circulation 2018;138:345–55](https://pubmed.ncbi.nlm.nih.gov/29712712/)) used a life-table method with HRs from 34 years of follow-up. Their *extreme* contrast, 5 vs 0 low-risk lifestyle factors, separated life expectancy at 50 by **14.0 years (women) and 12.2 (men)**. The following 10th-to-90th-percentile NHANES comparisons were computed with the earlier Cox v2 artifact; the current v3 examples and validation are below.

   | half-life | women | men |
   |---|---|---|
   | none | 14.1 y | 16.5 y |
   | 30 y | 8.8 y | 10.8 y |
   | **20 y (default)** | **7.2 y** | **9.1 y** |
   | 10 y | 4.5 y | 6.1 y |

   These spreads were computed before the age-band factor (step 2). The factor multiplies everyone in a band by the same k, so it shifts the level, not the ordering, and changes these spreads only slightly.

   In that v2 check, the unattenuated 10th–90th percentile spread was as large as Li's extreme contrast. The 20-year setting reduced it. The attenuation setting remains an unvalidated modeling choice for v3; see the current sensitivity in the tables below.
5. **Outputs** (`LifespanCurve`; the app reads the `LifespanEstimate` summary above):
   - survival curve from the current age to 110;
   - life expectancy (the integral of S) and the expected age at death;
   - the SD of the age at death;
   - median and 25th/75th percentile ages;
   - P(reach 80/90/100);
   - the headline fields: `headlineAge` and `rangeLowAge`–`rangeHighAge`, rounded half-up, plus the `headline` sentence;
   - `expectedYear(currentYear)`: the current year plus the remaining life expectancy, rounded to a whole year.

   There is deliberately no exact-date output.
6. **Scope.** Ages 18–85, matching the health score's extrapolated range (`extrapolatedAgeRange`), and complete profiles only. Under 18 gives no estimate. This module does not repeat the packaged model's 1st–99th-percentile and nearest-neighbour support checks. A caller must only pass a profile the model itself accepts.

## Validation

Generated by `lifespan_reference.py validate` (model `personal-cox-bmi35-v3-20261024`). The following tables are for the current packaged model.

### 1. Life table reproduction (HR = 1, no attenuation)

| Sex | e65 published (Table A) | e65 spreadsheet | e65 this method | max abs diff vs spreadsheet e(x), ages 1-99 | max abs diff vs recomputation from q(x) |
|---|---|---|---|---|---|
| male | 18.4 | 18.3587 | 18.3587 | 9.8e-06 | 7.0e-13 |
| female | 20.8 | 20.8307 | 20.8307 | 1.2e-05 | 6.5e-13 |

### 2. Personal hazard ratio among NHANES training profiles

HR relative to the same-sex, same-age reference (log-mean-exp). Mean HR should be ~1 by construction; the median sits below 1 because a minority of high-risk profiles carries most of the deaths.

| Sex | Ages | n | mean HR | median HR | 10th-90th pct HR | HR of the mean profile |
|---|---|---|---|---|---|---|
| male | 35-44 | 257 | 0.96 | 0.77 | 0.40-1.77 | 0.82 |
| male | 45-54 | 242 | 0.98 | 0.81 | 0.35-1.90 | 0.81 |
| male | 55-64 | 212 | 1.02 | 0.80 | 0.42-1.83 | 0.85 |
| male | 65-74 | 221 | 1.03 | 0.80 | 0.37-1.92 | 0.84 |
| male | 75-79 | 66 | 1.03 | 0.88 | 0.46-1.75 | 0.90 |
| female | 35-44 | 255 | 0.96 | 0.72 | 0.41-1.76 | 0.80 |
| female | 45-54 | 254 | 1.02 | 0.79 | 0.40-2.01 | 0.85 |
| female | 55-64 | 252 | 1.03 | 0.79 | 0.39-1.98 | 0.82 |
| female | 65-74 | 176 | 0.97 | 0.73 | 0.38-1.96 | 0.79 |
| female | 75-79 | 65 | 1.01 | 0.80 | 0.46-1.87 | 0.86 |

### 3. Five-year survival: Cox model vs. life-table version

Same NHANES training profiles. Cox = the packaged model (NHANES 2007-2012, deaths to 2019). Life table = this method (2024 US period table x personal HR), before and after the per-band hazard factor k. Gap = life table - Cox, percentage points.

| Sex | Ages | n | mean Cox S5 % | life-table S5 % before | gap before pp | k | life-table S5 % after | gap after pp | rank correlation |
|---|---|---|---|---|---|---|---|---|---|
| male | 35-44 | 257 | 98.61 | 98.55 | -0.06 | 0.957 | 98.61 | +0.00 | 0.985 |
| male | 45-54 | 242 | 96.88 | 97.34 | +0.47 | 1.181 | 96.88 | +0.00 | 0.999 |
| male | 55-64 | 212 | 93.07 | 93.94 | +0.86 | 1.150 | 93.07 | +0.00 | 0.999 |
| male | 65-74 | 221 | 87.52 | 88.08 | +0.56 | 1.052 | 87.52 | +0.00 | 0.997 |
| male | 75-79 | 66 | 80.60 | 78.03 | -2.57 | 0.864 | 80.60 | +0.00 | 0.994 |
| female | 35-44 | 255 | 99.02 | 99.19 | +0.16 | 1.205 | 99.02 | +0.00 | 0.998 |
| female | 45-54 | 254 | 97.69 | 98.32 | +0.63 | 1.379 | 97.69 | +0.00 | 0.998 |
| female | 55-64 | 252 | 94.88 | 96.07 | +1.19 | 1.318 | 94.88 | +0.00 | 0.998 |
| female | 65-74 | 176 | 91.17 | 92.10 | +0.92 | 1.126 | 91.17 | +0.00 | 0.994 |
| female | 75-79 | 65 | 86.00 | 83.61 | -2.40 | 0.838 | 86.00 | +0.00 | 0.990 |

### 4. Example profiles (attenuation half-life: none / 20 y default / 10 y)

| Profile | HR | headline (20 y): about / range | table avg age at death | expected age (none / 20 / 10) | median | 25th-75th pct | SD y | P(80) | P(90) | P(100) |
|---|---|---|---|---|---|---|---|---|---|---|
| female_20_typical | 0.53 | 84 / 78-93 | 82.1 | 88.6 / 83.7 / 82.7 | 86.4 | 77.9-92.5 | 12.8 | 70% | 35% | 4% |
| male_30_typical | 0.37 | 82 / 75-91 | 78.1 | 89.1 / 81.8 / 80.0 | 84.5 | 75.3-90.9 | 12.8 | 64% | 29% | 2% |
| male_45_readme | 0.35 | 84 / 78-92 | 79.6 | 90.3 / 84.4 / 82.5 | 86.4 | 78.4-92.4 | 11.1 | 71% | 35% | 4% |
| female_55_former_smoker_htn | 1.45 | 82 / 75-90 | 84.2 | 81.0 / 82.2 / 82.8 | 84.0 | 75.2-90.4 | 10.9 | 63% | 27% | 2% |
| female_72_never_smoker_active | 0.25 | 94 / 89-100 | 87.4 | 99.0 / 94.3 / 92.5 | 94.9 | 89.4-99.7 | 8.0 | 95% | 73% | 23% |
| female_72_smoker_diabetes | 0.67 | 89 / 84-95 | 87.4 | 90.2 / 89.5 / 89.1 | 90.0 | 84.2-95.0 | 7.6 | 87% | 50% | 7% |
| male_84_hypertension | 0.66 | 92 / 88-96 | 90.6 | 92.5 / 92.4 / 92.2 | 91.9 | 88.2-95.9 | 5.2 | - | 63% | 8% |

### 5. Sanity case: 72-year-old women

| Contrast | model log-HR gap | none | 20 y | 10 y |
|---|---|---|---|---|
| active never-smoker vs same + current smoker + diabetes | 1.00 (HR x2.71) | 8.9 y | 4.8 y | 3.5 y |
| active never-smoker vs inactive, fair health, smoker, diabetes | 2.38 (HR x10.76) | 17.4 y | 12.1 y | 9.8 y |
| literature HRs (smoking 3.0 x diabetes 1.80), average woman | 1.69 (HR x5.40) | 9.1 y | 8.7 y | 8.2 y |

### 6. Edge ages (expected age at death, default 20 y half-life)

| Age | avg man | README man (HR) | avg woman | 55F profile (HR) |
|---|---|---|---|---|
| 18 | 77.28 | 80.62 (0.34) | 82.08 | 80.37 (1.85) |
| 19 | 77.33 | 80.73 (0.34) | 82.10 | 80.35 (1.85) |
| 30 | 78.09 | 82.14 (0.34) | 82.42 | 80.13 (1.85) |
| 34 | 78.44 | 82.73 (0.34) | 82.59 | 80.11 (1.85) |
| 35 | 78.54 | 82.89 (0.34) | 82.64 | 80.11 (1.85) |
| 36 | 78.63 | 83.09 (0.33) | 82.69 | 80.12 (1.84) |
| 44 | 79.50 | 84.95 (0.29) | 83.19 | 80.69 (1.69) |
| 45 | 79.62 | 84.40 (0.35) | 83.27 | 80.11 (1.90) |
| 78 | 87.77 | 95.59 (0.21) | 89.19 | 89.71 (0.90) |
| 79 | 88.19 | 96.03 (0.21) | 89.55 | 90.04 (0.90) |
| 80 | 88.63 | 96.45 (0.21) | 89.91 | 90.40 (0.90) |
| 81 | 89.09 | 96.88 (0.21) | 90.31 | 90.78 (0.90) |
| 84 | 90.60 | 98.28 (0.21) | 91.61 | 92.05 (0.90) |
| 85 | 91.15 | 98.79 (0.21) | 92.09 | 92.52 (0.90) |

### 7. Calendar-year computation (README man, born 1981-03-14, assessed 2026-10-24)

- exact age = 45.6135 y; log HR = -1.0505
- remaining life expectancy = 38.9334 y = 14220.1 days
- expected calendar year = 2065 (no day or date is exposed)
- headline: You're likely to live to about 85. Most people like you live to between 79 and 92.

## Limits

- **Observational, not causal.** These are associations from one baseline survey. The difference between two profiles is not the years gained by changing a habit. The `compare()` rules from the model README carry over unchanged.
- **Period life table.** 2024 death rates are held fixed for the rest of life. The table does not project future mortality improvement, so cohort life expectancy, especially for young users, is probably higher. COVID-era tables (2020–2022) were lower; 2024 is the latest published table.
- **NHANES-based HRs.** The HRs come from the following, and none of these limits goes away by moving to a life table:
  - 5-year follow-up;
  - an unweighted sample (no survey weights);
  - no external validation;
  - the non-monotone general-health term ("very good" is fitted below "excellent");
  - BMI 23–35 is flat by design; above 35 the fitted slope is positive, and below 23 lower BMI is fitted as worse. None of these associations estimates a weight-change benefit.
- **Attenuation is a modelling choice.** Its shape (exponential) and half-life come from the literature, not from LifeTwin data. The reported sensitivity matters most for low-HR profiles. For example, the active 72-year-old woman's v3 expected age is 99.0 with none, 94.3 at 20 y and 92.5 at 10 y.
- **Not population-specific.** Race, income and geography are not in the model or this table.

## Recommended presentation

The owner chose option 1: expected age plus range. This prototype supports it with the following recommendations:

1. **Headline:** "You're likely to live to about {headlineAge}. Most people like you live to between {rangeLowAge} and {rangeHighAge}." Then: "A rough estimate from people with a similar profile, not a prediction for you." The expected age is the integrated curve, which is what the owner asked for. The p25–p75 range shows the spread without a false endpoint.
2. **"How?" tap:** the survival curve to 110, P(80/90/100), the attenuation note, and the model caveats: observational, NHANES 2007–2012, 5-year model extended with the US 2024 life table.
3. **Calendar year:** secondary only, if at all, labelled "around {year}". **No exact day or date anywhere.** With an SD of 8–13 years, a date implies about 4,000× more precision than the estimate has.
4. **Profile comparisons** ("what if I…"): keep the existing "Modeled difference between profiles" framing. Show years only alongside the caveat that it is an association, not a guaranteed gain, or keep comparisons on 5-year percentages as today.
5. **Gate on support:** show nothing when the packaged model returns `missing_inputs`, `unsupported_age` or `unsupported_profile`.

## Open questions for the model owner (Victor)

1. Is the model-card line "Do not extrapolate a life expectancy" lifted for this use, and with which wording? If it is, the card, AGENTS.md and MASTER_PLAN.md need matching edits before anything ships.
2. Is a log-mean-hazard reference from the 2,000-row support sample acceptable? Or should the reference come from the full fitting set, survey-weighted, by single year of age and sex?
3. Is a 20-year half-life acceptable? Or can the data inform it: refit with exposure-by-follow-up-time interactions over the full 2007–2019 linked mortality follow-up (beyond 5 years), and check whether the self-rated-health and activity HRs decay?
4. ~~Should the age 75–79 calibration gap be closed?~~ Resolved 2026-10-24 (owner: "age bands should be extrapolated and adjusted"): a per-band multiplicative hazard factor, nearest band held constant outside 35–79.
5. The smoking × diabetes HR (2.7) is half the literature's (5.4) because self-rated health and hypertension absorb part of it. For a lifespan, is a model without self-rated health better, since it mostly predicts short-term (reverse-causation) mortality?
6. Is a cohort life table (with projected improvement, for example from the SSA Trustees) preferable to the 2024 period table for users under 50?
