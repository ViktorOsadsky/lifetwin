# LifeTwin Convex backend (experimental branch only)

A TypeScript port of the non-prediction FastAPI backend in [`server/`](../server/README.md) to [Convex](https://docs.convex.dev) HTTP actions. It lives only on branch `codex/b-convex-backend` and is not a decision to switch. FastAPI is still the backend of record.

The public contract is unchanged: same paths, methods, status codes, `ApiError` envelope, `X-Request-ID`/`Cache-Control: no-store`/`nosniff` headers, and byte-identical JSON bodies, including Python float formatting such as `"height_cm":178.0`. The Flutter app and `contracts/check.py` can use it in place of FastAPI.

## Layout

| Path | Purpose |
| --- | --- |
| `convex/http.ts` | Mounts one dispatcher for every method under `/` |
| `convex/lib/api.ts` | Routing, 404/405/307, body budget, request deadline, error envelope, CORS |
| `convex/lib/models.ts` | Request validation that mirrors the strict Pydantic models and their redacted 422 messages |
| `convex/lib/parsing.ts`, `conversation.ts` | Intake parser, grounding and conversation state machine (main at `6805b96`: includes PR #18 spoken-answer normalization, PR #20 Apple Health `import` and PR #22 import follow-up) |
| `convex/lib/providers.ts` | Chat Completions extractor (`fetch`, bounded body, strict output validation) |
| `convex/lib/advisor.ts`, `quiz.ts`, `voice.ts` | Curated plans with Tavily reviewed-page check, quiz bank delivery, Cartesia token minting |
| `convex/lib/py.ts`, `jsonload.ts` | CPython-compatible whitespace, `\w`/`\d`/`\b`, round-half-even, `repr(float)`, `json.loads` and `json.dumps` |
| `convex/content/questions.json` | Byte-for-byte copy of the server quiz bank (a test fails on drift) |
| `convex/content/openapi.ts` | FastAPI's `/openapi.json`, generated, served verbatim |
| `convex/schema.ts`, `sessions.ts`, `crons.ts` | Opt-in ephemeral session store |
| `parity/generate.py` | Builds the FastAPI reference fixture `tests/fixtures/parity.json` |
| `parity/replay.py`, `parity/e2e_local.py` | Replay the fixture over HTTP; end-to-end checks on a local deployment |
| `tests/` | vitest + convex-test |

Pinned versions: `convex` 1.47.0 (the only runtime dependency), `convex-test` 0.0.63, `vitest` 5.0.5, `@edge-runtime/vm` 5.0.0, `typescript` 5.9.3, `@types/node` 22.18.0 (exact versions in `package.json`, locked in `package-lock.json`).

## Run locally without a Convex account

Anonymous local deployments need no login (Convex CLI "agent mode", beta):

```sh
cd convex
npm ci
CONVEX_AGENT_MODE=anonymous npx convex dev      # or: npm run dev:local
```

The CLI downloads the open-source Convex backend binary, runs it on `127.0.0.1:3210` (client API) and `127.0.0.1:3211` (HTTP actions), and writes the git-ignored `convex/.env.local`. The HTTP API is the **site** URL:

```sh
curl http://127.0.0.1:3211/health
uv run python contracts/check.py --base-url http://127.0.0.1:3211
```

A cloud deployment (`npx convex deploy`) needs a Convex account and a team decision. None was created for this branch.

### Pointing the app at it

The app reads `API_BASE_URL` at build time (`app/lib/voice/http_conversation_guide.dart`, default `http://localhost:8000`):

```sh
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3211          # simulator
flutter run --dart-define=API_BASE_URL=https://<deployment>.convex.site # cloud
```

The local backend listens on loopback only, so a physical phone needs a cloud deployment or a tunnel. This was not exercised with the app.

## Configuration

Set with `npx convex env set NAME value` (local or cloud deployment). Keys live only in Convex environment variables, never in the app or Git. Everything is blank by default, and blank means keyless mode with no network calls.

| Variable | Default | Notes |
| --- | --- | --- |
| `LLM_PROVIDER` | blank (`openai`) | Only `chat_completions` is ported. Blank/`openai` means guided mode, even if `OPENAI_*` are set (see gaps). |
| `LLM_BASE_URL` | `https://api.meta.ai/v1` | Requests go to `{base}/chat/completions` |
| `LLM_MODEL`, `LLM_API_KEY` | blank | Both required |
| `LLM_REASONING_EFFORT` | `minimal` | `minimal`, `low`, `medium`, `high`, or empty to omit. Muse returned no content without it (observed live by the team) |
| `TAVILY_API_KEY` | blank | Used only when a plan request sets `use_web_research: true` |
| `CARTESIA_API_KEY`, `CARTESIA_VOICE_ID` | blank | Both required for `/api/voice/token` |
| `CARTESIA_VERSION`, `CARTESIA_TTS_MODEL`, `CARTESIA_STT_MODEL` | `2026-08-14`, `sonic-3.6`, `ink-2` | |
| `CARTESIA_TTS_SPEED`, `CARTESIA_TOKEN_TTL_SECONDS` | `0.9`, `300` | Bounded 0.6 to 1.5 and 60 to 900 |
| `API_PROVIDER_TIMEOUT_SECONDS`, `API_REQUEST_TIMEOUT_SECONDS`, `API_MAX_BODY_BYTES` | `12`, `25`, `32768` | Same bounds as FastAPI |
| `CORS_ORIGINS` | blank | Exact HTTP(S) origins, canonicalized; Starlette CORS semantics |
| `SESSION_STORE` | blank | `ephemeral` enables the session store below |

FastAPI refuses to start with an invalid value. Convex cannot refuse to deploy, so with an invalid value every business route returns a redacted `500 internal_error`, and the log names only the variable. `/health` and `/ready` keep answering.

## What is stored, for how long, and how it is deleted

**By default, nothing.** Every contract route is stateless. Conversation state stays caller-held exactly as in FastAPI, and `/api/capabilities` still reports `"health_data_storage": "none"`. A full keyless conversation writes no rows (tested).

**With `SESSION_STORE=ephemeral`** (opt-in), one extra route exists: `POST /api/sessions` with `{"action": "create" | "get" | "save" | "delete", "session_id"?, "conversation_state"?, "quiz_progress"?}`. Without the flag that route is a plain 404, like any unknown path.

| | |
| --- | --- |
| Table | `sessions`: `sessionId` (128-bit random, generated server-side), `conversation` (a validated `ConversationState` as JSON, **which can contain health answers**), `quiz` (`game_health` 0 to 100 plus scored question IDs; game state only), `expiresAt` |
| Lifetime | 30 minutes from creation, absolute. Saving never extends it |
| Deletion | A scheduled function deletes the row at `expiresAt`. Reads treat expired rows as gone even before that. A cron sweep every 5 minutes deletes anything past expiry. `{"action": "delete"}` removes it immediately |
| Access | The session ID is a bearer secret. It travels in the JSON body, never in a URL, so it is not in HTTP route logs. Convex clients can subscribe reactively with the public query `sessions:get({sessionId})` |
| Logs | No function logs health values, transcripts, keys or session contents. Errors log only request ID, method, route pattern and exception type. Convex's own logs show the method and path (for example `H(POST /api/onboarding/turn)`), not bodies |
| `capabilities` | Reports `"health_data_storage": "ephemeral_sessions_30_minutes"` while enabled |

Caveat before using real health data: deleting a Convex document removes it from every query at once, but the storage layer may keep earlier document versions for an internal retention window, and backups or snapshot exports would include live rows if someone enabled them. Check Convex's data-retention terms for the chosen plan first. This is why the store is off by default.

Assessment: the reactive database adds little that the current app needs. The app already holds state on the device, and the product rules keep conversation state client-side for the MVP. The store is kept minimal and opt-in so it can be evaluated for "resume after the app is killed" or "second screen follows the conversation", not presented as required.

## Prediction

`/api/predict`, `/api/compare` and `/api/sensitivity` validate their inputs and return the contract's 501 `prediction_not_implemented` body with null fields. When Track A's model exists, it would run as a separate Python inference service called from a Convex action. Convex does not run the Python model.

## Tests and results (October 23, 2026, local Mac)

```sh
cd convex && npm test && npm run typecheck          # vitest + convex-test, tsc
uv run python convex/parity/generate.py             # refresh the FastAPI reference (runs the Python suite)
uv run python convex/parity/replay.py --base-url http://127.0.0.1:3211
uv run python contracts/check.py --base-url http://127.0.0.1:3211
uv run python convex/parity/e2e_local.py            # local deployment only; toggles env vars
uv run pytest -q                                    # server/ unchanged
```

| Check | Result |
| --- | --- |
| vitest (5 files) | **92 passed**. Covers parser parity (normalize/parse_value/parse_reply/clarify/is_skip on 192 texts crossed with 11 fields, 667 grounding cases and 87 read-backs), 266 HTTP cases byte-identical through the Convex router (convex-test) with a fetch double that fails on any network call, named older-adult and PR #18/#20/#22 behaviors, Chat Completions, Tavily and Cartesia success and failure modes against FastAPI references, CORS, configuration errors, the request deadline, the body budget, and session TTL deletion |
| `contracts/check.py --base-url http://127.0.0.1:3211` | **24/24 PASS** against the local Convex deployment |
| `parity/replay.py` against the local deployment | **266/266** HTTP cases identical (status, content type, Allow, Location, body) |
| `parity/e2e_local.py` against the local deployment | **12/12**: real-runtime LLM call to a mock server (consent gate, grounding, `reasoning_effort`, `max_tokens`), the deadline abort after 1 s, session round trip, the reactive query, the deletion job scheduled at `expires_at`, and delete |
| `uv run pytest -q` | **372 passed**, `server/` untouched |
| `npm run typecheck` | clean |

Negative control: changing `max_tokens` or one read-back word makes the provider and parity tests fail.

The fixture covers every HTTP request the Python suite sends through `TestClient` and every parser call it makes, plus crafted edge cases: non-UTF-8 and UTF-16/32 bodies, NaN/Infinity, duplicate keys, deep nesting, wrong content types, `HEAD`/`PUT`/`DELETE`, trailing-slash redirects, lax query integers, `__proto__`. Regenerate it after any change to `server/`.

## Known gaps and behavior differences vs FastAPI

1. **No per-IP rate limit (60/min) and no concurrency limit (16).** Convex HTTP actions do not expose a reliable client IP, and module state is not shared across isolates. A public deployment needs Convex's rate-limiter component (stored keys), an ingress or proxy, or both. The 429 `rate_limit_exceeded` and `server_busy` responses never occur.
2. **The OpenAI Responses adapter (`LLM_PROVIDER=openai` with `OPENAI_API_KEY`/`OPENAI_MODEL`) is not ported.** In that configuration Convex stays in keyless guided mode and reports `llm_configured: false`. That fails safe: no network call, no health text sent. Use `chat_completions`, which also works with `https://api.openai.com/v1`.
3. **`/docs` and `/redoc` (Swagger UI) are 404.** `/openapi.json` is served verbatim.
4. **Request deadline.** A 504 is returned on time, but unlike asyncio cancellation the in-flight handler is not cancelled, and Convex logs an "unawaited operation" warning. Provider calls have their own aborting deadlines, so in practice this only matters if `API_REQUEST_TIMEOUT_SECONDS` is set below the provider timeouts.
5. **Client disconnects** do not cancel work, unlike the FastAPI middleware.
6. **Invalid configuration** gives per-request 500s instead of a failed startup (see Configuration).
7. **Deep JSON nesting threshold** is fixed at 972 levels (400 `request_rejected`), measured under TestClient. CPython's real limit depends on stack depth, so uvicorn may differ by a few levels.
8. **Invalid UTF-8 inside an otherwise UTF-8 body** (for example lone surrogates encoded in UTF-8) is rejected with 400. CPython's `surrogatepass` decoding accepts some of these.
9. **Logs.** FastAPI disables access logs. Convex always records function executions (method and path, no bodies) in the deployment's logs.
10. **Defect copied from FastAPI, not fixed here:** heights that are whole multiples of 10 cm are read back wrongly, for example 170 cm becomes "about 5 feet 7 inches (about 17 cm)". `_plain(cm, 0)` in `server/lifetwin/onboarding/service.py` strips zeros from `"170"`. The port is bug-compatible to keep parity, so fix it in `server/` first, then regenerate the fixture.

## Next steps if the team wants to pursue this

Decide on accounts, hosting, budget and data-retention review (all are team decisions), add a rate limit, run the Flutter app against a deployment, and keep `parity/generate.py` in CI so the two backends cannot drift.
