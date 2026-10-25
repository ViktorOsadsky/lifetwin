# Expected lifespan: one-time reveal (proof of concept)

**Current status:** `TwinRepository.lifespanEstimate` is a one-time rough guide. [#126](https://github.com/ViktorOsadsky/lifetwin/pull/126), merged as `41dce10`, replaced the CDC-only summary with an age-weighted CDC/projection blend. [#138](https://github.com/ViktorOsadsky/lifetwin/pull/138), merged as `9ace866`, centers the separate health score on **0**, with positive meaning healthier than the same-sex, nearby-age survey-group median. The historical CDC calculations below describe a retained component, not the entire current headline or clinical validation.

**Owner override (2026-10-24):** A rough expected year and age range may be shown once as a proof of concept, labelled as an estimate, never as a specific date. Daniel, after talking to Viktor in person:

> "We should extrapolate an expected death year or date, but then it basically goes away as we focus on relative health score. It doesn't matter how accurate it is for this, as it will never be truly accurate if we extrapolate. it is more of a proof of concept. Age bands should be extrapolated and adjusted. higher should mean better health rating. the set is fine. He [Viktor] is okay with the extrapolation. We don't really need beyond five years."

The written rules stay in place for everything else: [AGENTS.md](../AGENTS.md) and [MASTER_PLAN.md](../MASTER_PLAN.md) scope the one-time reveal as a proof of concept. The [model card](../model_handoff/lifetwin_on_device/MODEL_CARD.md) documents the Cox model's validated five-year scope and the unvalidated long-range projection.

**Presentation ruling (owner, 2026-10-24): option 1.** The headline is an expected age rounded to a whole year, with the 25th–75th percentile ages as the range:

> You're likely to live to about {age}. Most people like you live to between {p25} and {p75}.

Add a "rough estimate" note, and put the model caveats behind a "How?" tap. Never use deterministic wording ("you will die…"), and never show exact days or dates. The override allows an expected YEAR (`expectedYear`), never a day or date.

**App API** ([app/lib/README-model.md](../app/lib/README-model.md), "Lifespan reveal"):

- `repo.lifespanEstimate` → `LifespanEstimate { expectedAge, p25Age, p75Age, expectedYear, status, caveat }`, computed from the current profile. It is null without a health score, which covers no profile, missing inputs, an unsupported profile, under 18 and over 85.
- `expectedYear` = current year + (expectedAge − actual current age), rounded half-up to a whole year. There is no day/date output. The historical CDC SD figures below do not describe uncertainty in the blended summary.
- `status`: `available` where projection weight is at least one half; otherwise `extrapolated`/Rough guide (completed ages 18–39 and 75–85). These names do not establish validation of the lifetime guide.
- `repo.lifespanRevealSeen` / `markLifespanRevealSeen()`: shown once, then de-emphasised. Persisted, and cleared by `deleteMyData()`.

## Current blend and interpretation

This is source behavior at [merged `9ace866`](https://github.com/ViktorOsadsky/lifetwin/blob/9ace866404bb8df89de673dd299041e25791ccad/app/lib/twin/lifespan.dart), not a new model choice:

| Component / case | Current behavior |
| --- | --- |
| Projection weight `w(age)` | 0 through 35; linear rise to 1 at 45; 1 through 70; linear decline to 0 at 79; 0 thereafter. Accepted assessment ages remain 18–85. |
| CDC component | The personalized CDC-table mean and 25th/75th percentile ages calculated below. |
| Projection component | Repeated one-year Cox survival steps to 110, advancing age with every other input fixed. Center is the interpolated 50% survival crossing; bounds use the 75% and 25% crossings. |
| Displayed summary | `(1 − w) × CDC age + w × projection age`, with bounds kept around the center. It mixes different estimands; it is not mean life expectancy or a validated distribution. |
| Unreached projection threshold | Sentinel age 110 plus its open-ended flag. The flag survives a blend only if the resulting associated age is still at least 110. Show **110+** for retained flags; it means the simulated threshold was not reached within the followed curve, not guaranteed personal survival. |
| Fractional model age in the direct lifespan helper | Projection starts at the floor of age; blend weight and calendar-year calculation use actual age. Confirmed app-profile age still requires whole years; this helper does not bypass input/support gates. |
| `annualCurve` | Selects the CDC component when `w < 0.5`, the projection component otherwise. It is not a blended curve, so its crossings need not equal the displayed blended summary. |
| Missing / unsupported / under 18 / over 85 | Repository returns no estimate; never substitute zero or a hand-filled age. |

Confirmed-profile writes use [`mergeConfirmed`](../app/lib/twin/checkin_applier.dart), which rejects fractional age updates. An existing known age is retained; a fresh profile stays incomplete. Direct-helper fractional-age behavior therefore does not establish fractional-age intake support.

Supported current Cox outputs remain years 1–5 for supported assessment ages 35–79. Neither repeating one-year steps nor blending extends that validation. Nothing past 79 is validated. The recurrence assumes unchanged future inputs; comparisons remain observational, without causal years gained. The [source projection handoff](../model_handoff/SURVIVAL_PROJECTION_HANDOFF.md) and [36-case SSA sanity report](research/lifespan-sanity.md) explain the limits. The pinned sanity grid samples only pure weights 0/1 and does not validate interior blends or fractional-age behavior.

Blending was introduced to reduce the earlier hard-switch steps. The seam and long-range trends must be reassessed for Cox BMI35 v3; the prior Cox v2 measurements do not establish this refit's behavior.

## Retained CDC component: code and reproduction

The remainder records the CDC component's definition and historical calculation checks. Those checks do not validate the current blended headline, its projection tail or its uncertainty.

Code:

- [`app/lib/twin/lifespan.dart`](../app/lib/twin/lifespan.dart): pure Dart, runs on the phone. `LifespanEstimate` is the summary the app shows; `LifespanCurve` is the full calculation. The headline is `LifespanEstimate.headline`.
- [`app/lib/twin/lifespan_data.dart`](../app/lib/twin/lifespan_data.dart): generated data.
- [`server/tools/lifespan_reference.py`](../server/tools/lifespan_reference.py): Python reference.
- [`server/tools/lifespan_validation.py`](../server/tools/lifespan_validation.py): produces the tables below.
- Golden vectors: [`app/test/twin/lifespan_golden.json`](../app/test/twin/lifespan_golden.json). The regenerated vectors await app implementation checks.

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
5. **CDC component outputs** (`LifespanCurve`; the app blends this with the projection as described above):
   - survival curve from the current age to 110;
   - life expectancy (the integral of S) and the expected age at death;
   - the SD of the age at death;
   - median and 25th/75th percentile ages;
   - P(reach 80/90/100);
   - the headline fields: `headlineAge` and `rangeLowAge`–`rangeHighAge`, rounded half-up, plus the `headline` sentence;
   - `expectedYear(currentYear)`: the current year plus the remaining life expectancy, rounded to a whole year.

   There is deliberately no exact-date output.
6. **Scope.** Ages 18–85, matching the health score's extrapolated range (`extrapolatedAgeRange`), and complete profiles only. Under 18 gives no estimate. This module does not repeat the packaged model's 1st–99th-percentile and nearest-neighbour support checks. A caller must only pass a profile the model itself accepts.

## CDC component calculation checks

The v3 five-year Cox evaluation is in the [model card](../web/survival_lab/MODEL_CARD.md). The CDC component tables previously printed here used an outdated BMI knot in the lifespan reference encoder, so they have been withdrawn. The encoder and generated app vectors now use the knot named in the model artifact. Regenerate and review the component report during app implementation before quoting its lifespan figures. No blended lifetime validation has been done.

## Limits

- **Observational, not causal.** These are associations from one baseline survey. The difference between two profiles is not the years gained by changing a habit. The `compare()` rules from the model README carry over unchanged.
- **Period life table.** 2024 death rates are held fixed for the rest of life. The table does not project future mortality improvement, so cohort life expectancy, especially for young users, is probably higher. COVID-era tables (2020–2022) were lower; 2024 is the latest published table.
- **NHANES-based HRs.** The HRs come from the following, and none of these limits goes away by moving to a life table:
  - 5-year follow-up;
  - an unweighted sample (no survey weights);
  - no external validation;
  - the non-monotone general-health term ("very good" is fitted below "excellent");
  - BMI 23–35 is flat by design; above 35 the fitted slope is positive, and below 23 lower BMI is fitted as worse. None of these associations estimates a weight-change benefit.
- **Attenuation is a modelling choice.** Its shape (exponential) and half-life come from the literature, not from LifeTwin data. The impact of this assumption should be reviewed with the corrected encoder before quoting numerical lifespan examples.
- **Not population-specific.** Race, income and geography are not in the model or this table.

## Recommended presentation

The owner chose a one-time rough age plus range. Keep the current method and limits with that presentation:

1. **Headline:** "You're likely to live to about {headlineAge}. Most people like you live to between {rangeLowAge} and {rangeHighAge}." Then: "A rough estimate from people with a similar profile, not a prediction for you." The current center is the weighted CDC mean/projection crossing, not the integral of one displayed curve. Preserve any 110+ flags and explain that this is an unvalidated rough guide.
2. **"How?" detail:** name the actual component/blend and fixed-input assumption. The selected component curve is not a blended survival distribution. Retain observational, supported-horizon and past-79 limits; historical CDC milestones/attenuation are component details, not properties of the projection.
3. **Calendar year:** secondary only, if at all, labelled "around {year}". **No exact day or date anywhere.** Historical CDC spread calculations are not a validated uncertainty interval for this blended guide.
4. **Profile comparisons** ("what if I…"): keep supported-horizon modeled percentage-point differences and the observational framing. Do not translate the rough guide into causal years gained. Cosmetic and quiz/game health remain separate.
5. **Gate on support:** show nothing when the packaged model returns `missing_inputs`, `unsupported_age` or `unsupported_profile`.

## Open questions for the model owner (Victor)

1. Is the model-card line "Do not extrapolate a life expectancy" lifted for this use, and with which wording? If it is, the card, AGENTS.md and MASTER_PLAN.md need matching edits before anything ships.
2. Is a log-mean-hazard reference from the 2,000-row support sample acceptable? Or should the reference come from the full fitting set, survey-weighted, by single year of age and sex?
3. Is a 20-year half-life acceptable? Or can the data inform it: refit with exposure-by-follow-up-time interactions over the full 2007–2019 linked mortality follow-up (beyond 5 years), and check whether the self-rated-health and activity HRs decay?
4. ~~Should the age 75–79 calibration gap be closed?~~ Resolved 2026-10-24 (owner: "age bands should be extrapolated and adjusted"): a per-band multiplicative hazard factor, nearest band held constant outside 35–79.
5. The smoking × diabetes HR (2.7) is half the literature's (5.4) because self-rated health and hypertension absorb part of it. For a lifespan, is a model without self-rated health better, since it mostly predicts short-term (reverse-causation) mortality?
6. Is a cohort life table (with projected improvement, for example from the SSA Trustees) preferable to the 2024 period table for users under 50?
