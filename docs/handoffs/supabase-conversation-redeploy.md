# Supabase conversation configuration and redeployment

Track B, requested in [#231](https://github.com/ViktorOsadsky/lifetwin/issues/231).

The runtime loader, deployment helper and new setter-only migration now accept
`CONVERSATION_PROVIDER`. Existing applied migrations stay unchanged. Provisioning
validates `claude`, `muse` or `local`; the database setter rejects other values.
Owner-only setter privileges remain unchanged. No model, app, contract or provider
credential value changes are committed.

Validation: 28 provisioning/helper tests passed, including preservation of the
conversation override alongside Muse personalization and rejection of unsupported
values. Runtime/helper/latest-migration allowlists are checked together. All 121 Edge
tests, Deno formatting/type checks and source export checks passed. The
setter-only migration was applied through MCP Bridge as version
`20261025113550`; security/performance advisories before it had no WARN/ERROR
findings. The existing hosted function remains v5 until the final redeployment.

PR/merge and live deployment state are recorded in this change's PR. The next
dependency is Daniel's Edge intent port: review and merge it after applicable
checks, then deploy the final merged bundle via MCP Bridge to project
`plpywefoeepfunptjujc` and verify live capabilities and synthetic conversations.
Use Claude for conversations and PDFs, preserving Muse personalization and all
provider consent boundaries. Do not claim FastAPI parity from schema checks.
