# Product refinement with Vince — October 23, 2026

Meeting title: **Digital twin health prediction product refinement with Vince**. Participant metadata supplied with the notes: **Justin Wu**. Vince appears in the title and conversation; the transcript does not reliably attribute individual statements. Source: the user-supplied transcript, reconciled on October 24. This is a decision summary, not a verbatim transcript or evidence of clinical effects.

## Refined product promise

**LifeTwin is a daily health companion: bring your health information, explore your twin's modeled outlook, and get a practical plan that adapts as you report what really happened.**

The mascot and game make the experience approachable. The recurring value is understanding the outlook, trying scenarios and receiving a useful revised plan, beyond seeing one survival percentage.

## Meeting themes and product decisions

| Transcript theme | Decision carried into the product vision | Boundary / unresolved work |
| --- | --- | --- |
| “The onboarding is too long”; upload health documents immediately | Put upload at entry, alongside Apple Health and voice/text. Confirm extracted values and ask only for missing required inputs. | Upload/OCR is planned. File formats, limits, provider processing and candidate provenance need design. The transcript's conversion concern is a hypothesis, not measured conversion evidence. |
| A five-year survival percentage alone is unsatisfying | Show supported annual survival, plain-language model drivers and scenario comparisons. Keep small/flat changes visible without dramatizing them. | The meeting's approximate percentages for young users are not validated product claims. Respect each model's age/support rules and horizon. |
| See an exact year of death or life expectancy rise when exercise changes | Preserve the desire for a tangible, interactive future through overlaid supported curves and signed percentage-point differences. | Do not ship an exact death year, arbitrary probability cutoff or years gained. Any future lifespan summary needs separate model support and validation; the current Cox model card explicitly rules it out. |
| Record actual exercise today and see the twin respond tomorrow | Add brief real-world check-ins and acknowledge activity in the twin. Keep actual logs separate from hypothetical experiments. | No automatic next-day physiological or survival gain. Current backend daily logs are history only; weekly confirmed inputs and supported Cox aggregation windows are separate paths. |
| Notifications and calculations do not establish agency | Target an opt-in daily agent that reviews new data and feedback, chooses feasible cited actions, prepares a schedule and explains revisions. | Scripted check-ins, score computation, LLM interpretation and reminders alone do not fulfill the agent loop. Scheduling, durable local state and execution location remain design dependencies. |
| A “secretary but for health” | A short daily schedule, accept/edit/dismiss controls and completion feedback lead into the next revision. | Educational habit planning, not prescribing or autonomous treatment. The LLM does not invent a medical health score or personal survival number from how a user feels. |
| Refine the pitch once the app is more refined | Align the pitch with low-friction entry, interactive outlook and adaptive daily support. | Present planned capabilities as roadmap until demonstrated. Do not use “predict the day you die” as a product claim. |

## Target demonstration and acceptance

1. Offer upload/import immediately; allow decline, unreadable-document fallback and voice/text without losing confirmed information. Verify each candidate's value, units and date before use; follow up only where needed.
2. Reveal a supported outlook and explain model-grounded drivers. If the selected model cannot support the person or horizon, show the limitation without a number.
3. Try a supported activity scenario on the experiment twin. Show the actual modeled difference and reset it without changing the real profile.
4. Prepare a short cited daily schedule from confirmed context, goals and constraints. The user edits or accepts it and records what actually happened.
5. Replay the next daily planning run with changed feedback. Explain a concrete plan revision or why the plan stayed the same; demonstrate missing-data and provider-failure behavior. An animation may acknowledge progress without claiming a medical improvement.

Measure intake time to first useful result (retain the existing 60-second usability target), follow-up question count, extraction corrections and completion/drop-off. For the agent, inspect a replayable input → action/evidence → plan revision trace. These are proposed acceptance measures; no results were supplied by the meeting.

## Scope, sources and next dependency

This is **Track D product/trust documentation**, coordinated through the existing B/C/D boundaries. Victor remains Track A owner; no new human owners or deadlines are assigned. No application code, shared schema or model version changes in this refinement.

Current implementation evidence is in [the backend run guide](../../server/README.md), [shared contracts](../../contracts/README.md), [Apple Health notes](../apple-health.md), [voice notes](../voice-cartesia.md), [Cox integration guide](../../model_handoff/lifetwin_on_device/README.md), [Cox model card](../../model_handoff/lifetwin_on_device/MODEL_CARD.md) and [offline sensitivity analysis](../model-sensitivity.md). The original [spec §§3–5 and §15](../../projectspec.md) supplies the prediction/privacy constraints; [MASTER_PLAN.md](../../MASTER_PLAN.md) governs the refined behavior.

Next: B/C/D agree upload/extraction/confirmation and plan-revision contracts, user-consented local history, deletion, local-day scheduling and foreground/background execution. Then implement and validate them in follow-up PRs. The existing on-device provenance decision and planned Apple Health raw-sample server boundary remain unchanged.
