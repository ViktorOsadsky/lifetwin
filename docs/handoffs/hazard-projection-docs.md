# Current Cox score and proposed health-index/projection handoff

Track / task: D trust and submission copy, [#108](https://github.com/ViktorOsadsky/lifetwin/issues/108), documentation draft [#115](https://github.com/ViktorOsadsky/lifetwin/pull/115). Docs only; existing owners are unchanged.

## Current main and held proposal

The current-main model behavior reviewed from `0417b45` is the negated Cox log-relative-hazard score, its survey percentile and the CDC life-table reveal. [PR #126](https://github.com/ViktorOsadsky/lifetwin/pull/126), reviewed at `02f57169976337db66e74aa9feaa740043d0e636`, is **open and explicitly held for owner confirmation**. Its latest “Projection with fixes” section supersedes the earlier unavailable-threshold description in its body. These docs do not promote that proposal to implemented or approved behavior.

| Output | Current main | Proposal in held PR #126 |
|---|---|---|
| Health score | `−log_relative_hazard_score`, including age/sex terms; higher is better. | Cox health index `exp(median s of the band − s(profile))`, removing age/sex terms from both; 1.0 is the group median and higher is better. |
| “Healthier than X of 100 people your age” | Same-sex, nearby-age percentile from unweighted NHANES reference rows. | Same reference rows and band as the index; retain the survey qualification, not a national ranking. |
| Separate hazard index | No separate getter. | No separate lower-is-better `hazardIndex` getter; the proposed ratio is exposed as `healthScore`. |
| Rough lifespan guide | CDC 2024 life-table wrapper throughout eligible ages 18–85. | Ages 35–79: yearly Cox projection; ages 18–34 and 80–85: retained CDC fallback with extrapolated status. Under 18, over 85, missing or unsupported inputs remain unavailable. |
| Neural output | This bundled app snapshot uses Cox. | The shared lab loads/computes a neural result, but the app does not read it for the displayed score or reveal. This is not a claim that neural execution or artifacts were removed. |

References: [current score](../../app/lib/twin/twin_model.dart), [current repository getter](../../app/lib/twin/twin_repository.dart), [proposed score/reference code](https://github.com/ViktorOsadsky/lifetwin/blob/02f57169976337db66e74aa9feaa740043d0e636/app/lib/twin/twin_model.dart), [proposed lifespan code](https://github.com/ViktorOsadsky/lifetwin/blob/02f57169976337db66e74aa9feaa740043d0e636/app/lib/twin/lifespan.dart), and [source Cox card](../../model_handoff/lifetwin_on_device/MODEL_CARD.md).

## Proposed index contract

Here `s` is the Cox log relative hazard without `age_decade` and `female`, using the same-sex, nearby-age survey band already ranked by `ageGroupPercentile`. The proposal selects the lower median when a band has an even number of rows. The index is a positive ratio of modeled hazards, not a probability or a 0–100 clinical score. The proposed `healthGroupLabel` names the actual band; ages outside 35–79 use the nearest band's reference and retain the rough-guide warning. Raw Cox log hazard remains available internally.

Proposed history points carry `engine: cox_index_v1`, `health_index` and the raw `score`. Default history/sparkline reads exclude untagged or other-engine points rather than mixing the old negative-log scale with the new ratio. No historical profile is invented to recompute an old index. [Proposed score and history API](https://github.com/ViktorOsadsky/lifetwin/pull/126/files).

## Proposed projection, flags and fallback

For assessment ages 35–79, the proposed reveal uses `LifeTwinProjectionLab.assess(profile, includeExtrapolation: true)['annual']`: multiply one-year Cox survival at each advanced age while all other inputs stay fixed, **assuming nothing changes**. It is an unvalidated recurrence, not a fitted longitudinal model or mean life expectancy. The root lab also has a five-year-block experiment; this proposal selects the yearly path.

`expectedAge` would contain the interpolated 50% survival crossing; `p25Age` and `p75Age` the 75% and 25% crossings. If a threshold has not been reached by the simulation limit of 110, the API would return the sentinel age 110 and its corresponding `openEnded`, `p25OpenEnded` or `p75OpenEnded` flag. The proposed headline prints **110+** for a flagged threshold. That means the simulated threshold was not reached within the followed curve; it is neither an observed crossing nor a validated personal age. The latest proposal makes the seeded demo Rosa available; the earlier “Rosa is null” behavior is superseded.

For ages 18–34 and 80–85, the proposal would retain the [CDC life-table method](../lifespan-estimate.md), including its mean expected age and 25th–75th-percentile range, with `extrapolated`/rough-guide status. It would therefore mix a projection median inside 35–79 with a different method's mean outside. The source/PR acknowledges large discontinuities at 34→35 and 79→80, tracked as a strict known bug. These seams remain unresolved; do not imply continuity or a validated birthday-related change in outlook.

The measured Cox scope remains supported assessment ages 35–79 and horizons 1–5. Those results do not validate either lifetime method, open-ended flags or the method switch. Nothing past 79 is validated in this rough guide. No exact death date, clinical prediction, guaranteed survival or causal years gained is supported. [Projection definition](../../model_handoff/lifetwin_on_device/README.md#projection-definitions), [latest held proposal](https://github.com/ViktorOsadsky/lifetwin/pull/126).

## Verification and next dependency

Result: factual current-main documentation plus conditional copy for the latest held proposal. No app code, inference method, model artifact, schema or model version changes. The CDC method is not globally superseded: it remains current main and the proposed out-of-range fallback.

PR / merge state: docs draft #115 remains conditional; engine #126 is open under an explicit owner hold. These changes are on the draft PR branch and are not merged. Owner confirmation and applicable checks remain dependencies; a strict known-bug test or arithmetic golden check does not establish clinical or long-range validation.

Checks actually run: all local Markdown targets in these five documents resolve; `git diff --check` passes. Stage logs contain **107 / 104 / 123 / 124 words**, including tool/timing/rating lines and link labels, with all minutes/ratings still `[fill in]`. The confirmed team section is unchanged, and the model card's Development and Data/interpretation paragraphs match the source card exactly. No engine, provider, UI or device tests were run by this documentation review.

Next dependency: root coordinates the #107/#108 contract differences, owner hold and failing-check/known-seam concerns. After any approved engine merge, inspect the actual merged implementation and reconcile these five docs and shared guides before claiming the proposed index or reveal is shipped. Daniel retains final device/demo acceptance and stage timing/rating entry.
