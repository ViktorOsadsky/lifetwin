# LifeTwin: Figma design handoff

For the Claude Code session that builds the first full Figma draft. Daniel reviews in Figma and requests edits from there.

## 0. Start here

- Repo: `~/lifetwin` (GitHub `ViktorOsadsky/lifetwin`).
- Read first, in order:
  1. This doc.
  2. `MASTER_PLAN.md` on branch `codex/master-agent-guide` (PR #2, unmerged). It holds the game direction. Read it with `git show origin/codex/master-agent-guide:MASTER_PLAN.md`; don't merge, since PR #2 also deletes `docs/`.
  3. `docs/tracks/C-flutter-app.md` and `docs/prd-reconciliation.md`.
  4. `contracts/fixtures/*.json` for every number shown in the designs.
- Figma connector (Claude Code): `claude mcp add --transport http figma https://mcp.figma.com/mcp`, then sign in with the Stanford Figma account. Load the `figma-use` and `figma-generate-design` skills before any canvas write.
- Create the file in Daniel's Stanford team. Name: `LifeTwin · Cal Hacks 13`.
- **Superseded:** the dark palette in `projectspec.md` §11 and the dark first-pass Claude Design canvas. The look is now light (section 3). That canvas is ideation history only; log it as such.

## 1. Product in one line

A playful digital twin that shows your modeled longevity outlook, lets you test lifestyle changes on the twin, and turns the promising ones into a researched plan. It aims for curiosity, never fear.

## 2. Structure (revised)

Order follows the MASTER_PLAN product loop. Tabs: **Twin · Levers · Plan**. The Lab and Studio open from inside the flow.

| # | Screen | Purpose | Key content |
|---|---|---|---|
| 1 | Meet your twin | Hook in 10 s | 6 preset twins to pick; "Use a sample profile" link |
| 2 | Profile: basics | Inputs | Age, sex, height, weight, **imperial/metric toggle** (API wants metric), progress 1 of 2 |
| 3 | Profile: habits | Inputs | Sleep slider, active minutes stepper, smoking segmented (Never/Former/Current), drinks stepper, progress 2 of 2. Twin reacts live |
| 4 | Twin (home) | Baseline | Twin as hero with organ badges (lungs, sleep, move); 10-year outlook (big but secondary to the twin); 20-year; similar people; collapsible curve; label "Modeled association, not cause"; primary CTA "Explore levers" |
| 5 | Levers | Sensitivity search | Ranked single bounded changes (e.g. "Sleep +1 h"), each with a signed pts result or "No modeled effect" / "Uncertain"; CTA "Research a plan" |
| 6 | Plan | Researched plan | 3 ranked items, each with **Model** row and **Evidence** row (`[SOURCE]` placeholders), buttons "Try on twin" and "Skip"; follow-up question input |
| 7 | Lab | Experiment | Baseline twin (muted) vs experiment twin (vibrant); overlaid curves; signed deltas; **editable** input rows; "Reset"; separate "Record real measurements" |
| 8 | Twin studio | Cosmetics | Tabs Skin / Hair / Top / Extras; note "Looks never change your numbers"; reached by tapping the twin |

**States to design (one frame each):** loading (twin "thinking"), unsupported profile (`status: "unsupported"` shows `limitation.message`, no curve), under-18 / out-of-range age (fixtures `predict_minor.json`, `predict_age_out_of_range.json`), API error, empty plan.

**"Try on twin" flow:** tapping it on a Plan item first shows a sheet with the assumed input change ("Active minutes: 30 → 180 / week"). Confirm, then the Lab opens with that change applied. It never asserts weight or lab changes.

## 3. Visual direction: light, alive, health-reactive

**Core idea:** the background is the twin's world. The healthier the modeled outlook, the more vibrant and alive the world gets. A lower outlook makes it calmer and paler, **never dark, grey-red or alarming**.

### Base palette

| Token | Hex | Use |
|---|---|---|
| `white` | `#FFFFFF` | Cards, sheets |
| `mist` | `#F4F8FF` | App ground (lowest tier) |
| `ink` | `#0E1B3D` | Primary text (navy, not black) |
| `ink-2` | `#4A5878` | Secondary text (≥ 4.5:1 on white) |
| `line` | `#E3EAF5` | Dividers, card borders |
| `blue-600` | `#2563EB` | Primary buttons, links, "You" curve |
| `blue-400` | `#5AA9FF` | Highlights, sky |
| `blue-100` | `#DCEBFF` | Chips, selected states |
| `green-600` | `#0E9F6E` | Positive deltas text, "Experiment" curve |
| `green-400` | `#34D399` | Vitality, success fills |
| `green-100` | `#D3F7E6` | Positive chips |
| `baseline` | `#8A97B0` | Baseline / similar-people curve (dashed) |
| `sun` | `#FFD66B` | Small accents only: sparkles, milestone reactions |

- White text only on `blue-600` or darker. Navy text everywhere else.
- Deltas use sign plus color plus an icon, never color alone.

### Vitality backgrounds (the health-reactive layer)

Four tiers. Each is a soft gradient layer behind content; cards stay white so text contrast never depends on the tier.

| Tier | Name (shown) | Background | Ambient detail |
|---|---|---|---|
| 4 | Thriving | Vivid mesh: `#34D399` → `#5AA9FF` → `#FFFFFF`, saturated | Floating leaves or sparkles, sunlight bloom, twin bounces |
| 3 | Good | Fresh blue-green: `#BFF0DA` → `#CFE6FF` → `#FFFFFF` | Light drifting particles |
| 2 | Steady | Pale sky: `#E3F0FF` → `#F4F8FF` | Still, gentle |
| 1 | Resting | Soft lavender-mist: `#ECEBFA` → `#F4F8FF` | Still. Twin calm, not sad |

- **Tier source (open decision for Track B):** preferably the API returns a `vitality_tier` (1 to 4) derived server-side, keeping the rule that the app computes no health numbers. Fallback: map from `prediction.survival_10_year` vs the cohort curve at 10 years. Pick one and log it.
- **Lab:** the baseline side shows its tier, the experiment side its own tier, so a better scenario visibly brightens. This is the demo's "wow" moment.
- Tier changes animate as a 600 to 800 ms crossfade. Reduced motion means an instant swap with no particles.
- The background must never be the only signal. The tier name and the numbers stay visible.

### Type

- Display: **Bricolage Grotesque** 700/800 (headlines, big numbers, tabular figures).
- Body/UI: **DM Sans** 400/600/700.
- Minimum 12 px everywhere. The "Modeled association, not cause" chip is 12 px or larger.

### Shape and spacing

- Radii: cards 24, controls 22 (pills), chips 999.
- Spacing scale: 4, 8, 12, 16, 20, 24, 32. Screen side padding 20.
- Touch targets ≥ 44 px.
- Device frame: iPhone 390 × 844. No fake status bar.

## 4. Components to build (as Figma components with variants)

- **Twin**: original flat-vector character, built from layers so parts swap. Variants: `mood` = happy / calm / tired / thinking; `size` = S 56, M 120, L 240. Properties: skin (5 tones), hair style (short / bob / curly) and color (5), top color (5), extra (none / glasses / headband). Geometry reference: `Twin.dc.html` in the first-pass canvas: head circle r50, cheeks, round body, simple stroke eyes and mouth.
- **Organ badge**: lungs, sleep (moon), move (pulse), heart (reserved). States neutral / positive / attention (attention = blue, never red).
- **Outlook stat**: big number, label, sublabel.
- **Curve chart**: You (blue-600, 3 px), Similar people (baseline, dashed), Experiment (green-600), 10-year marker, axis 50 to 100 %, x 0 to 20 years. Collapsed and expanded.
- **Lever card**: change label, signed result, state = positive / none / uncertain.
- **Plan item**: rank, title, Model row, Evidence row, Try on twin / Skip, states open / added / skipped.
- **Input rows**: slider, stepper, segmented control, unit toggle.
- **Buttons**: primary (blue), positive (green), secondary (white plus border), ghost. States default / pressed / disabled / loading.
- **Tab bar**: Twin, Levers, Plan.
- **Chip**: "Modeled association, not cause", tier name, delta.
- **Vitality background**: 4 variants (tiers).

Use variables for every color, radius and spacing token above. Mode: Light only for now.

## 5. Content and numbers (from fixtures, never invented)

Demo profile = `compare_demo_futures.json` request `a`: 45, male, 165 cm, 68 kg, sleep 5 h, 30 active min/week, current smoker, 3 drinks/week, diet quality 2.

| Shown | Value | Source |
|---|---|---|
| Baseline 10-year | 84.8 % | compare `a.prediction.survival_10_year` |
| Baseline 20-year | 67.6 % | compare `a.prediction.survival_20_year` |
| Similar people 10-year | 93.6 % | compare `a.cohort_curve[10]` |
| Experiment 10-year / 20-year | 94.7 % / 87.9 % | compare `b.prediction` |
| Deltas | +9.9 pts at 10 y, +20.3 pts at 20 y | compare `differences` |
| Risk factor order | smoking, sleep, exercise, weight | compare `a.risk_factors` |
| Experiment changes | Smoking Current → Never; Sleep 5 → 8 h; Active 30 → 180 / week; Diet "Not used by this model" | compare `b` request, `ignored_fields` |
| Advisor answer | Smoking is the largest modeled factor; association, not guaranteed effect | `advisor_what_first.json` |
| Lever results | `[± x.x pts]` placeholders | No fixture yet (sensitivity endpoint not built) |
| Evidence | `[SOURCE]` placeholders | Track D curates |

Curves: plot all 21 yearly points from the fixture arrays.

## 6. Guardrails (from MASTER_PLAN and spec §15)

- No death dates or countdowns. Say "outlook", never "you will die by".
- No body shaming. The twin's body never changes with weight.
- Cosmetics never affect predictions, and the UI says so.
- "Modeled association, not cause" stays visible wherever numbers appear.
- Plan items never claim a numeric benefit without a supported model input.
- The baseline only changes via "Record real measurements".

## 7. Figma file layout

Pages:
1. **Cover**: title, one-line pitch, link to repo.
2. **Foundations**: color variables, vitality tiers, type ramp, spacing, radii.
3. **Components**: section 4.
4. **Flow**: screens 1 to 8 in a row, with prototype links wired (tabs, CTAs, Try on twin → sheet → Lab).
5. **States**: loading, unsupported, minor, error, empty plan; plus each Lab tier pairing.
6. **Stage log**: notes per stage (below).

## 8. Figma track requirements (Cal Hacks "Idea to Demo")

- The Figma file is shared with **"Anyone"** and you are **Edu verified**.
- Deliverables: demo video (≤ 3 min), stage log (≤ 200 words per stage), **Figma Slides** deck (required), embedded Figma files plus repo link.
- Stage log per stage (Ideation, Prototyping, Handoff, Code generation): tool used and why, minutes spent, rating 1 to 5, how the output reached the final project, and friction or dead ends.
- Record honestly as you go:
  - Ideation: first-pass dark canvas in Claude Design, abandoned for the light direction.
  - The Figma connector was blocked in canvas-attached Claude chats, so you moved to Claude Code.
  - Figma Make outputs web code while the app is Flutter, so handoff goes Figma → Claude Code → Flutter.
- Make one git commit per Figma build step and per handoff step, so the path is traceable.

## 9. Build order for the Claude Code session

1. Inspect the new file; create pages.
2. Variables (colors, spacing, radii) and text styles.
3. Twin component and variants. Get Daniel's sign-off on the twin before mass use.
4. Remaining components.
5. Screens 4 (Twin home) and 7 (Lab) first: they carry the demo.
6. Screens 1, 2, 3, 5, 6, 8, then states.
7. Prototype links.
8. One screenshot per screen; fix clipping and overlap; stop.

## 10. Open decisions

- Vitality tier source: API field vs app mapping (section 3).
- Twin art direction sign-off (proportions, outline or no outline on light backgrounds).
- Whether Lottie (connector available) is used for milestone reactions such as confetti or a heart pulse. The twin itself stays an original vector.
- Deployed-URL requirement: is a Flutter web build needed (`docs/prd-reconciliation.md`, open item)?
