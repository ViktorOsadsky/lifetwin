# UI handover note for Justin's agent, from Daniel

Daniel is handing the LifeTwin UI to Justin. Daniel's design session has stopped all of its UI building, so nothing of Daniel's will edit the Figma file or the Flutter app from now on. That session stays available for UI/UX comments only. Below are Daniel's own design concerns, which the next UI pass should resolve, followed by where the current work stands.

## Daniel's concerns (his words in quotes)

1. **"Way too many words."** "Everything should be super easily understandable and not overwhelming. Remember, the old people are using this."
   - One idea per screen.
   - Titles of 4 words or fewer, and at most one supporting line of 8 words or fewer.
   - Plain everyday words, no jargon (cohort, modeled, baseline…).
   - Explanations go behind a "Why?" tap.
   - Bigger type, and 56 pt or larger primary buttons.
2. **"The sky does not fade seamlessly into the background."**
   - Scenes are full-bleed and dissolve into the page, with no seams.
   - No habitat boxed inside a rounded card.
3. **"Too blocky and bubbly"**, then the hairline-list replacement **"looks worse, too bland."**
   - The target is in between: warm tile rows with large tinted illustrated icons, coloured by category.
   - No stacked cards, no pill chips, and no plain hairline rows either.
   - One filled button per screen.
4. **Health must feel "very friendly",** because these are potentially dark topics.
   - Gentle, encouraging words. Never "risk", "warning" or "you should".
   - Numbers in calm grey, never red or green.
   - A wrong quiz answer gets a kind line from Pip, not a failure state.
5. **"The bottom nav bar is not centered vertically in its box."** The cause is the 34 pt home-indicator area under a 49 pt bar. The proposed fix is an iOS 26-style floating tab bar, with content measured as centred.
6. **"A lot of the assets that are circles are cut off — quality check everything."** A read-only audit found:
   - clipped `shade` ellipses inside the Habitat component's `bush/*` and `tree/canopy` (41 hits);
   - the sun cut off at the top on F2–F6;
   - F1 badge glyphs clipped by 2 pt;
   - Experiment's boxed tiles clipping the scene art.
7. **The twin's body should reflect the user's real data.** In Daniel's words: "the twins should have body shapes that reflect the measurements and data that is provided by the app and wearables and agent conversations." This supersedes his earlier "user-chosen only" ruling. Safeguards, per `docs/design-brief.md` §3:
   - only **confirmed** measurements drive the body;
   - **experiments never reshape it**, so improvements show through the habitat, tier and pose;
   - a few dignified silhouettes with no numbers or labels, every pose and outfit fitting every shape;
   - body shape never signals health.

   Hair, skin, age cues and access aids stay user-chosen. A "That's not quite me" adjustment is recommended, not decided. **This conflicts with `AGENTS.md` and `MASTER_PLAN.md` as written**, so a team doc update is needed before it ships.
8. **Use the provided design skills.** Use the newest `hackathon-pack/skills/creative-web-worlds` from GitHub `main` (flutter-mobile, playful-game-ui, figma-mobile-workflow, mobile-comparison-gates), plus impeccable, hig-* and motion-design. Daniel also liked a **fresh-context critic that scores the UI from 1 to 10, with 8.5 or more needed to move on**.

## Where things stand

- **Rules and specs:** `docs/design-brief.md` on branch `claude/design-handoff-mcp-setup-d0d680` (draft [PR #23](https://github.com/ViktorOsadsky/lifetwin/pull/23)). Items 1–6 above are §7b, §7c, rule 13 and §7d there. The full handoff is in `docs/ui-handoff.md`.
- **References:** `docs/design-references.md`, including §5 on friendly lists and gentle health UI.
- **Figma:** [LifeTwin · Cal Hacks 13](https://www.figma.com/design/HijjDCe1bvFQDlz8upTSWy). Built so far:
  - variables, including Scene tier modes and Character skin tones;
  - components (twin rig, Pip, Habitat);
  - F1–F8.

  **The build was stopped mid-way:** F9–F15 may be partial on the Flow page. None of concerns 1–6 has been applied yet.
- **Flutter:** `app/` on that branch (package `lifetwin`) has every screen, the theme tokens and the habitat, twin and Pip painters. It's a shell to **port into `main`'s `app/` (package `lifesim`)**, which already has Apple Health, Cartesia voice onboarding and the AI-helper consent. Checked after the stop: `app/` is unchanged since the PR #23 commit `247596e`, `flutter analyze` is clean and `flutter test` passes 85/85 (widget tests and goldens only; no simulator or device run).
- **Rules that still hold:**
  - no invented survival numbers (placeholders plus "Example numbers · linked, not proven");
  - cosmetics never tied to health;
  - Apple Health per `docs/apple-health.md`.
