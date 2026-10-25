# Track D: Advisor, Trust & Demo

**Owner:** _TBD_ · **Master doc:** §5, §15, §16, §12 phases 4–5

Read [MASTER_PLAN.md](../../MASTER_PLAN.md) for current requirements, [tech-stack.md](../tech-stack.md) for choices and [the backend run guide](../../server/README.md) for implemented intake, curated educational plans, research adapter and quiz delivery. Contracts/checkers now exist. App/Cartesia/check-in/model work has since landed; live-provider/device validation must still be reported separately. The master guide records current boundaries. Upload and autonomous daily planning remain planned.

## Mascot guide, fortune and quiz

- Implement the LLM conversation guide (“Muse” in the user description): one clear question at a time, schema-shaped candidate fields, ambiguity/unit follow-ups, confirmation and correction. Voice and text share the same guide; Cartesia integration is documented in the voice guide.
- Write grounded magic-ball narration: mascot presentation uses the validated model value/horizon, never an invented exact death date. Coordinate animation events with C and validated context with B.
- Author a small reviewed bank of challenging food-choice and situational questions with options, answers, explanations, difficulty and source links. C scores deterministically and updates independent game health/reactions immediately; quiz results never change medical inputs or predictions.
- Own evidence retrieval, sensitivity interpretation and plan-to-experiment mappings from the master guide. Plans must distinguish modeled association, external evidence, and proposed action; unmodeled supplements/actions receive no invented numerical benefit.

## Advisor (§5)

- Logic behind `POST /api/advisor` (B hosts the route). Shapes in `contracts/advisor.schema.json`.
- **Context (current decision, may change):** the user's inputs plus the model's results (prediction, comparison, risk factors),
  plus curated evidence-based guidelines you assemble (§5.3). Build the context in **one function**, so changing what the LLM
  sees later is a single edit.
- Must do everything in §5.2: explain in plain language, name modeled risk factors, suggest realistic changes, answer
  per-variable questions, compare scenarios, explain uncertainty.
- Must separate model patterns, established evidence and general recommendations (§5.1), and never present associations as causes.
- Never invent a personal survival number (§5.3). Validate value, units, horizon, profile/scenario and model version together; a matching number in the wrong context fails. Keep cited evidence statistics and quiz scores distinct. The planned checker must improve beyond the original number-membership heuristic.
- Safety (§15): no diagnoses, no medication advice, no dates of death, no guarantees.
- LLM key on the server only. The user's inputs go to the LLM provider, so mention that in the app.

## Trust copy (§15 prediction transparency)

Write the short, reusable text the app shows: dataset used, prediction horizon, model limits, observational nature,
association vs. cause. Hand it to Track C.

## Demo (§16)

- Script follows the updated master guide: upload/import or talk/type → confirm missing inputs → outlook/drivers → experiment/reset → daily schedule → real check-in → explained next-plan revision; include quiz error/recovery separately. Prepare 3-minute and 2-minute versions, accurately labeling unavailable capabilities, provider setup and any fixture mode.
- Keep one held-out profile the team hasn't tuned on, and rehearse a judge changing an input live.
- Rehearse on the actual iPhone ([ios-testing.md](../ios-testing.md)), including what to say if the network drops.
- Quote only measured model numbers from Track A's eval report.

## October 23 product refinement (planned)

Use [the meeting decisions](../meetings/2026-10-23-product-refinement.md) to refine the pitch: a daily health companion that helps users understand their modeled outlook and adapt a practical plan. Keep document upload at entry and ask only for missing inputs. The exact-death-year request is an aspiration for a tangible future, not permission to invent a date, cutoff or years gained.

Define the agent's bounded observe → evidence/action selection → daily schedule → completion feedback → explained revision loop with B/C. Include goals, constraints, missing data, declined actions and provider failure; prove a changed-input revision in replay. Notifications, LLM interpretation or health-score calculations alone are insufficient. Subjective wellbeing informs feasibility and tone, never an invented medical score or prescription. Respect on-device check-in history and the model's supported reassessment windows. The current curated advisor and scripted check-ins do not yet fulfill this planner requirement.
