---
name: hackathon-backend
description: Build a small reliable backend for an agentic hackathon product, including jobs, evidence, idempotency and approval-bound actions. Use for shipping end-to-end agent workflows under a deadline.
---

# Hackathon backend

Start from the user's chosen stack and repository. Keep one server, one durable store, one provider adapter and one demonstrable vertical slice until it works. Separate a browser's display state from the durable job state. Preserve an API contract before adding parallel work.

## Define the narrow contract

Represent a job with ID, tenant, state, input version, idempotency key, revision and timestamps. Evidence records retain source URL/ID, fetched time, content hash, extraction method and the exact facts used. Action records bind tool name, normalized arguments, policy version, approval scope and outcome request ID. Store large source bodies outside the model's prompt; pass selected evidence and citations.

Expose only the few routes required: create job, inspect job, inspect evidence, approve exact action and cancel pending work. Validate payloads and tenant ownership on the server for every read, stream and action. The server computes spend limits, permissions and totals; client controls are presentation. A cancelled HTTP connection does not prove an external job was cancelled.

## Make long work survive

Return a job ID quickly. Stream events with sequence IDs or poll revisioned state; reconnect by reading durable state and resuming from the last sequence. Display the same job on refresh. Use bounded provider timeouts, a total deadline, capped retries with jitter for safe reads and real cancellation where supported. Respect Retry-After and quotas. Do not retry an irreversible write after an uncertain outcome until its remote idempotency key or request ID has been reconciled.

The portable [job_ledger.py](scripts/job_ledger.py) demonstrates transactional idempotency and revision checks with SQLite. It is a local reference, not a hosted queue or complete production security system. Read [runtime-contract.md](references/runtime-contract.md) for the state model and provider adapters. If using Convex, SpacetimeDB or another sponsor backend, implement these invariants using that platform's actual transactions and permissions; do not force SQLite into the product.

## Keep a useful failure state

Use typed states: queued → running → awaiting_approval → ready → executing → succeeded. Reads can finish directly from running. Failed and cancelled are terminal. An executing operation whose result is unknown becomes uncertain; a separate reconciliation path determines the actual remote outcome. Each transition atomically checks the expected revision and appends an event. Approval authorizes the exact hash and expiry, not everything a model may generate next. Changed vendor, product, amount, currency, address or policy requires a new action revision.

Keep mock and live adapters explicit and interchangeable through the same contract. Show the actual mode in the UI and submission. A local success never claims a Visa payment, Hyphenate post or live Apify run. Bright Data's published challenge disqualifies mocked/hardcoded demo data; a replay is unsuitable for that prize even if it is useful while developing.

## Verify the costly mistakes

Run `python3 scripts/test_job_ledger.py`. Then exercise your actual app: double-click a mutation, refresh during a job, reconnect a stream, change an approved item, receive a provider timeout after submission, open another tenant's job and interrupt the process after persisting an action. Check server logs for redacted request IDs and state transitions. A clean frontend build alone does not validate these behaviors.

Deliver the runnable slice, setup/env variable names, API/data contract, a seeded demo, observed latency and cost, failure behavior and explicit limits. Never silently introduce a second backend just to qualify for a second prize.
