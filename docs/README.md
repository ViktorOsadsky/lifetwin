# LifeTwin working docs

Start with [MASTER_PLAN.md](../MASTER_PLAN.md), the current product and agent implementation guide, and [AGENTS.md](../AGENTS.md) for PR/merge rules. [`projectspec.md`](../projectspec.md) remains the original modeling and privacy specification. Updated product/stack decisions are recorded in [prd-reconciliation.md](prd-reconciliation.md); the original spec is preserved. See the [backend run guide](../server/README.md) and [implemented contracts](../contracts/README.md) for implementation details. The master guide distinguishes the existing app/voice/model/check-in work from implemented document upload and the stateless coach from proposed unattended planning.

| Doc | For |
|---|---|
| [meetings/2026-10-23-product-refinement.md](meetings/2026-10-23-product-refinement.md) | October 23 source notes, refined promise, decisions, open questions and acceptance criteria |
| [backend-status.md](backend-status.md) | Historical October 23 backend audit; newer feature boundaries are in the master guide and backend run guide |
| [MASTER_PLAN.md](../MASTER_PLAN.md) | Mascot-led game vision, voice/text intake, fortune, quiz, sensitivity, plans, experiment loop and delivery gates |
| [tech-stack.md](tech-stack.md) | Confirmed Flutter/LottieFiles plus proposed packages, model/API, LLM/research, deployment and deferred voice |
| [prd-reconciliation.md](prd-reconciliation.md) | Where each master-doc section lives, and every place a team decision changes it |
| [team-plan.md](team-plan.md) | The four tracks, sync points, contracts, checkpoints and rollback |
| [tracks/A-data-model.md](tracks/A-data-model.md) | Victor: dataset, training, evaluation |
| [tracks/B-api.md](tracks/B-api.md) | FastAPI server and deployment |
| [tracks/C-flutter-app.md](tracks/C-flutter-app.md) | Flutter app screens and visualizations |
| [tracks/D-advisor-demo.md](tracks/D-advisor-demo.md) | AI advisor, safety copy, demo |
| [demo/upload-demo.md](demo/upload-demo.md) | Synthetic portal PDFs, matching text and upload demo sequence; no real patient data |
| [demo/voice-usability-demo.md](demo/voice-usability-demo.md) | Clearly labeled synthetic voice-session dataset; not real study evidence |
| [ios-testing.md](ios-testing.md) | Running the app on the test iPhone and the simulator |
| [model-sensitivity.md](model-sensitivity.md) | Which inputs move the packaged Cox model's 5-year estimate most, by age band and sex, with [machine-readable lever ranking](model-sensitivity.json); observational, not causal |
| [lifespan-estimate.md](lifespan-estimate.md) | One-time lifespan reveal (proof of concept, owner override 2026-10-24): expected age and year from the CDC 2024 US life table times the Cox relative risk, calibrated per age band, with validation and attenuation sensitivity |
| [document-upload.md](document-upload.md) | Health-document upload: on-device text recognition, `/api/documents/extract`, confirmation, privacy boundary, failure modes |
| [apple-health.md](apple-health.md) | Apple Health import: what is read, read-back rules, privacy decisions, what is left |
| [design/agentic/agentic-handoff.md](design/agentic/agentic-handoff.md) | Approved K/Q/R/S and other screen exports, HTML source and twin/cosmetic design masters |
| [design/wellness-ui-handoff.md](design/wellness-ui-handoff.md) | Wellness Home, Q/R/S presentation boundaries, validation and pending engine/art dependencies |
| [design/painted-card-direction.md](design/painted-card-direction.md) | UI remake direction: painted-card look, bear or human twin, final screens, art assets and pipeline, Flutter notes |
| [wearable-prototype-plan.md](wearable-prototype-plan.md) | Draft wrist activity-tracker prototype: hardware, metrics, feature list, phases and team decisions |
| [cal-hacks-submission.md](cal-hacks-submission.md) | Updated Devpost copy, four Figma-track stage drafts, measured model facts and Daniel's final submission placeholders |
