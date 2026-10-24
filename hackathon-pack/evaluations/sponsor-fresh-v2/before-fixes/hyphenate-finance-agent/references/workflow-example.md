# Local workflow gate and scenario guide

Run from the skill folder:

```sh
python3 scripts/test_finance.py -v
python3 scripts/test_workflow.py -v
python3 scripts/test_workflow.py --report
```

The example company is a festival. A cash-application agent proposes applying a $97 bank receipt with a documented $3 fee against a $100 receivable. A separate controller approves the exact snapshot. All actors, sources, money and decisions are synthetic. The journal is only a fixture; the helper does not derive the fee or prove the accounting treatment from documents.

`workflow_checks.gate(proposal, context)` composes the existing balance/evidence syntax check with selected execution-boundary checks. It returns `ready_for_adapter`, `errors`, `execution_surface: local_example`, and `posted: false`. Even the happy path makes no network call.

## Additional local fields

The proposal extends the finance fixture with `posting_period` (`YYYY-MM`), `requested_by`, `operation_key`, and `source_versions` mapping every source ID to its version. `proposal_hash` hashes all proposal fields using sorted, compact JSON. Restrict the example to JSON strings, integers, arrays and objects; this Python serialization is not a cross-language canonicalization protocol.

The trusted context supplies:

| Field | Meaning |
| --- | --- |
| `tenant_id` | Active tenant, independently resolved by the application. |
| `chart_of_accounts` | Entity → valid account IDs. |
| `open_periods` | Entity → periods currently open. |
| `current_source_versions` | Complete evidence snapshot required **for this case**, including a newly arrived credit note. |
| `current_policy_version` | Policy currently governing the case. |
| `approval` | `actor`, `decision` (`approved` is required), `proposal_hash`. |
| `actor_roles` | Actor → roles; the example requires `controller`. |
| `approver_entities` | Actor → authorized entity IDs within the active tenant. |
| `operation_status` | Business operation key → remote outcome; `confirmed` blocks replay, any other recorded value requires reconciliation. An absent key represents no attempted operation in this fixture. |

The proposing model must not populate trusted context, grant roles, invent an approval or delete an operation record. A real adapter obtains those from its own authorization, document, ledger and audit stores and rechecks them at commit time. This helper accepts well-formed local dictionaries; use proper input validation for external payloads.

## Temporal exercise and limits

The March proposal passes. In June, March is closed and a new credit note appears, so the old proposal must be held even if its debits and credits still balance. A revised June snapshot requires a fresh independent approval. That test demonstrates invalidation and review boundaries; it does **not** calculate the credit note's accounting correction. Implement the relevant accounting policy and post-period adjustment in the actual workflow before showing it as autonomous accounting.

The scenario runner also exercises controller rejection, a balanced edited amount, an invented account, stale policy, self-approval, entity/tenant scope mismatch, timeout/unknown outcome and confirmed replay. Unknown outcome requires querying the real adapter by its documented operation/request identity before retrying. The local helper merely reports that hold; it does not perform recovery.

Production needs remain: authoritative source reconciliation, exact journal semantics and dates, immutable durable audit events, stable business duplicate identity, atomic idempotency/approval checks with the write, scoped execution credentials, verified bank details, evidence confidentiality, and remote verification. `ready_for_adapter` is a local check result, not authorization to move money.
