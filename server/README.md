# LifeTwin backend

This implements the backend requested after the [master guide](../MASTER_PLAN.md). All credential values in [`.env.example`](../.env.example) remain blank. No API key is needed to start or test it. `POST /api/predict` serves Track A's trained survival model (see Survival forecast below). Training, comparison math and sensitivity scanning are intentionally unimplemented; those routes return HTTP 501 with null prediction/model fields, without mock health estimates.

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
| `GET /ready` | Core service readiness; reports `prediction: available` when the model files loaded (else `not_implemented`) and voice deferred. Does not claim provider readiness. |
| `GET /api/capabilities` | Actual keyless/configured feature modes, no credential values. |
| `POST /api/onboarding/turn` | Stateless guided mascot conversation (v2: see below). Typed text and final speech transcripts use identical validation. Optional consent-gated LLM extraction is available through a provider adapter. |
| `POST /api/recommendations` | Two or three personal suggestions from the confirmed profile and habit notes, ordered by the model's lever ranking and grounded in the package's wellness cards (CDC sources). Stateless; deterministic templates unless the person opted in to outside-AI wording. |
| `POST /api/checkin/start`, `/api/checkin/turn` | Not yet used by the app. History lives on the phone; weekly answers come back as `profile_update` for the app to apply to the profile and forecast, daily answers are history only. An emergency reply pauses the conversation (`emergency: true`, `concerned` mascot event; also in onboarding). Mochi's daily (sleep last night, movement today, how you feel; drinks yesterday on Tuesdays and Saturdays) and weekly (every model input that changes week to week, then how the week went) check-ins. Same read-back, follow-up, chatter and control rules as onboarding; "same as last week" offers the caller-sent previous answer for a yes. Stateless: nothing is stored and no health value is logged. Scripts live in `lifetwin/checkin/scripts.py`. |
| `POST /api/coach/plan` | Not yet used by the app. Mochi's daily plan (2-4 cited items: workout, food pattern, habit, encouragement) chosen deterministically from `lifetwin/coach/catalog.py`, with per-item `changes`, a replayable `trace`, an input snapshot id and a twin `mood`. Stateless: the phone sends the previous plan and feedback back each time; stale or altered revisions get 409. Red flags pause movement; the emergency line is shared with onboarding; supplements get one fixed pharmacist reply. With `outside_ai_consent.muse`, Muse (`LLM_*` settings) may reword item messages only, behind a strict check, `COACH_LLM_DAILY_CAP` (30 per client per day) and `COACH_LLM_TIMEOUT_SECONDS` (10). |
| `POST /api/documents/extract` | Recognised text of a health document (the phone does the OCR; never the image) in, candidate values to confirm out: height, weight, smoking, explicit diabetes/hypertension diagnoses, and blood pressure/A1c/LDL as information. Identifiers are stripped first; nothing is stored or logged. Muse by Meta helps only with `DOCUMENT_MUSE_ENABLED=true` and the person's consent. See [document-upload.md](../docs/document-upload.md). |
| `POST /api/change/start`, `/api/change/turn` | Change a saved answer by talking it through with Mochi; there are no edit fields. Mochi says the current value, asks what changed, reads the new value back and returns it as `profile_update` (the check-in shape) only after a yes. Big jumps are double-checked; age moves only by a birthday; sex at birth never changes once saved; diabetes changes only after asking whether a doctor said so. One probe and a `habit_note` only with `memory_consent`. Stateless: the caller sends the profile each turn; nothing is stored or logged. The only way saved answers change apart from onboarding, check-ins, Apple Health import with read-back and Delete my data; experiment levers never call it. Words live in `lifetwin/change/scripts.py`. |
| `POST /api/voice/token` | Consent-gated short-lived Cartesia token plus STT/TTS settings; 503 `voice_unavailable` when not configured. See Voice (Cartesia). |
| `POST /api/advisor` | Cited curated educational plan for selected topics. Optional bounded web retrieval; no inferred health improvements or personalized treatment. |
| `GET /api/quiz/questions` | 38 source-reviewed questions across nutrition, food safety, movement, sleep and everyday habits plus answers, explanations and local/offline scoring metadata. Optional topic, difficulty and bounded limit filters. |
| `GET /api/quiz/questions/{id}` | One explicit question version; unknown versions return 404. |
| `POST /api/predict` | Survival at 1/3/5 years and a curve to 5 years from the trained model, or `unsupported` with a plain reason. HTTP 501 only when the model files are missing. |
| `POST /api/compare`, `/api/sensitivity` | Validated request shells only; HTTP 501 `prediction_not_implemented`, null prediction/model version. |

Start a conversation:

```json
{"action":"start"}
```

The response contains caller-held `state`, a caption and mascot events. Send its full state back with `{"action":"reply","state":<returned state>,"text":"I'm 35"}`. Extracted values appear only in `pending_profile`; send `action: "confirm"` with that returned state to accept them. `correct`, `skip`, and `cancel` are explicit actions. A bare weight/height without units triggers clarification; no value is silently committed. Voice capture/transcription/synthesis remain deferred, so `input_mode: "transcript"` means the caller already has a final transcript.

Replies about the conversation itself are recognized before any value is read (`lifetwin/onboarding/intents.py`): repeat ("what?", "pardon"), slower/louder (the prompt is repeated and `speech_hint` is `"slower"` or `"louder"`; otherwise `null`), help, "why do you need this"/"is this private", go back or "change my age" (the question reopens; the saved answer stays until a new one is confirmed, and "keep it" or "skip" keeps it), and start over (the answers are cleared only by an explicit phrase in the same turn, such as "yes, start over"; a plain "start over" asks first and repeats the current question or read-back, so a bare "yes" afterwards answers that, never the reset). In the done phase, replies such as "thank you", "ok" or "what now?" get a kind reply and the conversation stays ready. Questions back such as "is 72 old?" are never read as answers. A read-back is confirmed only by an unmistakable yes; "no, 47" replaces only the value being read back, and "I guess" is asked about again. Fillers, stutters and transcript punctuation are removed first. The behavior is pinned by `tests/data/conversation_dialogues.json`.

### Onboarding conversation v2

Mochi's words live in one place, `lifetwin/onboarding/script.py` (`SCRIPT`, `ORDER`, the phrase banks); the habit follow-ups in `probes.py`; habit notes in `habits.py`; the model-input mapping and twin hints in `model_inputs.py`.

- **Order.** First Mochi asks whether it may remember the little things (`state.memory_consent`). Then age, sex at birth and smoking; then Apple Health is offered (`phase: "offering"`; a yes returns `client_action: "open_health_import"`, and the app answers with action `import`, or `skip` if nothing was used); then only what is still missing: height, weight, sleep, general health, a doctor's diagnosis of high blood pressure, diabetes, sitting time, lighter and harder activity. Alcohol and blood pressure readings are no longer asked. With Apple Health's weekly exercise total, only the harder part is asked and the rest is read back as lighter activity.
- **Steering.** A topic the person brings up beside an answer ("I'm 72 and I walk my dog") is asked next, with their own words as the bridge ("You mentioned you walk your dog every morning."). "Can we talk about my sleep?" opens that topic; "go back" still works. One turn of small talk gets a kind reply, then Mochi steers back. Wording varies by a per-session `state.seed` (0 is the canonical wording); question numbers are never spoken.
- **"I don't know".** Many phrasings ("no idea", "I'd have to check", "my doctor would know", "pass") record the field in `state.unknown_fields`, distinct from `skipped_fields` and from a value, and it is never asked again in the session. Sleep, general health, sitting and activity get one simpler question first (`state.proxy_field`); an answer to it is read back as a rough estimate and, once confirmed, listed in `estimated_fields` and in a habit note (`estimate_for`, `estimate`). A blood pressure reading is kept as context (`habit_notes[].reading`), never as a diagnosis; the diagnosis question is asked once more, then left unknown.
- **Habit follow-ups.** At most three per onboarding, chosen by the lever they help (`probes.py`), always skippable ("let's move on"), never with `memory_consent: false`. Answers become `state.habit_notes` (short words from the reply; `source: "said"`).
- **Model inputs.** Every turn returns `model_inputs`: the on-device package's `profile` map built from confirmed answers only, with its exact codes (sex 1/2, smoking 0/1/2, general health 1-5, minutes), and the package's input ids that are `missing`, `unknown`, `skipped` or `estimated`. Nothing is filled in. `status` is `ready` only when all eleven inputs are known and age is 35-79; otherwise it is `still_learning` (or `unsupported_age`), and the model gives no number: the app shows "still learning".
- **Twin hints.** `character_hints.mood` is `good`, `okay` or `not_great` (the check-in wellbeing scale), from a feeling in the person's words, else the health rating (excellent/very good/good → good, fair → okay, poor → not_great). `energy` is `high` (150+ moderate-equivalent activity minutes a week, vigorous counted double), `medium` (30-149) or `low` (under 30), one step lower with under 6 hours of sleep; with sleep only, 6+ hours is `medium`. Both are null until there is something to go on.
- **Suggestions.** The turn that completes the intake returns `recommendations` (the same as `POST /api/recommendations`) and speaks the first one. Order: quitting for current smokers; activity ("none versus any": a 10-15 minute start for people doing none, a faster pace for walkers without pain or a fear of falling, encouragement at 150+); more sleep only under 7 hours; sitting less. Never weight, years, dates, percentages or supplements. Asked about a supplement, Mochi always gives one fixed reply (ask your pharmacist or doctor, bring the bottles).
- **Check-ins**, lightly: "I don't know" is recorded in `unknown_fields`; with `memory_consent` (sent by the app at start) one optional follow-up ("What did you do?", "Did anything keep you up?") adds a habit note.

### Outside-AI wording (opt-in, off by default)

With the person's consent for the active provider (`outside_ai_consent: {"muse": true}` on a turn or a recommendations request), that provider may phrase Mochi's next question and draft the suggestions from the given facts and the person's own words. It never reads or decides values; read-backs are never rephrased. Every line is checked (no years, dates, diagnoses, medicines, doses, supplements, promises, percentages, links, weight, or numbers that are not in the facts) and replaced by the template if it fails; `phrased_by` says which was used. `PERSONALIZE_PROVIDER=muse` (default) reuses `LLM_API_KEY`/`LLM_MODEL`/`LLM_BASE_URL`; `claude` is a placeholder that reports unconfigured until it is built. `/api/capabilities` returns `personalize: {provider, display_name, company, configured}`; the app's consent text must use `display_name` ("Muse by Meta"), and consent for one provider never covers another. The payload holds answers and habit notes, never a name or contact details, and is never logged.

Get a keyless plan:

```json
{"topics":["sleep","nutrition"],"use_web_research":false}
```

Plan topics are `physical_activity`, `sleep`, `nutrition`, `smoking`, and `supplements`, with at most three distinct selections. The profile is optional and does not produce model rankings. All action effects/experiment assumptions are null and explicitly **unmodeled**, which does not mean zero effect. Supplements get a safety-discussion resource, not a product, dose, purchase, or invented survival gain. Retrieved pages cannot rewrite the reviewed plan. Source links/access notes are included.

Quiz answer metadata is intentionally public because scoring runs immediately on the Flutter device. It is not a competitive or secret-answer service. Apply each question/version penalty once, use the supplied recovery/review rules, and keep game health separate from health inputs and forecasts. No quiz submission endpoint mutates a medical profile.

## Optional providers, left blank

- `OPENAI_API_KEY` and `OPENAI_MODEL`: both must be explicitly configured for the HTTPX Responses structured-extraction adapter. Before sending a turn to it, the caller must set `provider_consent: true`; otherwise guided mode continues. No model ID is guessed. Refused, invalid, ambiguous, incomplete and timed-out provider results fall back to clarification/guided mode. See [official Structured Outputs documentation](https://developers.openai.com/api/docs/guides/structured-outputs).
- `TAVILY_API_KEY`: used only when `use_web_research: true`. The adapter sends fixed topic queries, not profiles/transcripts, and retrieves only reviewed authority URLs. At most three searches and five extraction URLs, with request/overall deadlines and bounded response sizes. Blank key returns labeled curated/unconfigured research without a network call.
- `MODEL_ARTIFACT_PATH`: folder with the survival model files; blank means the repository root. Missing files keep `/api/predict` at 501.
- `PERSONALIZE_PROVIDER`: `claude` or `muse`. Blank picks `claude` when `ANTHROPIC_API_KEY` is set (owner ruling 2026-10-24: switch to Claude Haiku), else `muse`. Outside-AI wording is used only on turns that carry the person's consent for that provider (`outside_ai_consent: {"claude": true}`; a Muse consent never carries over). The check-in care reply may be reworded the same way (`outside_ai_consent` on `/api/checkin/turn`), and the safety sentence must survive or the template stands.
- `ANTHROPIC_API_KEY`, `CLAUDE_MODEL` (default `claude-haiku-5-5`): Claude by Anthropic through the official `anthropic` SDK (`lifetwin/core/claude.py`). Structured outputs (JSON schema), thinking off at effort `low`, short `max_tokens`, a cached system prompt, one attempt within 6 s. A refusal, a cut-off reply, any API error or a timeout falls back silently to the templates or the local parser; only the error type is logged. `LLM_ALLOW_CONTRIBUTOR` does not apply to Claude.
- `ONBOARDING_DEMO`: `1` shortens the onboarding demo to one habit follow-up. The memory question, the Apple Health offer after age, sex and smoking, and the question order are unchanged. Default off. Estimated spoken time of the demo path with Apple Health: about 138 s (150 s with three follow-ups); most of the rest is the read-backs and the opening and closing lines.

Live provider access has **not** been exercised; all provider tests use doubles/mock transports. The implemented advisor is curated, not an LLM-personalized planning agent. Cartesia voice is implemented as token minting only. These distinctions are returned in API modes/capabilities.

## Voice (Cartesia)

The phone talks to Cartesia directly for Ink speech-to-text and Sonic text-to-speech, using a short-lived access token minted by this server. The `sk_car_` API key never leaves the server and no audio passes through it.

| Variable | Default | Notes |
| --- | --- | --- |
| `CARTESIA_API_KEY` | blank | Server-side secret. Blank means voice is unavailable. |
| `CARTESIA_VOICE_ID` | blank | Required with the key; blank means voice is unavailable. |
| `CARTESIA_VERSION` | `2026-08-14` | Sent as the `Cartesia-Version` header. |
| `CARTESIA_TTS_MODEL` | `sonic-3.6` | Returned to the app. |
| `CARTESIA_STT_MODEL` | `ink-2` | Returned to the app. |
| `CARTESIA_TTS_SPEED` | `0.9` | Bounded 0.6 to 1.5. |
| `CARTESIA_TOKEN_TTL_SECONDS` | `300` | Bounded 60 to 900. |

`POST /api/voice/token` with `{"voice_consent": true}` returns `schema_version`, `token`, `expires_in`, `cartesia_version`, and the `stt` and `tts` connection settings (model, `pcm_s16le` encoding, sample rate, websocket URL; TTS also voice ID, speed and `calm` emotion). A missing or false consent is a 422 ("Please agree to use your voice first."). Missing configuration, or any Cartesia error or timeout, is a 503 `voice_unavailable` ("Voice isn't available right now. You can keep going by typing.") with no upstream text, key or token in the body or logs. Responses are `Cache-Control: no-store` and go through the normal request budget. `GET /api/capabilities` reports `voice` as `available` only when both the key and voice ID are set, otherwise `unavailable`.

Privacy: audio and transcripts go to Cartesia only after the user consents, and only while they use tap-to-talk. This server does not receive or store audio. Typed input remains a complete alternative.

The live Cartesia path is **untested without a key**. Tests mock the HTTP transport and check the exact request sent to `https://api.cartesia.ai/access-token`; the websocket STT/TTS protocol is the client's responsibility and is not exercised here.

## Conversation guide LLM

Select the extraction provider with environment variables (all blank by default; blank means keyless guided mode, with no network calls):

| Variable | Meaning |
| --- | --- |
| `LLM_PROVIDER` | `anthropic` (Claude; `ANTHROPIC_API_KEY`/`CLAUDE_MODEL`), `chat_completions` (Muse), or `openai` (uses `OPENAI_API_KEY`/`OPENAI_MODEL` exactly as before). Blank: `anthropic` when `ANTHROPIC_API_KEY` is set, else `openai`. |
| `LLM_BASE_URL` | Chat Completions base URL; defaults to `https://api.meta.ai/v1` when `chat_completions`. Requests go to `{base}/chat/completions`. |
| `LLM_MODEL` | Model ID, required. |
| `LLM_ALLOW_CONTRIBUTOR` | `false` (default). A `-contributor` model ID (e.g. `muse-spark-1.3-contributor`, cheaper; Meta may train on content) is refused unless this is `true`. `/api/capabilities` then reports `may_train_on_content: true` in `personalize` and `coach.personalize`; the app's consent screens must disclose it. |
| `LLM_API_KEY` | Bearer key, required; kept server-side and never logged or returned. |
| `LLM_REASONING_EFFORT` | `minimal` (default), `low`, `medium`, `high`, or blank to omit. Reasoning models such as Muse otherwise spend the whole token budget thinking and return no answer (observed live). |
| `DOCUMENT_MUSE_ENABLED` | `true` (default, owner ruling). With `chat_completions` or `anthropic` configured, that provider may read identifier-stripped document text (the words only, never the photo), only for requests whose `outside_ai_consent` names it: `{"claude": true}` or `{"muse": true}`. A bare `true` (older app, asked naming Muse) covers Muse only. Set `false` to disable. |

Muse example (supply your own key):

```sh
LLM_PROVIDER=chat_completions
LLM_BASE_URL=https://api.meta.ai/v1
LLM_MODEL=muse-spark-1.3
LLM_API_KEY=...
```

`ChatCompletionsExtractor` sends a system instruction plus the user's reply with `response_format` `json_schema` ([Meta structured output docs](https://dev.meta.ai/docs/structured-output)), then validates the reply strictly against `ExtractionResult` and applies the same grounding rules (exact quote, asked field) as every provider. HTTP errors, timeouts, non-JSON, refusals, truncated or schema-invalid output all fall back to guided clarification with no value filled. `/api/capabilities` `llm_configured` reflects the selected provider. Claude can be added later through its own adapter or an OpenAI-compatible endpoint by changing these variables.

Privacy: when `provider_consent` is true, the user's typed or transcribed reply text is sent to the configured provider. Collecting consent and explaining this is the app's job. Meta's `-contributor` model variants are cheaper because content "may be used to train future Meta models" ([models](https://dev.meta.ai/docs/models)); they are refused unless `LLM_ALLOW_CONTRIBUTOR=true`, and the consent copy must then say so (see `may_train_on_content` in capabilities).

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

Next: confirm the smoking coding and the missing-value policy with Track A, ask the intake for time sitting, high blood pressure and general health, and implement compare/sensitivity on the same model. Do not replace the remaining 501 routes with plausible sample mortality numbers.

## Survival forecast (`POST /api/predict`)

The server runs Track A's trained DeepSurv model (`model.keras`, `preprocessor.joblib`, `baseline_hazard.csv`, `metrics.json`, committed at the repository root by Victor). The files are loaded once at startup without TensorFlow: the Dense weights are read from the `model.weights.h5` inside `model.keras` with h5py and run as a numpy forward pass; the scikit-learn preprocessor is loaded with joblib (pinned to scikit-learn 1.9.1, the version that saved it). Survival is `S(t) = exp(-H0(t) * exp(risk))`, with `H0` the last baseline row at or before `t`. Parity with Keras 3.15.1 (numpy backend) was checked on 52 inputs: largest risk difference 6.3e-7.

The request is the confirmed `HealthProfile`. Mapping: age; sex male→1, female→2; BMI from `height_cm`/`weight_kg`; `sleep_hours`; `exercise_minutes_weekly` → moderate minutes, with 0 extra vigorous minutes; smoking never/former/current → 0/1/2 (unknown → missing; the coding is **assumed**, not yet confirmed by Victor); diabetes → 0/1. Time sitting, high blood pressure and general health are not asked yet and are filled in by the model's missing-value policy; the response lists them in `filled_in`.

Response (`contracts/prediction.schema.json`): `status` `supported` or `unsupported`; `survival` at 1, 3 and 5 years (probabilities 0–1); a monthly step `curve` from `(0, 1)` to `max_horizon_years` (5); `model_version` (`deepsurv-nhanes-` plus a short SHA-256 of the four files); `filled_in`; `reason` (plain words, when unsupported); `limitations`. There is never a date, countdown or life expectancy. `unsupported` (with empty `survival`/`curve`) is returned when age or sex is missing, age is above 80 (not capped) or below 18, or when height/weight, sleep or exercise is missing: the model's missing-value indicators for those inputs were learned from very few people and move the result far more than any real answer would.

`MODEL_ARTIFACT_PATH` sets the folder holding the four files (blank: the repository root; the Docker image uses `/app/model`). If any file is missing, the route keeps returning HTTP 501 `prediction_not_implemented`, and `/ready` reports `prediction: not_implemented`. Profiles are never logged.

