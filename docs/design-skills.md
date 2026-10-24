# Design skills for the Figma build

Compiled 2026-10-23 for the session that follows the Figma handoff (`docs/figma-handoff.md`, currently untracked in the main checkout). It lists which skills to load at each build step and where established iOS and accessibility practice conflicts with the handoff.

## 1. Skills by build step

| Handoff step (§9) | Load | Why |
|---|---|---|
| Every canvas write | `figma:figma-use` + `figma:figma-generate-design` | Required by the Figma connector. Covers Plugin API rules, auto-layout and incremental assembly. |
| 1–2. Pages, variables, text styles | `figma:figma-generate-library` | Variable collections, scopes and text styles for a reusable token library. |
| 3–4. Twin and other components | `figma:figma-generate-library`, `design:design-system` | Variant sets and component properties (twin mood/size/skin/hair/top/extra). |
| 5–6. Screens and states | `impeccable` (`ios.md`, `craft-floor.md`, `onboard.md`, `delight.md`), `hackathon-pack/skills/creative-web-worlds` | iOS platform rules, quality floor, first-run flow, playful character without slop. |
| 7. Prototype links and motion | `figma:figma-use-motion`, `impeccable` `animate.md` | Prototype transitions, the 600–800 ms tier crossfade, reduced-motion variant. |
| 8. Review | `design:design-critique`, `design:accessibility-review`, `impeccable` `audit.native.md`, `creative-web-worlds` `craft-review.md` | One batched critique and accessibility pass, then one fix round. |
| Copy | `design:ux-copy` | "Outlook" language, error/unsupported states, the association chip. |
| Handoff to Flutter | `design:design-handoff`, `figma:figma-design-to-code` | Spec sheet for Track C. Figma-to-Flutter is manual, since Figma Make outputs web code. |
| Slides deck (§8) | `figma:figma-use-slides` | The Figma Slides deck the Cal Hacks track requires. |

Not useful here: `taste-skill`, `redesign-skill` and `frontend-design` target web pages and landing sites. The installed `lottie` skill targets HyperFrames video, not the Flutter `lottie` package. `figma-swiftui` is for SwiftUI, but the app is Flutter.

### Repo-local

**Updated on `main` by PR #7:** `creative-web-worlds` now routes mobile and game work to `references/flutter-mobile.md`, `references/playful-game-ui.md`, `references/figma-mobile-workflow.md`, `references/mobile-comparison-gates.md` and `references/mobile-game-source-atlas.md`. These take precedence over the web scroll guidance for LifeTwin, and the build applies them through `docs/design-brief.md` §7a. Key changes:
- The twin lives in a layered habitat rather than on a gradient.
- Each screen shows a small, legible loop.
- Captures cover the stress-size matrix (320×693, 390×844, 430×932, normal and enlarged text).
- Designs are compared against primary references (Finch, Toca Boca, Pok Pok, …).

Before PR #7, `hackathon-pack/skills/creative-web-worlds` was the only design skill in the repo. Its reusable rules: a finite, authored motion sequence rather than identical fade-ups; judging intermediate mobile states, not just endpoints; tap alternatives for every gesture; reduced motion keeping the resolved content; and the review lens in `references/craft-review.md`. Its Pocket Market sample (`hackathon-pack/research/design/`) was rejected for generic typography and flat primitives. The lesson recorded there is to produce the asset and type first, then decorate.

### Online skills

**Installed 2026-10-23** to `~/.claude/skills/` (user scope, markdown and LICENSE only, reviewed before install):

- `motion-design` from LottieFiles/motion-design-skill @ `f9a8a041`. Use with `impeccable` `animate.md` for twin reactions and tier crossfades.
- 14 `hig-*` skills from raintree-technology/apple-hig-skills @ `48bd383b`, a structured index of the Feb 2025 HIG snapshot. The most relevant are `hig-foundations`, `hig-patterns`, `hig-platforms` (iOS, games), `hig-components-controls`, `hig-components-layout` (tab bars) and `hig-components-dialogs` (sheets). The repo's CLI, MCP server and scripts were not installed.

Other candidates found by web search, not installed. Star counts and maintenance are as the pages reported them and have not been independently verified.

| Skill | Publisher | Fit |
|---|---|---|
| [LottieFiles/motion-design-skill](https://github.com/LottieFiles/motion-design-skill) | LottieFiles (official), MIT, markdown only | Timing, easing, emotion-to-motion. Best fit for twin reactions. |
| [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills) `web-design-guidelines` | Vercel (official), MIT | 100+ accessibility and UX rules. Mostly matters if a Flutter web build happens. |
| Flutter official skills ([docs](https://docs.flutter.dev/ai/agent-skills)) | Flutter team | Adaptive layout and routing for Track C, not visual design. Repo name is ambiguous (`flutter/skills` vs `flutter/agent-plugins`). |
| [raintree-technology/apple-hig-skills](https://github.com/raintree-technology/apple-hig-skills) | Small org, MIT | HIG split into 14 skills (Feb 2025 HIG). Take the markdown only. Skip its CLI, MCP server and scripts. |
| [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | Community, MIT | Broad palette, font and UX database. Overlaps impeccable. Runs a Python script, so read it first. |

No good gamification or mascot skill exists. If needed, write a small project skill from the twin rules in the handoff (§4, §6).

## 2. Conflicts between the handoff and best practice

Each one needs Daniel's call before the relevant build step. The handoff wins until then, as impeccable's "the brief wins" rule says.

1. **Two greens fail contrast.** `green-600` `#0E9F6E` is 3.39:1 on white and 2.94:1 on `green-100`. It is used for positive-delta text, which needs 4.5:1 (WCAG 1.4.3). Proposed `green-700` `#047857`: 5.48:1 on white, 4.76:1 on `green-100`. Keep `#0E9F6E` for the Experiment curve and fills.
2. **The baseline curve is just under the non-text minimum.** `#8A97B0` is 2.94:1 on white against the 3:1 of WCAG 1.4.11. `#7A879F` gives 3.62:1 on white and 3.40:1 on mist with almost no visual change.
3. **Fonts vs Dynamic Type.** HIG puts body and controls on SF Pro with Dynamic Type. The handoff uses DM Sans for body text. A custom face is fine for a game-like app in Flutter. Keep DM Sans but size the ramp on iOS text styles: Large Title 34, Title 1 28, Title 2 22, Title 3 20, Headline 17/600, Body 17, Callout 16, Subhead 15, Footnote 13, Caption 12. This also respects the handoff's 12 px floor.
4. **Custom controls.** HIG and impeccable both treat reinvented sliders, steppers and segmented controls as the most common native-app tell. Draw them with iOS anatomy (track, thumb, ± buttons, segmented pill), tinted `blue-600`, rather than new shapes.
5. **Safe areas without a status bar.** The handoff says "no fake status bar". Still reserve the 390 × 844 insets (top 47, bottom 34) so the tab bar and hero don't collide with the Dynamic Island or home indicator in Flutter.
6. **The outlook number vs the hero-metric template.** Impeccable flags big-number-plus-label as a generic scaffold. The handoff already makes the twin the hero and the number secondary, so keep that ordering strict on screen 4.
7. **Dark mode.** HIG treats dark mode as first-class. The handoff is light-only "for now". Build variables with a single Light mode, but structure them so a Dark mode can be added later.

Checked and fine: ink 16.9:1, ink-2 7.1:1 on white and 6.7:1 on mist, white on `blue-600` 5.17:1, ink on `blue-100` 14.0:1, ink on `green-400` 8.8:1. `blue-400` (2.46:1) and `line` are decorative only and must never carry text.
