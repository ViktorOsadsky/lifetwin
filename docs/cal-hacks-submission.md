# Cal Hacks 13 "Idea to Demo" (Figma track) submission drafts

Drafted 2026-10-23 while the layered design build ran. These are drafts for Daniel to edit: minutes and ratings are left as `[fill in]` because they weren't measured. Requirements come from the Figma handoff §8: a demo video of 3 minutes or less, a stage log of 200 words or less per stage, a **Figma Slides** deck (required), embedded Figma files plus the repo link, the file shared with "Anyone", and Edu verification.

## 1. Stage log

### Ideation
**Tool:** Claude Design canvas, then Claude Code with the repo's MASTER_PLAN. **Why:** fast visual exploration of a health-outlook "digital twin". **Minutes:** [fill in]. **Rating:** [fill in]/5.
The first pass was a dark, dashboard-like canvas. We abandoned it for a light, health-reactive world: the healthier the modeled outlook, the more vibrant the twin's background. A lower outlook turns calm and pale, never dark or alarming. The product then shifted from a form-plus-dashboard to a pet game: a mascot-led conversation, a magic-ball fortune, experiments on the twin and a food quiz. The dark canvas is kept as ideation history only.
**How it reached the final project:** the palette direction and the vitality-tier idea survived; the layouts did not.
**Friction:** the early concept read as a medical dashboard, which conflicted with the "curiosity, never fear" goal.

### Prototyping
**Tool:** Figma through the Figma MCP connector in Claude Code. **Why:** the connector was blocked in canvas-attached Claude chats, so we moved to Claude Code, where it can write variables, components and screens directly. **Minutes:** [fill in]. **Rating:** [fill in]/5.
We built foundations first: 60 variables (primitives, semantic colours scoped by use, spacing, radii) and 11 iOS-sized text styles in Bricolage Grotesque and DM Sans. Then components (twin, mascot, magic ball, controls), then the 15-screen flow, a comparison of the original 8-screen handoff, and every error and empty state. Agents built and reviewed in layers. Figma writes ran one at a time, because concurrent writes to one file aren't safe.
**Friction:** two palette greens failed WCAG contrast and were replaced. The original handoff's two-page intake form conflicted with the project rules, so the flow was rebuilt around a mascot conversation.

### Handoff
**Tool:** Claude Code reading the Figma variables and a written brief (`docs/design-brief.md`). **Why:** Figma Make outputs web code, but the app is Flutter, so handoff goes Figma → Claude Code → Flutter. **Minutes:** [fill in]. **Rating:** [fill in]/5.
Every Figma colour variable maps one-to-one to a Flutter `LtColors` token, and text styles map to `LtType`. A final unification pass checked that Figma and Flutter hold identical values.
**Friction:** [fill in after review].

### Code generation
**Tool:** Claude Code agents writing Flutter (Riverpod, go_router, flutter_svg, lottie, health). **Minutes:** [fill in]. **Rating:** [fill in]/5.
Screens, the twin and mascot painters, vitality backgrounds with a reduced-motion fallback, and a working activity log with an Apple Health import. The import computes a 4-week weekly average on the device and sends only that number.
**Friction:** [fill in: device signing, HealthKit capability, anything that failed].

## 2. Demo video script (target 2:45)

| Time | Shot | Voice-over |
|---|---|---|
| 0:00–0:15 | Game room: twin and mascot Pip in a soft "Steady" world | "Meet your twin. LifeTwin turns a longevity model into a game you actually want to open." |
| 0:15–0:45 | Mascot intake: type two answers, the unit clarification, the confirm card | "No forms. Pip asks one thing at a time, checks units, and you confirm every value before it's used." |
| 0:45–1:10 | Magic-ball fortune, then the curve sheet | "Pip reveals your modeled outlook. The numbers are illustrative today, and we always label it 'association, not cause'." |
| 1:10–1:40 | Levers, then Plan, then "Try on twin" | "Which small changes move the model? The plan separates what the model says from what the evidence says." |
| 1:40–2:05 | Experiment: the baseline twin muted and the experiment twin brightening a tier | "Try a change on your twin and watch its world brighten. Your real baseline never moves until you record real measurements." |
| 2:05–2:25 | Activity tab: log a run, then the Apple Health import and its privacy copy | "Activity comes from a quick log or Apple Health. Only a 4-week average ever leaves your phone." |
| 2:25–2:40 | Quiz: a wrong answer makes the twin sick, then recovery | "And the quiz is just a game: wrong answers make your twin sniffle, never your outlook." |
| 2:40–2:45 | Figma file and repo link | "Designed in Figma, built in Flutter." |

Record on the iPhone 13 Pro (or the simulator if signing blocks). Don't show any number as a real prediction.

## 3. Figma Slides deck outline (required)

1. Title: LifeTwin, with the twin and Pip hero.
2. The problem: longevity advice is either scary or abstract.
3. The idea: a twin whose world reacts to modeled health.
4. The product loop: intake → fortune → levers → plan → experiment → quiz.
5. Design system: tokens, vitality tiers, type ramp, contrast fixes.
6. Characters: twin variants, mascot states, guardrails (no body shaming, cosmetics never change numbers).
7. Activity: manual log plus the Apple Health import, and the privacy boundary.
8. Process: the four stages with tools, friction and ratings (from the stage log).
9. Responsible design: illustrative numbers, association-not-cause, no death dates.
10. Demo and links: embedded Figma file, repo, video.

Build it with the `figma:figma-use-slides` skill once the screens are final.

## 4. Lottie milestone reactions (open decision input)

A read-only LottieFiles public search on 2026-10-23 for confetti, heart pulse, sparkles, a crystal ball and floating leaves found mostly untitled uploads with very few downloads. The best candidates:
- [Magic Crystal Ball](https://lottiefiles.com/animations/magic-crystal-ball-X3bO89Mis6): 17 KB, 477 downloads.
- [sparkles](https://lottiefiles.com/animations/sparkles-hSvFKzMnWx): 5 KB, 460 downloads.

None uses our palette, and each would need recolouring and a licence check (the LottieFiles free licence) before use.

**Recommendation:** author our own small set (sparkle burst, heart pulse, magic-ball glow, twin sneeze/recover) in our tokens, and keep Flutter-native animation as the fallback. Third-party assets would be the only off-palette element in an otherwise unified design.

## 5. Not covered by these drafts

- Minutes, ratings and the final friction notes need Daniel's input.
- File sharing ("Anyone") and Edu verification are account actions for Daniel. Changing sharing is an outward-facing setting, so it wasn't done here.
- **App integration follow-up:** the backend already serves `POST /api/onboarding/turn` (mascot intake) and 8 reviewed CDC/FDA quiz questions (`GET /api/quiz/questions`). The current Flutter build uses a local script and sample questions, so wiring those endpoints is the next app task.
