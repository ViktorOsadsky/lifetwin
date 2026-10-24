# LifeTwin agent instructions

Before making changes, read [MASTER_PLAN.md](MASTER_PLAN.md), [TEAM_PLAN.md](TEAM_PLAN.md), and the relevant sections of [projectspec.md](projectspec.md).

- `MASTER_PLAN.md` resolves current product and stack decisions. `TEAM_PLAN.md` is the work-splitting document. Preserve its owners; do not invent assignments or claim planned code exists.
- Use short branches and GitHub PRs, then merge to `main` after applicable checks and repository protections pass. Do not push changes directly to `main` or force-push it. Default branch names: `codex/<track>-<task>`.
- Keep work within the assigned track. Coordinate shared contract changes before dependent implementation, and update documentation with changed decisions.
- The app is Flutter/Dart with a Python model/API backend. The Next.js stack in the original spec is superseded.
- Cosmetic SVG twin settings must not affect model predictions. Keep real baseline data separate from hypothetical experiments.
- Use supported survival probabilities and curves; never fabricate personal predictions or exact death dates. Maximize modeled survival at a supported horizon, and distinguish observational associations from causal effects.
- Research and plans must cite supporting sources. Unsupported actions or supplements receive no invented survival benefit. Keep raw profiles out of logs and web queries; keep provider keys server-side.
- Run checks relevant to your change and report what actually ran. The master guide identifies planned tooling that does not yet exist.
- Leave a handoff with the PR/merge state, affected contracts, validation, limitations, and next dependency. See the template in the master guide.
