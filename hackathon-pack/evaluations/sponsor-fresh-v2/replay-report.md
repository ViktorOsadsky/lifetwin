# Authorized boundary fixes and replay

The initial fresh tasks and critique were completed before the parent authorized narrow implementation fixes. Original helpers, contracts, authored tests, my runners and initial output JSON are retained under `before-fixes/`. Initial reports are historical evidence, not a statement of the current helper behavior.

## Correcting this evaluator's initial Apify probe

The first probe compared a synthetic request `build` string directly with response `buildId`. Official REST documentation establishes that the request uses a tag or build **number**, while the response has separate opaque `buildId`, `buildNumber` and `actId` fields. Therefore that first comparator was not a valid live request/response assertion. It was a meaningful prompt to inspect the boundary, but needed correction before implementing a fix.

The [official run request](https://docs.apify.com/api/v2/actors-runs-post) and [run metadata](https://docs.apify.com/api/v2/actor-run-get) were read for the fix. `apify-corrected-boundary-replay.json` runs the preserved original helper and the new helper against **the same contract-correct numeric build fixture**. The benign case is accepted by both. Different `actId`, different `buildNumber`, or missing `buildNumber` still return envelopes before the fix and now hold before any dataset read. This establishes the actual gap without relying on the original invalid comparison. All these response mutations are offline doubles; no live service violation is claimed.

## Hyphenate delta

Changed `scripts/workflow_checks.py`, `scripts/test_workflow.py` and `references/workflow-example.md` only. The context now requires trusted `prior_decisions`, with `[]` representing a review store's complete empty history for this case. A record contains exactly a 64-character lowercase proposal hash and an approved/rejected decision. Missing or malformed history fails closed. Any earlier rejection of the exact current hash holds despite a later replacement `approved` decision. A revised hash needs a fresh independent approval; a historical approval cannot authorize the current proposal.

The independent resale probe changes from `ready_for_adapter: true` in `initial-results.json` to `false` with `rejected_snapshot_requires_revision` in `after-fixes-results.json`. The original 11 resale and 7 shopping cases retain their expected outcomes. The new authored scenarios test unchanged reapproval, revised/fresh approval and revised/stale approval; malformed/missing history and history-as-current-approval are separately exercised. All 17 author workflow scenarios pass; the full finance suite has **12 passing test methods**.

The history is a trusted application boundary, not model-generated authority. This helper cannot establish that a history store is complete, immutable or tenant-correct. It cannot decide whether changing a metadata field is a substantive revision. The adapter must supply complete scoped history and enforce real policy, review identity and persistence. `ready_for_adapter` still never posts.

## Apify delta

Changed `scripts/bounded_run.py`, `scripts/test_apify.py` and `references/operations.md`, plus the author's offline `research/integrations/apify-doc-refinement/scenario-check.py` fixture to use the new contract. Its generated plan/output/report were rerun. The author's fixture build number is explicitly labeled synthetic.

`make_plan` now binds `reviewedActorId` into its digest. Plans may still omit identity/build for review. `collect` refuses to start without a reviewed Actor ID and exact numeric build selector; mutable tags such as `latest` remain plan-only in this executor even though the platform supports them. CLI execution takes `--reviewed-actor-id` and numeric `--build`. The input schema must be reviewed for that build, not assumed identical to a current Store schema.

Every start/poll response must match the reviewed Actor ID and numeric build, contain an opaque build ID, retain the same run ID, and retain the same opaque build ID across polls. Mismatch returns no dataset envelope. It issues no abort against an unverified run and no replacement start; existing state requires read-only reconciliation. Known nonterminal runs still use the existing bounded polling/owned-run abort behavior. Unknown start outcomes still have no automatic retry. Returned provenance now includes `actorId` and `buildNumber` separately from `buildId`.

The full Apify suite has **16 passing test methods**. Independent Apify coverage grew from 10 to **12 offline cases** to explicitly cover Actor and missing-build identity. Wrong build is now held by the supplied helper, while the independent application gate continues to hold missing coverage, off-scope source and unknown measured cost. The author's five-page scenario still fetches offsets 0/2/4 and blocks budget mutation before network. No paid execution, deployed build or real collection occurred.

## Validation evidence

- `hyphenate-tests.log`: 12 tests pass; `hyphenate-author-rerun.json`: 17 scenarios pass.
- `apify-tests.log`: 16 tests pass; author scenario: five synthetic rows, 0/2/4 pages, mutation blocked.
- `visa-tests.log`: 16 tests pass; unchanged Visa policy helper.
- `after-fixes-results.json`: 11 resale cases, 7 shopping cases, rejection-history probe now holds.
- `apify-rerun-results.json`: 12 independent lifecycle/evidence cases, zero paid runs.
- `apify-corrected-boundary-replay.json`: contract-correct preserved before/after comparison.

These reruns verify implementation behavior on the explicit cases; they do not establish that a new agent follows revised prose better. No author's unrelated evaluation conclusions were used to generate the initial tasks. The authored test/scenario source was read only after initial outputs existed, to maintain those baseline fixtures during the authorized fixes.
