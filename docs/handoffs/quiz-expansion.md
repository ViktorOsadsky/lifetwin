# Quiz expansion handoff — October 24, 2026

Track / task: D content/server data, #69. No UI changes.

Result: bank 2.1 adds 30 reviewed questions to the existing eight, for 38 total. Added content covers food choices/safety (8), sleep (7), movement (8) and everyday habits (7), with moderate and challenging questions. Explanations cite CDC or NHLBI/NIH pages checked October 24; the original FDA citations are retained. Existing eight versioned questions and game effects are unchanged. Scoring vectors now reference bank 2.1.

Contract: the prerequisite [PR #83](https://github.com/ViktorOsadsky/lifetwin/pull/83) adds `sleep`/`habits` topics and exact-host NIH citation validation. The content PR uses that additive contract. Answering only changes cosmetic game health; no confirmed profile or prediction writes exist here.

Validation: 38 quiz tests pass, including all new versions reachable through detail/list APIs, both difficulties for the new topics, default limit 20 versus all 38 with `limit=100`, game recovery vectors, unsafe citations and profile/prediction isolation. All 28 generated schemas match; offline contracts pass (API-only cases explicitly skipped there). Source-link results are recorded in the PR; no network checks were added to unit tests.

Next dependency: Daniel can refresh any app-bundled question bank from `server/lifetwin/quiz/content/questions.json` and request `GET /api/quiz/questions?limit=100` when loading the whole server bank. The endpoint retains its bounded default of 20. This task does not claim the Flutter bundle or screens were updated, nor that quiz performance measures medical health.
