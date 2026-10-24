# Expected lifespan: research prototype

**Status: prototype only, not wired into any screen and not part of any API.** The owner (Daniel) asked for an estimated age at death built from the model's probabilities. This contradicts three written rules: [AGENTS.md](../AGENTS.md) ("never fabricate personal predictions or exact death dates"), [MASTER_PLAN.md](../MASTER_PLAN.md) ("no exact death year") and the [model card](../model_handoff/lifetwin_on_device/MODEL_CARD.md) ("Do not extrapolate a life expectancy"). Those rules are unchanged here. If the estimate ships, they have to be amended first, and the model owner (Victor) has to sign off on the model-card change.

**Presentation ruling (owner, 2026-10-24): option 1.** The headline is an expected age rounded to a whole year, with the 25th–75th percentile ages as the range:

> You're likely to live to about {age}. Most people like you live to between {p25} and {p75}.

Add a "rough estimate" note, and put the model caveats behind a "How?" tap. Never use deterministic wording ("you will die…"), and never show exact days or dates. The calendar year is available in the API for a secondary view, but it is not the headline.

Code:

- [`app/lib/twin/lifespan.dart`](../app/lib/twin/lifespan.dart): pure Dart, runs on the phone. The headline is `LifespanEstimate.headline`.
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
   - The reference is fixed at the assessment age. A person stays as much above or below their peers as they are today, apart from the attenuation in step 4. It does not follow peers as they acquire hypertension or diabetes.
3. **Proportional hazards on the table.** μ_person(a) = HR(t) · μ_pop(a) for a ≥ the current age. In the year starting at age y, survival from y+u to y+v is ((1 − v·q_y)/(1 − u·q_y))^HR. Integrals, moments and percentiles all have closed forms. With HR = 1 the method returns the life table exactly.
4. **Attenuation.** The model's HRs come from five years of follow-up after one baseline survey. Holding them for decades overstates differences, for three reasons:
   - Exposures change: smokers quit and inactive people start moving. This is regression dilution. Clarke et al. ([Am J Epidemiol 1999;150:341–53](https://pubmed.ncbi.nlm.nih.gov/10453810/)) found that associations with a single baseline measurement understate the true association by about one-third in the first decade of follow-up, one-half in the second and two-thirds in the third. The baseline-measurement slope therefore falls to about 0.75 of its first-decade value by year 15 and 0.5 by year 25: roughly a 20-year half-life.
   - Relative risks shrink with age. For blood pressure, proportional differences in vascular mortality are "about half as extreme at ages 80–89 as at ages 40–49" ([Prospective Studies Collaboration, Lancet 2002;360:1903–13](https://pubmed.ncbi.nlm.nih.gov/12493255/)).
   - Short-term HRs for self-rated health and inactivity are inflated by illness that is already present (reverse causation), and that effect fades with follow-up.

   **Implementation:** log HR is held at full strength for the model's validated 5 years, then multiplied by 0.5^((t − 5)/h), evaluated at the midpoint of each life-table year. Default h = **20 years**; `None` turns attenuation off.

   **External check for h:** Li et al. ([Circulation 2018;138:345–55](https://pubmed.ncbi.nlm.nih.gov/29712712/)) used the same life-table method with HRs from 34 years of follow-up. Their *extreme* contrast, 5 vs 0 low-risk lifestyle factors, separated life expectancy at 50 by **14.0 years (women) and 12.2 (men)**. Here the 10th-to-90th-percentile NHANES HR profiles at 50 are separated by:

   | half-life | women | men |
   |---|---|---|
   | none | 14.1 y | 16.5 y |
   | 30 y | 8.8 y | 10.8 y |
   | **20 y (default)** | **7.2 y** | **9.1 y** |
   | 10 y | 4.5 y | 6.1 y |

   Without attenuation, the 10th–90th percentile spread already equals or exceeds Li's extreme contrast, which can't be right. 20 y puts it at about half to three-quarters of Li's extreme. That fits both Clarke's dilution data and Li's long-follow-up HRs. 10 y is also defensible, and the sensitivity is reported throughout.
5. **Outputs** (`LifespanEstimate`):
   - survival curve from the current age to 110;
   - life expectancy (the integral of S) and the expected age at death;
   - the SD of the age at death;
   - median and 25th/75th percentile ages;
   - P(reach 80/90/100);
   - the headline fields: `headlineAge` and `rangeLowAge`–`rangeHighAge`, rounded half-up, plus the `headline` sentence;
   - `expectedCalendarYear(asOf)`.

   There is deliberately no exact-date output.
6. **Scope.** Ages 30–85, matching the app's extended range, and complete profiles only. This module does not repeat the packaged model's 1st–99th-percentile and nearest-neighbour support checks. A caller must only pass a profile the model itself accepts.

## Validation

Generated by `lifespan_reference.py validate` (model `personal-cox-v2-20261024T182404Z`). Section numbers (§) below refer to these tables.

### 1. Life table reproduction (HR = 1, no attenuation)

| Sex | e65 published (Table A) | e65 spreadsheet | e65 this method | max abs diff vs spreadsheet e(x), ages 1-99 | max abs diff vs recomputation from q(x) |
|---|---|---|---|---|---|
| male | 18.4 | 18.3587 | 18.3587 | 9.8e-06 | 7.0e-13 |
| female | 20.8 | 20.8307 | 20.8307 | 1.2e-05 | 6.5e-13 |

### 2. Personal hazard ratio among NHANES training profiles

HR relative to the same-sex, same-age reference (log-mean-exp). Mean HR should be ~1 by construction; the median sits below 1 because a minority of high-risk profiles carries most of the deaths.

| Sex | Ages | n | mean HR | median HR | 10th-90th pct HR | HR of the mean profile |
|---|---|---|---|---|---|---|
| male | 35-44 | 257 | 0.96 | 0.77 | 0.41-1.68 | 0.83 |
| male | 45-54 | 242 | 0.98 | 0.81 | 0.35-1.90 | 0.81 |
| male | 55-64 | 212 | 1.02 | 0.80 | 0.42-1.85 | 0.85 |
| male | 65-74 | 221 | 1.03 | 0.81 | 0.37-1.95 | 0.84 |
| male | 75-79 | 66 | 1.03 | 0.84 | 0.46-1.76 | 0.90 |
| female | 35-44 | 255 | 0.96 | 0.73 | 0.41-1.80 | 0.80 |
| female | 45-54 | 254 | 1.01 | 0.79 | 0.41-1.91 | 0.85 |
| female | 55-64 | 252 | 1.03 | 0.81 | 0.40-1.95 | 0.82 |
| female | 65-74 | 176 | 0.97 | 0.74 | 0.39-2.01 | 0.79 |
| female | 75-79 | 65 | 1.01 | 0.80 | 0.45-1.93 | 0.86 |

### 3. Five-year survival: Cox model vs. life-table version

Same NHANES training profiles. Cox = the packaged model (NHANES 2007-2012, deaths to 2019). Life table = this method (2024 US period table x personal HR). Gap = life table - Cox, percentage points.

| Sex | Ages | n | mean Cox S5 % | mean life-table S5 % | gap pp | rank correlation |
|---|---|---|---|---|---|---|
| male | 35-44 | 257 | 98.62 | 98.55 | -0.07 | 0.985 |
| male | 45-54 | 242 | 96.88 | 97.34 | +0.46 | 0.999 |
| male | 55-64 | 212 | 93.06 | 93.93 | +0.88 | 0.999 |
| male | 65-74 | 221 | 87.49 | 88.09 | +0.60 | 0.997 |
| male | 75-79 | 66 | 80.52 | 78.01 | -2.52 | 0.992 |
| female | 35-44 | 255 | 99.02 | 99.19 | +0.17 | 0.998 |
| female | 45-54 | 254 | 97.70 | 98.32 | +0.62 | 0.998 |
| female | 55-64 | 252 | 94.90 | 96.07 | +1.17 | 0.998 |
| female | 65-74 | 176 | 91.16 | 92.09 | +0.93 | 0.993 |
| female | 75-79 | 65 | 85.96 | 83.59 | -2.37 | 0.989 |

### 4. Example profiles (attenuation half-life: none / 20 y default / 10 y)

| Profile | HR | headline (20 y): about / range | table avg age at death | expected age (none / 20 / 10) | median | 25th-75th pct | SD y | P(80) | P(90) | P(100) |
|---|---|---|---|---|---|---|---|---|---|---|
| male_30_typical | 0.39 | 82 / 75-91 | 78.1 | 88.4 / 81.6 / 79.9 | 84.3 | 75.0-90.8 | 12.9 | 64% | 28% | 2% |
| male_45_readme | 0.30 | 85 / 79-93 | 79.6 | 92.0 / 85.0 / 82.8 | 87.0 | 79.2-92.8 | 10.9 | 73% | 37% | 4% |
| female_55_former_smoker_htn | 1.10 | 84 / 77-92 | 84.2 | 83.4 / 83.7 / 83.9 | 85.5 | 77.2-91.6 | 10.6 | 68% | 32% | 3% |
| female_72_never_smoker_active | 0.22 | 95 / 90-100 | 87.4 | 100.4 / 94.9 / 92.9 | 95.4 | 89.9-100.1 | 8.1 | 95% | 75% | 26% |
| female_72_smoker_diabetes | 0.60 | 90 / 85-96 | 87.4 | 91.0 / 90.0 / 89.5 | 90.6 | 84.8-95.6 | 7.7 | 88% | 53% | 9% |
| male_84_hypertension | 0.77 | 92 / 88-95 | 90.6 | 91.8 / 91.7 / 91.6 | 91.2 | 87.7-95.0 | 4.9 | - | 58% | 6% |

### 5. Sanity case: 72-year-old women

| Contrast | model log-HR gap | none | 20 y | 10 y |
|---|---|---|---|---|
| active never-smoker vs same + current smoker + diabetes | 1.00 (HR x2.72) | 9.4 y | 4.8 y | 3.4 y |
| active never-smoker vs inactive, fair health, smoker, diabetes | 2.41 (HR x11.09) | 18.3 y | 12.2 y | 9.7 y |
| literature HRs (smoking 3.0 x diabetes 1.80), average woman | 1.69 (HR x5.40) | 9.1 y | 8.7 y | 8.2 y |

### 6. Edge ages (expected age at death, default 20 y half-life)

| Age | avg man | README man (HR) | avg woman | 55F profile (HR) |
|---|---|---|---|---|
| 30 | 78.09 | 81.95 (0.36) | 82.42 | 80.88 (1.53) |
| 31 | 78.17 | 82.09 (0.36) | 82.46 | 80.88 (1.53) |
| 32 | 78.26 | 82.23 (0.36) | 82.50 | 80.89 (1.53) |
| 33 | 78.35 | 82.38 (0.36) | 82.54 | 80.90 (1.53) |
| 34 | 78.44 | 82.53 (0.36) | 82.59 | 80.92 (1.53) |
| 35 | 78.54 | 82.68 (0.36) | 82.64 | 80.93 (1.53) |
| 36 | 78.63 | 82.88 (0.35) | 82.69 | 80.96 (1.53) |
| 78 | 87.77 | 94.88 (0.24) | 89.19 | 88.91 (1.06) |
| 79 | 88.19 | 95.31 (0.24) | 89.55 | 89.26 (1.06) |
| 80 | 88.63 | 95.71 (0.24) | 89.91 | 89.63 (1.06) |
| 81 | 89.09 | 96.12 (0.24) | 90.31 | 90.03 (1.06) |
| 82 | 89.57 | 96.55 (0.24) | 90.72 | 90.45 (1.06) |
| 83 | 90.08 | 97.01 (0.24) | 91.16 | 90.90 (1.06) |
| 84 | 90.60 | 97.47 (0.24) | 91.61 | 91.36 (1.06) |
| 85 | 91.15 | 97.96 (0.24) | 92.09 | 91.85 (1.06) |

### 7. Calendar-year computation (README man, born 1981-03-14, assessed 2026-10-24)

- exact age = 45.6135 y; log HR = -1.2061
- remaining life expectancy = 39.5355 y = 14440.0 days
- expected calendar year = 2066 (no day or date is exposed)
- headline: You're likely to live to about 85. Most people like you live to between 79 and 93.

### Reading the validation

- **Life table reproduction is exact.** HR = 1 matches a textbook recomputation from q(x) to 7e−13 years. It matches the spreadsheet e(x) to 1e−5, which is the float32 storage in the NCHS files. It matches Table A after rounding.
- **The reference does what it claims.** Mean HR is 0.96–1.03 in every age/sex band. The *median* HR is 0.73–0.84, so most people come out somewhat above the table average. That is real: a minority of high-risk profiles carries most deaths. The owner should still expect "most users beat the average" in the product, and note that this is not flattery.
- **Calibration gap at 5 years (§3).** The 5-year survival this method produces stays within ±1.2 percentage points of the Cox model's own five-year survival for ages 35–74. At 75–79 it is 2.4–2.5 pp *lower*. Expected reasons:
  - The 2024 table includes nursing-home residents; NHANES (civilian, non-institutionalized) does not.
  - NHANES tops ages out at 80.
  - The Cox baseline averages 2007–2019 mortality.

  Rank correlation is 0.985–0.999. Ordering within each band is preserved, so the two disagree on level, not on who is at higher risk.
- **Sanity case (§5).** Compare a 72-year-old woman who is an active never-smoker with the same woman as a current smoker with diabetes:
  - The model separates them by 4.8 years at the default half-life (9.4 with no attenuation, 3.4 at 10 y).
  - Published HRs on the same table give 8.7 years at the default (9.1 with none): Jha et al. ([NEJM 2013;368:341–50](https://pubmed.ncbi.nlm.nih.gov/23343063/)) report current vs never smoking at HR 3.0 for women, and the ERFC ([NEJM 2011;364:829–41](https://pubmed.ncbi.nlm.nih.gov/21366474/)) reports diabetes at HR 1.80.
  - For context: Jha reports smokers lose more than 10 years of life expectancy. Taylor et al. ([Am J Public Health 2002;92:990–6](https://pubmed.ncbi.nlm.nih.gov/12036794/)) found that women who quit at 65 gain 2.7–3.7 years. The ERFC found a 50-year-old with diabetes dies about 6 years earlier, and having 2 of diabetes/stroke/MI costs about 12 years at 60 ([JAMA 2015;314:52–60](https://pubmed.ncbi.nlm.nih.gov/26151266/)).

  The model's smoking × diabetes hazard ratio (2.7) is half the literature's (5.4). It adjusts for self-rated health and hypertension, which partly mediate smoking and diabetes, so the smoking and diabetes gap is understated. The full contrast, which adds inactivity and fair health, is 12.2 years (default) and is driven by self-rated health and activity. **Consequence:** in example 5, a 72-year-old woman who smokes and has diabetes but is active and rates her health "very good" comes out *above* the table average (90 vs 87). That is what the model says, but a user would find it surprising.
- **Edges (§6).** The age term is not extrapolated, so the estimate is continuous through 34→35 and 79→80. Each year adds the life table's increment, and the personal HR changes only through the reference, which is flat outside 35–79. The HRs at 30–34 and 80–85 use reference profiles from 35 and 79 and are unvalidated. The model never saw anyone under 35, and NHANES ages above 80 are top-coded.
- **Precision.** The SD of the age at death is about 13 years at 30, 11 at 45 and 8 at 72. A whole-year headline with a p25–p75 range is the honest resolution. A day-level date would carry roughly 4,000 days of SD. The closed-form mean and SD agree with brute-force numerical integration to 1e−7.

## Limits

- **Observational, not causal.** These are associations from one baseline survey. The difference between two profiles is not the years gained by changing a habit. The `compare()` rules from the model README carry over unchanged.
- **Period life table.** 2024 death rates are held fixed for the rest of life. The table does not project future mortality improvement, so cohort life expectancy, especially for young users, is probably higher. COVID-era tables (2020–2022) were lower; 2024 is the latest published table.
- **NHANES-based HRs.** The HRs come from the following, and none of these limits goes away by moving to a life table:
  - 5-year follow-up;
  - an unweighted sample (no survey weights);
  - no external validation;
  - the non-monotone general-health term ("very good" is fitted below "excellent");
  - the near-zero, slightly inverse BMI slope above 27, and lower BMI below 23 fitted as worse.
- **Attenuation is a modelling choice.** Its shape (exponential) and half-life come from the literature, not from LifeTwin data. The reported sensitivity matters most for low-HR (very healthy) profiles. For example, the active 72-year-old woman's expected age is 100.4 with none, 94.9 at 20 y and 92.9 at 10 y.
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
4. Should the age 75–79 calibration gap (life table 2.4 pp below Cox) be closed? One option is an institutionalization adjustment; another is calibrating the reference so the mean life-table S5 matches the Cox mean S5 per band.
5. The smoking × diabetes HR (2.7) is half the literature's (5.4) because self-rated health and hypertension absorb part of it. For a lifespan, is a model without self-rated health better, since it mostly predicts short-term (reverse-causation) mortality?
6. Is a cohort life table (with projected improvement, for example from the SSA Trustees) preferable to the 2024 period table for users under 50?
