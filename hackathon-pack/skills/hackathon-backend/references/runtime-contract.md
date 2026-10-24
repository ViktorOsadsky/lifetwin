# Runtime contract

## Provider interface (our app contract)

`discover()` returns observed capabilities and schemas. `read(input, deadline)` returns structured facts with source and fetched time. `propose(input)` returns a non-executed action and its version/hash. `execute(approvedAction, idempotencyKey)` returns provider request ID and status. `reconcile(requestId)` reports the remote outcome. `cancel(requestId)` reports whether cancellation is actually supported and confirmed. None of these are asserted sponsor API names.

Keep application errors separate from provider statuses. A 200 may contain an application error; a transport timeout may conceal success. Normalize `failed`, `timed_out`, `cancelled`, `partial`, `awaiting_user`, `unknown_outcome` without discarding original provider codes. Only bounded reads get automatic retries unless the provider documents an idempotent write contract.

## Store

The reference ledger deliberately excludes auth and approval verification; they belong in the API/action service. Its idempotency key must be namespaced by tenant and operation before use. The caller must bind a verified approval to a proposal hash and then use an atomic revision check when entering executing. Persist the same action ID as the remote idempotency key where supported. Local deduplication cannot guarantee exactly-once remote effects after a crash. Distributed systems need provider reconciliation.

Use a stable canonical representation for hashes and reject ambiguous monetary formats (floats, NaN, locale strings). A schema-valid payload can still be semantically wrong. If two distinct users are allowed to approve, define who can approve which operation and enforce separation of duties where the workflow needs it.

## Sponsor backend options

[Convex agents](https://docs.convex.dev/agents/overview) support persisted messages and reactive agent workflows; see the actual installed SDK and [tool approval](https://docs.convex.dev/agents/tool-approval). [SpacetimeDB docs](https://spacetimedb.com/docs) are relevant for transactional shared state and subscriptions. They are alternatives selected for the product, not mandatory dependencies. Recheck current APIs before copying snippets.

Technical grounding: [SQLite transactions](https://www.sqlite.org/lang_transaction.html), [SQLite WAL](https://www.sqlite.org/wal.html), [HTTP semantics and idempotency](https://www.rfc-editor.org/rfc/rfc9110.html#name-idempotent-methods). SQLite fixtures prove local transactional behavior only.
