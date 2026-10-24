# Backend functionality and remaining work

Audit date: **October 23, 2026, Pacific time**. Baseline: `a8e5013` (the merged backend foundation). This report covers the existing Python backend, its contracts, reliability, packaging and verification. Frontend development and ML training/implementation are excluded. Credentials remain blank; no real provider requests or paid deployment were performed.

**Assessment:** a working, tested backend foundation for guided intake, curated educational plans and quiz content. It is not yet the complete conversational health-planning agent. Providing API keys alone will not turn the current curated advisor into a personalized LLM planner or make research discover arbitrary new evidence/products.

## Implemented functionality

| Capability | What actually works | Limits / relevant code |
| --- | --- | --- |
| API/service startup | FastAPI app, OpenAPI docs, health/readiness, capabilities and startup validation of bundled quiz content | Readiness covers this service, not external-provider health. [App](../server/lifetwin/app.py) |
| Mascot intake | Stateless `start`, `reply`, `confirm`, `correct`, `skip`, `cancel`; captions/events; caller-held conversation state | Questions and transition logic are deterministic. No free-form advisor chat. [Service](../server/lifetwin/onboarding/service.py) |
| Health-input parsing | Eleven optional fields; explicit units/categories; supported metric/imperial conversions; several explicitly labeled answers per reply | Conservative grammar rejects ambiguous, hypothetical, historical, conflicting or unparseable statements instead of guessing. Not all natural speech or spelled-out numbers are understood. [Parser](../server/lifetwin/onboarding/parsing.py) |
| Confirmation/correction | New values stay in `pending_profile`; confirmation updates `confirmed_profile`; corrections preserve unrelated pending values; cancellation clears returned state | The server does not authenticate or persist caller-supplied state. It is not an authoritative health record. |
| Optional LLM extraction | Consent-gated OpenAI Responses adapter identifies exact evidence spans; local parsing checks full context before proposing values | Requires explicit key **and** model ID. It extracts candidate fields; it does not generate the whole conversation or personalized plans. [Adapter](../server/lifetwin/onboarding/providers.py) |
| Text/transcript parity | Typed replies and already-transcribed final speech use the same endpoint and confirmation rules | No audio upload, microphone capture, STT, TTS, streaming audio, or speech playback implementation. |
| Educational advisor | One to three selected topics produce cited, curated next steps for activity, sleep, nutrition, smoking or supplement safety | Topic order is preserved; actions are not benefit-ranked. Optional profile only adds an age-related limitation where relevant. There is no `question` field/chat response or personalized treatment. [Advisor](../server/lifetwin/advisor/service.py) |
| Research adapter | Opt-in Tavily search/extract uses fixed topic queries and exact pre-reviewed authority URLs, with deadlines, caps, URL checks and explicit partial/unavailable states | This checks retrieval/availability. Fetched text is discarded; it cannot rewrite plans or establish new clinical claims. Profile/transcript data is not placed in queries. [Research](../server/lifetwin/research/tavily.py) |
| Evidence/citations | Curated publisher/title/URL/review-date records and action-to-source IDs; referenced action sources must exist | This is a local source review, not clinical certification. There is no automated claim-level evidence assessment or freshness-maintenance system. |
| Quiz content | Eight reviewed CDC/FDA questions with versioned IDs, options, answer, explanation, sources, difficulty and recovery effects; filtering and detail lookup | Answers are deliberately public for local/offline scoring. No server-side scoring/session mutation or competitive anti-cheat is intended. [Quiz](../server/lifetwin/quiz/router.py) |
| Game-state separation | Quiz contracts specify bounded game-health effects, once-per-version scoring, recovery/review rules and no impact on clinical state | The backend delivers rules/content; it does not change a health profile when a quiz answer is wrong. |
| Deferred features | Existing reserved routes return HTTP 501 with null result/model fields | Kept empty as instructed. They were not implemented during this audit. |

Raw intake fields: `age`, `sex`, `height_cm`, `weight_kg`, `sleep_hours`, `exercise_minutes_weekly`, `smoking_status`, `alcohol_drinks_weekly`, `diabetes`, `systolic_bp`, `diastolic_bp`. Ranges in [the input model](../server/lifetwin/core/models.py) are format/data-admission limits, not clinical validation. All fields can remain unknown/skipped.

Every plan action has `modeled_effect_status: "unmodeled"`, `modeled_effect: null` and `experiment_assumptions: null`. Unmodeled means **unknown**, not zero. Completing an action does not assert a physiological change. The supplement topic supplies general safety-discussion guidance; it does not select a product or dose.

## Endpoint inventory

| Method / path | Behavior |
| --- | --- |
| `GET /health` | 200 liveness; exempt from workload limits |
| `GET /ready` | 200 service readiness; explicitly labels unavailable/deferred capabilities |
| `GET /api/capabilities` | Keyless/configured flags and storage/mode labels, never credential values |
| `POST /api/onboarding/turn` | 200 conversation result; 409 invalid transition; 422 invalid fields |
| `POST /api/advisor` | 200 curated educational plan, including labeled unconfigured/unavailable research where appropriate |
| `GET /api/quiz/questions` | 200 bank/filter results; `limit` is 1–20; `total` counts all matches before limit |
| `GET /api/quiz/questions/{question_id}` | 200 explicit question version; 404 unknown version; 422 malformed ID |
| Reserved `POST /api/predict`, `/api/compare`, `/api/sensitivity` | 501 empty/deferred response, unchanged |

Business API error bodies use [ApiError](../contracts/error.schema.json), with a server-generated request ID and no raw submitted values. Validation errors are now described with that same schema in OpenAPI. HTTP exception headers such as `Allow` are preserved. CORS preflight and framework redirect responses follow their middleware/protocol behavior, rather than the business JSON body contract.

## Reliability and privacy

- Default request budget: 32 KiB body, 25-second overall deadline, 16 concurrent requests and 60 requests/IP/minute. Limits are configurable within server-defined bounds. `/health` and `/ready` remain available during saturation.
- Actual body chunks are counted; a false `Content-Length` does not bypass the limit. Work is cancelled on observed client disconnect, timeout or task cancellation; capacity is released afterward.
- Rate buckets store only bounded IP/timestamp data. Limits are per process, not a distributed/global quota system.
- Provider calls have bounded response sizes and deadlines. Both adapters handle malformed/deeply nested JSON and HTTP failures without leaking provider data. Owned provider clients disable environment proxy configuration and redirects.
- LLM extraction requires explicit per-turn consent; deterministic parsing can succeed without contacting it. Requests use structured output and `store: false`; this is not a claim of zero provider retention under every account policy. Provider policy/account review remains necessary before real health-data use. [Official API guidance](https://developers.openai.com/api/docs/guides/structured-outputs).
- No accounts, durable sessions, database, profile/transcript/audio persistence or health analytics. Access logs are disabled in the supplied run commands and container. These are deliberate MVP choices, not forgotten storage features.
- CORS accepts explicit HTTP(S) origins only. Invalid ports, controls, userinfo, paths, queries/fragments are rejected; case, IDNs and default ports are normalized and duplicates removed.

## Refinements completed in this audit

| Reproduced issue / verification gap | Resolution |
| --- | --- |
| OpenAPI advertised `HTTPValidationError`, while actual 422 bodies were redacted `ApiError` objects | Declared the real error response models; regression validates actual 422/409 bodies against the published OpenAPI schema |
| Custom error handler dropped the `Allow` header on 405 responses | Preserved HTTP exception headers; regression verifies `Allow: POST` |
| Nonnumeric/out-of-range CORS ports and empty query/fragment components were accepted | Strict validation plus canonicalization; regressions cover ports, controls, userinfo, paths, IDNs, IPv6 and duplicates |
| Deep JSON under the byte cap raised unhandled `RecursionError` in both provider adapters | Converted it into the existing unavailable/guided-fallback paths; regression tests use mock transports |
| OpenAI's owned HTTP client implicitly trusted environment proxies, unlike the research client | Disabled proxy-environment use and verified client closure on failure |
| Provider byte buffers grew before testing their cap | Check the next chunk size before copying it into the buffer |
| Offline contract checker printed `PASS` for cases with no response fixture | Distinguishes request-only validation, static-response validation and cases requiring replay; reports exact response-check count |
| A schema-validation traceback could print an invalid API response's complete contents | Replay failures now identify the case/schema without echoing response values; regression uses a private-text sentinel |
| CI did not replay actual API contracts or build the deployment image | Added in-process replay, positive/error semantic assertions, a supported-Python test matrix, and container build/HTTP replay in CI |
| The first container smoke probe could race startup and receive a connection reset | Added bounded readiness retries for transient connection failures before replay; persistent failures still fail CI with container logs and cleanup |

The raw API-key/model configuration in [`.env.example`](../.env.example) remains empty. No frontend or ML implementation was changed.

## Verification evidence and limits

| Check | Observed result / scope |
| --- | --- |
| Baseline local suite | 154 tests passed before changes |
| Refined local suite | **175 tests passed** on Python 3.11; includes provider fallback, protocol/OpenAPI, CORS and contract-CLI regressions |
| Contract schemas | 13 generated schemas; drift and structural checks |
| Offline fixtures | Six valid request fixtures and one static response; other response cases are explicitly not claimed as verified offline |
| In-process replay | **11 actual responses** checked against schemas, HTTP status and selected behavioral assertions; covers success, deferred routes, invalid transitions/inputs and missing content |
| Packaging/runtime | CI now builds the non-root Python 3.11 container and replays all 11 cases over its HTTP socket. The audit PR's checks are the authoritative run results; Docker is unavailable on the local Mac |
| Runtime compatibility | CI matrix covers the declared Python 3.11, 3.12 and 3.13 range; local verification uses 3.11. Inspect PR checks for each runner's result |
| Providers | Mock transports/doubles only; no real credentials, account access, retention policy, cost, model quality or provider latency verified |
| Cloud hosting | No deployed HTTPS endpoint, ingress configuration, production load test or monitoring installation verified |

One installed Starlette/TestClient deprecation warning remains; it does not fail the suite. It should be addressed through a tested dependency/client compatibility update, not by hiding warnings.

Reproduce from the root with the dependencies installed:

```sh
uv run ruff check server contracts
uv run ruff format --check server contracts
uv run pytest -q
uv run python contracts/export.py --check
uv run python contracts/check.py
uv run python contracts/check.py --in-process
# Against a running keyless API/container:
uv run python contracts/check.py --base-url http://127.0.0.1:8000
```

## Specific remaining backend work

These are product/integration tasks, not claims of defects in the current keyless behavior. Track B owns API/infrastructure boundaries; Track D owns conversation/advisor/research/content behavior. Human owners for B/D remain unassigned in [the splitting document](team-plan.md).

| Priority / task | Specifically missing | Completion evidence |
| --- | --- | --- |
| P1 — Real provider qualification (B/D) | Choose an account-available LLM model, configure credentials outside Git, review provider consent/retention, and evaluate authorized live extraction/research. Current `configured` flags mean configuration exists, not that an account/provider works | Live happy-path/refusal/quota/timeout tests with synthetic inputs, measured latency/cost, and published provider-mode/limit documentation; keys stay out of source/logs |
| P1 — Backend voice integration (B/D) | Select STT/TTS provider and turn-based versus streaming transport; define audio/session schemas, format/size limits, consent, cancellation/interruption and text fallback. A final transcript is all the present API accepts | Contracted server audio flow tested with provider doubles, plus separately authorized live synthetic-audio verification; no default raw-audio persistence |
| P1 — Conversational guide and advisor beyond extraction (D/B) | Adaptive LLM questions, supported user-question input, preferences/goals context and grounded plan generation. Current questions and plan text are fixed; the optional LLM only extracts spans | Versioned request/response contracts; source-bound answers; ambiguity/refusal/citation tests; deterministic fallback; no invented clinical claims |
| P1 — Evidence discovery and claim-level provenance (D/B) | Search beyond the fixed reviewed URL set, extract the actual facts used, retain fetched-at time/content digest/extraction method/applicability, validate citations and communicate stale/contradictory evidence. Current retrieval only reports source availability | Bounded retrieval with safe URL/redirect handling, provenance tied to each generated claim, missing/stale/conflicting-source tests, and no profile data in search queries |
| P1 — Public backend deployment and budgets (B) | Choose hosting/access/budget; configure HTTPS, ingress/proxy trust, exact origins and abuse/cost controls across workers/instances. Container CI is not a cloud deployment | Reachable staging service, configured ingress/session-level budget enforcement as needed, saturation/restart/outage tests and documented rollback. Accounts are not required merely to satisfy this task |
| P2 — Operational visibility (B) | Structured redacted latency/error/provider-availability metrics, quota/cost monitoring and actionable alerts. Existing request IDs and suppressed access logs do not provide a monitoring system | Evidence that synthetic failures/slowdowns are visible while health data, transcripts and keys are absent from logs/metrics |
| P2 — Plan lifecycle and non-clinical progression (D/B) | Decide/version any server contract for plan selection, dismissal, check-ins and user preferences. Current plans are returned per request, without progress management | Idempotent state transitions only if server-managed state is chosen; explicit ownership/retention/delete rules. Otherwise document caller-owned state and avoid adding a database just for completeness |
| P2 — Optional supplement/product research (D) | Actual product discovery, current availability/price timestamps and separating seller claims from efficacy evidence. Current supplement support is safety guidance only | Cited products with evidence/applicability limits and uncertainty; no dosing, automatic purchases or unsupported quantified health benefits |
| P2 — Content and contract maintenance (D/B) | Expand/review quiz content if desired, track source staleness/link changes, and formalize service-metadata response schemas if external consumers need them. Existing quiz content and business schemas work | Reviewed versioned content with provenance; source-change checks; backward-compatible contracts and replay coverage |
| P3 — Dependency compatibility cleanup (B) | Resolve the upstream TestClient warning while retaining the locked, tested runtime range | Clean tested client/dependency update across the supported Python matrix; no suppressed warnings or unverified mass upgrade |

No backend database, account system, purchase flow or durable job queue is required by the current bounded, keyless MVP. Add one only when an approved product/latency requirement makes its ownership and lifecycle necessary. Excluded frontend and ML work remains outside this report's implementation queue.
