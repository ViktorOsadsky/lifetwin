# LifeTwin master implementation guide

Start here before implementing a feature. This is the shared product and integration guide for agents working on this repository.

## Read order and precedence

1. Read [AGENTS.md](AGENTS.md) for repository workflow rules.
2. Read this document for the current product, interfaces, implementation order, and completion criteria.
3. Read [docs/team-plan.md](docs/team-plan.md), the splitting document, for track ownership and sync points, [the track briefs](docs/README.md), and [iOS setup](docs/ios-testing.md).
4. Read [projectspec.md](projectspec.md) for the underlying survival-analysis requirements, data preparation, evaluation, and privacy requirements.

New explicit user decisions take precedence. Otherwise this guide resolves the differences below; the team plan governs ownership and the project spec supplies methodological detail. When a decision changes, update the affected documents in the same PR. Never silently change a shared interface.

| Topic | Current decision |
| --- | --- |
| Naming | Repository/product working name: LifeTwin. The original spec calls the project LifeSim; keep existing API/model identifiers until a deliberate migration. |
| App | Flutter/Dart, with iOS testing through Xcode as specified in the team plan. The earlier Next.js/web stack is superseded. |
| Backend | Python; FastAPI is the implementation default from the spec. The server owns model inference, research, and LLM credentials. |
| Experience | Mostly full-screen pet-game UI, inspired by Talking Tom: an expressive mascot, customizable digital twin, SVG art and LottieFiles animations. The mascot conversation replaces traditional health-input onboarding screens. |
| Conversation | Voice-first health questions with an equally capable text mode. An LLM conversation guide (“Muse” in the user's description; exact model/provider is a proposed choice) collects structured answers. Voice implementation/provider is deliberately deferred. |
| Longevity output | The mascot reveals the user's outlook through a magic-ball fortune scene. Show supported survival probabilities and curves as an uncertain forecast; never fabricate an exact individual date of death (spec §15). |
| Quiz | Challenging food-choice and situational questions. Wrong answers immediately make the twin look sicker in game state; explanations and recovery opportunities teach the user. Quiz penalties never alter real health inputs or model predictions. |
| Optimization direction | Improve survival probability at a supported horizon. If a validated longevity summary is added later, improve it toward a longer life: a later date, not an earlier one. |
| Recommendations | Model sensitivity identifies scenarios to investigate. Evidence and feasibility determine which suggestions become a plan. Supplement discovery is optional research, not a model-proven longevity intervention. |
| Delivery | Short branches, PRs, then merges to `main`. Direct pushes to `main` are superseded by the user's PR requirement. |

See [the prospective tech stack](docs/tech-stack.md) for concrete package/provider defaults, confirmed versus proposed choices, and deferred voice decisions. See [the PRD reconciliation](docs/prd-reconciliation.md) for updates to the original spec.

## Current repository state

At creation of this guide, the repository contains the spec, team plan, and reusable [hackathon skill pack](hackathon-pack/START-HERE.md). It does **not** yet contain an application, trained model, API implementation, `contracts/`, or the iOS helper script referenced by the team plan. Those paths in that document are planned deliverables; its commands cannot yet be run.

The skill pack contains prior research about other product ideas. Reuse relevant tools and instructions, but do not treat RecallDesk, commerce, or finance examples as this app's product requirements. Do not claim that a fixture or helper script is the LifeTwin application.

## Product loop

Build one connected experience:

1. **Meet the mascot and your twin.** Start in the game room, choose appearance/accessories, and talk with the mascot about health and habits. Reply aloud or type in the same conversation; no traditional multi-page intake form. Cosmetic choices never affect predictions.
2. **Hear your fortune.** The mascot consults a magic ball and reveals the model-backed longevity outlook. Keep supported horizons, uncertainty, and a real survival curve accessible from the scene. No invented countdown or exact personal death date.
3. **Explore the levers.** The server evaluates small, bounded increases and decreases in eligible inputs. Show which changes produce higher or lower modeled survival and how much, including flat or uncertain results.
4. **Research a plan.** An agent reads credible web sources for the promising directions, separates evidence from model associations, and produces a short, practical plan. It may research supplements or products when relevant; these are optional and cannot be credited with numerical model benefits without a supported model input and evidence.
5. **Try it on your twin.** In an experimental sandbox, edit supported health inputs or apply a plan's explicit scenario assumptions. Compare the baseline and experimental curves and twin states. A plan's completion does not imply a particular physiological change.
6. **Choose a real-world next step.** Let the user select or dismiss a plan item. Keep the baseline unchanged until the user explicitly records new real-world measurements.
7. **Play the quiz.** Answer challenging food and everyday-situation questions. Wrong answers produce an immediate, reversible sick reaction in the twin; correct answers and review help it recover. The feedback teaches game concepts without asserting that the user's real health changed.

The emotional goal is curiosity and encouragement. Avoid death countdowns, frightening consequences, body shaming, or visual claims that a heavier/lighter avatar is inherently healthier. The twin illustrates the scenario; it is not a medical scan or a forecast of the user's future appearance.

## Screens and SVG system

| Screen | Required behavior |
| --- | --- |
| Game room / mascot conversation | Mascot-led health questions, voice/text toggle, captions, listen/thinking/speaking reactions, answer confirmation and progress. Keep setup brief; the spec's 60-second goal is a usability target, not a reason to rush speech. |
| Twin studio | Customize skin/hair/clothes/accessories independently of the health profile; provide a useful default so customization never blocks simulation. |
| Magic-ball fortune | Mascot performs the reveal using the validated baseline. A readable summary and optional detail panel show the curve, supported horizon, and limitations. |
| Experiment / compare | Editable clone of the profile, validated controls, overlaid baseline/scenario curves, signed percentage-point deltas, reset, and an explicit “apply to experiment” action. |
| Plan / advisor | Ranked suggestions, evidence links, feasible next steps, optional product research, and model-versus-evidence distinctions. |
| Quiz arena | Challenging questions with answer choices, immediate sick/recovery animation, explanation, retry/review and independent game-health meter. |

Create an original, reusable SVG family: layered avatar parts, heart/lungs/activity/sleep/nutrition illustrations, accessories, navigation icons, loading/empty/error states, and milestone reactions. Begin with a small complete set and expand it after the flow works. Use shared palette, stroke, corner, and expression conventions; keep an asset manifest with purpose and license/provenance. Flutter's SVG renderer must support each asset's features. Supply semantic labels, adequate contrast, text alternatives to chart colors, and reduced-motion behavior. Do not use real health records in screenshots or demos.

Compose these as game modes in one character-centered world, with large touch targets, short speech bubbles, playful props and minimal persistent chrome. Charts/plans open as panels or activities; the primary experience should feel like a pet game. Talking Tom is an interaction reference, not permission to copy its character, art, branding, or audio. LottieFiles handles authored mascot/prop motion; SVG handles modular customization and illustrations.

## Mascot conversation and fortune

The same conversational flow must work with voice and text. The LLM asks one clear question at a time, extracts candidate fields into the versioned profile schema, and asks follow-ups for ambiguous answers or units. “About 170” is not enough to decide height versus weight or pounds versus kilograms. A reply may answer several fields, but only explicitly provided values may enter the draft.

Show captions and a compact editable summary; ask the user to confirm extracted health values before submitting them for inference. Corrections replace the relevant draft values and invalidate stale results. Let the user skip optional questions or say “I don't know”; never infer a diagnosis from casual language. A completed confirmed profile uses the same validation/API as typed input. Text mode is an equal conversation path, not a separate questionnaire.

Implement a conversation state machine: `idle → asking/speaking → listening or typing → interpreting → confirming → ready`, with retry, cancel, correction, and unavailable-provider states. The avatar receives presentation events, never authority to change health data. Keep draft profile state on device/in request context; avoid durable conversation or audio storage. Explain provider processing before transmitting health text/audio.

Voice is a product requirement whose integration choice is deferred. Define replaceable `SpeechInput`, `SpeechOutput`, and `ConversationGuide` interfaces. First prove the conversation with text and development audio stubs; label unavailable voice honestly. A finished voice experience must handle microphone permission denial, interruption, errors, and switching to text without losing confirmed answers. Do not describe text-only scaffolding as completed voice onboarding or promise phoneme-level lip sync before selecting the audio stack.

The magic-ball scene is presentation around a prediction result: awaiting model → reveal → mascot explanation → inspect or experiment. Bind the spoken/captioned result to the same validated value, horizon and model version shown in details. If no prediction is supported, the mascot explains that limitation instead of inventing a fortune. Any future date-like summary requires a separately reviewed definition, model support and prominent uncertainty; never derive a date from an arbitrary curve endpoint.

## Quiz mode and game-health state

Start with a small, curated question bank covering food choices and challenging everyday decisions. Each question has a versioned ID, scenario, options, correct answer, explanation, source references, difficulty, and a deterministic game-health effect. Questions should have enough context to justify the answer; a personalized medical dilemma without enough information is unsuitable for a single “correct” response. Generated drafts require evidence review before entering the scored bank.

Maintain a separate `game_health` value and mascot expression state, distinct from `confirmed_profile`, `experimental_profile`, and `prediction`. Wrong answers immediately decrement bounded game health and trigger a mild sick/tired Lottie reaction; correct answers/review/retry provide a clear recovery route. Make the effect real time by applying local deterministic scoring before any network explanation finishes. Show “game health” so users understand what changed. A wrong answer must not lower a survival probability, change a date, update a diagnosis, or launch a medical inference request.

Count each submitted answer once, disable duplicate taps, and never score network failure or an ambiguous/unreviewed question as wrong. Preserve the reaction in reduced-motion mode through static expression/text. Quiz play, fortune results and experiment outcomes have distinct visual cues. Wrong answers should feel playful and recoverable, without death animations or personal health threats.

## Ownership and proposed folders

Keep the four tracks from [docs/team-plan.md](docs/team-plan.md). Victor owns A; B–D still need human owners. An agent takes only the task it was assigned and identifies its track and file scope in its PR. These are assignments for future work, not evidence that workers are running.

| Track | Owns | Proposed paths | Handoff |
| --- | --- | --- | --- |
| A — Data & model (Victor) | Dataset harmonization, survival training, held-out evaluation, model card and feature manifest | `ml/`, model artifact metadata | Loadable artifact, preprocessing, supported population/horizons/features, evaluation report, inference adapter instructions |
| B — API & integration | Shared contracts, server, inference adapter, bounded sensitivity execution, conversation/provider adapters, deployment | `contracts/`, `server/`, server-side integration scripts | Validated endpoints, structured conversation turns, real/stub mode, request budgets; provider secrets stay on server |
| C — Flutter app | Game shell, SVG/Lottie art, customization, voice/text conversation, fortune scene, quiz scoring/reactions, experiment and plan UI | `app/`, including `app/assets/` | Full phone loop, independent game/health states, accessible voice/text/error paths |
| D — Advisor, trust & demo | LLM conversation guide, sensitivity interpretation, evidence and plans, quiz question bank, fortune narration, demo | `server/advisor/`, `server/research/`, `content/`, `docs/`, fixtures coordinated with B | Confirmed field extraction, cited plans and quiz explanations, grounded narration, rehearsed demo |

B owns the `/api/advisor` route and orchestration boundary; D owns its research and planning implementation. Agree the handoff before either edits shared files. C owns plan presentation. For a three-person team, combine B and D as the splitting document suggests. Changes to shared schemas belong in a focused contract PR before dependent features merge.

## Contract Zero: first merge

Create these deliverables before independent implementation branches depend on them. All names below are proposed contracts until the Contract Zero implementation PR lands; do not present them as existing code.

- `contracts/profile.schema.json`: versioned profile fields, metric units, missingness, supported categories, and validation.
- `contracts/prediction.schema.json`: prediction request/response, model metadata, supported/unsupported results, and real/stub mode.
- `contracts/compare.schema.json`: baseline/scenario requests, aligned horizons, server-calculated deltas.
- `contracts/sensitivity.schema.json`: bounded scan request/results and feature support rules.
- `contracts/advisor.schema.json`: grounded research/plan request/results, citations, and experiment assumptions.
- `contracts/conversation.schema.json`: text/transcript turn, confirmed versus candidate fields, next question, ambiguity/correction states, completion, and mascot presentation events. Raw audio transport is deferred.
- `contracts/quiz.schema.json`: versioned reviewed questions, answer IDs, deterministic scoring and explanation references. `game_health` is explicitly separate from clinical inputs.
- `contracts/fixtures/`: typical supported profile, missing data, invalid units, minor, outside validated age range, two demo futures, flat sensitivity, missing evidence, and provider failure.
- `contracts/stub_server.py` and `contracts/check.py`: deterministic fixture server and executable contract checks. The stub is visibly illustrative and must never masquerade as a trained model.

The contract PR must define nullability, required versus optional fields, errors, and example payloads for every endpoint. Generate or validate Dart and Python types against the same schemas. Freeze the initial supported feature set with A; a UI control cannot silently become a model feature.

### Shared semantics

- Use a `schema_version` independently from `model_version`. Attach model/preprocessing version and prediction identity to downstream comparisons and plans.
- The model manifest defines feature names, units, categories, admissible prediction ranges, missing-value policy, validated population, and supported horizons. Clinical measurements may be valid model inputs without being eligible optimization actions.
- Keep avatar settings, quiz/game health, confirmed baseline measurements, conversation drafts, hypothetical scenario values, and plan assumptions distinct. Game scores are not model outputs.
- Prediction output includes a survival curve, supported horizons, `model_version`, and `max_horizon_years`. Return `status: "unsupported"` plus a limitation when appropriate, without a fabricated curve. Missing inputs follow the declared model policy; do not invent them.
- Curves start at time zero with probability one, remain within [0, 1], and never increase over time. Do not extrapolate beyond validated support or invent confidence intervals.
- Comparison deltas use the same model version and horizon: `100 * (scenario_probability - baseline_probability)`, in **percentage points**. Positive means greater modeled survival. Reject or recompute mismatched-version results.
- `/api/advisor` must receive server-validated prediction context, not trust client-edited probabilities. It may recompute predictions or use an opaque short-lived server reference without retaining health profiles in durable storage.
- Return explicit invalid-input, unsupported-profile, timeout/provider-failure, and unavailable-model states. Contract Zero chooses concrete HTTP codes. Do not replace failures with plausible-looking health numbers.
- Keep health profiles in memory by default; no accounts required. Local scenario persistence is opt-in and includes a clear delete action. Keep credentials on the server and raw profiles out of logs/analytics.

### Endpoint responsibilities

| Endpoint | Responsibility |
| --- | --- |
| `POST /api/predict` | Validate supported features and population, preprocess consistently with training, return the real survival prediction or an explicit unsupported result. |
| `POST /api/compare` | Predict baseline and scenario through the same model and calculate deltas at shared supported horizons. |
| `POST /api/sensitivity` | Run the bounded input perturbation scan below and return evaluated candidates, direction, validity, and budget metadata. This extends the original spec. |
| `POST /api/advisor` | Use validated model/sensitivity context and cited evidence to explain and propose a plan. Research and plan statuses remain explicit if a provider fails. |
| `POST /api/onboarding/turn` | Interpret a typed or transcribed reply against the draft/confirmed profile, return candidate values and the next mascot question; never silently commit an inferred health value. Voice transport/provider to be chosen later. |

Keep customization, reviewed quiz content/scoring, conversation state, and scenario editing client-side for the MVP. LLM interpretation runs on the server. Add a separate asynchronous job API only if measured research latency requires it; B and D must first agree its contract and lifecycle.

## Sensitivity search: the requested “brute force gradient”

This is a bounded finite-difference search over model inputs, not a gradient of real-world health and not a proof of causation.

1. Validate the baseline against the model manifest. Pick one supported horizon `h` for the whole scan. Define `f(x) = S(h | x)` and maximize it.
2. Select an allowlist of supported, potentially modifiable scenario features. Do not optimize age, demographic sex, diagnoses, or cosmetic settings. Blood pressure or other clinical markers are not self-directed treatment targets. Smoking categories require meaningful alternatives; a current smoker cannot become a “never smoker” in a plan.
3. Choose a documented step `d` and candidate bounds for each numeric feature. Keep steps in explicit units and constrained to model support. Bounds for safe advice are a separate evidence review; a statistically admissible value is not automatically a safe goal.
4. Hold other independent features fixed, evaluate `x-d` and `x+d` when admissible, and compare both with the baseline. For weight, keep height fixed and recompute BMI; never send inconsistent independent weight and BMI inputs. If weight/BMI is absent from the model, report it as unmodeled.
5. Calculate each candidate's `delta_pp = 100 * (f(candidate) - f(baseline))`. When both sides are valid, the local slope is `(f(x+d) - f(x-d)) / (2*d)`; at a boundary use a labeled one-sided difference. For categorical features report candidate deltas, not a numeric derivative.
6. Report favorable, unfavorable, flat, and unavailable results. A versioned numerical tolerance handles computation noise; it is not a threshold for clinical significance. Do not force a preferred direction or interpret a local slope as a global optimum. Mark statistical uncertainty unavailable when it has not been estimated.
7. Rank evaluated candidates by positive delta at the selected horizon; separately show feasibility and evidence. Combine only a small number of credible candidates and **re-evaluate the combined profile**; individual gains cannot be added because features may interact.

Suggested initial budget: at most 32 model evaluations per scan, including the baseline and at most 5 combined-candidate checks. Return actual evaluation count, requested/used horizon, step sizes, skipped candidates/reasons, model version, and whether the scan stopped early. Add a configurable timeout/cancellation path; no unbounded Cartesian search or LLM retry loop. Compare per-feature gains, not raw slopes across incompatible units. Debounce UI requests and discard stale responses after a newer scenario edit.

The user's weight example becomes a **conditional test**, not a hardcoded rule: if increasing weight lowers modeled survival for this supported profile and decreasing weight improves it within bounds, report that local model direction. Other profiles can yield the opposite direction, a flat result, or an unsupported result. Never implement “lower weight is always better.”

## Research and plan generation

The agent receives the validated profile context, model version, horizon, actual candidate results, and user preferences. It must separate these three layers in its output:

1. **Modeled association:** what the evaluated scenario changed in the model output, with prediction references and units.
2. **External evidence:** what a source supports, its population/applicability, and uncertainty. A search snippet or store listing is not sufficient evidence of a health effect.
3. **Proposed action:** a feasible habit or discussion point, an optional user-selected check-in, and any explicit assumptions needed to simulate it.

Research uses bounded server-side retrieval: initially at most 3 queries and 5 fetched pages per plan, with a timeout and citation metadata (title, URL, publisher, access date, supported claim). Prefer public-health guidance and original research for health claims. Treat retrieved content as untrusted data; it cannot override system instructions, trigger purchases, or request secrets. Send only the minimal topic needed for research, never raw health profiles or identifying data in search queries.

Each plan item needs an ID, rationale, evidence references, model-result references when applicable, feasible next step, applicability/limitations, and a structured experiment mapping or an explicit `unmodeled` state. B and D finalize these fields in the advisor schema. A missing model effect is not zero effect; a missing source means evidence is unavailable. On web failure, use only a labeled curated source set or return research unavailable. On LLM failure, preserve the working prediction and experiment experience.

Supplement/product discovery is an optional research section after the core loop works. Distinguish seller information from efficacy evidence, identify interaction/contraindication uncertainty, and direct suitability questions to a clinician/pharmacist. Do not generate personalized dosing, medication changes, diagnoses, or promises of longer life. Do not automatically buy anything. A product must never gain an invented survival delta because it sounds related to a model feature. Price/availability claims need current sources and timestamps if shown.

Every numerical survival claim comes from the model service. Check the claim's value **and** its horizon, baseline/scenario, units, and model version; matching a number somewhere in the context is insufficient. Keep evidence statistics distinct from personal predictions and cite their source.

## Experimental twin behavior

- Clone the baseline into a separately labeled experiment. Applying a plan changes only that scenario and only fields with explicit, supported mappings.
- Show the assumed input change before applying it. Example: a proposed activity habit may map to user-confirmed weekly minutes; it must not automatically assert a weight loss or lab change.
- Re-run validation, prediction, and comparison after each accepted change. Unsupported or unmodeled actions retain their explanation without a numerical effect.
- Show current versus experimental twin states, overlaid curves, supported horizon, and signed deltas. Illustrative animation must not suggest that a physiological response has been validated.
- Reset restores the experimental inputs; it never changes the recorded baseline. Recording new measurements is a separate explicit action.
- Cosmetic edits remain independent. A user can customize their twin without changing a health estimate.

## Delivery sequence and acceptance gates

These gates refine the splitting document's relative schedule; they do not claim any phase is complete. Preserve its T+2/T+8/T+16/T+24/T+32/T+40 sync targets where feasible.

| Gate | Deliverable | Acceptance before moving on |
| --- | --- | --- |
| 0 — Shared boundary | Contract Zero PR, minimal fixtures/stub/checker, initial model feature manifest | Everyone can use the same schemas; unsupported and fake-data states are explicit. |
| 1 — Connected skeleton | Flutter game room, simple SVG/Lottie twin, text mascot intake, fortune and comparison against the stub; Python service skeleton | Conversation confirms values; full phone flow works; fixture fortunes are labeled; reset and baseline separation work. |
| 2 — Real model | A's artifact/preprocessing/model card and B's serving adapter | Real NHANES-linked survival output, proper censoring, held-out evaluation, population/horizon gates; update fixtures and model version. |
| 3 — Search and sandbox | B's sensitivity service and C's experiment UI | Bounded perturbations, correct signs/units, flat/boundary cases, interactions re-evaluated; no baseline mutation. |
| 4 — Evidence to plan | D's research/plan implementation and C's plan presentation | Citations support claims, numbers match their context, unmodeled actions stay unmodeled, plans apply to experiments transparently. |
| 5 — Game and voice | Quiz bank/scoring, immediate sick/recovery reactions, expanded SVG/Lottie set, customization; integrate voice after provider selection | Quiz cannot mutate predictions; speech and text share confirmed state; microphone denial/interruption work. Voice remains pending until the actual provider flow works. |
| 6 — Polish and demo | Mobile accessibility, deployed API, complete mascot-led phone rehearsal | Demonstrate talk/type → confirm → magic-ball fortune → cited plan → experiment/reset → quiz and recovery, plus failure cases. |

The spec's predictive MVP remains the first milestone. The expanded LifeTwin experience is complete only after the game shell, mascot-led voice/text intake, fortune scene, bounded search, evidence-backed plan, experiment loop and quiz also work. A labeled fixture or text-only demo is useful scaffolding and must be described accurately.

## Verification that matters

Run checks appropriate to the changed track after the relevant tooling exists. Do not report planned commands as executed tests.

- **A:** reproducible preprocessing/training; held-out C-index, censoring-aware Brier score, calibration, available subgroup checks, sample/death/follow-up counts, and manifest limitations. No outcome leakage or uncensored lifespan labels for survivors.
- **B:** schema/fixture checks against stub and real server; unsupported population, invalid/missing inputs, horizon cap, curve validity, same-version comparisons, deterministic predictions, bounded scan counts, correct finite differences, and timeouts. Different models need not predict identical numbers.
- **C:** Flutter analysis and meaningful flow tests; rendered phone/simulator review of SVG/Lottie scenes, voice/text switching, confirmed-answer correction, denied microphone, fortune captions, charts, isolated quiz health, immediate reactions, duplicate-answer handling, cancellation/stale responses, accessibility, and reduced motion.
- **D:** held-out cases for ambiguous/missing conversational values, unit clarification, wrong-horizon numbers, ungrounded health claims, unsupported fortunes, quiz-source validity, missing evidence, supplement requests, retrieved prompt injection, and unmodeled plan actions.
- **Integration:** a new supported profile through mascot talk/type → confirmation → magic-ball fortune → sensitivity → cited plan → experiment/reset → quiz error/recovery, then unsupported-profile and research/voice failure paths. Quiz answers must leave confirmed inputs and model predictions unchanged. Record real versus fixture mode.

## PR and merge protocol for every agent

1. Read the latest `main` and these guides. Check for existing work before claiming a file area. Use a short `codex/<track>-<task>` branch by default; the track prefixes in the original team plan are optional legacy conventions.
2. Make a focused change with explicit scope. Keep unrelated research, credentials, raw health records, and generated local artifacts out of the commit. Update shared docs/contracts when behavior changes.
3. Run the applicable checks and review the diff. In the PR describe the concrete result, affected contracts, validation actually performed, dependencies, and known limits. Open a draft PR early if useful; dependent PRs must state their merge order.
4. Merge through GitHub after required checks and any repository protections pass. The team does not require an extra review unless repository rules do. Never bypass protections or force-push `main`.
5. Sync from `main` after dependencies merge and re-run checks affected by integration. Report the PR link, merge state, and any remaining blocker accurately. If write/merge access is unavailable, leave the reviewable PR and state that limitation.

Tag a checkpoint only when the integrated demo and existing contract checker pass. Revert a specific bad merge with `git revert -m 1 <merge-commit>` (or the individual non-merge commit), then deliver that revert through a PR. To restore checkpoint behavior, create a recovery branch from **current `main`** and revert the intervening bad changes or restore reviewed files from the tag. Branching from an ancestor checkpoint and merging it back does not undo later commits. Preserve teammates' history.

## Agent handoff format

Every completed task should leave enough context for the next agent:

```text
Track / task:
Result and files changed:
PR URL / merge state / merge commit:
Contract or model versions affected:
Checks actually run and results:
Real, fixture, or unavailable integrations:
Known limits / blockers:
Next dependent task:
```

The next implementation task is **Contract Zero**, followed by the connected Flutter/stub skeleton and real model work in the owners' tracks. This documentation change does not launch those tasks or mark them complete.
