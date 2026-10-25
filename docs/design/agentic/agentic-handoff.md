# Agentic UI designs: handoff

These are all the approved app screens and the twin sprite layers, exported from the Claude Design canvas so everyone on the team can use them without canvas access. Every screen passed two independent reviews before approval: one for design, one for accessibility and copy. A screen passes at 8.5 or higher with no blockers.

The rules every screen follows, including the owner's rulings and the engine contracts, are in [agentic-brief.md](agentic-brief.md). Read its last sections first. Where a screen and the brief disagree, the brief wins.

## Sets

| Set | What it covers | Status | Overview | Screens | Source | Flutter owner |
|---|---|---|---|---|---|---|
| K | Home and health score: reveal, Home, score detail, "See your estimate", age 27, large text, 320pt, under 18 | Approved 8.7 / 8.7 (a small polish round is running) | [sheet](screens/sheets/K-sheet.jpg) | [screens/K](screens/K) | [source/K](source/K) | Justin, #54 |
| Y | Experiment with your twin | Approved 8.6 / 8.8 | [sheet](screens/sheets/Y-sheet.jpg) | [screens/Y](screens/Y) | [source/Y](source/Y) | design session, #58 |
| Z | Conversation, daily and weekly check-ins, consents, delete my data | Approved 8.9 / 8.6 | [sheet](screens/sheets/Z-sheet.jpg) | [screens/Z](screens/Z) | [source/Z](source/Z) | design session, #58 |
| S | Upload, daily plan, Outlook drivers | Approved 8.7 | [sheet](screens/sheets/S-sheet.jpg) | [screens/S](screens/S) | [source/S](source/S) | Justin, #56 |
| Q | Quiz arena, Customize | Approved 8.8 / 8.7 | [sheet](screens/sheets/Q-sheet.jpg) | [screens/Q](screens/Q) | [source/Q](source/Q) | Justin, #55 |
| R | Failures, Settings, History, large text | Approved 8.6 / 8.7 | [sheet](screens/sheets/R-sheet.jpg) | [screens/R](screens/R) | [source/R](source/R) | Justin, #57 |
| H | ESP32 wristband | Approved 8.6 | [sheet](screens/sheets/H-sheet.jpg) | [screens/H](screens/H) | [source/H](source/H) | design session, #58 |

Sprite layers for the twin (bodies, poses, hats, age and build, cosmetics) are in [sprite-layers/](sprite-layers/README.md).

## Files
- `screens/<set>/<id>.jpg`: each screen at 390×844, the phone's first view.
- `screens/<set>/full/<id>.jpg`: the full scroll height, for screens that scroll.
- `source/<set>/<id>.dc.html`: the HTML source. Use it for exact sizes, colours, spacing, copy, and the accessibility notes in its comments.
  - The image URLs (`/_blob/…`) only resolve on the canvas. Use the files in `sprite-layers/` and `app/assets/`.
  - Files starting with `KN-` are board notes for set K, covering motion, placeholders and open questions.

## Things that are easy to get wrong
- **The health score leads.** On every screen that shows the outlook, the score card sits above the outlook and is stronger: bigger, and first in reading and screen-reader order.
  - The line under the score is "Feeling good now, and healthy years ahead." It's dropped at text scale 1.5× and up.
- **`healthScore` is a placeholder**, 0–100, until Viktor's spec lands. 72 appears in every design.
  - Don't add bands, colours by value, a formula or point values.
  - Habit ticks and check-in counts never feed it.
- **The lifespan screens are not for build** (K-1b, K-7, K-7c). They carry X–Y placeholders until Viktor's method is in, and the five-year outlook is the fallback.
- **Read numbers from the model or the store.** Don't hard-code them. The canonical persona is Rosa (97 of 100); some older R screens may still show an earlier persona.
- **Age 18+** for the score, outlook, lifespan and health advice. Under 18 gets Mochi, the room, Customize and the quiz.
- **Check-ins confirm once, at the end.** There's no per-answer "Looks right?". The Home check-in button is the `CheckInEntry` widget from #58; mount it, don't rebuild it.
- **Provider names:**
  - The outside-AI provider name comes only from `/api/capabilities` → `personalize.display_name`.
  - Voice is the literal "Cartesia". Make no retention or recording claims for either.
- **The body never signals health.** Body shape and age follow confirmed data only. Experiments and the score never reshape the twin.
- **Accessibility:**
  - Back, Home and close stay pinned.
  - Targets are at least 48pt, text is at least 17px, and contrast meets WCAG AA.
  - Large-text layouts were checked at 1.6×. Also check at 2×.
