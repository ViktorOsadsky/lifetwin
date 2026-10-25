---
version: 1
slug: "web-demo-index-html"
primary_target: "web/demo/index.html"
related_targets: []
---

Scope: booth demo `web/demo/index.html`. Mode: Experience. Audience: judges at a laptop (1440x900, keyboard). Task: watch a short attract loop, then type tricky everyday answers to Pip; the live keyless parser (/api/onboarding/turn) understands, asks again, and never keeps a value without a yes. After intake: a short fortune (placeholder numbers, labeled), and a quiz from /api/quiz/questions whose wrong answers only change game health. Offline replay takes over, labeled, when the API is unreachable. User note: needs some attraction (idle loop).

## Direction contract

THESIS: Try to trick Pip. The wording edge cases are the game; the booth refuses the chatbot-transcript layout and the dashboard of panels.
OWN-WORLD: Same pinned habitat, wide aspect, as a stage. Pip large on the meadow with speech bubbles; the judge's answers appear as their own bubbles. A three-count scoreboard on the sky: Understood, Asked again, Saved without your yes: 0. Typed answers in one big input on the ground plane.
STORY: Walkers-by see Pip being tricked by sample answers (attract loop, big captions). A judge presses any key, types their own, watches Pip read it back or ask again, says yes, sees the tally and the twin's card fill, then optionally hears a fortune and plays the quiz.
FIRST VIEWPORT: Habitat full-bleed. Pip large right of centre, twin left; speech bubble from Pip in 28px+; scoreboard upper right; input bar across the bottom with hint chips "Try saying..."; title "Try to trick Pip" top-left. Idle: captions replay the script and "Press any key to play" pulses once per loop.
FORM: Surface structure 4 of 7 (trick Pip) blended with 2 (attract theater) per user note, seed key 42ea5769. Signature interaction: Pip's read-back, where the heard phrase morphs into the confirmed value chip.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
