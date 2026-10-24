# Track D: Advisor, Trust & Demo

**Owner:** _TBD_ · **Master doc:** §5, §15, §16, §12 phases 4–5

## Advisor (§5)

- Logic behind `POST /api/advisor` (B hosts the route). Shapes in `contracts/advisor.schema.json`.
- **Context (current decision, may change):** the user's inputs plus the model's results (prediction, comparison, risk factors),
  plus curated evidence-based guidelines you assemble (§5.3). Build the context in **one function**, so changing what the LLM
  sees later is a single edit.
- Must do everything in §5.2: explain in plain language, name modeled risk factors, suggest realistic changes, answer
  per-variable questions, compare scenarios, explain uncertainty.
- Must separate model patterns, established evidence and general recommendations (§5.1), and never present associations as causes.
- **Never states a number the model didn't produce** (§5.3). `contracts/check.py` rejects any percentage in an answer that isn't
  in the request's model output. Keep that passing.
- Safety (§15): no diagnoses, no medication advice, no dates of death, no guarantees.
- LLM key on the server only. The user's inputs go to the LLM provider, so mention that in the app.

## Trust copy (§15 prediction transparency)

Write the short, reusable text the app shows: dataset used, prediction horizon, model limits, observational nature,
association vs. cause. Hand it to Track C.

## Demo (§16)

- Script follows the master doc's seven steps. Prepare a 3-minute and a 2-minute version.
- Keep one held-out profile the team hasn't tuned on, and rehearse a judge changing an input live.
- Rehearse on the actual iPhone ([ios-testing.md](../ios-testing.md)), including what to say if the network drops.
- Quote only measured model numbers from Track A's eval report.
