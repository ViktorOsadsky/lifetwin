# Master doc reconciliation

Maps every section of [`projectspec.md`](../projectspec.md) to its owner track, and records each place a team decision changes it.
The master doc itself is unchanged.

## Team decisions that change the master doc

| Master doc | Says | Team decision | Status |
|---|---|---|---|
| §7 Frontend | Next.js, TypeScript, Tailwind, shadcn/ui, Recharts, Framer Motion | **Flutter / Dart**, tested on iOS through Xcode. Chart and animation packages are Track C's choice | Decided |
| §7 Deployment, §13 MVP item 7 | Frontend on Vercel; "demonstrated through a deployed URL" | Backend still gets a deployed URL. The app runs on the iPhone. A Flutter **web** build could also be deployed if the URL requirement applies to the app itself | **Open:** confirm what the deployed URL must show |
| §6.4 Model selection | Cox first; random survival forest only if validation justifies it | Victor chooses the method. The master doc's order is the recommended default, not a requirement. Any model must still output S(t), a horizon cap and a validated population (§3.1, §3.2, §6.5) | Decided |
| §9 `/api/predict` request | Example sends `bmi` | The app sends `height_cm` and `weight_kg` (what §2.2 onboarding collects), and the server computes BMI. §9 allows the schema to be "adjusted to match the final trained model" | Decided in contracts |
| §5.3 Advisor context | Profile, predictions, comparisons, attributions, curated guidelines | The LLM gets the user's inputs plus the model's results (predictions, comparisons, risk factors). Guidelines are curated by Track D. **May change later** | Decided, revisable |
| §15 Privacy | "Keep scenario comparisons in browser state" | Keep them in on-device app state (no account, no server storage) | Follows from Flutter |

## Where each master-doc section lives

| Master doc | Track | Notes |
|---|---|---|
| §1 Overview | All | Unchanged |
| §2.1 Landing | C | Copy and design direction as written |
| §2.2 Onboarding | C (UI), B (validation) | Inputs follow `contracts/profile.schema.json`. Fields the model doesn't use come back in `ignored_fields` and are shown as informational (§2.2) |
| §3.1 Longevity overview | C (UI), B (numbers) | 10-year and, if follow-up supports it, 20-year headline from `prediction.survival_<N>_year`; out-of-population profiles get `status: "unsupported"` + `limitation` |
| §3.2 Survival curve | C | Curve from `survival_curve`, capped at `max_horizon_years` |
| §3.3 Lifestyle controls | C | Previous curve muted, new curve contrasting, persistent "modeled, not causal" label |
| §4 Compare your futures | C (UI), B (`/api/compare`) | Deltas in percentage points are computed by the server, never the app |
| §5 AI advisor | D | `/api/advisor`; never states a number the model didn't produce (§5.3) |
| §6 ML architecture | A | NHANES 1999–2018 + linked mortality through 2022, `SEQN`, `MORTSTAT`, `PERMTH_INT`, right censoring, C-index / Brier / calibration |
| §7 Backend (FastAPI, joblib) | B | Unchanged: FastAPI, serialized artifact from A, training offline |
| §8 Architecture | B | Same diagram with Flutter in place of Next.js |
| §9 API | B | Contract in `contracts/`. Keeps the master doc's `prediction`, `survival_curve` and `model_version`, and adds `status`, `limitation`, `max_horizon_years`, `risk_factors`, `cohort_curve`, `used_fields` and `ignored_fields` for §2.2, §3.1 and §3.2 |
| §10 Pages | C | Flutter screens named Landing, Onboarding, Dashboard and Compare; Dashboard and Compare are the priority |
| §11 Design | C | Colors as given (`#080B12`, `#7C8CFF`, `#39D5A0`, `#8C95A8`, `#F4F6FB`) become the app's theme |
| §12 Development plan | All | The master doc's five phases map onto the sync points in [team-plan.md](team-plan.md) |
| §13 MVP | All | Item 7 open (see above) |
| §14 Optional features | After MVP | Apple Health fits the Flutter/iOS choice well, but only after the MVP works |
| §15 Safety and privacy | D (copy), B (logging), C (display) | Rules repeated at the end of [team-plan.md](team-plan.md) |
| §16 Demo | D | Demo script follows the master doc's seven steps |
| §17 Success criteria | All | Used as the definition of done |

## Headline horizons

The master doc's §9 example shows 5 and 10 years; §3.1 asks for 10 and, "where supported by follow-up data", 20.
The stub server returns 10 and 20. The real horizons come from Victor's follow-up analysis: curves and headlines stop at the
model's `max_horizon_years`.
