# LifeTwin design direction: painted card

Status: design direction for the Flutter UI remake (track C). It supersedes the visual sections of `docs/ui-remake-handoff.md`: character design, colour, line and space, and controls and type. That handoff's behaviour, copy, data and consent rules still hold.

- **Canvas (Claude Design):** references, generated art and every concept: https://claude.ai/artifact/Smu6yoUWwhtuJCvdJsqVne (private; the owner can share it)
- **Generated art (Figma):** https://www.figma.com/design/m2vIKuVlQQSa9m3ELVRdZc
- **Reference research:** [references.md](references.md) covers 35 captured apps and games (Talking Tom 2, Pou, Pokémon Sleep, Neko Atsume, Finch, Duolingo, Memoji, Co–Star, Alto's Odyssey, Headspace and more), with the lesson taken from each.
- **Prototypes:** [prototypes/](prototypes/), the playable room test and the Room ↔ Onboarding swoosh. The motion spec is [motion-swoosh.md](motion-swoosh.md).
- **Open Tier-1 decision:** how the room is built in Flutter. The options are (1) a pre-rendered room plus sprite actors (recommended), (2) Flame with an isometric room, (3) `flutter_scene` 3D, or (4) the three.js prototype in a WebView. Owner ruling pending.
- **Twin asset library (Figma):** https://www.figma.com/design/m2vIKuVlQQSa9m3ELVRdZc/?node-id=52-2 (see section 6). The screens are on the page "Final screens · painted card".

## 1. Decisions (owner, 2026-10-24)

| Decision | Ruling |
|---|---|
| Art style | **Painted trading card.** It comes from the Cal Hacks sponsor bear cards: soft gouache shading, a warm cocoa outline, a cream muzzle and belly, tiny dot eyes, rosy cheeks, tiled pastel panels, and bronze, silver and holo tiers. Flat ink (Nori) and cut paper were rejected as the main look. |
| Characters | **One twin on screen.** The user picks **Bear** or **Human** in Customize. Both share the same chibi build, face, outfits and access aids. |
| Signature item | A navy floppy sun hat with a gold band and gold "Cal" script, with the bear's ears through two holes in the crown. |
| Layout system | **"Storybook panels + card frame"** (concept C refined with grafts from B and A, below). It won two independent critiques. |
| UI vs art | Painted raster art carries the charm. The UI layer is flat, outlined and opaque, and **text never sits on paint**. |

## 2. Fortune: honest by construction (read before designing copy)

`POST /api/predict` (PR #29) returns survival at **1, 3 and 5 years** as probabilities, plus a monthly curve to `max_horizon_years` (5). It **never** returns a lifespan, a date or a life expectancy (`server/README.md`). The owner asked for a ball that "tells you when you die". The honest version, consistent with `AGENTS.md`, is:

- the ball ceremony (dim, mist, anticipation beat, reveal);
- a **personal** result (the owner asked for this): **"Your look ahead: About N in 100"**, with "chance you're still here in 5 years". `N = round(100 × survival[5])`, the same as `outOf100`. Under it:
  - 100 small bear heads (filled means still here);
  - the app's exact `forecastSentence`, "Out of 100 people with answers like yours, about N were still living 5 years later.";
- a detail view, "See what shaped it", with:
  - the person's own curve, using the `curve` field, on an honest 0–100 axis, with markers at 1, 3 and 5 years;
  - "Built from your answers", showing each confirmed input with its source (told me / Health app);
  - "We assumed", listing the response's `filled_in` labels, each with "Add an answer";
  - the limits (5 years at most, a US survey, links not causes, not a promise or a date);
- **"Linked, not proven."** is always visible, with "Why?" linking to the limitations from the response;
- **never** an age, range of ages, date, countdown, clock, percentage gauge, grade, star, skull or red numerals.

The fortune has three states:

| State | When | Screen |
|---|---|---|
| supported | `status: supported` | the result sheet |
| still learning | 501, or the model is missing | misted ball. "Still learning" / "The ball isn't ready yet." / Play the quiz |
| unsupported | `status: unsupported` | the bear says the plain `reason`. Primary: "Add an answer" |

**Real model output used in the designs** (`deepsurv-nhanes-73700ee880b6`, run locally through `POST /api/predict` on 2026-10-24). The design example is profile C.

| Profile | 1 yr | 3 yrs | 5 yrs | `filled_in` |
|---|---|---|---|---|
| A: 34 F, active, never smoked, 7.5 h sleep | 99.9 | 99.6 | 99.3 → "99 in 100" | sitting time, diabetes, high blood pressure, self-rated health |
| B: 52 M, BMI 28, 120 min/wk, 6.5 h | 99.5 | 98.2 | 96.7 → "97 in 100" | same |
| **C: 68 F, 165 cm / 68 kg, 60 min/wk, former smoker, 7 h** | 98.5 | 94.8 | **90.8 → "91 in 100"** | same |
| D: 79 M, 0 min/wk, 8 h | 96.0 | 86.4 | 76.7 → "77 in 100" | same |
| 84 F | — | — | `unsupported`: "The survey this forecast learns from does not record exact ages above 80, so we cannot make a forecast for you yet." | — |

Notes:
- The smoking coding is still unconfirmed by the model author.
- The four always-filled inputs suggest onboarding should ask about sitting time, diabetes, blood pressure and self-rated health.

> **Tier-1 decision (team):** a true "when you die" age range would need a model that supports it. Until the team decides, the fortune shows horizon survival only.

## 3. Visual system

### Colour

| Token | Value | Use |
|---|---|---|
| ink | `#4A2F25` | outlines, text on light |
| paper | `#FFFDF8` | panels, bubbles, sheets |
| cream | `#FBF4EA` | page ground |
| mint / mint-lip | `#9FD9C3` / `#5FAF93` | primary buttons, selection |
| lavender | `#B9B4F0` | Room mode tint |
| peach | `#F8B9A0` | Customize mode tint |
| night | `#1E2547` | Fortune card back |
| gold | `#E8B64C` (rule `#E2B357`) | card keylines, Cal |
| brace | `#B4532F` | `{ Name }` banner braces |

Every text pair meets 4.5:1. Measured: ink on paper 11.98:1, on mint 7.65:1; gold on night 7.96:1. Non-text borders that carry state are solid ink, 2.5px or more (3:1 or better).

### Type

Fredoka 600 for display and bubbles, Atkinson Hyperlegible for body (it was designed for low-vision readers).

- Body text is 17pt or larger, and nothing is below 15pt.
- Titles are at most 4 words, with one support line of at most 8.
- The twin's bubble is at most 12 words.

### Shape grammar

Panels, bubbles, buttons, tiles and chips share one **soft** style (the owner asked for softer borders):
- **controls** (buttons, chips, pills, tiles, switches): a 2px `#8C6B5D` outline (4.7:1 on paper), so state stays at 3:1 or better; the outline on mint is `#7A5B4E`;
- **containers** (window line, panels, sheets, banner, bubbles): a lighter 1.5px `#A88B7D`;
- a 28px radius;
- a soft shadow, `BoxShadow(color: 0x24 ink, offset: Offset(0,6), blurRadius: 16)`.

**Low detail behind the UI:** flat mode tints, no textures or dot patterns, and at most two sparkles per screen.

- **Plate windows** carry an airy card frame: a 1.5px outer line, a 6px cream rim, a 1px gold inner rule at 70% and a 30px radius. Gold corner sparkles appear only on the night screens, because the day plates already have painted ones.
- **`{ Name }` banner:** 44px tall, Fredoka 22, half over the window's top edge. Maximum width 240px; it scales down to 18px, then ellipsises. With no name it reads "My twin".
- **Lip button:** a flat fill over a darker base offset by 4–5px. Build one shared `LipButton` as a Stack of two rounded rectangles, because BoxDecoration cannot draw inset shadows. The primary is at least 56pt tall (64pt standard) and every target at least 48pt.
- **No blur effects** (no BackdropFilter).

### Mode tints

The background behind the panels changes per mode:

| Mode | Tint |
|---|---|
| Room | lavender |
| Onboarding | mint |
| Fortune | night |
| Customize | peach |

Layout stays put; only the light changes.

## 4. Screens (final artboards V-1 to V-9)

Renders are in `docs/design/screens/`; the static source is in `docs/design/mockups/`.

Every screen has the same skeleton:
1. a mode-tinted background;
2. a framed **plate window** with the `{ Name }` banner;
3. one overlapping **sheet** (cream, or night on the fortune screens) holding the controls.

Text lives only on bubbles and sheets. The window shrinks first when space is short (Fortune to a 160pt minimum, Customize to 200pt); then the sheet scrolls. Test at 375×667 and at 1.3× text.

| # | Screen | Maps to handoff | Contents |
|---|---|---|---|
| V-1 | Room | F1 | Calm island with the chosen twin sprite, contact shadow and warm glow. Bubble: "Hi! Want to chat?" Mood chip: "Feeling cozy". Dock: **Customize** · **Talk** (primary) · **Fortune**, labels 17pt. |
| V-2 | Onboarding | F2 | Back button. Twin on the island; one question bubble. Progress dots. **Hold to talk** (88pt), "Type instead" link, then two full-width chips: **Use my Health app** and **AI helper: Off** (the switch state is visible; keep the word "AI" for honest consent). |
| V-3 | Readback | F2/F3 | Bubble: "You're 5 foot 8. Right?" A dashed value card, "5 ft 8 in", so people can confirm by eye. **Yes** (72pt, filled) and **Change** (60pt). Progress stays put until Yes. |
| V-8 | Ceremony | F4 | A tall night window, with the bear holding the glowing ball. Bubble: "Want to peek ahead?" **Ask the ball** / Back to room. Motion: 2 glow pulses (about 1.2s each), the mist clears, then V-4. Reduced motion: crossfade. |
| V-4 | Fortune result | F4 | Night card: "Your look ahead", then **"About 91 in 100"** and "chance you're still here in 5 years", then 100 bear heads (91 filled), then the app's `forecastSentence`, then **"Linked, not proven."** with Why?, then **See what shaped it**. Back sits in the window corner. The numbers are from real model output for profile C. |
| V-9 | Outlook detail | F4 | A scrolling night view, with the "Example person" pill. It has: the personal curve (0–100 axis, markers 99 · 95 · 91); "Built from your answers" (value · source); "We assumed" (`filled_in`, dashed, each with Add an answer); the limits; and a pinned **What could help**. |
| V-5 | Still learning | F4 (current) | Misted ball and shrugging bear. "Still learning" / "The ball isn't ready yet." **Play the quiz** / Back to room. The unsupported state reuses this layout with the plain `reason` and "Add an answer". |
| V-6 | Customize | F11 | Twin on the pedestal. A **Bear / Human** switch with sprite thumbnails. Tabs: Hats · Tops · Glasses · Fur · Aids, 17pt labels. Die-cut tiles as radios; the Cal hat is selected with mint fill, outline and a check. **Save look** (64pt). |
| V-7 | Room, human | F1 | Same as V-1 with the human Cal sprite. Proves the swap. |

Screens not drawn yet (F5–F10, F12–F15) follow the same skeleton. Pick the mode tint per screen, and use the sheet for lists and forms. One primary action per screen.

## 5. Twin and art assets

The assets live in `app/assets/twin/` and `app/assets/scene/`. Every file has a 1x display-size version plus `2.0x/` and `3.0x/` variants beside it. Anchors, Figma node IDs and suggested uses are in `app/assets/twin/manifest.json`. Dart paths are in `app/lib/ui/twin_assets.dart`. Section 6 has the naming rule.

| Asset | File (under `app/assets/`) | 1x size | How it was made |
|---|---|---|---|
| Bear, base | `twin/bear/base/default.png` | 180×180 | generated on white, cut out (alpha) |
| Bear, Cal hat | `twin/bear/base/cal_hat.png` | 180×180 | same |
| Human, base | `twin/human/base/default.png` | 180×180 | same |
| Human, Cal hat | `twin/human/base/cal_hat.png` | 180×180 | same |
| Cal hat, alone | `twin/accessory/hat/cal.png` | 180×180 | same; ear holes cleared |
| Bear poses (Cal hat) | `twin/bear/pose/{stand, wave, walk_side, walk_front, walk_back, sit, jump, think, stretch, sleep, eat, hold_ball, shrug, dizzy}.png` | 180 long side | cut from two generated pose sheets; `stand` is the Cal-hat base art; `shrug` is a separate generation, cropped |
| Human poses (Cal hat) | `twin/human/pose/{hold_ball, shrug, wave, walk_side, sit, jump}.png` | 180 long side | generated and cut out (alpha); 3.0x kept at native size (about 490px) |
| Calm island | `scene/room.jpg` | 390×585 | Room, Onboarding and Readback; the twin sprite is composited on it |
| Calm peach pedestal | `scene/customize.jpg` | 390×585 | Customize; the twin sprite is composited on it |
| Calm night, empty | `scene/night.jpg` | 390×585 | the fortune screens (V-4, V-5, V-8); the twin sprite is composited on its open floor |
| Night, revealed (legacy) | `scene/fortune_reveal.jpg` | 390×585 | baked bear holding the ball; no longer used by the app, kept for the static mockups |
| Night, still learning (legacy) | `scene/fortune_learning.jpg` | 390×585 | baked bear with the misted ball; same |

**Sizes.** A sprite shows at about 180pt tall, so 1x is 180px on its long side, 2.0x is 360px and 3.0x is 540px. Scenes are 390×585 at 1x, 780×1170 at 2.0x and native 933×1400 at 3.0x. Nothing is upscaled past its source: the pose crops are 416–504px on their long side, so their 3.0x files keep native size (slightly soft on 3x screens). Re-cut the pose sheets at a higher resolution if that shows.

**Pipeline.** The image model cannot output alpha, so we generate on flat white and cut out with `tools/art/cutout.py`, a standard-library flood fill from the border that also clears enclosed holes and feathers the edge. Rules:

- One character per image, generous padding.
- A continuous cocoa outline, which is what stops the flood fill.

**Customization model:**

- Signature looks are **whole-character sprites** (base, Cal hat). A flat overlay cannot put ears through hat holes.
- Small items (glasses, scarf, hearing aid) are **anchored overlays** on a per-character head or neck anchor.
- Fur and skin tone are separate sprites, not hue filters, so outlines stay cocoa.
- Demographic cues (age shown on the muzzle and hair, body silhouettes) need their own sprite sets. Generate them only after the team settles the body policy (`AGENTS.md` versus the owner's data-driven ruling, still open).

**Fortune poses (gap closed):** both twins now have fortune poses on the shared night plate. The ceremony (V-8) and the supported result (V-4) composite the chosen twin's `hold_ball` pose on `scene/night.jpg`, with a contact shadow and a soft glow behind the ball; still learning and unsupported (V-5) use `shrug`. Every screen now composites the chosen twin. A pose a twin lacks falls back to that twin's own standing sprite (`twinAsset` in `twin_assets.dart`); all pose art wears the Cal hat, so a twin with no hat stands without the ball. The baked plates remain only because the static mockups reference them.

## 6. Figma ↔ code naming

- **Page:** "Twin · Assets" in the LifeTwin Figma file, https://www.figma.com/design/m2vIKuVlQQSa9m3ELVRdZc/?node-id=52-2. Raw generations are on "Generated art", grouped into sections and named `reference/…` (model sheets, room top-down) or `raw/…`.
- **Rule:** one name everywhere, in snake_case with no spaces, where a slash is a folder. The Figma component `twin/bear/pose/walk_side` is the file `app/assets/twin/bear/pose/walk_side.png`, which Dart loads as `'assets/twin/bear/pose/walk_side.png'`.

| Family | Names |
|---|---|
| Base sprites | `twin/{bear\|human}/base/{default\|cal_hat}` |
| Bear poses | `twin/bear/pose/{stand\|wave\|walk_side\|walk_front\|walk_back\|sit\|jump\|think\|stretch\|sleep\|eat\|hold_ball\|shrug\|dizzy}` |
| Human poses | `twin/human/pose/{hold_ball\|shrug\|wave\|walk_side\|sit\|jump}` (no Figma component yet) |
| Accessories | `twin/accessory/hat/cal` |
| Scenes | `scene/{room\|customize\|night}` (legacy: `fortune_reveal`, `fortune_learning`) |
| References (Figma only) | `reference/{model_sheet_bear\|model_sheet_bear_cal_hat\|model_sheet_human\|demographics_bear\|demographics_human\|room_topdown}` |

- **Cells:** each sprite component is a 256×256 cell. The art is fitted and centred, with the feet on a baseline at 92% of the cell height (235.5px), so swapping poses never moves the feet. Scenes are 390×585 cells. The label under each cell is the exact asset path.
- **Export settings:** every component exports PNG (scenes: JPG) at 1x with no suffix, 2x with the suffix `@2.0x` and 3x with `@3.0x`. Figma turns the slashes into folders. Flutter expects variants in **`2.0x/` and `3.0x/` subfolders**, so move `name@2.0x.png` to `2.0x/name.png` (and the same for 3.0x). Figma exports include the cell padding. The shipped files in `app/assets/` are cut from the high-resolution sources at the sizes in section 5, so use Figma exports only for new art that has no source file.
- **Twin component set:** "Twin" (node `52:667`) has the variants `type=bear|human`, `look=default|cal_hat` and `pose=…`. Poses exist only for `type=bear, look=cal_hat`; the other three looks have `pose=stand` only, which makes 16 variants. Each variant nests the path-named sprite component, and the set's description lists the Flutter path of each variant. Screen V-1 Room uses an instance (`type=bear, look=cal_hat, pose=stand`); the original image is hidden beneath it.
- **Code:** `app/lib/ui/twin_assets.dart` maps `TwinType`, `TwinLook` and `TwinPose` to these paths. In Dart, `TwinLook.plain` is Figma's `look=default`, because `default` is a reserved word.
- **pubspec:** register the folders. Flutter finds the `2.0x/` and `3.0x/` variants automatically, so list only the 1x folders:

```yaml
flutter:
  assets:
    - assets/twin/            # manifest.json
    - assets/twin/bear/base/
    - assets/twin/bear/pose/
    - assets/twin/human/base/
    - assets/twin/human/pose/
    - assets/twin/accessory/hat/
    - assets/scene/
```

## 7. Flutter notes

- Package `lifesim`. Add the `assets:` list from section 6 to `pubspec.yaml`.
- **Fonts are bundled** in `app/assets/fonts/` and registered in `pubspec.yaml` (no `google_fonts`, no network), one folder per family: Atkinson Hyperlegible Regular and Bold (400, 700) and Fredoka as one variable TTF (`wght` axis). Both are under the SIL Open Font License 1.1; the license texts ship beside the fonts (`atkinson_hyperlegible/OFL.txt`, `fredoka/OFL.txt`) and must stay with them. Fredoka styles set `fontVariations: [FontVariation('wght', 500 or 600)]`, because `fontWeight` alone does not reliably drive a variable axis.
- Put tokens in one `lib/ui/theme.dart` (colours, type, radii, shadows). Shared widgets: `LipButton`, `PlateWindow` (frame, banner and sparkles), `Bubble`, `Chip`, `DotArray`, `ModeScaffold` (tint background).
- Reuse the existing logic unchanged: `VoiceOnboardingController` (phases, `startTalk`/`stopTalk`, `setTyping`, `setAiHelper`, `confirm`/`change`), `HealthImportScreen`, and `HttpForecastClient.predict`. The remake replaces only the widgets.
- Reduced motion: every ceremony beat has a static frame.

## 8. Critique log

- Round 1 (fresh critics, 21 renders each). A Open Sky 7.3/7.3. B Card Table 7.8/8.0. C Storybook 8.1/8.3. No direction passed the 8.5 gate. Both critics picked C and gave the same graft list (B's frame and night card, A's bubble, Save look and fortune order).
- Round 2: refined C with the grafts (W). Two fresh critics scored it 8.3 and **8.6**, with no blockers. Fixes: an airy frame, a grounded twin, a rebalanced fortune card, 17pt labels.
- Owner feedback: "borders can be a little softer … too many details (background usually)." Response: softer borders and shadows, no textures, calm repainted plates, and the twin composited on every non-fortune screen (V). One critic's request for more card texture was declined, because it conflicts with the owner's direction.
- Round 3: a fresh critic scored V at **8.6, with no blockers. GATE PASSED.** The polish it suggested (chin clearance, bubble/sparkle collision, a solid read-back value box, lighter container borders, a back button on Learning, a cane icon for Aids) was applied.
- Copy decision: one critic suggested renaming "AI helper" to "Smart helper". It stays "AI helper", so consent to sending answers to an AI service is explicit.
