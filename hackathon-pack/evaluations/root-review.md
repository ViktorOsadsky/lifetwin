# Root review and iteration record

2026-10-23. This report distinguishes actual executed checks from proposed product validation. No model weights, customer study, live payment or private finance system was involved.

## Finance skill

Executed `python3 skills/hyphenate-finance-agent/scripts/test_finance.py`: eight tests passed. These exercise group-specific balances, cross-entity/currency false matches, integer money, absent evidence, replay, preserved OpenAPI security/reference data and MCP pagination. The balanced `invented_account` fixture deliberately passes the small helper, revealing its semantic limitation. Review tightened the SKILL.md instruction to require the authoritative entity-specific chart of accounts before execution and state exactly what the helper does not establish. No false Hyphenate API schema or successful post is claimed.

## Backend skill

Executed `python3 skills/hackathon-backend/scripts/test_job_ledger.py`: five tests passed, including 32 concurrent same-key reservations accepting one creation, conflicting payload rejection, revision conflict, tenant-namespaced keys and unknown-outcome no-retry. Local SQLite state and history are actual results. Provider exactly-once execution, API authentication, a deployed queue and tenant authorization are not covered; the runtime reference explicitly assigns those to the application adapter/server. Independent behavioral review is recorded under research/integrations/root-runtime-forward-tests.md when complete.

## ML / evaluation skill

The initial seven tests passed. An additional actual probe supplied a prediction with an ID but no `label`; the scorer silently counted it as an abstention, hiding a malformed provider response. Review changed this to a schema error, added a regression, and added explicit per-label false-positive/recall metrics so a false-compatible result is visible. Rerun: nine tests passed. Missing prediction IDs still count against task coverage; explicit null means abstention. All-abstain cannot earn perfect accuracy. This is exact-label fixture scoring, not a trained model or semantic-citation oracle.

## Prize, sponsor and demo skills

An independent agent completed three realistic requests and saved the full responses at [peer-root-evals.md](../research/ideas/peer-root-evals.md). It corrected runtime-versus-coding-only Factory use, cache-only Bright Data eligibility, summing mutually exclusive placements, an irrelevant real-identity CRS request, redundant backends and fabricated payment/recovery demo claims. All three passed the stated behavioral checks; no instruction change was justified solely to create an iteration log.

The strategy's source review also found an actual arithmetic inconsistency: Apify's five listed main prizes sum to $4,600 while the card says $5,000. The separately listed $400 Actor award is a possible explanation, not confirmed. The published inventory preserves the conflict. CREAO and Figma source differences, cash labels on hardware and the solo/team contradiction are likewise preserved.

## Pack completeness

An early local checker validated discovered files and reported nine skills passing while the design agent was still authoring the tenth. Review identified that discovery alone could give a false impression of completion. The verifier now checks the explicit ten-skill manifest; it correctly failed with `creative-web-worlds` missing. The final run passed with all ten entrypoints and local links present: 32 completeness/link/test groups, including 80 local unit-test / fixture cases. All ten entrypoints also passed the creator's YAML/skill validator.

The no-overwrite installer was exercised in an isolated temporary folder: ten new copies succeeded, an identical repeat skipped all ten, and an altered existing skill caused a refusal with existing content preserved. Actual installation then copied all ten new skills into `/Users/flare/.codex/skills`; SHA-256 inventories of every installed tree matched the source pack. See `install-checks.json` and `installed-skills.json` in this directory.

## Other independent iterations

The integration author reproduced root-identified namespace, mutation, polling and concurrent-reservation failures before fixing them; before/after outputs are in [verification.md](../research/integrations/verification.md). Idea research disconfirmed numerous attractive concepts and tightened its recommendation against direct recall and consignment competitors. Creative design preserves screenshot-based revisions and functional checks. These are separate kinds of evidence; test counts should not be represented as a universal quality score.
