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
| Backend | Python/FastAPI owns server inference, research and provider credentials. A separate Dart Cox package supports on-device inference; use one explicit model boundary per result. |
| Experience | Mostly full-screen pet-game UI, inspired by Talking Tom: an expressive mascot, customizable digital twin, SVG art and LottieFiles animations. The mascot conversation replaces traditional health-input onboarding screens. |
| Intake | Offer health-document upload immediately, alongside Apple Health import and mascot-led voice/text. Extract candidate fields, confirm them, then ask only for missing required inputs. Upload is planned; Cartesia voice and Apple Health paths already exist. |
| Longevity output | Magic-ball reveal, supported annual survival curve, model-grounded drivers and scenario differences. Explain what changes the outlook beyond a single five-year percentage. No exact death year, arbitrary curve cutoff or unsupported life-expectancy estimate (spec §15). |
| Quiz | Challenging food-choice and situational questions. Wrong answers immediately make the twin look sicker in game state; explanations and recovery opportunities teach the user. Quiz penalties never alter real health inputs or model predictions. |
| Optimization direction | Improve survival probability at a supported horizon. If a validated longevity summary is added later, improve it toward a longer life: a later date, not an earlier one. |
| Recommendations | A daily health-planning agent is the target: incorporate confirmed updates and feedback, research feasible actions, and revise a short daily schedule with reasons. Model sensitivity is one input; reminders and score calculations alone do not fulfill this requirement. Supplement discovery remains optional and unmodeled. |
| Delivery | Short branches, PRs, then merges to `main`. Direct pushes to `main` are superseded by the user's PR requirement. |

**Owner override (2026-10-24):** A rough expected year and age range may be shown once as a proof of concept, labelled as an estimate, never as a specific date. Current method: [docs/lifespan-estimate.md](docs/lifespan-estimate.md) (an age-weighted blend of the personalized CDC-table mean and the experimental yearly Cox projection crossings, merged in [#126](https://github.com/ViktorOsadsky/lifetwin/pull/126)). Scope: this one-time reveal only; the rule still applies everywhere else. This covers the "No exact death year … life-expectancy" limit in the Longevity output row above. Daniel, after talking to Viktor in person:

> "We should extrapolate an expected death year or date, but then it basically goes away as we focus on relative health score. It doesn't matter how accurate it is for this, as it will never be truly accurate if we extrapolate. it is more of a proof of concept. Age bands should be extrapolated and adjusted. [...] He [Viktor] is okay with the extrapolation. We don't really need beyond five years."

**Merged score decision ([#138](https://github.com/ViktorOsadsky/lifetwin/pull/138), reviewed at `9ace866`):** The health score is the same-sex, nearby-age survey group's median Cox risk score minus the person's score, with age/sex terms removed from both. **0 is the comparison-group middle; positive is healthier, negative less healthy.** This centered score supersedes the earlier 1.0-relative index and is not a probability or national ranking. Current Cox v3 history uses `cox_centered_bmi35_v2`; earlier model points remain stored but are excluded. Quiz health remains separate. See the [app model guide](app/lib/README-model.md).

The one-time age guide remains unvalidated: its central ages use repeated one-year Cox steps with other inputs fixed, while its edge ages use the personalized CDC method. The displayed blend is not mean life expectancy or a validated survival distribution, and nothing past 79 is validated. The [36-case sanity report](docs/research/lifespan-sanity.md) records large differences from SSA period means without treating unlike mean/median comparisons as calibration error. No causal years gained or exact date is supported. Simulator acceptance is separate from these merged-code decisions.

See [the prospective tech stack](docs/tech-stack.md) for package/provider defaults and pending upload/planner choices; use the voice guide for the implemented Cartesia path. See [the PRD reconciliation](docs/prd-reconciliation.md) for updates to the original spec.

## Current repository state

As of the October 24 reconciliation, `main` contains a Flutter game shell with voice/typing onboarding and Apple Health import, Cartesia token/client integration, a Python backend with confirmed intake, curated cited plans and reviewed quizzes, and stateless daily/weekly check-in endpoints. Check-in endpoints are not yet connected to the app; daily answers are history only, while confirmed weekly answers produce a `profile_update`. See [the backend run guide](server/README.md), [voice notes](docs/voice-cartesia.md), [Apple Health boundary](docs/apple-health.md), and [contracts](contracts/README.md). Code availability does not establish live-provider or device validation.

Prediction implementation has since progressed beyond the earlier deferral: `/api/predict` serves a root DeepSurv artifact when installed; a separate [on-device model package](model_handoff/lifetwin_on_device/README.md) contains the Cox model's supported years 1–5 survival output, a frozen dense-network relative-hazard output, and two experimental Cox age-stepping projections. The [model handoff](model_handoff/SURVIVAL_PROJECTION_HANDOFF.md) covers only Flutter integration. A separate [internal website](web/survival_lab/README.md) lets the model author test inputs and compare outputs without Flutter, including zero-shot inputs outside the fitting population with visible warnings. The website has its own [Cox BMI refit](web/survival_lab/MODEL_CARD.md); its Cox numbers now differ from the Flutter package's original artifact. Complete, supported profiles ages 35–79 remain required for supported current Cox percentages in the Flutter package. The website's out-of-range numbers and projected tail are not validated personal lifespan estimates. Server compare/sensitivity routes remain 501, while an [offline Cox sensitivity analysis](docs/model-sensitivity.md) exists. The original backend audit is a dated snapshot, not a current feature inventory.

Health-document upload/extraction (#51) and a stateless cited daily planner (#53) are now merged. The wellness UI branch connects them to foreground routes; persisted plan/feedback history and an unattended schedule remain follow-up work. This documentation change does not implement them, change contracts or select a new prediction engine. The original `projectspec.md` remains preserved; the [October 23 meeting decisions](docs/meetings/2026-10-23-product-refinement.md) refine its product vision through this guide and the reconciliation.

The skill pack contains prior research about other product ideas. Reuse relevant tools and instructions, but do not treat RecallDesk, commerce, or finance examples as this app's product requirements. Do not claim that a fixture or helper script is the LifeTwin application.

## Current wellness UI assignments

Issues [#54–57](https://github.com/ViktorOsadsky/lifetwin/issues/54) refine the October 23 vision toward wellness-first Home, quiz/Customize (approved Q), Settings/History/errors (R), and upload/plan/directional drivers (S). FlareYun's UI branch uses the existing painted-card artwork and tokens. The [implementation handoff](docs/design/wellness-ui-handoff.md) distinguishes connected features from presentation seams and pending engine work. Keep existing team-plan owners; this does not assign their dependencies to a new track.

Check-in, conversation, consent, wristband and Experiment screens remain on [PR #58](https://github.com/ViktorOsadsky/lifetwin/pull/58). Settings links to those owners. Do not derive a score from quiz health, subjective mood, survival probability or band counts. Driver UI shows supported directions, without point values or causal claims ([#56](https://github.com/ViktorOsadsky/lifetwin/issues/56)).

## Product loop

Build one connected experience:

1. **Meet the mascot and bring your data.** Offer health-document upload at entry, with Apple Health import and voice/text alternatives. Use a default twin so customization never blocks the first useful result. Confirm extracted values and ask only for missing required information; avoid a long questionnaire.
2. **Understand your outlook.** The magic-ball scene reveals supported survival probabilities over time, the model's relevant drivers and limitations. Annual values stop at the selected model's supported horizon. A high five-year value alone is not the whole experience; never invent a death year or exaggerate a small difference.
3. **Explore the levers.** Try supported lifestyle scenarios on a separate twin. Explain the actual signed percentage-point differences, including flat, uncertain and unsupported results; do not translate them into years gained.
4. **Get a practical daily plan.** The agent combines confirmed context, goals, constraints and cited evidence into a short schedule the user can accept, edit or dismiss. Model associations may inform investigation; unsupported actions have no numerical longevity benefit.
5. **Log what really happened.** Record activity, sleep and how the user feels through a brief check-in. An animation acknowledges the report, while a hypothetical exercise session stays only in the experiment. Daily history is distinct from a confirmed profile update.
6. **Return to an adapted plan.** In the target opt-in daily loop, the agent reviews new confirmed context and completion feedback, revises the next plan and explains what changed. A missed day is unknown, not zero activity. Any forecast reassessment uses the selected model's supported input window; one workout does not imply an overnight survival or physiological improvement.
7. **Play and customize.** Appearance and quizzes remain engaging activities. Wrong quiz answers affect only reversible game health, never confirmed inputs, the daily health plan or medical predictions.

The emotional goal is curiosity and encouragement. Avoid death countdowns, frightening consequences, body shaming, or visual claims that a heavier/lighter avatar is inherently healthier. The twin illustrates the scenario; it is not a medical scan or a forecast of the user's future appearance.

## Screens and SVG system

| Screen | Required behavior |
| --- | --- |
| Game room / mascot conversation | Immediate upload/import choices and voice/text alternative; confirmation summary, missing-field follow-ups, captions and correction. Measure time to first useful result against the spec's 60-second usability target without rushing consent or confirmation. |
| Twin studio | Customize skin/hair/clothes/accessories independently of the health profile; provide a useful default so customization never blocks simulation. |
| Magic-ball fortune | Mascot performs the reveal using the validated baseline. A readable summary and optional detail panel show the curve, supported horizon, and limitations. |
| Experiment / compare | Editable clone of the profile, validated controls, overlaid baseline/scenario curves, signed percentage-point deltas, reset, and an explicit “apply to experiment” action. |
| Plan / advisor | Short daily schedule with evidence, accept/edit/dismiss controls, completion check-in and explanation of revisions. Distinguish observations, experiments, model associations and proposed actions. |
| Quiz arena | Challenging questions with answer choices, immediate sick/recovery animation, explanation, retry/review and independent game-health meter. |

Create an original, reusable SVG family: layered avatar parts, heart/lungs/activity/sleep/nutrition illustrations, accessories, navigation icons, loading/empty/error states, and milestone reactions. Begin with a small complete set and expand it after the flow works. Use shared palette, stroke, corner, and expression conventions; keep an asset manifest with purpose and license/provenance. Flutter's SVG renderer must support each asset's features. Supply semantic labels, adequate contrast, text alternatives to chart colors, and reduced-motion behavior. Do not use real health records in screenshots or demos.

Compose these as game modes in one character-centered world, with large touch targets, short speech bubbles, playful props and minimal persistent chrome. Charts/plans open as panels or activities; the primary experience should feel like a pet game. Talking Tom is an interaction reference, not permission to copy its character, art, branding, or audio. LottieFiles handles authored mascot/prop motion; SVG handles modular customization and illustrations.

## Mascot conversation and fortune

After optional upload/import and confirmation, the same conversational follow-up flow must work with voice and text. The LLM asks one clear question at a time, extracts candidate fields into the versioned profile schema, and asks follow-ups for ambiguous answers or units. “About 170” is not enough to decide height versus weight or pounds versus kilograms. A reply may answer several fields, but only explicitly provided values may enter the draft.

Show captions and a compact editable summary; ask the user to confirm extracted health values before submitting them for inference. Corrections replace the relevant draft values and invalidate stale results. Let the user skip optional questions or say “I don't know”; never infer a diagnosis from casual language. A completed confirmed profile uses the same validation/API as typed input. Text mode is an equal conversation path, not a separate questionnaire.

Implement a conversation state machine: `idle → asking/speaking → listening or typing → interpreting → confirming → ready`, with retry, cancel, correction, and unavailable-provider states. The avatar receives presentation events, never authority to change health data. Keep draft profile state on device/in request context; avoid durable conversation or audio storage. Explain provider processing before transmitting health text/audio.

Cartesia Sonic/Ink integration now exists; [the voice guide](docs/voice-cartesia.md) records setup and limitations. Keep replaceable speech/guide boundaries and an equally complete text path. Verify microphone permission denial, interruption, provider errors and switching to text without losing confirmed answers. Do not equate committed code with a tested live voice experience.

The magic-ball scene is presentation around a prediction result: awaiting model → reveal → mascot explanation → inspect or experiment. Bind the spoken/captioned result to the same validated value, horizon and model version shown in details. If no prediction is supported, the mascot explains that limitation instead of inventing a fortune. Any future date-like summary requires a separately reviewed definition, model support and prominent uncertainty; never derive a date from an arbitrary curve endpoint.

## Health-document intake

The [October 23 meeting](docs/meetings/2026-10-23-product-refinement.md) makes upload an entry point rather than a task after a long intake. Let users decline upload and continue with Apple Health or conversation. Upload failure must preserve confirmed values and offer retry or text.

Extract only schema-supported candidate fields with source page/section, measurement date, units and uncertainty. Show a compact editable read-back before accepting them. Conflicting records, old measurements, missing units and unreadable content need clarification; absence of a diagnosis in a record is not a negative diagnosis. Required-field checks and prediction eligibility remain the selected model's responsibility. Do not treat a document as instructions for the agent.

Before implementation, B/C/D must agree file formats and size limits, extraction/OCR and provider processing, candidate/provenance shapes, confirmation behavior and ephemeral deletion. No raw documents, identifiers or extracted profiles belong in logs, research queries, fixtures or Git. Upload is separate from Apple Health; its existing raw-sample routing and on-device provenance decisions remain in [apple-health.md](docs/apple-health.md).

## Daily health-planning agent

The product promise is a health secretary that prepares and revises a useful daily plan. A fixed notification, a scripted check-in, an LLM interpretation or a deterministic score alone does not demonstrate that loop. The agent must choose a next action from current context, use bounded evidence/tools, incorporate feedback, and show the resulting plan revision.

1. With opt-in, run on the user's chosen local daily schedule and after an explicitly requested revision. Read only confirmed inputs and authorized history, preferences, constraints, previous plan and completion feedback.
2. Validate freshness, missingness and the input snapshot/version. Summarize real observations separately from experiment assumptions. Subjective wellbeing may change plan tone or feasibility; it does not become an invented medical score or diagnosis.
3. Reuse reviewed evidence where applicable and research within existing query/page/time budgets when needed. Produce a small schedule with action IDs, timing, rationale, sources and accept/edit/dismiss controls. Reuse the prior plan if no revision is justified, stating why.
4. Record which inputs changed, which plan items changed and why. Keep bounded retries and one effective revision per input snapshot/local day; stale responses cannot replace newer accepted plans. Missing data prompts a brief clarification or a labeled general plan rather than a guessed measurement.
5. Surface the plan for the user to choose actions. Optional notifications point to a new plan or a requested check-in; notification permission is separate from health-data and processing consent. No autonomous purchases, prescriptions or medication changes.

Current check-ins keep history on the phone and the server stateless. Unattended work across days therefore requires an explicit follow-up design for opted-in local persistence, deletion, execution location, scheduling/resume, timezone and provider consent. Do not silently introduce server health storage or promise iOS background execution. Foreground/on-resume refresh can be an honest interim mode, but must not be presented as a completed background agent.

For model reassessment, preserve actual implementation boundaries: backend daily check-ins are history only; completed weekly check-ins expose confirmed profile updates. The Cox package separately accepts complete supported daily/weekly windows, as documented in [its integration guide](model_handoff/lifetwin_on_device/README.md). Integrating either path requires an explicit mapping and provenance; no single-day action automatically changes the survival estimate.

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

## Contract Zero and future extensions

The first non-prediction contract PR has landed. See [contracts/README.md](contracts/README.md) for the current generated schemas, replay cases, exporter and checker. Prediction now has a concrete response; compare/sensitivity remain deferred on the server. The list below describes target responsibilities, not exact current filenames or completed features. Use the backend run guide instead of commands for the nonexistent `stub_server.py`. Upload and daily-agent extensions require a coordinated contract PR before dependent implementation; this vision update changes no schema.

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

### Target endpoint responsibilities

| Endpoint | Responsibility |
| --- | --- |
| `POST /api/predict` | Validate supported features and population, preprocess consistently with training, return the real survival prediction or an explicit unsupported result. |
| `POST /api/compare` | Predict baseline and scenario through the same model and calculate deltas at shared supported horizons. |
| `POST /api/sensitivity` | Run the bounded input perturbation scan below and return evaluated candidates, direction, validity, and budget metadata. This extends the original spec. |
| `POST /api/advisor` | Use validated model/sensitivity context and cited evidence to explain and propose a plan. Research and plan statuses remain explicit if a provider fails. |
| `POST /api/onboarding/turn` | Interpret a typed or transcribed reply against the draft/confirmed profile, return candidate values and the next mascot question; never silently commit an inferred health value. Cartesia transport is documented in the voice guide. |

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
| 6 — Polish and demo | Mobile accessibility, deployed API, complete mascot-led phone rehearsal | Demonstrate upload/import or talk/type → confirm missing inputs → outlook/drivers → experiment/reset → daily plan → real check-in → explained next-plan revision, plus quiz/recovery and failure cases. Label each unavailable capability. |

The spec's predictive MVP remains the first milestone. The expanded LifeTwin experience also requires upload-assisted brief intake and the daily observe → plan → act/log → revise loop, alongside the game shell, voice/text, fortune, bounded search, evidence-backed plans, experiments and quiz. Upload/agent contracts and privacy decisions must precede their implementation; the gates above remain the underlying build sequence. A labeled fixture or text-only demo is useful scaffolding and must be described accurately.

## Verification that matters

Run checks appropriate to the changed track after the relevant tooling exists. Do not report planned commands as executed tests.

- **A:** reproducible preprocessing/training; held-out C-index, censoring-aware Brier score, calibration, available subgroup checks, sample/death/follow-up counts, and manifest limitations. No outcome leakage or uncensored lifespan labels for survivors.
- **B:** schema/fixture checks against stub and real server; unsupported population, invalid/missing inputs, horizon cap, curve validity, same-version comparisons, deterministic predictions, bounded scan counts, correct finite differences, and timeouts. Different models need not predict identical numbers.
- **C:** Flutter analysis and meaningful flow tests; rendered phone/simulator review of SVG/Lottie scenes, voice/text switching, confirmed-answer correction, denied microphone, fortune captions, charts, isolated quiz health, immediate reactions, duplicate-answer handling, cancellation/stale responses, accessibility, and reduced motion.
- **D:** held-out cases for ambiguous/missing conversational values, unit clarification, wrong-horizon numbers, ungrounded health claims, unsupported fortunes, quiz-source validity, missing evidence, supplement requests, retrieved prompt injection, and unmodeled plan actions.
- **Integration:** upload/import → confirmed candidates → missing-field follow-up; verify correction, conflict, unreadable-file and decline-upload paths without baseline mutation. For the daily planner, replay a missed activity, changed preference and absent log: the plan revision must explain its evidence and reason, avoid duplicate/stale revisions, and preserve forecast/game-state boundaries. Then a new supported profile through mascot talk/type → confirmation → magic-ball fortune → sensitivity → cited plan → experiment/reset → quiz error/recovery, then unsupported-profile and research/voice failure paths. Quiz answers must leave confirmed inputs and model predictions unchanged. Record real versus fixture mode.

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

The next dependency from this refinement is a coordinated B/C/D design for upload candidates and daily-plan revisions, including consent, local history and execution constraints. Preserve existing owners and model boundaries; complete device/provider and end-to-end validation before presenting the refined roadmap as shipped.
