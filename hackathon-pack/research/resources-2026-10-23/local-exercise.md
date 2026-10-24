# Local exercise of the new resource routes

Date: October 23, 2026. This is the author's local behavioral exercise, **not an independent fresh-context evaluation** and not a live provider integration. Parent agent will arrange the independent review.

## Request and resulting decision

Scenario: a team has chosen a maintenance assistant that reads failed-CI evidence and prepares a repair recommendation. A saved CREAO agent will do its core analysis; a custom frontend shows job progress. They want a suitable sponsor track and a reliable completion flow. Existing access and all event eligibility remain to be verified.

Using sponsor-track-builder plus prize strategy, the appropriate conditional primary is **CREAO AI-First Disruptor**: removing the saved agent removes the core analysis. Do not claim a judged entry yet. The required run ID/agent ID, judge-readable run link and live demo are not present in this local exercise. The event pack's $2,500 award conflicts with earlier Devpost $3,000 wording; use the source-specific amount and ask organizers if it affects a final decision. No probabilities or additive winnings are claimed.

| Requirement / decision | Implementation or evidence artifact | Current state |
|---|---|---|
| CREAO saved agent does core work | Actual saved agent, its ID, one accessible run link, observed result feeding the UI | Planned; no account or run created |
| Product stays responsive during multi-minute run | Server starts async run, saves ID/job association; UI displays pending/running/result | Local state pattern exercised; no live trigger |
| Do not trust unsigned callbacks | Callback only wakes reconciliation; authenticated provider lookup supplies canonical status and result | Local injected lookup exercised |
| Retry and duplicate handling | Stable start idempotency key; durable terminal transition; poll missed callback | Terminal/poll pattern exercised; provider start not executed |
| Judge artifact | Devpost CREAO track, README agent ID/run link, demo showing core work | Checklist only; no submission |
| Atlassian secondary fit | Requires a Forge app, even if assistant mentions Jira | Exclude under current scenario: no Forge app |
| Factory secondary fit | Requires meaningful running-product Droid SDK use | Exclude if only used as coding aid |
| Cartesia secondary fit | Voice central to a useful task | Exclude unless actual user need makes voice part of core workflow |
| Mana secondary fit | Actual contribution paragraph and shareable chats/commits | Conditional only if genuinely used; local code is not Mana proof |

## Observed defect, correction and rerun

The first local callback implementation trusted the received `completed` body. A forged event moved the synthetic job from pending to completed and saved a fabricated finding, although the canonical fixture was pending. The event's actual Tech Stack says callbacks are unsigned, so the route now explicitly requires known-job binding, authenticated status lookup, terminal de-duplication and polling reconciliation. In the corrected experiment the same event leaves the job pending and performs zero terminal effects.

The first corrected run also exposed a smaller fixture/consumer defect: after changing a canonical fixture to failed, its old result remained visible. Terminal persistence was narrowed to store successful output only for completed state; assertions were strengthened for failed/cancelled output. Rerun passed seven cases: forged pending completion, unknown run, lookup timeout, missed callback reconciled through polling, three duplicates, canonical failure and canonical cancellation. The completed result is the canonical finding and only one terminal effect is recorded.

Artifacts: [executable experiment](creao_callback_exercise.py) and [actual final results](local-exercise-results.json). Run with `python3 hackathon-pack/research/resources-2026-10-23/creao_callback_exercise.py` from the workspace. It uses only the standard library and SQLite in memory. Fixtures are explicitly normalized adapter data, not a claim about every raw GET response field. It does not implement or test real authentication, network retries, cancellation requests, webhook delivery, process restart or simultaneous multi-process callbacks. Those remain implementation checks when a project actually selects CREAO.
