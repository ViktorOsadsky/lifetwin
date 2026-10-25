# Centred Cox score and blended reveal handoff

Track / task: D trust and submission copy, [#108](https://github.com/ViktorOsadsky/lifetwin/issues/108), docs [#115](https://github.com/ViktorOsadsky/lifetwin/pull/115). Docs only; existing owners are unchanged.

## Merged source and superseded states

Reviewed main `9ace866`: [#126](https://github.com/ViktorOsadsky/lifetwin/pull/126) merged at `41dce10` with source head `614e37d`; [#138](https://github.com/ViktorOsadsky/lifetwin/pull/138) then merged the centred score. The old #126 hold is resolved. The former negative-log score and the intermediate 1.0-relative index are historical display scales, not current behavior. The earlier CDC-only wrapper remains the CDC component of the current blend.

## Current score and history

`healthScore = median band s − s(profile)`, where `s` is the Cox log relative hazard without `age_decade` and `female`. The same-sex, nearby-age survey band is the one ranked by `ageGroupPercentile`; an even-sized band uses its lower median. **0 is the survey-group middle; positive is healthier and higher is better.** This is the log of the former hazard ratio (`exp(score)`), not a probability, clinical score or nationally representative ranking. `healthGroupLabel` names the actual band. Outside 35–79, eligible ages use the nearest reference band and retain the rough-guide warning. Raw full Cox log hazard stays internal; no separate lower-is-better `hazardIndex` getter exists.

History uses `engine: cox_centered_v1`, the centred value under `centered_score` and raw hazard under `score`. Default history/sparkline readers exclude legacy negative-log, `cox_index_v1` and other-engine points, rather than mixing scales or inventing historical profiles. [Current score](../../app/lib/twin/twin_model.dart), [history](../../app/lib/twin/history_log.dart), [repository](../../app/lib/twin/twin_repository.dart).

## Current blend, projection and flags

The projection component reads `LifeTwinProjectionLab.assess(profile, includeExtrapolation: true)['annual']`: multiply one-year Cox survival at each advanced age while all other inputs stay fixed, **assuming nothing changes**. It is an unvalidated recurrence, not a fitted longitudinal model. The root lab also has a five-year-block experiment; the app selects the yearly path.

Projection contributes its interpolated 50% survival crossing to `expectedAge`, and 75%/25% crossings to `p25Age`/`p75Age`. A threshold not reached by 110 uses sentinel 110. Its open-ended flag survives only if the corresponding blended value remains at least 110; retained flags show **110+**, not an observed crossing or guaranteed age.

Each age summary is `(1 − w) × CDC age + w × projection age`. `lifespanProjectionWeight(age)` is zero through 35, rises linearly to 1 at 45, remains 1 through 70, falls linearly to zero at 79 and stays zero thereafter. CDC contributes a mean expected age and 25th–75th-percentile ages; projection contributes crossing ages. This mixture is not mean life expectancy or a validated survival distribution. `annualCurve` selects CDC where CDC has the larger weight and projection otherwise; it is not a blended curve whose crossings equal every displayed summary.

`projectionWeight` records w; Rough guide/`extrapolated` applies where w < 0.5 (completed ages 18–39 and 75–85). Fractional ages are supported: projection input age is floored to completed years; the weight and remaining-year calculation retain the fractional age. Under 18, over 85, missing/unsupported inputs or an absent required lab remain unavailable. The latest merged loader reads neural asset bytes and decodes UTF-8 explicitly to avoid a large-file background-isolate stall before `runApp`; this loading fix does not change model values. The lab still computes neural output that the app does not read for score/reveal. [Reveal](../../app/lib/twin/lifespan.dart), [loader](../../app/packages/lifetwin_on_device/lib/lifetwin_on_device.dart).

Blending resolves the earlier large hard-switch steps, but remaining years increasing at 35–45 and expected age falling at 70–79 remain acknowledged known bugs. Do not describe a validated aging trend or resolved lifespan model. The measured Cox scope is assessment ages 35–79 and horizons 1–5; those metrics do not validate lifetime components, flags or blending. Nothing past 79 is validated in this rough guide. No exact date, clinical prediction, guaranteed survival or causal years gained is supported. [Source card](../../model_handoff/lifetwin_on_device/MODEL_CARD.md), [projection definition](../../model_handoff/lifetwin_on_device/README.md#projection-definitions).

## Verification and next dependency

Result: five docs reconciled to actual merged #126/#138. No engine code, model artifact, inference values, schema or version change in this docs diff. Root owns shared master/team/lifespan-guide reconciliation separately.

PR/merge state: engine changes are merged; these docs are locally committed on #115's branch for normal PR checks/review, not published or merged by this author. Stage timing/rating fields remain intentionally unmeasured.

Checks actually run: local Markdown targets, `git diff --check`, confirmed-team preservation and exact source-card Development/Data-and-interpretation paragraphs. Stage logs: 111 / 105 / 121 / 117 words including tools/timing/rating lines and link labels, all under 200. No engine, provider, UI or device test is claimed by this docs review.

Next dependency: root reviews/publishes the docs through #115. Daniel retains final recording/device acceptance and stage timing/rating entry. The separate #133 script must use zero-centred narration and an actual displayed seed value; earlier 1.0/1.65 requirements are superseded by #138. Its timed simulator rehearsal remains separate from this source reconciliation.
