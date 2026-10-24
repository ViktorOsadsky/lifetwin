# LifeTwin agent instructions

Before making changes, read [MASTER_PLAN.md](MASTER_PLAN.md), [docs/team-plan.md](docs/team-plan.md), [docs/tech-stack.md](docs/tech-stack.md), and the relevant sections of [projectspec.md](projectspec.md).

- `MASTER_PLAN.md` resolves current product and stack decisions. `docs/team-plan.md` is the work-splitting document; the track briefs are indexed in `docs/README.md`. Preserve its owners; do not invent assignments or claim planned code exists.
- Use short branches and GitHub PRs, then merge to `main` after applicable checks and repository protections pass. Do not push changes directly to `main` or force-push it. Default branch names: `codex/<track>-<task>`.
- Keep work within the assigned track. Coordinate shared contract changes before dependent implementation, and update documentation with changed decisions.
- The app uses Flutter/Dart and LottieFiles with a prospective Python/FastAPI backend. Other stack defaults are proposed in `docs/tech-stack.md`; voice-provider implementation is deferred.
- Build a pet-game experience: mascot-led voice/text intake, magic-ball fortune, customizable SVG/Lottie twin, experiments, and quiz. Do not substitute a traditional multi-page intake form.
- Keep cosmetic settings, quiz/game health, confirmed health inputs, and hypothetical experiments separate. Wrong quiz answers immediately change only game health and sick/recovery reactions; they never alter medical predictions.
- Use supported survival probabilities and curves; never fabricate personal predictions or exact death dates. Maximize modeled survival at a supported horizon, and distinguish observational associations from causal effects.
- Research and plans must cite supporting sources. Unsupported actions or supplements receive no invented survival benefit. Keep raw profiles out of logs and web queries; keep provider keys server-side.
- Run checks relevant to your change and report what actually ran. The master guide identifies planned tooling that does not yet exist.
- Leave a handoff with the PR/merge state, affected contracts, validation, limitations, and next dependency. See the template in the master guide.
