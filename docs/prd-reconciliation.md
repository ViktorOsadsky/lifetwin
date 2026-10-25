# Master doc reconciliation

Maps every section of [`projectspec.md`](../projectspec.md) to its owner track, and records each place a team decision changes it.
The original spec itself is unchanged. [MASTER_PLAN.md](../MASTER_PLAN.md) governs current product/implementation decisions; this file records differences from that spec. The app, voice path, check-in APIs and model packages now exist; document upload and autonomous daily planning remain planned. See the master guide for distinct server/on-device model boundaries. See [the backend run guide](../server/README.md) for working commands and [tech-stack.md](tech-stack.md) for technology choices.

## Team decisions that change the master doc

| Master doc | Says | Team decision | Status |
|---|---|---|---|
| Current implementation scope | Full predictive product vision | Earlier backend deferral has been superseded by merged app/voice/check-in/model work. Server predict serves DeepSurv; the separate Cox package supports years 1–5 and has its own population/support rules. Server compare/sensitivity remain 501. Upload and daily planning are not implemented | Current code boundaries in master guide and run guides |
| §1, §2, §10, §11 Product/UI | Scientific dashboard with traditional onboarding screens | Mostly full-screen pet-game UI inspired by Talking Tom; original SVG art and LottieFiles motion, customizable twin, charts/plans as activities or panels | User decision |
| §2.2 Onboarding | Multi-step health questionnaire, sliders/selections | Offer document upload immediately, Apple Health import or mascot voice/text; confirm candidate fields, then ask only for missing required inputs. Cartesia voice exists; upload is planned | October 23 meeting refinement |
| §3, §15 Longevity presentation | Survival probabilities/curves, no exact death date | Magic-ball reveal adds supported annual outlook, model drivers and scenario differences beyond a lone five-year percentage. The request for an exact death year is translated into interactive supported curves, never a cutoff-derived date or years gained | October 23 aspiration reconciled with model/safety limits |
| §5, §14 Recurring value | Advisor and optional short-term challenges | Target an opt-in daily health secretary: observe confirmed updates/feedback → prepare a cited schedule → user acts/logs → agent revises and explains. Real history, experiments, quiz health and medical predictions stay separate | October 23 meeting; planner/scheduler contracts pending |
| New quiz mode | Not in original scope | Challenging food/situation questions; wrong answers immediately make the twin look sicker through independent, reversible game-health state. Quiz answers do not modify confirmed inputs or predictions | User decision |
| §4, §5 Scenario/advisor | Manual comparison and curated advisor context | Add bounded finite-difference input search, cited web research, practical plans and explicit plan-to-experiment mappings; supplements are optional research with no invented model effect | User direction; contracts to implement |
| Team workflow | Earlier split allowed direct merges to main | Every change goes through a branch, PR and merge after required checks/protections | User decision |
| §7 Frontend | Next.js, TypeScript, Tailwind, shadcn/ui, Recharts, Framer Motion | **Flutter / Dart**, tested on iOS through Xcode. Chart and animation packages are Track C's choice | Decided |
| §7 Deployment, §13 MVP item 7 | Frontend on Vercel; "demonstrated through a deployed URL" | Backend still gets a deployed URL. The app runs on the iPhone. A Flutter **web** build could also be deployed if the URL requirement applies to the app itself | **Open:** confirm what the deployed URL must show |
| §6.4 Model selection | Cox first; random survival forest only if validation justifies it | Victor chooses the method. The master doc's order is the recommended default, not a requirement. Any model must still output S(t), a horizon cap and a validated population (§3.1, §3.2, §6.5) | Decided |
| §9 `/api/predict` request | Example sends `bmi` | The app sends `height_cm` and `weight_kg` (what §2.2 onboarding collects), and the server computes BMI. §9 allows the schema to be "adjusted to match the final trained model" | Planned contract decision |
| §5.3 Advisor context | Profile, predictions, comparisons, attributions, curated guidelines | The LLM gets the user's inputs plus the model's results (predictions, comparisons, risk factors). Guidelines are curated by Track D. **May change later** | Decided, revisable |
| §15 Privacy | "Keep scenario comparisons in browser state" | Keep scenarios on device. Check-in history stays on the phone; an across-day planner needs explicit local persistence, consent and deletion decisions. No implied durable server health store | Follows from Flutter and existing check-in boundary |

**Owner override (2026-10-24):** A rough expected year and age range may be shown once as a proof of concept, labelled as an estimate, never as a specific date. Method: [lifespan-estimate.md](lifespan-estimate.md) (the CDC 2024 life table plus the model owner's Cox relative risk, adjusted by age band). Scope: this one-time reveal only; the rule still applies everywhere else. This qualifies the "Longevity presentation" row.

## Where each master-doc section lives

| Master doc | Track | Notes |
|---|---|---|
| §1 Overview | All | Unchanged |
| §2.1 Landing | C | Game-room welcome and mascot introduction replace the original scientific landing direction |
| §2.2 Onboarding | C (upload/conversation UI), B (extraction/validation boundary), D (guide) | Upload/import first, confirm candidates, then missing-field voice/text follow-ups; coordinate upload schema before implementation |
| §3.1 Longevity overview | C (UI), A/B (model boundaries) | Show only the selected model's supported annual values and limitations; current artifacts stop at five years. Do not promise the original 10/20-year headlines |
| §3.2 Survival curve | C | Curve from `survival_curve`, capped at `max_horizon_years` |
| §3.3 Lifestyle controls | C | Previous curve muted, new curve contrasting, persistent "modeled, not causal" label |
| §4 Compare your futures | C (UI), B (`/api/compare`) | Deltas in percentage points are computed by the server, never the app |
| §5 AI advisor | D | `/api/advisor`; never states a number the model didn't produce (§5.3) |
| §6 ML architecture | A | NHANES 1999–2018 + linked mortality through 2022, `SEQN`, `MORTSTAT`, `PERMTH_INT`, right censoring, C-index / Brier / calibration |
| §7 Backend (FastAPI, joblib) | B | Unchanged: FastAPI, serialized artifact from A, training offline |
| §8 Architecture | B | Same diagram with Flutter in place of Next.js |
| §9 API | B | Contract in `contracts/`. Keeps the master doc's `prediction`, `survival_curve` and `model_version`, and adds `status`, `limitation`, `max_horizon_years`, `risk_factors`, `cohort_curve`, `used_fields` and `ignored_fields` for §2.2, §3.1 and §3.2 |
| §10 Pages | C | Character-centered game modes: room/conversation, studio, fortune, experiment/compare, plan and quiz; see the master guide |
| §11 Design | C | Cute cohesive SVG/Lottie game world; palette is chosen for that direction and accessibility. Original scientific palette is reference only |
| §12 Development plan | All | The master doc's five phases map onto the sync points in [team-plan.md](team-plan.md) |
| §13 MVP | All | Item 7 open (see above) |
| §14 Optional features | After MVP | Apple Health fits the Flutter/iOS choice well, but only after the MVP works |
| §15 Safety and privacy | D (copy), B (logging), C (display) | Rules repeated at the end of [team-plan.md](team-plan.md) |
| §16 Demo | D | Upload/import or talk/type → confirm missing inputs → outlook/drivers → experiment/reset → daily schedule → real check-in → explained next-plan revision; quiz/recovery remains separate. Label unavailable capabilities |
| §17 Success criteria | All | Used as the definition of done |

## Headline horizons

The master doc's §9 example shows 5 and 10 years; §3.1 asks for 10 and, "where supported by follow-up data", 20.
Planned stub horizons are illustrative, not promised real outputs. The real horizons come from Victor's follow-up analysis: curves and headlines stop at the
model's `max_horizon_years`.

## October 23 product refinement source

The [meeting decision record](meetings/2026-10-23-product-refinement.md) cites the user-supplied transcript, preserves requests and unresolved questions, and maps them to acceptance criteria. The original spec stays unchanged. No schemas or model versions change in this documentation PR; B/C/D must agree upload and plan-revision contracts before dependent code.
