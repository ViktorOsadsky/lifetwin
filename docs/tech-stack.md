# Prospective LifeTwin tech stack

Read [MASTER_PLAN.md](../MASTER_PLAN.md) for product behavior and [team-plan.md](team-plan.md) for ownership. This is an implementation proposal, not an inventory of installed dependencies or working services. Flutter and LottieFiles are user-confirmed; other choices are defaults to validate during Contract Zero. Voice implementation remains deferred at the user's request.

Sources were checked October 23, 2026 (Pacific time). Pin compatible versions during the first implementation PR and commit lockfiles; do not copy “latest” version numbers into the plan without running the build. Prospective service choices do not establish credentials, account access, budget, or deployment.

## App and game presentation

| Layer | Choice / status | Purpose and boundary |
| --- | --- | --- |
| App | **Flutter / Dart — confirmed** | iOS first, Xcode for device/simulator testing. Use standard Flutter composition, gestures and animation controllers for the pet-game shell. |
| Motion authoring | **LottieFiles — confirmed** | Author mascot, magic-ball, sick/recovery, listening/thinking/speaking and reward animations. Export versioned local assets with documented animation segments. [LottieFiles authoring and formats](https://docs.lottiefiles.com/en). |
| Motion playback | **`lottie` — proposed** | Start with exported Lottie JSON and app-controlled playback via `AnimationController`; bundle assets for predictable offline reactions. This is the community Flutter player, not an assumed LottieFiles SDK. Validate one complete export on the test iPhone before producing the full asset family. [Player documentation](https://pub.dev/packages/lottie). |
| SVGs | **`flutter_svg` — proposed** | Layered cosmetic avatar parts, icons, food/organ illustrations and static fallback expressions. Lottie motion and static SVG share palette/shape conventions. [Package documentation](https://pub.dev/packages/flutter_svg). |
| App state | **Riverpod (`flutter_riverpod`) — proposed** | Separate conversation drafts, confirmed profile, experiments, prediction requests and quiz health; keep async loading/error/cancellation explicit. [Package documentation](https://pub.dev/packages/flutter_riverpod). |
| Navigation | **`go_router` — proposed** | One game-room shell with modes/panels for fortune, quiz, studio, plan and experiments. Navigation must preserve confirmed conversation state. [Package documentation](https://pub.dev/packages/go_router). |
| HTTP | **Dio — proposed** | Typed API adapters, timeouts, cancellation, request IDs and stale-response rejection; never log raw health payloads. [Package documentation](https://pub.dev/packages/dio). |
| Survival charts | **`fl_chart` — proposed** | Curve/compare detail panels with accessible labels and API-provided numbers. Configure interpolation to preserve non-increasing survival curves rather than smoothing them into invalid values. [Package documentation](https://pub.dev/packages/fl_chart). |
| Quiz runtime | **Plain Dart deterministic state machine — proposed** | Bundle a reviewed versioned JSON question bank. Score locally so wrong-answer sick reactions happen immediately, including offline; keep scores separate from medical data. |
| Data persistence | **In-memory by default — proposed** | No database or account needed for the first demo. If a user opts to save small scenario snapshots, use `flutter_secure_storage`, with deletion and backup behavior verified on the target platform. Keep audio and transcripts ephemeral. [Package documentation](https://pub.dev/packages/flutter_secure_storage). |

A full game engine is unnecessary for the initial scene-based pet game. Reconsider only if measured gameplay needs physics or a continuous game loop. Export a small compatible motion set first. The app state machine selects idle/listening/thinking/speaking/fortune/quiz-sick/recovering segments; Lottie artwork does not own health calculations or scoring. DotLottie-specific features are deferred until a chosen runtime demonstrates them on device.

## Server, contracts and model

| Layer | Proposed default | Purpose and boundary |
| --- | --- | --- |
| API | **Python 3.11 + FastAPI + Uvicorn + Pydantic** | One server for validation, model inference, conversation turns, sensitivity and advisor routes. Python 3.11 is an initial compatibility target, subject to A's tested scientific dependencies. Pydantic defines validated boundary types; export/check shared JSON schemas. [FastAPI documentation](https://fastapi.tiangolo.com/). |
| Python tooling | **uv**, `pyproject.toml`, committed `uv.lock` | Reproducible server/training environments; isolate optional heavy model dependencies if needed. [uv documentation](https://docs.astral.sh/uv/). |
| Server networking | **HTTPX**, explicit timeouts | Provider API calls and bounded research retrieval behind adapters. Only allow safe public HTTP(S) retrieval; block private-network targets and validate redirects for fetched URLs. |
| Contracts | **JSON Schema + Pydantic + Dart boundary validation** | `contracts/` schemas and deterministic fixtures shared by all tracks. Ensure the Dart parser and Python service agree on optional fields, units, enums, errors and versions. |
| Training/data | **pandas, NumPy, scikit-learn; NHANES + linked mortality** | Offline harmonization, preprocessing, censoring-aware split/evaluation. Record cycles, feature mappings and dataset provenance. The spec supplies the data-method requirements. |
| Survival baseline | **lifelines Cox model**, Victor has final method choice | Start with a small reliable baseline unless A validates a better alternative. Survival output and supported population/horizons remain the shared boundary. [lifelines documentation](https://lifelines.readthedocs.io/en/latest/). |
| Model artifact | **joblib plus JSON manifest/model card and checksum** | Bundle preprocessing and trained artifact for inference; load only the team's trusted versioned artifacts. Package a small artifact with the deploy image initially; large data stays out of Git. |
| Sensitivity search | **Deterministic Python service using the model adapter** | Finite differences, bounded candidates, re-evaluated combined scenarios; no LLM-generated probabilities. Keep CPU inference off the async request loop if latency measurements require it. |
| Storage/jobs | **No durable health-data store or queue initially** | Short bounded requests, cancellation/timeouts and explicit unavailable states. A durable job contract/storage choice requires a follow-up design if measured research latency makes it necessary. |

## LLM, research and deferred voice

| Layer | Proposed default | Purpose and boundary |
| --- | --- | --- |
| Conversation guide / “Muse” | **OpenAI Python SDK, Responses API with Structured Outputs** | Return schema-shaped next questions and candidate extracted health fields. User confirmation and server validation determine the profile. “Muse” is a functional label here; the user has not specified a separate vendor SDK. [Official OpenAI documentation](https://developers.openai.com/api/docs/guides/structured-outputs). |
| Advisor and narration | **Same provider adapter**, separate prompts/schemas | Generate cited plans and mascot explanations from validated server context. Exact model ID goes in `OPENAI_MODEL`; choose and record an account-available model after a short latency/grounding evaluation in Contract Zero. Do not hardcode an unverified model name. Schema compliance does not establish medical correctness. |
| Agent orchestration | **Plain async Python workflow** | Explicit steps: validate context → scan → bounded search/fetch → grounded plan → validate references and claims. Start with a bounded orchestrator that can be inspected and replayed. |
| Web research | **Tavily Search**, bounded public-source retrieval and curated fallback | Server-side search returns candidate source URLs; verify health claims against the source itself and record citations. Keep queries topic-only. Use HTTPX retrieval with the network restrictions above. [Tavily Search API](https://docs.tavily.com/documentation/api-reference/endpoint/search). |
| Quiz content | **Reviewed local JSON bank with source links** | D authors/reviews; C renders and scores. LLMs may draft questions offline, but cannot improvise authoritative scored answers during a session. |
| Speech recognition | **Provider undecided — deferred** | Implement a `SpeechInput` adapter emitting final transcript, partial transcript, cancellation and errors. Audio capture format/transport, provider and credential exchange are decided together later. |
| Speech synthesis | **Provider undecided — deferred** | `SpeechOutput` adapter receives only approved mascot text and emits playback lifecycle events. Captions/text must remain complete when audio is unavailable. |
| Voice transport | **Deferred** | Choose streaming versus turn-based after provider/device evaluation. Start with text and explicitly labeled development stubs. Provider keys stay server-side; a later direct-to-provider audio path needs provider-supported short-lived credentials. |

Use strict structured results for extraction and planning, handle refusals/incomplete responses, and validate their meaning against the profile/model context. Keep prompts and schemas versioned. Do not retain raw audio or conversation transcripts by default; disclose third-party processing and validate the selected provider's retention settings before real health-data testing.

## Deployment and verification

| Layer | Proposed default | Purpose and boundary |
| --- | --- | --- |
| Backend deploy | **Docker on Railway**, one CPU service initially | Reproducible Python dependencies and model artifact, HTTPS API, environment secrets, health/readiness checks. Deployment is a later implementation task; no account/budget assumed. [Railway FastAPI guide](https://docs.railway.com/guides/fastapi). |
| App delivery | **Local iPhone/simulator first**, TestFlight later if needed | Follow [ios-testing.md](ios-testing.md). Backend gets a deployed URL. Whether a public Flutter web demo is required remains open in [prd-reconciliation.md](prd-reconciliation.md). |
| Flutter checks | **`dart format`, `flutter analyze`, `flutter test`, `integration_test`** | Meaningful conversation/game-state tests, API parsing and actual rendered device review. Test the Lottie export on device before asset production. |
| Python checks | **pytest, HTTPX test client, Ruff**, contract checker | Validation/error paths, deterministic model adapter, scan budget/directions, grounded output and extraction fixtures. |
| CI and source control | **GitHub Actions + PR merges** | Run applicable Flutter/Python/contracts checks when implementations exist; keep provider-backed tests opt-in. GitGuardian currently checks this docs PR but does not replace app tests. |
| Diagnostics | **Structured redacted server events + request IDs** | Track latency, provider failures and scan budget without raw health/audio/transcript payloads. Add third-party crash/analytics tools only with an explicit data-scrubbing design. |

Expected backend configuration: `OPENAI_API_KEY`, `OPENAI_MODEL`, `TAVILY_API_KEY`, `MODEL_ARTIFACT_PATH`, and `APP_ENV`. Flutter gets only the public `API_BASE_URL` and mode flags. Commit an `.env.example` with placeholders during implementation, never actual keys. Public provider-backed routes need server-side rate/concurrency limits and budget caps before external demonstration.

## Decisions still needed

- Voice/STT/TTS provider, transport, microphone capture/playback packages and interruption behavior; preserve the common voice/text conversation contract while deferred.
- Exact LLM model ID based on actual account access and a short evaluation; provider proposal is OpenAI, not an established integration.
- A's final model, feature set, validated population and horizons; no UI promise may exceed these.
- Public app URL versus phone-only demo, and owners/access/budget for proposed external services.

Everything else above is a default agents can implement against. Revise the relevant schema/docs in a PR when evidence warrants a change; do not introduce competing packages for the same responsibility without a reason.
