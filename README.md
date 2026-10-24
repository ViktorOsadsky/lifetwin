# lifetwin

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
