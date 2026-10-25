# Current Cox score and proposed health-index/projection handoff

Track / task: D trust and submission copy, [#108](https://github.com/ViktorOsadsky/lifetwin/issues/108), documentation draft [#115](https://github.com/ViktorOsadsky/lifetwin/pull/115). Docs only; existing owners are unchanged.

## Current main and held proposal

The current-main model behavior reviewed from `0417b45` is the negated Cox log-relative-hazard score, its survey percentile and the CDC life-table reveal. [PR #126](https://github.com/ViktorOsadsky/lifetwin/pull/126), reviewed at `787e71a4c4e6283c273db05a9ca64a4f9bdbf37b`, is **open and explicitly held for owner confirmation**. Its latest “Projection with fixes, seams blended” section supersedes the earlier hard-switch and unavailable-threshold descriptions in its body. These docs do not promote that proposal to implemented or approved behavior.

| Output | Current main | Proposal in held PR #126 |
|---|---|---|
| Health score | `−log_relative_hazard_score`, including age/sex terms; higher is better. | Cox health index `exp(median s of the band − s(profile))`, removing age/sex terms from both; 1.0 is the group median and higher is better. |
| “Healthier than X of 100 people your age” | Same-sex, nearby-age percentile from unweighted NHANES reference rows. | Same reference rows and band as the index; retain the survey qualification, not a national ranking. |
| Separate hazard index | No separate getter. | No separate lower-is-better `hazardIndex` getter; the proposed ratio is exposed as `healthScore`. |
| Rough lifespan guide | CDC 2024 life-table wrapper throughout eligible ages 18–85. | Weighted CDC/projection age summaries: projection weight rises from 0 at 35 to 1 at 45, stays 1 through 70, then falls to 0 at 79. Pure CDC below 35 and from 79 onward. Under 18, over 85 and missing/unsupported inputs remain unavailable; fractional ages with positive projection weight also return null. |
| Neural output | This bundled app snapshot uses Cox. | The shared lab loads/computes a neural result, but the app does not read it for the displayed score or reveal. This is not a claim that neural execution or artifacts were removed. |

References: [current score](../../app/lib/twin/twin_model.dart), [current repository getter](../../app/lib/twin/twin_repository.dart), [proposed score/reference code](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/app/lib/twin/twin_model.dart), [proposed lifespan code](https://github.com/ViktorOsadsky/lifetwin/blob/787e71a4c4e6283c273db05a9ca64a4f9bdbf37b/app/lib/twin/lifespan.dart), and [source Cox card](../../model_handoff/lifetwin_on_device/MODEL_CARD.md).

## Proposed index contract

Here `s` is the Cox log relative hazard without `age_decade` and `female`, using the same-sex, nearby-age survey band already ranked by `ageGroupPercentile`. The proposal selects the lower median when a band has an even number of rows. The index is a positive ratio of modeled hazards, not a probability or a 0–100 clinical score. The proposed `healthGroupLabel` names the actual band; ages outside 35–79 use the nearest band's reference and retain the rough-guide warning. Raw Cox log hazard remains available internally.

Proposed history points carry `engine: cox_index_v1`, `health_index` and the raw `score`. Default history/sparkline reads exclude untagged or other-engine points rather than mixing the old negative-log scale with the new ratio. No historical profile is invented to recompute an old index. [Proposed score and history API](https://github.com/ViktorOsadsky/lifetwin/pull/126/files).

## Proposed blend, projection and flags

The proposed projection component uses `LifeTwinProjectionLab.assess(profile, includeExtrapolation: true)['annual']`: multiply one-year Cox survival at each advanced age while all other inputs stay fixed, **assuming nothing changes**. It is an unvalidated recurrence, not a fitted longitudinal model or mean life expectancy. The root lab also has a five-year-block experiment; this proposal selects the yearly path.

The projection component's `expectedAge` is the interpolated 50% survival crossing; its `p25Age` and `p75Age` are the 75% and 25% crossings. A threshold not reached by simulation age 110 uses sentinel 110 and an open-ended flag. In a blend that flag survives **only when the blended associated value is still at least 110**. Only retained flags produce **110+** in the headline. This is an unfinished simulated threshold, not an observed crossing or validated personal age. The latest proposal provides a seeded Rosa result.

Each displayed age summary would be `(1 − w) × CDC age + w × projection age`. The projection weight `lifespanProjectionWeight(age)` is zero through 35, rises linearly to 1 at 45, remains 1 through 70, falls linearly to zero at 79, and stays zero thereafter. Ages 18–34 and 79–85 therefore use pure CDC; the blend covers intermediate edges. CDC contributes a mean expected age and 25th–75th-percentile ages, while projection contributes crossing ages. This weighted summary is not mean life expectancy or a validated distribution. The exposed `annualCurve` selects the CDC component where CDC has the larger weight and the projection component otherwise; it is not a blended survival curve.

`projectionWeight` records the weight. `extrapolated`/Rough guide applies where CDC has more than half the weight: completed ages 18–39 and 75–85. Fractional ages with positive projection weight receive no estimate because the projection lab requires completed years. The previous large hard-switch seam steps are resolved by blending, but the PR still records a strict known bug: remaining years increase over 35–45 and expected age falls over 70–79. Do not describe a validated aging trend or a resolved lifespan model.

The measured Cox scope remains supported assessment ages 35–79 and horizons 1–5. Those results do not validate either lifetime component, open-ended flags or blending. Nothing past 79 is validated in this rough guide. No exact death date, clinical prediction, guaranteed survival or causal years gained is supported. [Projection definition](../../model_handoff/lifetwin_on_device/README.md#projection-definitions), [latest held proposal](https://github.com/ViktorOsadsky/lifetwin/pull/126).

## Verification and next dependency

Result: factual current-main documentation plus conditional copy for the latest held proposal. No app code, inference method, model artifact, schema or model version changes. The CDC method is not globally superseded: it remains current main and contributes to the proposed blended guide.

PR / merge state: docs draft #115 remains conditional; engine #126 is open under an explicit owner hold. These changes are on the draft PR branch and are not merged. Owner confirmation and applicable checks remain dependencies; a strict known-bug test or arithmetic golden check does not establish clinical or long-range validation.

Checks actually run: all local Markdown targets in these five documents resolve; `git diff --check` passes. Stage logs contain **107 / 106 / 124 / 123 words**, including tool/timing/rating lines and link labels, with all minutes/ratings still `[fill in]`. The confirmed team section is unchanged, and the model card's Development and Data/interpretation paragraphs match the source card exactly. No engine, provider, UI or device tests were run by this documentation review.

Next dependency: root coordinates the #107/#108 contract differences, owner hold and applicable-check/known-trend concerns. After any approved engine merge, inspect the actual merged implementation and reconcile these five docs and shared guides before claiming the proposed index or reveal is shipped. Daniel retains final device/demo acceptance and stage timing/rating entry.
