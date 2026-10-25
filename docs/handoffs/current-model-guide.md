# Current model guide reconciliation

Track D / #108, reviewed merged main `9ace866` (#126/#138). Root coordinated these shared guides separately from the five-file #115 documentation change; owners remain unchanged.

Updated MASTER_PLAN.md, docs/team-plan.md, docs/lifespan-estimate.md and the docs index to describe the zero-centred Cox score and current age-summary blend. The historical CDC method, tables and owner quotation remain explicitly scoped to the retained component. Current flags, fractional-age floor, curve/summary distinction, unvalidated tail and observational comparison rules are explicit. No model, schema, UI, provider or numerical result changed.

Validation: local Markdown targets and whitespace checks. This documentation task ran no model, provider or device checks. Other agents own #107/#134 runtime acceptance and #133 timed rehearsal at the same pinned build; this prose does not establish their success.

Delivery: short docs branch `codex/d-current-model-guide`, normal PR/checks/merge required. Next dependency: review alongside #115 and the actual runtime acceptance records; future engine decisions must update these method claims together.
