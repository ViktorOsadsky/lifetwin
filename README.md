# lifetwin

LifeTwin is a pet-style health game: talk or type to a mascot, hear a magic-ball longevity forecast, customize an SVG/Lottie twin, explore model-backed scenarios, follow an evidence-backed plan, and play challenging health quizzes. The non-prediction Python backend now supports conversational intake, cited educational plans and quiz delivery. The Flutter app, voice implementation and longevity model remain to be built.

## Start here

- [Backend status and remaining work](docs/backend-status.md): current functionality, audit findings/fixes, verification and a prioritized backend-only backlog.
- [Backend run guide](server/README.md): working endpoints, blank-key startup, limits, tests, and deliberately empty prediction routes.
- [Shared API contracts](contracts/README.md): generated schemas, fixtures and offline/live checks for Flutter integration.
- [Master implementation guide](MASTER_PLAN.md): current product decisions, sensitivity search, research/planning, experimental twin, contracts, and delivery gates.
- [Team splitting document](docs/team-plan.md): track owners and sync points; [track briefs and iOS workflow](docs/README.md).
- [Prospective tech stack](docs/tech-stack.md): Flutter/LottieFiles plus proposed app, API, ML, LLM, research, testing, and deployment choices.
- [Project specification](projectspec.md): survival modeling, data, evaluation, and privacy requirements.
- [Agent instructions](AGENTS.md): required reading and PR/merge workflow for repository contributors.

The current app direction is Flutter/Dart with a Python backend. Use PRs and merge them into `main`; follow the master guide where it updates earlier stack and design decisions.

## Agent skills

The [hackathon skill pack](hackathon-pack/START-HERE.md) contains ten reusable agent skills, supporting references, helper scripts, and evaluation evidence.

| Skill | Purpose |
| --- | --- |
| [creative-web-worlds](hackathon-pack/skills/creative-web-worlds/SKILL.md) | Distinctive 2D/3D interfaces, scroll motion, mobile design, and visual review. |
| [hyphenate-finance-agent](hackathon-pack/skills/hyphenate-finance-agent/SKILL.md) | Autonomous finance workflows, approvals, reconciliation, and evidence. |
| [apify-evidence-engine](hackathon-pack/skills/apify-evidence-engine/SKILL.md) | Actor discovery, bounded web extraction, and source-backed evidence. |
| [visa-agentic-commerce](hackathon-pack/skills/visa-agentic-commerce/SKILL.md) | Generative AI shopping experiences and verified commerce integrations. |
| [hackathon-idea-lab](hackathon-pack/skills/hackathon-idea-lab/SKILL.md) | Demand research, competitor analysis, and idea validation. |
| [hackathon-prize-strategy](hackathon-pack/skills/hackathon-prize-strategy/SKILL.md) | Track selection, eligibility, and submission planning. |
| [hackathon-backend](hackathon-pack/skills/hackathon-backend/SKILL.md) | Durable jobs, idempotency, and failure recovery. |
| [hackathon-ml-evals](hackathon-pack/skills/hackathon-ml-evals/SKILL.md) | Baselines, model evaluation, and bounded training decisions. |
| [sponsor-track-builder](hackathon-pack/skills/sponsor-track-builder/SKILL.md) | Meaningful sponsor integrations and required evidence. |
| [hackathon-demo-director](hackathon-pack/skills/hackathon-demo-director/SKILL.md) | Judge-ready demos, rehearsals, and accurate submission claims. |

### Use

Give an agent the relevant `SKILL.md` path, or install the skills into its skills directory. The installer previews changes by default and refuses to overwrite different existing skills.

```sh
python3 hackathon-pack/scripts/install_skills.py
python3 hackathon-pack/scripts/install_skills.py --apply
```

Run the pack's offline checks from the repository root:

```sh
python3 hackathon-pack/scripts/verify_pack.py
```

The pack's event research is dated October 23, 2026. Check current sponsor rules before relying on it. Local checks do not establish live sponsor access, and these skills do not contain the application implementation described in `projectspec.md`.
