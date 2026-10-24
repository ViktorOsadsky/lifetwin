# Apify source refinement — 2026-10-23

## Source findings and change

The supplied [Google Doc](https://docs.google.com/document/d/1k6NGZcCUv7DZJ0kVWwQW419nb-Uz3vDlTyZt7nqdVNY/edit) and its 50 embedded hyperlink entries were inspected. The public [Hive resources](https://hive.hackberkeley.org/resources) inventory links an Apify Drive folder; a fresh public HTTP read of that folder found one visible document row, the same supplied guide. Sanitized evidence is in `drive-folder-inventory.json`; raw folder HTML was removed. No extra hidden/private folder content is claimed.

The existing skill already had useful bounded execution, provenance, failure handling and a local Actor normalizer. New `references/starter-pack.md` adds decision-oriented routes for Console/Apify AI, existing plugins versus direct MCP, API clients versus Actor SDKs, six exact starter Actor identities, tasks/schedules/webhooks/storage, credit handling, and submission evidence. The entrypoint links it only for those workflows.

Current [official MCP docs](https://docs.apify.com/mcp) support OAuth/Bearer connection, the exact four-tool unauthenticated configuration, `callOptions`, run-versus-output separation, and auto-loaded result/poll/abort/key-value dependencies. Operations now explain this final inventory, the full-permission Actor exclusion, inferred output schema limits, documented wait bounds, and private storage IDs as access-bearing data. [Permissions](https://docs.apify.com/actors/running/permissions), [plugins](https://docs.apify.com/agents/plugins), [tasks](https://docs.apify.com/actors/running/tasks), [webhooks](https://docs.apify.com/integrations/webhooks), [storage](https://docs.apify.com/storage), and [REST run options](https://docs.apify.com/api/v2/actors-runs-post) were checked.

The current [Cal Hacks 13.0 Devpost](https://cal-hacks-13-0.devpost.com/) confirms five Best use of Apify awards plus a separate Best Actor award. The supplied document and prize entries do not specify Store publication, monetization, stacking or detailed sponsor judging criteria. The reference states those limits instead of inventing requirements. No event-version conflict was found; an early internal suspicion was corrected after inspecting the exact event URL.

The source credit offer is summarized without copying the promotion code or a redemption URL. No credential, redemption, plugin installation, account setting, run, schedule, webhook or publication was performed.

## Live verification

- `mcp-tools-live.json`: fresh anonymous initialize, initialized notification and tools/list; server 0.19.3, protocol 2025-03-26, exactly four discovery/docs tools. These are observations rather than pinned requirements.
- `search-maps-live.json`: `Google Maps reviews`, limit 2; two current Actor matches. Search does not force the starter pack's broader Maps Actor when a specialized review Actor fits better.
- `website-content-details-live.json`: exact `apify/website-content-crawler` input/output schema, metadata, README summary and pricing. Observed model `FREE`; this does not prove total platform cost is zero. The required input fields include `startUrls` and `proxyConfiguration`.

The initial sandbox network tunnel rejected the MCP endpoint. A narrowly approved read-only network escalation then succeeded. This was a transport restriction, not an Apify authentication or billing test.

## Execution tests and correction

- `helper-tests.txt`: 13/13 existing tests pass, including budget/input isolation, immutable plan, mutation rejection, uncertain POST, failure/no-rerun, polling abort, pagination, JSON/SSE and discovery allowlist.
- `extractor-tests.txt`: 5/5 tests pass for decimal/unknown availability, graph/multiple offers, malformed JSON-LD, invalid prices and unsupported aggregate offers.
- Skill Creator `quick_validate.py`: pass.
- `scenario-check.py` / `scenario-results.json`: an offline five-page docs-evidence plan using the freshly discovered Actor schema. The initial draft missed the required `proxyConfiguration`; a required-field smoke check rejected it. The corrected draft passes that check and produces `five-page-plan.json`, with Actor crawl limits separate from the platform $0.20/5-item/120-second options. The value is an illustrative planning cap, not spending authorization.
- Fixture-only collection retrieves five explicitly synthetic rows over offsets 0, 2 and 4, retains source/provenance, and keeps unknown usage cost as null. A modified $100 cap is rejected before any API call. `collection-fixture-output.json` labels its mode; it is not cached real-world evidence.

No runtime defect was demonstrated, so implementation scripts were not changed. The scenario smoke check is not full JSON Schema validation. Authenticated execution/tool inventory, actual collection quality, pricing enforcement, target reachability, confirmed live abort, container/SDK build and Store publication remain unverified. Root-agent fresh-context independent review remains a separate required pass.
