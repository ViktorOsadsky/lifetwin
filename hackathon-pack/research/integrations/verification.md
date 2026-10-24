# Integration verification, 2026-10-23

## Deliverables and verified capability

`../../skills/apify-evidence-engine` contains account-free MCP discovery, a bounded REST plan/run/collect helper, failure-injection tests, and a custom snapshot-normalizer Actor starter. `../../skills/visa-agentic-commerce` contains the source-pinned integration guide and a signed-consent/state policy helper with offline tests. Both skill entrypoints passed the bundled `quick_validate.py` using temporary PyYAML dependency installation outside the pack. No account settings were changed.

Live Apify read-only calls completed without credentials or paid runs:

| Artifact | Actual operation | Outcome |
| --- | --- | --- |
| `apify-tools-live.json` | MCP initialize, initialized notification, tools/list | Server 0.19.3; protocol 2025-03-26; four account-free discovery/docs tools. |
| `apify-search-live.json` | search-actors, keywords Amazon products, limit 2 | Two Actor summaries with current input-field descriptions and event prices; no scraper run. |
| `apify-actor-live.json` | fetch-actor-details for apify/website-content-crawler | Returned input schema, pricing and metadata. No authentication or collection. |

The official MCP docs currently describe automatic inclusion of polling/result/abort dependencies when execution tools are selected. This differs from reading the default-category table alone. The skill requires actual tools/list discovery and explicitly separates account-free discovery from authenticated runtime.

Visa overview and Developer MCP setup were accessible. Official `visa/ai` source was locally inspected at `1c544e5c1ed45c8c075ca57e9e76e7876e34fd42`. Source links are in the skill's integration guide. The separate sandbox documentation route `/mcp/doc` could not be fetched by the web tool; direct HEAD returned 404. This was not treated as proof that JSON-RPC initialization fails. Separate unauthenticated `POST initialize` calls to documented Developer MCP and sandbox runtime MCP each returned 401; the Developer response required a Bearer token and identified OAuth resource-metadata discovery. Full sanitized results are in `visa-initialize-probes.json`. No tool call followed. No keys/certificates/session were available. There is no live VIC schema/tool/payment evidence, and no service-outage claim.

## Actual before → independent review → revision → rerun

Initial implementation tests passed (10 Apify, 14 Visa). A root-agent review independently identified these behavioral defects. New regression tests were run against the initial code **before** applying fixes:

- Apify: a legitimate Actor input field `maxItems` was incorrectly rejected; caller mutation changed the stored input after hashing; changed run budget was accepted; negative/NaN/infinite polling delays reached the network. `apify-before-review-fixes.txt`: 13 tests, 5 failed assertions and 1 error.
- Visa: two concurrent same-request submissions were both accepted under a barrier-injected ledger; cart contract could not bind variant/fulfillment/destination context. `visa-before-review-fixes.txt`: 16 tests, 1 failed assertion and 1 error.

Narrow fixes preserved independent Actor/run namespaces, snapshotted JSON input, added complete-plan integrity checks, validated polling delays, locked local reservation/outcome operations, and bound `contextDigest` to approval. The concurrency test still uses the same barrier injection; it now permits exactly one reservation. Documentation states the lock is local to an instance/process and requires durable transactional reservation in multi-worker deployments.

Reruns:

| Evidence | Result | Scope |
| --- | --- | --- |
| `apify-after-review-fixes.txt` | 13/13 pass | Budget/input handling, immutable plan, run polling, timeout abort, failure/no rerun, pagination, empty results, readonly allowlist, JSON/SSE, tool-list pagination. |
| `visa-after-review-fixes.txt` | 16/16 pass | Signed approval, material-term changes, expiry, forgery, environment, duplicate/concurrent reservation, unknown-state recovery, receipt boundary, terminal transitions, schema/money totals. |
| `actor-core-tests.txt` | 5/5 pass | JSON-LD graph/list, decimals, missing price, unsupported aggregate, malformed block, nonfinite price. |

Commands are in each skill. `commerce_policy.py --demo` returned `SIMULATED TEST DOUBLE` and `visaApiInvoked: false`. Example manifest validation returned `paymentAuthorized: false`.

Remaining gaps: no authenticated Apify Actor start, cost/abort verification against real billing, Actor Docker/SDK/cloud build, Store publication, VIC authentication, live runtime discovery, enrollment, merchant checkout or sandbox payment. Passing local tests verifies policy/protocol behavior, not financial or real-world extraction efficacy. Both templates preserve these limits explicitly.

## Primary sources

- [Apify MCP](https://docs.apify.com/mcp): connection, tools and unauthenticated boundary.
- [Apify REST run](https://docs.apify.com/api/v2/actors-runs-post): query limits, statuses, separate storage references.
- [Apify Python quick start](https://docs.apify.com/sdk/python/docs/quick-start): scaffold, local run and lifecycle.
- [Actor definition](https://docs.apify.com/actors/development/actor-definition/actor-json) and [input schema](https://docs.apify.com/actors/development/actor-definition/input-schema): packaging contracts.
- [Visa MCP overview](https://developer.visa.com/mcp-docs) and [Developer MCP setup](https://developer.visa.com/resources/mcp-get-started): documentation/runtime distinction.
- [Pinned official Visa source](https://github.com/visa/ai/tree/1c544e5c1ed45c8c075ca57e9e76e7876e34fd42): runtime client, auth utilities, example payload builders, direct API path.
