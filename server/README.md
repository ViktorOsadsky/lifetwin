# LifeTwin backend

This implements the **non-prediction** backend requested after the [master guide](../MASTER_PLAN.md). All credential values in [`.env.example`](../.env.example) remain blank. No API key is needed to start or test it. Death prediction, training, model loading, survival curves, comparison math and sensitivity scanning are intentionally unimplemented; their routes return HTTP 501 with null prediction/model fields, without mock health estimates.

For the audited functionality inventory, verified refinements and specific remaining backend tasks, read [backend status and remaining work](../docs/backend-status.md).

## Run

From the repository root, using Python 3.11 and [uv](https://docs.astral.sh/uv/):

```sh
uv sync --locked --python 3.11
# Optional: copy .env.example to .env; leave provider fields empty for keyless use.
uv run uvicorn lifetwin.app:app --host 127.0.0.1 --port 8000 --no-access-log
```

Open [the API docs](http://127.0.0.1:8000/docs). For a phone on the same trusted local network, bind to `0.0.0.0` and use the Mac's reachable address as Flutter's `API_BASE_URL`; localhost on a phone means the phone itself. Audio recording/playback and the Flutter UI are outside this backend implementation.

## Working routes

| Route | Behavior |
| --- | --- |
| `GET /health` | Lightweight liveness check; remains available while API capacity is occupied. |
| `GET /ready` | Core service readiness; explicitly reports prediction and voice deferred. Does not claim model/provider readiness. |
| `GET /api/capabilities` | Actual keyless/configured feature modes, no credential values. |
| `POST /api/onboarding/turn` | Stateless guided mascot conversation. Typed text and final speech transcripts use identical validation. Optional consent-gated LLM extraction is available through a provider adapter. |
| `POST /api/advisor` | Cited curated educational plan for selected topics. Optional bounded web retrieval; no inferred health improvements or personalized treatment. |
| `GET /api/quiz/questions` | Eight source-reviewed questions plus answers, explanations and local/offline scoring metadata. Optional topic, difficulty and bounded limit filters. |
| `GET /api/quiz/questions/{id}` | One explicit question version; unknown versions return 404. |
| `POST /api/predict`, `/api/compare`, `/api/sensitivity` | Validated request shells only; HTTP 501 `prediction_not_implemented`, null prediction/model version. |

Start a conversation:

```json
{"action":"start"}
```

The response contains caller-held `state`, a caption and mascot events. Send its full state back with `{"action":"reply","state":<returned state>,"text":"I'm 35"}`. Extracted values appear only in `pending_profile`; send `action: "confirm"` with that returned state to accept them. `correct`, `skip`, and `cancel` are explicit actions. A bare weight/height without units triggers clarification; no value is silently committed. Voice capture/transcription/synthesis remain deferred, so `input_mode: "transcript"` means the caller already has a final transcript.

Get a keyless plan:

```json
{"topics":["sleep","nutrition"],"use_web_research":false}
```

Plan topics are `physical_activity`, `sleep`, `nutrition`, `smoking`, and `supplements`, with at most three distinct selections. The profile is optional and does not produce model rankings. All action effects/experiment assumptions are null and explicitly **unmodeled**, which does not mean zero effect. Supplements get a safety-discussion resource, not a product, dose, purchase, or invented survival gain. Retrieved pages cannot rewrite the reviewed plan. Source links/access notes are included.

Quiz answer metadata is intentionally public because scoring runs immediately on the Flutter device. It is not a competitive or secret-answer service. Apply each question/version penalty once, use the supplied recovery/review rules, and keep game health separate from health inputs and forecasts. No quiz submission endpoint mutates a medical profile.

## Optional providers, left blank

- `OPENAI_API_KEY` and `OPENAI_MODEL`: both must be explicitly configured for the HTTPX Responses structured-extraction adapter. Before sending a turn to it, the caller must set `provider_consent: true`; otherwise guided mode continues. No model ID is guessed. Refused, invalid, ambiguous, incomplete and timed-out provider results fall back to clarification/guided mode. See [official Structured Outputs documentation](https://developers.openai.com/api/docs/guides/structured-outputs).
- `TAVILY_API_KEY`: used only when `use_web_research: true`. The adapter sends fixed topic queries, not profiles/transcripts, and retrieves only reviewed authority URLs. At most three searches and five extraction URLs, with request/overall deadlines and bounded response sizes. Blank key returns labeled curated/unconfigured research without a network call.
- `MODEL_ARTIFACT_PATH`: reserved and deliberately unused. Setting it does not enable prediction or load a file.

Live provider access has **not** been exercised; all provider tests use doubles/mock transports. The implemented advisor is curated, not an LLM-personalized planning agent. No audio provider is implemented. These distinctions are returned in API modes/capabilities.

## Limits and privacy

No accounts, database, durable sessions, health-profile store, transcript store or audio store. The caller holds conversation/scenario state. Client-reported state is not an authenticated medical record and must be revalidated at a future inference boundary.

The server bounds request bytes, request time, concurrency and per-IP request frequency. It cancels in-flight async work when a disconnected client is observed, redacts validation/provider exceptions, and returns request IDs plus no-store headers. Liveness/readiness probes bypass workload limits. Limits are **per process**, retain only bounded IP/timestamp buckets for rate limiting, and must be complemented by ingress limits for a public/multi-worker deployment. Proxy/IP trust must match the actual deployment; do not blindly trust forwarded headers.

Access logs are disabled in the run commands/container. Keep ingress/provider logging consistent with this privacy goal. Configure exact browser origins through `CORS_ORIGINS`; invalid ports, controls, userinfo, paths, queries and fragments are rejected, and equivalent origins are canonicalized/deduplicated. No key belongs in the Flutter build or Git. Third-party provider retention/consent must be reviewed before using real health data.

## Verify

```sh
uv run ruff check server contracts
uv run ruff format --check server contracts
uv run pytest -q
uv run python contracts/export.py --check
uv run python contracts/check.py
uv run python contracts/check.py --in-process
# With the server running:
uv run python contracts/check.py --base-url http://127.0.0.1:8000
```

Tests cover confirmation/corrections and ambiguity, keyless zero-network behavior, provider failure/grounding (including deeply nested JSON), citation/topic constraints, source retrieval budgets, quiz validation, request limits, cancellation, redacted errors, OpenAPI error consistency, CORS configuration and empty prediction routes. The replay checker checks 11 actual responses against schemas and semantic assertions. CI tests Python 3.11/3.12/3.13 and builds/smoke-tests the Python 3.11 runtime container; inspect the PR checks for observed results. No medical model or live provider success is claimed.

## Container and next handoff

The root [Dockerfile](../Dockerfile) packages the API and quiz assets with locked production dependencies and a non-root user. Bind address is `0.0.0.0`; port comes from `PORT` (default 8000). `/ready` is the readiness endpoint. Deployment to a paid/cloud service has not been performed by this change.

Next: integrate Flutter with these contracts, choose an actual voice implementation, configure/evaluate any desired provider, and let Track A implement the prediction model later in its own PR. Do not replace the 501 routes with plausible sample mortality numbers.
