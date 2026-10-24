# LifeTwin unified design brief

The single source for every design and Flutter build agent, compiled 2026-10-23. It reconciles `docs/figma-handoff.md` (untracked in the main checkout) with `MASTER_PLAN.md` and `AGENTS.md`. Where they disagree, MASTER_PLAN and AGENTS win. Skill routing is in [design-skills.md](design-skills.md).

Figma file: `LifeTwin · Cal Hacks 13`, <https://www.figma.com/design/HijjDCe1bvFQDlz8upTSWy>.

## 1. Guardrails (non-negotiable)

- No death dates, countdowns or "you will die by". Say "outlook".
- **No invented numbers.** Prediction is deferred and the survival fixtures were removed from `main`. Every survival figure, delta or curve uses a visible placeholder (`[xx.x %]`, `[± x.x pts]`) plus an "Illustrative — model not connected" chip. Curves are drawn as obviously schematic placeholder shapes.
- "Modeled association, not cause" is visible wherever outlook numbers appear.
- No body shaming. The twin's body never changes with weight. Cosmetics never change numbers, and the UI says so.
- Quiz/game health is separate from medical inputs. A wrong answer changes only game health and the twin's sick/recovery reaction.
- The baseline changes only through **Record real measurements**.
- No traditional multi-page intake form in the primary flow. Intake is a mascot conversation with voice (Cartesia, hold-to-talk, consent first) and an always-available type option.
- No red, grey-red, dark or alarming "bad" states. Attention uses blue.
- Deltas always use a sign and an arrow icon, never colour alone. The number text stays calm `ink-2`; only the arrow may be tinted (§7b).
- Do not copy Talking Tom or Apple Activity rings. Ring-like progress must not imitate Move/Exercise/Stand rings.

## 2. Unified tokens

These are the only colours. Figma binds every fill/stroke/text to a variable; Flutter reads them from one `LtColors` theme extension. No raw hex outside the token file.

### Colour

| Token | Hex | Use | Contrast |
|---|---|---|---|
| `surface` | `#FFFFFF` | Cards, sheets | — |
| `ground` | `#F4F8FF` | App ground (mist) | — |
| `ink` | `#0E1B3D` | Primary text | 16.9:1 on white |
| `ink-2` | `#4A5878` | Secondary text | 7.1:1 white, 6.7:1 ground |
| `line` | `#E3EAF5` | Dividers, borders (decorative only) | — |
| `blue-600` | `#2563EB` | Primary buttons, links, tint, "You" curve | white text 5.17:1 |
| `blue-400` | `#5AA9FF` | Sky, highlights (never text) | — |
| `blue-100` | `#DCEBFF` | Chips, selected states | ink 14.0:1 |
| `green-700` | `#047857` | **Positive delta text**, positive chip text | 5.48:1 white, 4.76:1 on green-100 |
| `green-600` | `#0E9F6E` | Experiment curve, positive fills/icons (never small text) | — |
| `green-400` | `#34D399` | Vitality, success fills (ink text on it 8.8:1) | — |
| `green-100` | `#D3F7E6` | Positive chips | — |
| `baseline` | `#7A879F` | Baseline / similar-people dashed curve | 3.62:1 white |
| `sun` | `#FFD66B` | Sparkles, milestone reactions only | — |
| `lavender-100` | `#ECEBFA` | Resting tier, calm surfaces | — |
| `blue-700` → `action/primary-pressed` | `#1D4ED8` | Pressed primary button | white 6.7:1 |

### Vitality tiers are a habitat, not a gradient (revised 2026-10-23)

Per the updated `creative-web-worlds` skill (`references/playful-game-ui.md`), the twin **inhabits a place**: a small garden/meadow habitat with foreground, midground and background, a clear ground (contact) plane with a contact shadow under the twin, and one light direction (upper left). Do not float the twin on a gradient behind rounded cards.

The tier changes the habitat through the Figma **Scene** collection, which has one mode per tier (Thriving / Good / Steady / Resting). A habitat frame sets its explicit variable mode, and the experiment vs baseline comparison is the same habitat in two modes.

| Tier | Mode | Habitat character |
|---|---|---|
| 4 | Thriving | Saturated sky, lush foliage, warm sun bloom, a few sparkles; twin upright and bouncy |
| 3 | Good | Fresh sky, healthy foliage, soft light, gentle drifting particles |
| 2 | Steady | Pale sky, quiet foliage, still air |
| 1 | Resting | Lavender-mist sky, muted foliage, calm dusk light; twin calm and resting, **never sad, dark, grey-red or wilted** |

Scene tokens: `scene/sky-top`, `scene/sky-bottom`, `scene/ground`, `scene/foliage`, `scene/foliage-deep`, `scene/light`, `scene/contact-shadow`. Palette roles stay separate: **frame surfaces** (white/ground cards and sheets), **scene colour** (Scene collection), **actions** (blue), **selection** (blue-100 plus a visible change on the selected object). Reserve the most contrast and saturation for the twin, the relevant needs and the next useful action, and let the scenery recede.

The tier name is always shown as a chip, so the habitat is never the only signal. Tier changes crossfade 700 ms (`easeOutCubic`); reduced motion swaps instantly with no particles or bobbing.

### Character colours (cosmetic only)

Figma **Character** collection: realistic, inclusive skin tones `char/skin/1…5` (`#F6D7C3`, `#E8B894`, `#C98E64`, `#8D5A3B`, `#5A3825`), hair `char/hair/black|brown|auburn|blonde|silver`, plus `char/cheek`, `char/line` (= ink) and `char/eye-shine`. Top colours reuse brand tokens. These never feed any number. Flutter mirrors them in `lt_cosmetics.dart`.

### Type (iOS text-style sizes, brand faces)

Display: **Bricolage Grotesque**. UI/body: **DM Sans**. Tabular figures for numbers.

| Style | Font | Size/line | Weight |
|---|---|---|---|
| Large Title | Bricolage | 34/41 | ExtraBold |
| Title 1 | Bricolage | 28/34 | Bold |
| Title 2 | Bricolage | 22/28 | Bold |
| Title 3 | DM Sans | 20/25 | SemiBold |
| Headline | DM Sans | 17/22 | SemiBold |
| Body | DM Sans | 17/22 | Regular |
| Callout | DM Sans | 16/21 | Regular |
| Subhead | DM Sans | 15/20 | Regular |
| Footnote | DM Sans | 13/18 | Regular |
| Caption | DM Sans | 12/16 | Medium |
| Stat XL | Bricolage | 56/60 | ExtraBold, tabular |

Nothing below 12. Flutter applies `MediaQuery.textScaler` so Dynamic Type scales these.

### Shape, space, layout

- Radii: card 24, sheet 28 (top corners), control 22 (pill), chip 999, small 12.
- Spacing: 4, 8, 12, 16, 20, 24, 32, 40. Screen side padding 20.
- Touch targets ≥ 44 × 44.
- Frame: iPhone 390 × 844. No drawn status bar, but reserve safe areas: top 47, bottom 34. Tab bar 49 + bottom inset.
- Shadows: `0 8 24 rgba(14,27,61,0.08)` for cards; `0 -4 24 rgba(14,27,61,0.10)` for sheets. No zero-offset glows.
- Icons: one stroke family, 2 px stroke, round caps, 24 grid. Original SVG (no emoji, no web icon fonts).

## 3. Characters

- **Twin** (the user's avatar): original flat vector built from swappable layers. Head circle r50 at M size, cheeks, round body, simple stroke eyes and mouth, no outline on light backgrounds (soft shadow instead). Variants: `mood` happy / calm / tired / thinking / sick / recovering; `size` S 56, M 120, L 240. Properties: skin (5), hair style short / bob / curly × colour (5), top colour (5), extra none / glasses / headband.
- **Twin body reflects the user's data (Tier-1 ruling by Daniel, 2026-10-23, superseding the earlier "user-chosen only" ruling A):** the twin's **body shape and height follow the user's confirmed measurements and data**: height and weight confirmed in the conversation or the Apple Health read-back, plus wearable data, through the agent conversation. Safeguards:
  1. **Only confirmed values** drive the body, never drafts, guesses or unconfirmed wearable readings. It changes only through the same explicit confirm or "Record real measurements" path as the baseline.
  2. **Experiments and plans never reshape the body.** The experiment twin keeps the baseline body; a better scenario shows through the habitat tier, energy and pose. That keeps "thinner = healthier" out of the Lab.
  3. **A small set of dignified, equally well-drawn silhouettes**, mapped from the measurements with no numbers, BMI or labels ("overweight", etc.) ever shown on the twin or in Studio. Every mood, pose and outfit fits every shape.
  4. **Body shape never signals health.** Health shows only through the habitat and tier, and the twin is drawn with the same care, joy and energy at every size.
  5. Age cues, hair, facial hair, skin tone and access aids stay **user-chosen in Studio**.
  6. *Recommended, not yet decided:* a gentle "That's not quite me" adjustment in Studio, one step either way, for when the data-derived shape feels wrong.

  ⚠ This conflicts with `AGENTS.md` and `MASTER_PLAN.md` as written ("no body shaming", "visual claims that a heavier/lighter avatar is inherently healthier", cosmetics kept separate from health inputs). Those team docs need an agreed update before this ships.
- **Mascot** (the guide, "Pip"): small round orb-creature with a leaf sprout, `blue-400` → `green-400` body, holds the magic ball in the fortune scene. States: idle, listening, thinking, speaking, celebrating. Clearly a different silhouette from the twin.
- **Magic ball**: glass sphere, `blue-100` inner glow, sparkles in `sun`.

## 4. Screens

### Primary flow (MASTER_PLAN), page "Flow"

Navigation: a game-room shell with minimal chrome. A bottom tab bar has 3 sections: **Room · Plan · Activity**. Fortune, Experiment, Quiz and Studio open from the room as full-screen modes or sheets.

| # | Screen | Key content |
|---|---|---|
| F1 | Game room | Twin (L) in the vitality world, mascot beside it with a speech bubble, props as entry points: magic ball (Fortune), lab flask (Experiment), quiz card (Quiz), mirror (Studio). Tier chip. |
| F2 | Mascot intake (conversation) | **Voice is real now** (main PR #19, Cartesia). First a consent card from Pip, "Talk with me?": voice goes to Cartesia only while the Talk button is held, recordings aren't kept, and you can type at any time. Buttons `Yes, I can talk` / type instead, plus "Use my Health app instead". Then the conversation: mascot and user bubbles with a live caption ("Hearing: …" / "You said: …"), a large hold-to-talk button (Talk / Stop listening), "Hear it again", a Talk/Type switch, one question at a time, unit clarification ("Is that cm or inches?"), progress dots. Match main's `app/lib/onboarding/voice_onboarding_screen.dart` copy. **AI helper consent** (open PR #20, likely to merge): after the voice question, a second short screen asks "Turn on the AI helper?" with a primary `Yes, turn it on` and a `Not now` that works fully. A small visible on/off switch for the helper stays in the conversation. When an answer needs the helper, a large `Yes, let the AI helper read it` button turns it on and re-sends the same answer. Consent screens must fit above the fold at 390×844, with their buttons visible without scrolling. Apple Health answers, once confirmed, move the conversation on. |
| F3 | Confirm your answers | Compact editable summary card of the extracted fields (age, sex, height, weight, sleep, activity, smoking, drinks). Each row is editable. "Looks right" primary button. |
| F4 | Magic-ball fortune | Mascot and magic ball reveal; outlook stat (placeholder) secondary to the scene; supported horizons 10 y / 20 y; "See the curve" detail sheet; association chip; illustrative chip. |
| F5 | Levers | Ranked bounded single changes ("Sleep +1 h", "Active +60 min/wk"), each `[± x.x pts]` or "No modeled effect" / "Uncertain"; CTA "Research a plan". |
| F6 | Plan | 3 ranked items, each with Model row + Evidence row (`[SOURCE]`), "Try on twin" / "Skip"; follow-up input. |
| F7 | Try-on sheet | Shows the assumed input change ("Active minutes: 30 → 180 / week"), Confirm opens Experiment. |
| F8 | Experiment / compare | Baseline twin (muted, own tier) vs experiment twin (vibrant, own tier); overlaid schematic curves; signed deltas; editable input rows; Reset; separate "Record real measurements". |
| F9 | Quiz arena | Question card, 3–4 answer choices, game-health meter (hearts), twin reacts. |
| F10 | Quiz feedback | Wrong answer: twin "sick" (pale green tint, droopy sprout, thermometer), explanation, "Help it recover" → review. Correct answer: sparkle recovery. Label "Game health only — your outlook didn't change". |
| F11 | Twin studio | Tabs Skin / Hair / Top / Extras; "Looks never change your numbers". |
| F12 | Activity log | Weekly summary card (4-week average active min/week, source chip "Manual" / "Apple Health"), week bar chart (schematic), list of workouts (type icon, duration, intensity, date), "+ Log workout", "Import from Apple Health" row. |
| F13 | Log workout sheet | Type segmented (Walk / Run / Cycle / Swim / Strength / Other), duration stepper, intensity segmented (Light / Moderate / Vigorous), date picker row, Save. |
| F14 | Apple Health import | Follows `docs/apple-health.md` on `main` (PR #12; user rulings 2026-10-24). Intro screen: read-only, never writes to Health, no clinical records. It says plainly that **readings are sent to LifeTwin's AI assistant through LifeTwin's server, with device names removed**. Suggested answers come from height and weight (latest within 1 y), exercise minutes (28-day weekly average), sleep (median of 14 nights, needs 3 or more) and blood pressure (average of the last 3 within 90 days). Each is **read back in plain words** with "Is this accurate?" and three buttons: `Yes, that's right` / `No, let me fix it` / `Go back`. Unconfirmed items go back to the mascot conversation. Tracker data (steps, active energy, workouts, resting HR) feeds the twin only and stays separate from the confirmed profile. US users see ft/in/lb. |
| F15 | Record real measurements | Sheet listing the confirmed inputs that would change the baseline, each with its source chip (Conversation / Manual log / Apple Health) and date or averaging period (provenance stays on the phone). Activity row offers "Use Apple Health (28-day average)" or "Use manual log". Explicit confirm. |

### Secondary page "Flow · handoff v1"

The original 8 handoff screens (Meet your twin, Profile basics, Profile habits, Twin home, Levers, Plan, Lab, Studio), built from the same components, for comparison. Frame label: "v1 handoff structure — the two-page form conflicts with AGENTS.md; reference only".

### States page

Loading (twin "thinking" + mascot thinking), unsupported profile (`limitation.message`, no curve), under-18, age out of range, API error, empty plan, empty activity log, Apple Health permission denied (manual log stays fully usable), voice unavailable or microphone denied (typing stays fully usable). Plus the Lab tier pairings (1→2, 2→3, 3→4).

## 5. Components (page "Components")

Twin, Mascot, Magic ball, Organ badge (lungs, sleep, move, heart; neutral / positive / attention), Outlook stat, Curve chart (collapsed/expanded, placeholder), Lever card, Plan item (open/added/skipped), Input rows (slider, stepper, segmented, unit toggle, text field), Buttons (primary blue, positive green, secondary, ghost × default / pressed / disabled / loading), Tab bar (Room / Plan / Activity), Chip (association, illustrative, tier, delta, source), Speech bubble (mascot / user), Workout row, Week bar chart, Vitality background (4 tiers), Sheet (grabber, title, close), Game-health meter.

## 6. Figma file layout

Pages: Cover · Foundations · Components · Flow · Flow · handoff v1 · States · Stage log.

## 7a. Mobile and game craft rules (updated skills on `main`, PR #7)

Read these from the read-only `main` checkout at `/private/tmp/claude-503/-Users-dqi26-lifetwin--claude-worktrees-design-handoff-mcp-setup-d0d680/6ec8a244-d0fe-48a1-94e6-6c5d1318288d/scratchpad/main-ro/hackathon-pack/skills/creative-web-worlds/`: `SKILL.md`, `references/playful-game-ui.md`, `references/flutter-mobile.md`, `references/figma-mobile-workflow.md`, `references/mobile-comparison-gates.md`, `references/mobile-game-source-atlas.md`, `references/craft-review.md`.

- **A small, legible loop on every game screen:** current state + useful choice + visible consequence, close together. A care or quiz action changes the twin's pose or state locally, not a distant toast or snackbar. One next useful action is easier to find than the secondary ones.
- **Character first:** test the twin's and Pip's silhouette and face at final phone size before adding particles or HUD. Personality comes from pose, asymmetry and one small prop. Twin and Pip must stay distinct silhouettes.
- **Controls and art are related layers:** one icon stroke, edge, radius and shadow family. Status chips, primary buttons and world props differ in depth to set hierarchy. Pressed buttons move their face inside a stationary hit region.
- **Pickers (studio, workout type):** the chosen object fills enough of its tile to recognise. Selection shows on the changed object as well as its control, with a live preview kept readable.
- **No dead bands** between the stage and controls on tall screens. No filler captions, placeholder stats or decorative cards.
- **Compare against primary references** from `mobile-comparison-gates.md` (Finch, Rooms, Crouton, Toca Boca, Pok Pok, Rytmos) at the same phone width. Name the largest visible gap and fix that first. No invented scores.
- **Figma:** keep twin, face, props and habitat as editable vector parts. Check that small instances scale their internal art (no clipping). Prototype links are "proposed" unless actually exercised.
- **Flutter:** stress matrix 320×693, 390×844 and 430×932 at normal and enlarged text, captured through the real app entrypoint and theme (not a test-only MaterialApp). Semantics `onTap` must activate custom controls. Animation controllers are created and disposed in the lifecycle. `disableAnimations` stops loops. Commit state on activation, then animate.

## 7b. Surfaces, lists and a gentle health tone (owner feedback 2026-10-23: "sky doesn't fade seamlessly", "too blocky and bubbly", "health things very friendly")

These rules are binding. Critics treat any violation as a top fix. A hard-edged scene, or a list of stacked cards, a visible container edge on the habitat, or more than two corner radii on a core screen counts as a **blocker** (score capped at 7.0).

**Seamless scenes**
1. A habitat is full-bleed and **dissolves into the page**. Its top sky colour equals the page `ground` token at the frame edge, and its bottom fades into the sheet or ground through a feathered gradient of at least 120 pt. No visible horizon line, seam, or rectangle edge where the scene meets content.
2. **No habitat inside a rounded card.** In Experiment, baseline and experiment share one continuous sky split by a soft vertical fade, or sit as two vignetted scenes with feathered edges. They are never two boxed tiles.
3. Content rises from the scene on **one sheet** per screen (top radius 28, `Shadow/Sheet`, grabber, surface **tinted from the page ground**, not white-on-grey), with the scene visible above it, like Apple Weather or Finch. Don't stack floating cards over the scene.

**Lists: light, not boxy**
4. Lists are **plain rows on the sheet** separated by **0.5 pt `line` hairlines inset to the text edge**, grouped under a small quiet section header (Caption, `ink-2`). **No container around a group**, and no per-row card, border or shadow.
5. Row anatomy (56–72 pt tall):
   - a leading **illustrated icon**, 28 pt, from the shared stroke family, optionally on a faint tinted circle;
   - a title in Headline;
   - one quiet secondary line in Subhead `ink-2`;
   - a trailing value as **plain `ink-2` text with a sign and a small arrow icon**, e.g. "about +x.x pts". **The number itself is never red or green**; only the small arrow icon may be tinted (`text/positive` for an increase). No bubble chip. Evidence and strength tags are secondary text with middot separators.

   Rank comes from order and type weight, not numbered circles.
6. **At most one filled pill button per screen**, for the screen's next useful action. Secondary actions are text buttons or tinted ghost buttons. Per-item actions become a tap on the row, which opens a sheet where "Try on twin" lives, or a small trailing text button. Never a filled button on every row.
7. **Chips are only for selectable filters.** "Modeled association, not cause" and "Illustrative — model not connected" appear **once per section** as a quiet footnote line with an info icon, not as chips on every row. The tier is a small label with an icon on the scene, not a bubble.
8. Shape scale: sheet 28, hero/fortune card 24, small controls and icon backdrops 12. **At most two distinct corner radii are visible on any screen.** Avoid pill shapes except the one primary button and segmented controls. Prefer whitespace and type hierarchy over containers.

**A gentle, friendly health tone**
9. Lead with encouragement and agency: "Small steps that may help", "Try it on your twin", "Here's what we noticed". Never "risk", "mortality", "death", "bad", "warning" or "you should". Numbers are secondary to words and always called an "outlook".
10. Uncertainty is warm and honest: "We're not sure yet", with a soft question icon, not "Uncertain". No modelled effect reads "Doesn't change the model, but it may still feel good". Errors and unsupported profiles apologise and offer a next step.
11. Each health concept gets a friendly illustration (moon for sleep, sneaker for activity, glass for drinks, leaf for food) in the shared style. Use calm colour: positive is green text and icon, everything else ink-2. Nothing alarming.
12. Wrong quiz answers and missed logs get a gentle line from Pip ("Pip is a little sleepy") and a recovery path: no failure colour, no streak loss, no guilt wording. The twin reacts kindly. Low tiers look restful, not sick. The quiz's "sick" is a playful sniffle with immediate recovery help.

**Tab bar (owner-reported defect 2026-10-23: "the bottom nav bar is not centered vertically in its box")**
13. **Floating tab bar, iOS 26 style.** Specs:
   - A single rounded bar, 64 pt tall, corner radius 28 (the sheet radius, so no third radius), inset 16 pt from the left and right edges.
   - It floats with its bottom edge 8 pt above the home-indicator safe area (about 26 pt above the screen bottom on 390×844), never inside that area.
   - Fill: the sheet tint at about 92 % with a light background blur, a 0.5 pt `line` border and `Shadow/Sheet`.
   - Icon (24) and label (Caption) as one group, **vertically centred inside the bar with equal top and bottom padding (measure it)**, and horizontally evenly spaced.
   - Selected = `action/primary` icon and label, with no pill behind it. Unselected = `ink-2`.

   Scenes and sheets continue behind and below it (no full-width bar box). Scroll content gets bottom padding of the bar height plus margins, so the last row clears the bar. Labels clamp at 1.2× text scale, as iOS does. Figma frames show a 134×5 home indicator (ink at 30 %, 8 pt from the bottom) so the spacing reads correctly.

   A tab bar whose content isn't optically centred in its visible box is a **blocker**.

## 7c. Fewer words, built for older adults, lists with warmth (owner feedback 2026-10-23, overrides §7b where they conflict)

> "Everything on the UI has way too many words. Everything should be super easily understandable and not overwhelming — older people are using this." "The listing that replaced the bubbling listing looks worse — too bland."

These are binding, and critics treat violations as **blockers**.

**Words**
1. **One idea per screen.** Each screen has one title of 4 words or fewer and at most **one** short supporting line of 8 words or fewer. No paragraphs, explanations or helper text on the main surface.
2. **Row text:** a title of 1–4 plain words. An optional second line of 5 words or fewer, only if it's essential. Drop labels the icon or picture already says.
3. **Explanations live behind a tap:** a small "Why?" or ⓘ opens a short sheet. The two required notes become **one** short line, "**Example numbers · linked, not proven**", with an ⓘ that opens the full wording ("Illustrative — model not connected" / "Modeled association, not cause"). It shows once wherever outlook numbers appear.
4. **Plain, everyday words at about a 6th-grade reading level:** "Sleep more", not "Increase sleep duration". No jargon (cohort, modeled, sensitivity, horizon, baseline) on the main surface. Pip's speech bubbles are 12 words or fewer.
5. **Bigger, calmer type:** row titles at Title 3 (20 pt) or Headline (17 pt), secondary text at 15 pt or more, and no Caption-size text for content. Targets of 56 pt or more for primary actions and 48 pt or more for rows. Two to five choices per screen. Primary actions use words, not just icons.

**Lists: warm, not bland, not bubbly**
6. Each list item is a **friendly tile row**:
   - a **large illustrated icon (40–44 pt) on a soft tinted rounded square** coloured by category (sleep lavender-100, activity green-100, drinks blue-100, food sun at low tint), so colour and picture carry meaning;
   - a short title;
   - a trailing result as one big friendly symbol plus a short word (e.g. a small up-arrow with "helps", or "maybe").

   Rows sit on the sheet with **generous 12–16 pt gaps**, and the tinted icon squares give the warmth. No heavy cards, no hairline-only rows, no number circles, no pill chips.
7. One featured item per list may be emphasised (a slightly larger tile, or the twin pictured beside it).
8. Keep §7b's seamless habitat, one filled button per screen, calm uncoloured numbers, two-radii limit (tiles use the 12 radius) and floating tab bar.

## 7d. Quality check: nothing clipped (owner feedback 2026-10-23: "a lot of the assets that are circles are kind of cut off — quality check everything")

**Rule:** every circle and round asset (sun, shading, badges, glyphs, avatars, icon backdrops, twin and Pip parts, the magic ball) sits **fully inside** all of its clipping ancestors at every size and in every instance. The only exception is deliberate edge-bleed scenery, which must be **named with a `bleed/` prefix** (e.g. `bleed/bush-front`), never clipped to a straight edge *inside* the scene, and never a focal object. Unintended clipping on a core screen is a **blocker**.

**Figma audit, read-only, 2026-10-23 ~23:45.** Fix these at the root (the components) so instances inherit the fix:
- **Habitat component** (Components page; `Aspect=Room` 27:662, `Aspect=Compact` 27:698): its `shade` ellipses are clipped by their own parents, `bush/back`, `bush/front` and `tree/canopy` (clipsContent on). That gives hard straight edges on the shading, 41 hits across the component and its tier instances. Turn off clipping on those part frames and keep each shade inside its shape (or boolean-intersect it). Rename deliberate edge bushes and the light bloom to `bleed/…`.
- **The sun is cut off** in every screen where a Habitat sits in a cropping `Scene` frame: F2–F6, `light/sun` clipped up to 124 pt at the top. Never crop a scene above the sun. Position the sun inside the visible sky for each aspect.
- **F1 need badges:** the `status-glyph` circles (20×20) are clipped 2 pt by the `Needs` row. Give the row enough height or padding.
- **F8 Experiment:** the boxed `Baseline · Steady` / `Experiment · Thriving` tiles clip the scene art (23 hits). Replace them with the continuous-sky layout from §7b.
- `Thriving` tier `sunlight-bloom` is clipped 200 pt by its tier frame. Rename it to bleed or contain it.

**How to verify (builders and critics must run this):**
1. A read-only script per page finds every ELLIPSE, or node with corner radius ≥ min(w,h)/2, whose bounds exceed a clipping ancestor by more than 0.75 px, excluding `bleed/*`. The result must be **0** on Components, Flow, Flow · handoff v1 and States.
2. Look at every screen at phone scale, and every component at its smallest size (Twin S, Pip S, badges, icon tiles).
3. In Flutter, Read the captures at 320×693 ×1.6 and 430×932 ×1.0 and check that no circle, avatar part, icon backdrop or sun is cut. Painters keep their art inside a bounded region (no `ClipOval` or `ClipRect` cutting the character), and the character stays the dominant subject even at 320 pt with large text.

## 7. Flutter mapping

`app/lib/theme/` holds `lt_colors.dart` (ThemeExtension with the colour tokens), `lt_type.dart` (the text styles above), `lt_space.dart`. Fonts are bundled in `app/assets/fonts/`. State uses Riverpod, routing go_router (per `docs/tech-stack.md`). Apple Health follows `docs/apple-health.md` on `main`: `app/lib/health/` (package `lifesim`) is the importer; raw 30-day samples go to the agents only through the server (Track B contract pending), with device and source names removed; provenance stays on the phone. The manual log stays on the device. The shared contracts are not changed in this build: activity source provenance is held in app state until Tracks A/B agree a field.
