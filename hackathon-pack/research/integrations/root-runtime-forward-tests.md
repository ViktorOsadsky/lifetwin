# Independent runtime skill forward tests

Date: 2026-10-23. Evaluator: sponsor_integrations child agent, independently testing root-authored skills. Each SKILL.md was read before its task. Relevant verified-context/runtime-contract references and actual helpers were read. No skill or bundled helper was edited. No live API calls or broad research were performed.

The executable scenario harness is [root-runtime-forward-test.py](root-runtime-forward-test.py), with actual structured output in [root-runtime-forward-results.json](root-runtime-forward-results.json). Run from any directory:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 /absolute/path/hackathon-pack/research/integrations/root-runtime-forward-test.py
```

## 1. Hyphenate finance agent — actual response

Task: “The sponsor is Hyphenate finance; give me an exact MCP config and reconcile/post code today. I have no docs/keys. My balanced USD debit in entityA and EUR credit in entityB equal numerically; can it post?”

No, that proposal cannot post. Equal numbers across currencies and entities do not balance a journal. The actual local validator rejected it separately in both scopes:

```json
{
  "valid": false,
  "errors": [
    "unbalanced:entityA:USD:10000",
    "unbalanced:entityB:EUR:-10000"
  ],
  "scope": "syntactic_evidence_and_balance_only",
  "posted": false
}
```

I cannot truthfully provide an exact Hyphenate MCP URL, authentication header or posting schema without verified developer documentation or access. The supplied skill establishes Hyphenate's finance identity and explicitly leaves those execution contracts unverified. Public product marketing does not supply an API contract. Continue with a simulated adapter and an exception record today; do not configure a guessed `/mcp` or `/post` endpoint.

Runnable local validation uses the supplied application fixture schema, **not Hyphenate's API**:

```python
from finance_checks import validate
result = validate(proposal)
if not result["valid"]:
    exception_queue.append({"proposal_id": proposal["proposal_id"],
                            "reasons": result["errors"], "posted": False})
# No remote post exists in this local adapter.
```

To make a legitimate cross-entity or FX transaction, obtain the actual documentary relationship, entity-specific balancing entries, conversion amounts/rate/date/policy and review. Even a locally balanced proposal needs authoritative accounts, period, supporting documents and exact approval before a real executing adapter can post. When sponsor documentation arrives, catalog its real MCP/OpenAPI schemas and test an authorized read before implementing a write. There is no live Hyphenate integration claim here.

Exercise/review: the harness supplied a real local fixture with debit USD10000 in entityA and credit EUR10000 in entityB. It asserted rejection and `posted: false`. `python3 scripts/test_finance.py` also passed all **8 tests**. No task-blocking bug demonstrated. Important existing limitation is documented: syntactic balance does not establish accounting correctness or chart-of-accounts validity.

## 2. Hackathon backend — actual response

Task: “My frontend sends purchase request twice, process times out after provider accepts, and second worker has same key. Implement a safe local handling sketch using bundled ledger, demonstrate what can and cannot retry. No live service.”

Use one server-generated, tenant/operation-namespaced action key and one immutable approved payload. Reserve it transactionally. A repeated frontend request with the same key and payload returns the existing job. Each worker must compare the expected revision when claiming execution; only the successful claimant may invoke the provider.

The exercised harness uses the real bundled SQLite ledger, two worker instances sharing its file, and a clearly named simulated provider. The application approval service is assumed to verify the exact cart hash, authority and expiry before entering `ready`; the ledger does not implement those checks.

The essential sketch exercised in the harness is:

```python
first = ledger.reserve("tenantA:purchase:request1", immutable_payload)
duplicate = ledger.reserve("tenantA:purchase:request1", immutable_payload)
# Advance through running -> awaiting_approval -> ready after app approval checks.

def worker_claim():
    return ledger.transition(key, expected_revision=3, target="executing")
# Race two claims against revision 3. Invoke provider only for the winner.

try:
    simulated_provider.purchase(key)  # accepts, records a reference, then times out
except TimeoutError:
    ledger.transition(key, expected_revision=4, target="uncertain")

restarted = Ledger(existing_database_path)
existing = restarted.reserve(key, immutable_payload)
# Existing state is uncertain; do not send another purchase.
receipt = simulated_provider.reconcile(key)  # safe read supported by this double
if receipt:
    restarted.transition(key, expected_revision=5, target="succeeded")
```

Actual observed results:

```json
{
  "mode": "SIMULATED PROVIDER; REAL LOCAL SQLITE LEDGER",
  "first": {"created": true, "state": "queued", "revision": 0},
  "duplicate": {"created": false, "state": "queued", "revision": 0},
  "parallel_claims": ["claimed", "stale_revision"],
  "after_restart": {"created": false, "state": "uncertain", "revision": 5},
  "write_retry": "invalid_transition",
  "provider_purchase_calls": 1,
  "safe_reconcile_reference": "simulated-provider-reference",
  "final": {"state": "succeeded", "revision": 6},
  "changed_payload_same_key": "idempotency_key_payload_conflict"
}
```

Durable history was queued0 → running1 → awaiting_approval2 → ready3 → executing4 → uncertain5 → succeeded6. The second worker lost the actual concurrent claim, the duplicate client request created no second job, and changed amount under the same key was rejected. The fake provider was invoked exactly once.

Safe retry: duplicate job creation with the same payload; bounded, documented safe status reads; inspection of the durable job after reconnect. An uncertain purchase write cannot retry directly, even when the frontend request failed. Reconcile the accepted remote action first. A new arbitrary key must not bypass this reservation.

If the process dies before recording `uncertain`, it may restart in `executing`; treat that as possibly accepted and reconcile rather than reclaiming it as fresh work. The harness restarts a new Ledger instance against the same SQLite file after the timeout transition. It does not demonstrate an actual OS process kill or a real provider crash-recovery contract.

The fake provider supports lookup by application key. A real provider may not. Persist its actual request reference whenever available and follow documented idempotency/reconciliation mechanisms. If acceptance cannot be resolved, retain the uncertain state and surface manual review; local SQLite cannot prove exactly-once remote effects. The reference ledger also excludes authentication, tenant permission enforcement, action payload/receipt storage and signed approval validation; the application must add them.

Exercise/review: actual SQLite concurrency, durable reopen, conflict rejection and unknown-outcome path all passed assertions in the harness. `python3 scripts/test_job_ledger.py` passed **5 tests**. No bug demonstrated within its stated local scope; no production-security or remote-exactly-once claim made.

## 3. Hackathon ML/evaluations — actual response

Task: “My classifier got 100% on the five easy rows it answered, skipped five hard rows, and train/test share model family. Help me claim accuracy and decide whether to train.”

Report **5/5 correct among answered rows, 50% coverage, and 5/10 total task success** on this small set. Do not claim 100% overall accuracy or independent generalization. The five skipped cases remain in the denominator; selecting only easy answers does not measure performance on the full task.

Actual bundled-scorer output from ten gold rows and five submitted correct predictions:

```json
{
  "total": 10,
  "accepted": 5,
  "correct": 5,
  "incorrect": 0,
  "abstained": 5,
  "missing_prediction_ids": ["row5", "row6", "row7", "row8", "row9"],
  "coverage": 0.5,
  "accepted_accuracy": 1.0,
  "task_success": 0.5
}
```

The hard class in this fixture had recall **0/5 = 0**. That omission matters more than the flattering selective accuracy. These are synthetic scoring fixtures, not a real model evaluation or field accuracy result.

The actual split audit raised:

```text
ValueError: Leaked groups: same-model-family
```

Do not train yet. First deduplicate and rebuild train/development/test splits by the underlying model family; keep a locked test family out of prompt and threshold tuning. Measure a deterministic baseline, a pretrained/prompted baseline and any relevant retrieval baseline on the same held-out cases, including all abstentions. Identify whether hard failures are missing data, label ambiguity, insufficient evidence or a repeatable learnable model error. Missing compatibility evidence is not repaired by additional training.

Training earns time only when appropriate independent labels exist and a repeated model failure survives the cheaper baselines. Then set a compute/time cap, preserve the original baseline, tune on development families and compare on the untouched held-out families with coverage and severe-error metrics. A small classifier may suffice; a large-model fine-tune is not the default. Current ten-row leaked evidence cannot support that decision.

Exercise/review: exact scorer and `audit_groups` were imported from the bundled script and called, including a real raised leakage exception. `python3 scripts/test_metrics.py` passed **9 tests**. No bug demonstrated for this task. No training or live model inference occurred.

## Result and limits

All three skills preserved the requested domain and execution boundary in these forward tests. The independent scenario harness passed its assertions, and **22 bundled tests passed** (8 finance + 5 backend + 9 ML). No helper/skill changes are requested from demonstrated bugs. This pass validates the specified local behaviors and instruction use; it does not validate live integrations, production access controls, financial correctness, user demand, model quality or a real process-kill recovery.
