# LifeTwin UI handoff

For whoever picks up the UI next (Justin may take it over). Written 2026-10-23 at about 23:35, while a layered design workflow was still running. Sections marked *pending* will change when it finishes. This follows the handoff template in `AGENTS.md`: PR/merge state, affected contracts, validation, limitations and next dependency.

## 1. Where everything is

| Thing | Location | State |
|---|---|---|
| Figma design | [LifeTwin · Cal Hacks 13](https://www.figma.com/design/HijjDCe1bvFQDlz8upTSWy), in Daniel's drafts (student team) | **Not shared yet.** Daniel has to share it or move it to a team project. |
| Design source of truth | `docs/design-brief.md` | Uncommitted on branch `claude/design-handoff-mcp-setup-d0d680` |
| Skill routing | `docs/design-skills.md` | Uncommitted |
| References to model from | `docs/design-references.md` (§1–4 inclusive avatars, health characters, cozy game UI, intake; §5 friendly lists and gentle health UI) | Uncommitted |
| Cal Hacks submission drafts | `docs/cal-hacks-submission.md` (stage log, demo script, Slides outline) | Uncommitted |
| Flutter game shell | `app/` in this worktree (package `lifetwin`) | Uncommitted. **Conflicts with `app/` on `main`** (see §4). |
| Original handoff (stale) | `~/lifetwin/docs/figma-handoff.md`, untracked in Daniel's main checkout | Superseded by the brief |

Nothing from this work is committed, pushed or in a PR. The branch is 39 commits behind `main`.

## 2. Decisions already made (don't relitigate)

- **Structure follows MASTER_PLAN,** not the old 8-screen handoff. That means a game room, mascot conversation intake (voice and text), magic-ball fortune, levers, plan, experiment, quiz, studio and activity, in 15 screens plus states. The old 8 screens exist on the Figma page "Flow · handoff v1" as reference only.
- **Light, health-reactive look.** The twin **lives in a habitat**. Four vitality tiers are four modes of the Figma **Scene** variable collection (Thriving / Good / Steady / Resting). Low tiers are restful, never sad or dark.
- **Twin body (Tier-1 ruling, Daniel, 2026-10-23, option A):** body shape, height, age cues, hair, facial hair and access aids are **user-chosen in Studio only**, never derived from or changed by weight, BMI or any health data.
- **Activity:** manual log plus the Apple Health import. **Apple Health follows `docs/apple-health.md` on `main`:** raw 30-day samples go to the AI agents through the server, with device names removed.
- **Owner feedback is binding** (brief §7b):
  - seamless scenes, with no seam or boxed habitat;
  - plain hairline lists, not stacked cards;
  - one filled button per screen;
  - numbers in calm grey, never red or green;
  - gentle, encouraging health copy;
  - at most two corner radii per screen;
  - an iOS 26-style **floating tab bar with its content centred**.
- **Fewer words, built for older adults** (brief §7c, which overrides §7b where they conflict): one idea per screen, titles of 4 words or fewer, explanations behind a "Why?" tap, bigger type, and lists as warm tile rows (large tinted illustrated icons), neither bland hairlines nor bubbly cards.
- **No invented numbers.** Prediction is deferred, so every outlook figure is a placeholder (`[xx.x %]`, `[± x.x pts]`) with an "Illustrative — model not connected" note and "Modeled association, not cause".

## 3. Design system (Figma)

- **Variables:**
  - Primitives;
  - Color (semantic, Light mode);
  - Spacing, Radius;
  - **Character** (5 realistic skin tones, 5 hair colours, cheek, line, eye-shine);
  - **Scene** (7 habitat colours × 4 tier modes).
- **Styles:** 11 text styles on iOS sizes (Bricolage Grotesque display, DM Sans UI), plus effect styles `Shadow/Card` and `Shadow/Sheet`.
- **Components:**
  - Twin: a rig with 6 moods × 3 sizes, moods change the pose, and looks are exposed through nested instances;
  - Pip (the mascot), the magic ball, and Habitat (Room and Compact aspects);
  - organ badges, buttons, inputs, tab bar, outlook, curve, lever, plan, chips, speech bubble, workout row, week chart, sheet, game-health meter.
  - *Pending:* the surfaces pass adds List row, Section header, Section footnote and Rising sheet, and turns cards into list rows.
- **Pages:** Cover, Foundations, Components, Flow (F1–F15), Flow · handoff v1, States, Stage log. F1–F8 are built. *Pending:* F9–F15, the handoff-v1 page, states and the surfaces rework.

## 4. Flutter app and the main conflict

- **This worktree's `app/` (package `lifetwin`)** has:
  - every screen, the theme tokens (`LtColors`, `LtScene`, `LtCosmetics`), go_router tabs and Riverpod state;
  - painters for the twin, Pip and the habitat;
  - an activity log, and a 42-case stress-size capture matrix (320×693, 390×844, 430×932 at 1.0× and 1.6× text).

  The last finished pass reported analyze clean and **69 tests passing**. It has never run in a simulator or on a device.
- **`main`'s `app/` (package `lifesim`)** has Track C's real pieces: the Apple Health importer (`lib/health/`), **Cartesia voice onboarding** (`lib/onboarding/`, `lib/voice/`), iOS signing and HealthKit entitlements for team `A5C3J42JT3`, and CocoaPods. Open **PR #20** adds the AI helper consent screen and fixes the Health-to-conversation handoff.
- **Next step: port, don't merge.** Move this worktree's game shell, theme, widgets and screens into `main`'s `lifesim` app:
  - Use `main`'s `lib/health/` importer in place of ours.
  - Host `main`'s voice onboarding as the intake screen.
  - Keep `main`'s iOS config.
  - Update package imports (`package:lifetwin/` → `package:lifesim/`) and merge the pubspec dependencies (ours adds flutter_riverpod, go_router, flutter_svg and lottie, plus bundled fonts).
  - Then run `cd app && flutter analyze && flutter test`.

## 5. How quality is gated

- **Skill gate:** every design or Flutter agent must load its named skills (impeccable, hig-*, motion-design, design:*, figma:*) and read the newest `creative-web-worlds` mobile references from GitHub `main`, then report `skills_loaded`.
- **Critic gate:** a fresh-context critic scores Figma and Flutter separately from 1 to 10 against a weighted rubric with evidence. **8.5 or more with no blockers passes.** Below that, an edit pass applies the critic's fixes and a new critic re-scores, for up to 4 rounds, followed by unification and a final independent score.
- *Pending:* the actual scores. The workflow script is `~/.claude/projects/-Users-dqi26-lifetwin--claude-worktrees-design-handoff-mcp-setup-d0d680/6ec8a244-d0fe-48a1-94e6-6c5d1318288d/workflows/scripts/lifetwin-layered-design-build-wf_eb1656d4-988.js`.

## 6. Validation actually run

- **Flutter:** `dart format`, `flutter analyze` and `flutter test`, run by the build agents: 69 tests passing on the last finished pass.
- **Figma:** structural audits found every colour bound to a variable and every text node using a text style on the built pages. Screenshots were reviewed for the Cover, components and F1–F8.
- **Not run:**
  - simulator or device runs;
  - screen-reader testing;
  - clicking through the prototype links (they count as *proposed*);
  - checking that the backend's real quiz bank and onboarding endpoints are wired into the app (they aren't yet).

## 7. Contracts

None changed by this work. The open dependencies are Track B's: the `apple_health_samples.v0` route, and PR #20's additive `conversation.request` change.

## 8. Open items

1. Share the Figma file with the new owner, or move it to a team project.
2. Commit this branch, then do the port into `main`'s app described in §4.
3. Wire the backend quiz bank (v2, 8 reviewed questions) and the `/api/onboarding/turn` intake into the app, replacing the local sample questions and script.
4. Build the Cal Hacks Figma Slides deck from `docs/cal-hacks-submission.md` §3. Add the stage-log minutes and ratings.
5. Lottie: author our own milestone set in our palette (see the submission doc §4).
6. Vitality tier source (API field vs app mapping) is still open with Track B.
