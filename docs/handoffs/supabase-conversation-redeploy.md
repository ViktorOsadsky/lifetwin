# Supabase conversation redeployment handoff

Track B, [#231](https://github.com/ViktorOsadsky/lifetwin/issues/231), October 25, 2026.

## Result and merge state

The final hosted `lifetwin-api` is **v7, ACTIVE, JWT verification enabled** in
LifeTwin project `plpywefoeepfunptjujc`. Base URL:
`https://plpywefoeepfunptjujc.supabase.co/functions/v1/lifetwin-api`.

- Configuration [#232](https://github.com/ViktorOsadsky/lifetwin/pull/232) merged as
  `28186d295b843f44c97b14cfef1794c082c7abfc`.
- Reviewed intent port [#233](https://github.com/ViktorOsadsky/lifetwin/pull/233)
  merged as `45e89e0f991574a7aee99a4e8f3d4135d7986d61`, then deployed through the
  existing scoped MCP Bridge shared session. Supabase reports bundle SHA-256
  `e4212ad61e9726aa70834be406f31cfb003f4ac4dcdc8eebb64f749df27ca81a`.

## Behavior and boundaries

Claude Haiku 5.5 is explicitly selected for conversations and PDFs. Muse remains
the Ideas/coach/recommendations personalizer. Existing keys were preserved and
remain server-side. Ignored private deployment files retain these provider choices
for future updates. The setter-only migration `20261025113550` was applied through
MCP Bridge; the redundant unapplied migration from the port was removed. The
23-setting runtime, helper and database allowlists agree; invalid conversation
providers are rejected. Anon, authenticated and service-role setter access is
denied. No health-data storage, model or app contract changes were introduced.

The Edge uses the exported Python intent lexicon/questions/prompt and the existing
`yes_no_checked` state field. Memory and other consent questions never go to
Claude. A model interpretation of other ambiguous replies requires both provider
consent and Claude-specific consent; a local no cannot become a model yes.
Spoken durations/frequencies use the merged quantity reader. Proposed health
values stay pending until confirmed.

Review added bounded unclear read-backs and a guard against saving an old answer
when unexplained words may be a correction. A second unclear read-back discards
the Edge's unsaved pending answer and asks for the right one; confirmed values do
not change. This intentionally differs from the reference server retaining its
pending draft. Existing pounds-rounding replay differences remain out of scope.

## Observed validation

- All checks on the final #233 head passed: Edge/content, Python 3.11/3.12/3.13,
  runtime-container HTTP checks and secret scanning.
- Integrated local validation: **134 Deno tests**, including all 187 intent rows
  through local and stubbed-Claude paths; **406 focused Python tests**; Deno
  format/type checks, Ruff, and all four source-export checks.
- Final v7 live smoke: **12 checks**, including a real Cartesia token mint with the
  token discarded. Capabilities report Claude conversations/PDFs and Muse
  personalization.
- Live synthetic regressions passed: the owner's exact memory phrase with and
  without Claude consent; refusal; one-check memory and read-back fallbacks;
  loose confirmation; numeric/word corrections; six spoken-math/wrong-unit cases.
  Unconfirmed values never entered confirmed inputs.
- A real Claude turn identified background speech only after consent and left
  confirmed inputs unchanged. Without consent the provider was not used.
- Invalid provider configuration was rejected in a rolled-back database check.
  Post-deployment security/performance advisories had no WARN/ERROR findings.

## Limits and next dependency

The v7 function's source-download read closed the Bridge shared IPC connection.
A direct read could not resolve the app-held Keychain credential; no credential
was extracted or copied as a workaround. Thus the reported bundle digest and
authoritative active-version/JWT metadata are recorded above, while a downloaded
source hash comparison is **unverified**. Deploy acceptance and the live behavior
checks succeeded; no uncertain deployment was retried.

This is not full FastAPI parity. Server prediction/compare/sensitivity remain
explicit 501s; Flutter keeps its existing on-device model. No physical-phone,
real microphone/audio playback, real-person data or fresh PDF-provider acceptance
is claimed by these synthetic checks. Relaunch the app to refresh cached provider
capabilities before testing the Claude consent UI. Flutter web feasibility is a
separate investigation; no hosting origin or production CORS change was made.
