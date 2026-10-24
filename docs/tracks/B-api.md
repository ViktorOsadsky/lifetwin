# Track B: API & Integration

**Owner:** _TBD_ · **Master doc:** §7 backend, §8, §9, §12 phase 5 (deploy, responsiveness)

Read [MASTER_PLAN.md](../../MASTER_PLAN.md) for expanded requirements and [tech-stack.md](../tech-stack.md) for prospective defaults. Contracts/server/scripts below are planned until implemented. B owns the route boundaries; D implements the conversation guide, research and planning logic.

## Build

- **FastAPI** server (§7) with `POST /api/predict`, `POST /api/compare` and `POST /api/advisor` (D implements the advisor logic;
  you host the route).
- Add proposed `/api/sensitivity` and `/api/onboarding/turn` contracts from the master guide: bounded input scans and schema-shaped conversational extraction/next questions. Confirmation gates profile updates; voice provider and audio transport remain deferred.
- Establish shared conversation and reviewed quiz schemas with C/D. Quiz scoring stays local and cannot write medical profile/prediction state. Public provider routes need request/concurrency/rate limits and budgets.
- Request and response shapes exactly as in `contracts/` (master doc §9 fields plus `status`, `limitation`, `max_horizon_years`,
  `risk_factors`, `cohort_curve`, `used_fields`, `ignored_fields`). `contracts/stub_server.py` is the reference behavior.
- Load Victor's artifact at startup (joblib or whatever Track A delivers) and wrap it so responses always match the contract.
- Server-side rules (§3.1, §3.2, §15):
  - validate inputs against the profile schema;
  - minors and ages outside the validated range → `status: "unsupported"` + `limitation`, no curve;
  - cap curves at the model's max horizon;
  - compute `/api/compare` deltas in percentage points on the server.
- Fast enough for slider dragging (§4.2): a prediction should take tens of milliseconds, so time it.
- No request bodies in logs (§15). LLM key in an environment variable only.
- Deploy (Render, Railway or similar, §7) and give the team the HTTPS URL.

## Done when

- `uv run --with jsonschema python contracts/check.py --base-url <your server>` passes.
- Real-model swap: regenerate the fixtures from the real server, bump `model_version`, and tell the team.
- The phone reaches the deployed URL.

**Open:** what the master doc's §13 "deployed URL" must show (backend only, or also a Flutter web build). See
[prd-reconciliation.md](../prd-reconciliation.md).
