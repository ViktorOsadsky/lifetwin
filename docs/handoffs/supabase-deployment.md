# Supabase backend deployment handoff

Track / task: B, deploy an app backend with server-side provider keys using MCP Bridge.

Result: LifeTwin project `plpywefoeepfunptjujc`, function `lifetwin-api`, JWT required.
Version 2 is ACTIVE with JWT verification enabled; all 12 deployed source hashes
match this implementation. The API is live at
`https://plpywefoeepfunptjujc.supabase.co/functions/v1/lifetwin-api`.
The owner chose Edge Functions because no Python hosting account was available.
The original FastAPI backend remains a local reference; no model artifacts were
changed. See [deployment guide](../../supabase/functions/lifetwin-api/README.md).

PR / merge state: [#204](https://github.com/ViktorOsadsky/lifetwin/pull/204), branch
`codex/b-supabase-deploy`. The PR records final checks and the merge commit.

Contracts: existing 28 JSON schemas retained, with an explicit hosted exception:
all three server prediction/compare/sensitivity routes return 501. Flutter uses
its existing on-device model. Shared `BackendHttpClient` attaches only the public
Supabase anon key within the configured HTTPS function URL and refuses redirects.
Provider keys and the service-role key never enter Flutter.

Credentials: imported the supplied local env as data into ignored mode-0600 files
in a mode-0700 directory. Nine settings were provisioned to encrypted Vault storage
via MCP Bridge. Owner-only setter; service-role-only getter/budgets; neither anon
nor authenticated clients have execute permission. Public client defines are in
the local `.env.deploy/flutter.json`; no credential file is committed. Future
key entry and update commands are in [backend credentials](../backend-credentials.md).

Validation observed:

- Full Python suite: 4,322 passed, 5 skipped, 12 expected failures; 28 exported
  schemas and 92 reference API fixtures passed in-process.
- Deno entrypoint type check and 106 tests passed, including deadline cancellation. Integration tests cover all 92 fixture
  statuses/response schemas, with the hosted prediction exception explicit.
- Flutter focused client/consent/document/coach checks: 67 passed; full analysis
  clean in a temporary validation copy. Only that copy's SDK floor was lowered to
  use the installed Dart 3.13.0; repository SDK/lock stayed unchanged.
- Live deployed smoke: 12 checks passed, including a real Cartesia token mint
  with a 300-second TTL, discarded without printing it. Audio playback unverified.
- Live consented Meta extraction from synthetic text returned a grounded pending
  age without changing the confirmed profile. Meta and Anthropic model-list
  access succeeded for the configured models; live Claude Messages unverified.
- Anonymous config getter/setter access denied; unauthenticated function calls
  rejected with 401. Supabase advisories were checked before/after provisioning: no WARN/ERROR
  findings remain. The aggregate private counter intentionally has deny-all RLS
  and no client policies (the remaining informational advisory). Actual daily/
  minute budget enforcement passed a rolled-back database check.

Limitations: bounded Edge port, not complete Python behavior parity. Advanced
transcript parsing, proxy estimates, optional habit probes, completion
recommendations, outside-AI wording, document AI and individualized coach
progression/memory callbacks remain reference-server features. Hosted plans are
reviewed general education. No web-research provider is configured. No new
physical-device or usability acceptance is claimed.

Next dependency: build the app with the public defines file and perform the
owner's device demo. Extend the Edge behavior only behind explicit contracts and
regression tests; do not imply full Python/model parity from schema conformance.
