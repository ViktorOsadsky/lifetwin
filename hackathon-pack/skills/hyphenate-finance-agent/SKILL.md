---
name: hyphenate-finance-agent
description: Build and evaluate autonomous finance workflows for Hyphenate's Cal Hacks track, and map verified Hyphenate API or MCP schemas into bounded, auditable agent tools. Use for Hyphenate finance automation, reconciliation, close and procurement; not the unrelated Hyphen products.
---

# Hyphenate finance agent

Read [verified-context.md](references/verified-context.md) for the supplied Cal Hacks track brief and verified resource links. Hyphenate at `hyphenate.ai` is the finance platform. `hyphen.ai`, `tryhyphen.com`, older Hyphenate chat SDKs and typography packages are different products.

The supplied brief is a **challenge specification, not a Hyphenate API contract**. It invites teams to build their own company, use a sandbox, borrow a schema or start with a dataset, and choose any models/frameworks. A Hyphenate platform integration is not stated as a submission requirement in that brief. Build a working autonomous finance seat using the chosen system; lack of a Hyphenate API need not block it. Label the actual execution surface precisely.

## Resolve the execution surface

Inspect the project's actual connected tools, sponsor starter pack and supplied OpenAPI first. Record source, timestamp, environment, auth mechanism, schema version, tool names and scopes. If MCP is available, initialize through the client's supported transport and inspect `tools/list`, including pagination. Inspect each selected `inputSchema` and output contract. If REST is available, follow its actual OpenAPI server and security scheme. Never invent a base URL, `/reconcile` endpoint or an API-key header. Read-only hints describe intent; they do not establish authorization.

Use [catalog_tools.py](scripts/catalog_tools.py) to turn a supplied MCP tool-list JSON or OpenAPI JSON into a local review catalog. This script neither connects nor executes. Preserve `$ref` pointers for resolution from the actual spec. For a track build without a sponsor API, choose one of the brief's linked sandboxes/ledgers or an explicit local simulation; verify that system's own current contract before connecting. A real third-party sandbox remains a third-party sandbox, not a verified Hyphenate integration.

## Build a hireable seat

Name the seat and decision rights: e.g. cash reconciliation analyst can propose matches and assemble exceptions; controller approves posting. Pick one complete messy workflow. Define the desired ledger state, source documents, permissions, exception queue, review event and measurable time/error saving. Agents can extract, propose and explain; deterministic code checks sums, identity, entity, currency, dates, thresholds and duplicate keys.

Model the company around the seats: assign a system of record **per fact** (bank for settled cash, signed contract/amendment for obligations, ledger for posted balances, controller for approved policy). Preserve disagreements instead of overwriting them. Store effective dates separately from arrival times and replay a later credit note, partial handoff or controller rejection across periods. A rejected proposal remains rejected until a revised, independently authorized decision; a closed period is not silently reopened. The requester cannot approve their own action. The brief permits a model to portray people; label those approvals simulated and retain independent actor/role checks.

Every proposed action carries tenant/entity, source IDs, document versions, currency, amount in integer minor units (or Decimal with currency scale), policy version, status and reason. Preserve gross amount, fees, net amount and tax separately. Group splits/batches explicitly. An equal amount alone is not a unique match. Multiple plausible matches, missing FX rates, unknown document dates and incomplete evidence go to review. A polished explanation cannot upgrade missing evidence.

Check proposed journals with [finance_checks.py](scripts/finance_checks.py). It validates a deliberately small local schema and does not assert accounting-policy correctness. Debit/credit balance is necessary but insufficient: resolve accounts against the authoritative entity-specific chart of accounts, then require correct period, documentary support and policy review. The helper deliberately accepts a balanced invented account name; an executing adapter must reject it.

For a runnable local example of the next boundary, [workflow_checks.py](scripts/workflow_checks.py) adds entity chart/period checks, source-version snapshots, independent approval bound to a proposal hash, role/scope checks and uncertain-outcome/replay blocking. Read its [local contract and scenario guide](references/workflow-example.md) before using it. It never posts and does not establish document truth, accounting policy or production authorization.

## Make changes observable

Separate ingest → normalize → propose → validate → review → execute → verify. Bind approval to a hash of the exact proposal and policy version. Any changed amount, vendor, bank detail, currency, source version or scope invalidates prior approval. Use least necessary scopes, an idempotency record, and reconciliation of an uncertain remote outcome before retrying a write. Bank-account change requests require independent verification from a known channel; the invoice itself cannot authorize them. Never log credentials or raw bank/card information.

## Win through a hard case

Demonstrate an exception a competent reviewer could miss: duplicate invoice under a changed filename, partial settlement plus fee, stale bank-details request, cross-entity ambiguity or a late credit note. Let a judge alter an input and show the proposal adapt or abstain. Trace a questioned number to its source. Show recovery after a timeout without double-posting. Deliver a short seat description, runnable workflow, exception/evidence view, test cases, and a precise real/sandbox/simulated matrix. Use the four track questions in the reference to structure the demo.

## Exercise and refine

Run `python3 scripts/test_finance.py` and `python3 scripts/test_workflow.py`; the latter emits scenario results with `--report`. See [evaluation.md](references/evaluation.md) for observed coverage and limits. For a new workflow, add a benign happy path, a numerically balanced but wrong proposal, an ambiguous match, a duplicate replay and a judge-supplied change. Review failures by financial consequence; revise the smallest instruction or adapter and rerun the failed case plus one unaffected case. Do not call a sandbox write or production integration tested when only these local checks ran.
