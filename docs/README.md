# LifeTwin working docs

Start with [MASTER_PLAN.md](../MASTER_PLAN.md), the current product and agent implementation guide, and [AGENTS.md](../AGENTS.md) for PR/merge rules. [`projectspec.md`](../projectspec.md) remains the original modeling and privacy specification. Updated product/stack decisions are recorded in [prd-reconciliation.md](prd-reconciliation.md); the original spec is preserved. See the [backend run guide](../server/README.md) and [implemented contracts](../contracts/README.md) for current non-prediction functionality. Flutter, audio, model and iOS helper paths remain future work.

| Doc | For |
|---|---|
| [backend-status.md](backend-status.md) | Audited backend functionality, concrete fixes, verification and prioritized remaining backend tasks; excludes frontend/ML implementation |
| [MASTER_PLAN.md](../MASTER_PLAN.md) | Mascot-led game vision, voice/text intake, fortune, quiz, sensitivity, plans, experiment loop and delivery gates |
| [tech-stack.md](tech-stack.md) | Confirmed Flutter/LottieFiles plus proposed packages, model/API, LLM/research, deployment and deferred voice |
| [prd-reconciliation.md](prd-reconciliation.md) | Where each master-doc section lives, and every place a team decision changes it |
| [team-plan.md](team-plan.md) | The four tracks, sync points, contracts, checkpoints and rollback |
| [tracks/A-data-model.md](tracks/A-data-model.md) | Victor: dataset, training, evaluation |
| [tracks/B-api.md](tracks/B-api.md) | FastAPI server and deployment |
| [tracks/C-flutter-app.md](tracks/C-flutter-app.md) | Flutter app screens and visualizations |
| [tracks/D-advisor-demo.md](tracks/D-advisor-demo.md) | AI advisor, safety copy, demo |
| [ios-testing.md](ios-testing.md) | Running the app on the test iPhone and the simulator |
| [model-sensitivity.md](model-sensitivity.md) | Which inputs move the packaged Cox model's 5-year estimate most, by age band and sex, with [machine-readable lever ranking](model-sensitivity.json); observational, not causal |
| [apple-health.md](apple-health.md) | Apple Health import: what is read, read-back rules, privacy decisions, what is left |
| [design/painted-card-direction.md](design/painted-card-direction.md) | UI remake direction: painted-card look, bear or human twin, final screens, art assets and pipeline, Flutter notes |
