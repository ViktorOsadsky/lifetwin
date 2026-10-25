# Brief: agentic screens v1 (Experiment with your twin, twin state, check-ins, recommendations, still learning, demo flow, delete data)

Paths below that start with `P/` refer to the design workspace; the exported copies are in this folder (`screens/`, `source/`, `sprite-layers/`).

## Owner direction (Daniel, 2026-10-24, quoted)
"onboarding is too long… 'i don't know' … omit the info … the voice agent should probe a little more detail … to get to know their habits … recommendations … implement the experiment with your twin feature … The character also has to reflect the state of the user. The demo will be a quick filling in with apple health after a few questions."

Further rulings:
- History lives on the phone.
- Confirmed weekly check-in answers update the forecast.
- Emergency line: "If you need help right now, please call 911." Mochi reflects it with a calm, concerned pose. There is a Call 911 button the person taps, and a Continue button. Never auto-dial.
- The character is kind and never sad because of a diagnosis.

## The model: binding contract
`P/model_ondevice/model_handoff/lifetwin_on_device/` holds an on-device Cox model in Dart. Read its README.md and MODEL_CARD.md. Dart 3.13 is installed, so you can compute real numbers for personas with a small script under P (pass the package path; do not modify the package).
- **`assess()`** returns:
  - `survival.status`: `available`, `missing_inputs`, `unsupported_age` (outside 35–79) or `unsupported_profile`;
  - `survival_percent_by_year` for years 1–5, given to decimals, e.g. 99.32;
  - `wellness_cards` (id, level strength/info/opportunity, title, message, `source_url`);
  - `avatar.strengths` and `avatar.opportunities`;
  - `input_provenance`.
- **`compare()`** returns an observational difference in percentage points, with `causal_interpretation: false`.
- **Inputs (11):** age, sex, height and weight (giving BMI), smoking status, diabetes diagnosed, hypertension diagnosed, general health (1–5), sleep hours, vigorous minutes a week, moderate minutes a week, and sitting minutes a day.
- **UI rules (binding):**
  - Show numbers only when status is `available`. Otherwise show the status message and no number.
  - Label the curve **"Modeled survival of similar people"** and a comparison **"Modeled difference between profiles"**.
  - Never show a death date, life expectancy or years gained.
    - **Owner override (2026-10-24):** A rough expected year and age range may be shown once as a proof of concept, labelled as an estimate, never as a specific date. Method: [docs/lifespan-estimate.md](../../lifespan-estimate.md) (the CDC 2024 life table plus the model owner's Cox relative risk, adjusted by age band). Scope: this one-time reveal only; the rule still applies everywhere else.
  - Never fill in healthy defaults. An unknown input stays unknown and the UI shows "still learning".
  - Show wellness cards beside the avatar, each with a visible source link. They are public-health guidance, not model output.
- **Weight:** BMI above 27 has a near-zero, slightly inverse fitted association, which is NOT evidence that gaining weight helps. A weight lever may only move toward the healthy range. If `compare()` shows a gain for moving away from it, show "Not counted" instead of a number.
- **Small differences:** for younger people, 5-year survival is often 99+ and differences can be below 1 point. Design an honest display for tiny differences, for example "less than 1 in 100" plus the exact point difference to one decimal, and an encouraging framing that doesn't inflate them. 100-bear grids only work when the difference is 1 or more; decide when to show them.

## Engine (the other session is building it on `codex/c-on-device-model`; the API isn't landed yet)
- **Experiment levers:** sleep, moderate minutes, vigorous minutes, sitting, smoking and weight. Each has a range and a step. Differences come from `compare()`. Levers are ordered by `docs/model-sensitivity.json` (most impactful first).
- **TwinState:** pose and mood derived from avatar strengths and opportunities, check-in wellbeing, recent sleep and activity, and an emergency flag.
- **Conversation:**
  - Demo order: age, sex and smoking, then the Apple Health offer, then only what's missing.
  - "I don't know" marks a field unknown.
  - Up to about 3 gentle habit probes, which become habit notes.
  - It accepts several answers in one reply.
- **`POST /api/recommendations`:** 2–3 personal suggestions grounded in wellness_cards and the person's own words.
- **Check-ins:** daily or weekly. The reply can carry `emergency: true`, which triggers the `concerned` mascot event, and a `resume` action.

## Visual system (must match the approved app)
- **Approved screens:**
  - V screens: `P/design/previews/V/` (V-sheet.png, V-4-Fortune, V-9-Outlook-full) and sources `P/design/canvas/project/V-*.dc.html`.
  - Last approved Experiment set X-1 to X-7: `P/design/previews/X/` and `P/design/canvas/project/X-*.dc.html`. Reuse its components: chips, lever rows, honesty dock, result card, bear arrays, dashed "no number" language, plate window, `{ Mochi }` banner, What-if pill, Sun tint.
  - Generators to copy from: `P/design/v_gen.py`, `P/design/x_gen.py`.
- **Tokens:**
  - Borders: containers 1.5px #A88B7D; controls 2px #8C6B5D; selected #7A5B4E.
  - Colours: ink #4A2F25; secondary #6B4E42; paper #FFFDF8; teal #24806A; mint #9FD9C3; What-if lilac #B9B4F0.
  - Shape: radius 28, soft shadow, lip buttons.
  - Type: Fredoka and Atkinson Hyperlegible.
- **Twin:**
  - Sprites are in `P/design/sprites/v2/{bear,human}/{hat,nohat}/*.png` (see `manifest_v2.json`).
  - Use one scale per character (stand pose at 196px) with every pose on the same baseline.
  - The twin is the bear OR a human-ish avatar, chosen in Customize.
  - New mood poses (concerned, sleepy, proud, thinking, listening) are being made by another agent. Until they land, use the closest existing pose and mark it in an HTML comment `<!-- POSE: concerned -->` so it can be swapped later.
- **Older adults first:**
  - Body text at least 17px (15px floor).
  - Targets at least 48pt, contrast at least 4.5:1.
  - Titles of 4 words or fewer; bubbles of 12 words or fewer.
  - No red numbers, no shaming words, no BMI shown.
- **Preview tooling:**
  - `python3 -I P/design/preview.py <file.dc.html> <abs out.png>` renders at 390×844. It resolves `asset://<path under design/>` and `/_blob/` IDs.
  - Write `asset://` paths; the lead swaps them for blob URLs at publish time.
- **Do NOT edit `canvas.json`** (the lead adds pages), other teams' files, or the X or V files.

## Review gate
After building, the lead runs two fresh critics. The gate is both scoring at least 8.5 with zero blockers. Their criteria:
- (a) craft and consistency with V and X;
- (b) clarity for older adults;
- (c) empowering, kind tone;
- (d) honesty and contract compliance;
- (e) data visualisation;
- (f) Flutter buildability.

## Engine confirmations (from the engine session, 2026-10-24)
- **Weight:** the engine returns `lever_supported: false` plus a `reason` when an alternative moves away from the healthy BMI range or would show a gain from BMI above 27. The UI shows "Not counted".
- **Differences:** the raw pp difference comes back unrounded (double). The UI owns the "less than 1 in 100" wording and the one-decimal rounding.
- **Emergency payload** (codex/d-twin-checkins 92779c9), shared by onboarding and check-ins:
  - `emergency: true` with mascot state `concerned`.
  - The exact say text is "I'm sorry you're going through that. If you need help right now, please call 911. We can carry on whenever you're ready."
  - It saves nothing, asks no next question and leaves the state unchanged.
  - Continue sends action `resume`, or the person says "continue". Either repeats the same question or read-back.
  - Call 911 is client-side (`tel:911`), tapped by the person.
- **Unknown inputs** are reported by the package's own field names: age, sex_nhanes, bmi, smoking_status, diabetes_diagnosed, hypertension_diagnosed, general_health, sleep_hours, vigorous_recreation_min_week, moderate_recreation_min_week, sedentary_min_day. The UI maps them to plain words.
- **Still pending:** the TwinState enum, each lever's id, range, step and unit, and the recommendations schema. Keep assuming these and mark them in comments.

## Sensitivity results (docs/model-sensitivity.md and .json, codex/d-model-sensitivity, 2026-10-24); these supersede the lever list above
- **Lever order** (the same for every age band and sex): Quit smoking (current smokers only), Vigorous activity, Moderate activity, +1 h sleep (short sleepers only), Less sitting.
- **Median 5-year effects at ages 65–79:** 4.74, 2.11, 2.02, 0.52 and 0.48 pp. At ages 35–49 every lever is under 0.6 pp, so the "less than 1 in 100" state is the COMMON case for younger users. Design it as a first-class, encouraging state, not an edge case.
- **Weight is never a favourable lever** in this model, so it is DROPPED from the Experiment. Don't show a weight lever or a "Not counted" weight row. If weight comes up, a wellness card (public-health guidance with a source) can cover it, outside the model numbers.
- **Sleep:** the lever is offered only to people sleeping under 7 h, and only goes up toward 7–8 h. Past 8 h the model lowers the estimate, so never offer more than 8.
- **Activity is effectively "none vs any".** Small first steps matter most, and extra minutes barely move the number for people already active. Frame it as "first steps" and avoid implying more is always better.
- **Combined changes are evaluated together, not summed.** Show ONE combined "Modeled difference between profiles" for the whole what-if twin, not a sum of per-lever numbers. Per-lever previews may show each lever alone, labelled as such.

## Owner rulings, batch 2 (relayed by the engine session, 2026-10-24)
1. **Outside AI:** "use muse for now, but we will do things with claude later". The consent copy reads the provider from `/api/capabilities` → `personalize.display_name`. It's "Muse by Meta" today and "Claude by Anthropic" later, with no copy change. Show "Muse by Meta" as the current example and note that it's dynamic.
2. **Supplements** are never suggested, in any recommendation or copy.
3. **988** comes later and is NOT in the current designs. The emergency line stays 911 only.
4. **Memory is opt-in,** asked early in onboarding and framed as improving results, e.g. "Can I remember the little things you tell me? It helps me give you better, more personal suggestions. You can change this any time." There's also a Settings toggle. "Mochi's notebook" (habit notes) appears only when memory is on.
5. **No direct editing.** Daniel: "people shouldn't be able to edit their things unless they consult with their agent first."
   - Saved answers have NO edit fields or editable chips.
   - "Change" or "Update" opens a short conversation with Mochi, who asks what changed and reads it back before saving.
   - Experiment levers are hypothetical and never save.
6. **Frequent check-ins:** "there needs to be a daily/frequent check in feature where new information comes in very frequently."
   - The daily check-in is light: a 30–60 second chat with 1–3 questions, plus a reminder.
   - Its entry point is in the Room.
   - The weekly check-in is a longer variant.

## Engine API (landed in draft PR #47, branch codex/c-on-device-model; see app/lib/README-model.md)
- **Repository:** `TwinRepository` provides `current`, `assess()`, `wellnessCards` (id, level, title, message, sourceUrl), `twinState()`, `experiment()` and `deleteMyData()`. There are NO profile setters, so changes go through Mochi.
- **Missing inputs:** `missingInputs` (package names) plus `missingLabels` (plain words). A missing height or weight reports as `bmi`.
- **TwinMood:** cheerful, content, curious, sleepy, cozy, concerned. There's no sad mood, and diagnoses are never read.
- **TwinStateReason and default pose:**
  - emergency → concerned
  - notFeelingGreat → cozy/sit
  - shortSleep (under 6 h) → sleepy
  - active (30+ min) → cheerful/jump
  - feelingGood → cheerful/wave
  - needsInput → content/wave
  - exploring (opportunities) → curious/thinking
  - steady → content/stand
- **UI sprite map:** concerned → concerned.png, sleepy → sleepy.png, curious → thinking.png, cheerful → proud.png (or jump/wave), cozy → sit.png, content → stand/wave. `listening` is used only while the agent probes.
- **Experiment levers (id, step, range):**
  - `smoking_status`: 2 → 1, current smokers only.
  - `vigorous_recreation_min_week`: step 15, up to 300.
  - `moderate_recreation_min_week`: step 15, up to 600.
  - `sleep_hours`: step 0.5, offered only under 7 h. Design it to go up to 8; asked the engine to cap it at 8.
  - `sedentary_min_day`: step 30, down to 60.
  - Weight is unsupported (`weight_not_a_lever`).
- **`ExperimentResult.status`:** available, no_change, not_counted, current_unavailable, alternative_unavailable or invalid_input.
  - `differenceByYear` gives raw pp for years 1–5.
  - Per lever: `{id, counted, reason, reasonText}`.
- **Copy:** the curve label is "Modeled survival of similar people"; "We assumed" is gone. Until the conversation redesign merges, onboarding produces "Still needed: …".

## Owner UX rule: less text (2026-10-24)
Daniel: "There should also be less text on screens to make it less daunting. and more understandable."
- **One idea per screen.** Each screen has one primary action and a short title of 4 words or fewer.
- **Body copy:** about 25 words or fewer per screen outside the honesty dock. Bubbles are 8 words or fewer.
- **Show, don't tell:** use icons, the twin's pose, bear arrays and chips instead of sentences. Long explanations go behind a "Why?" or "Learn more" sheet, never inline.
- **Honesty copy stays but gets shorter:** "Linked, not proven." plus "What-if only." are enough on the screen; the full caveat sits behind "Why?".
- **Plain words** at about a 6th-grade reading level. No jargon (no "pp", "profile", "inputs"), and numbers in words people use.
- **Progressive disclosure:** details appear on tap, not up front.

## Product vision (codex/d-product-vision, docs/meetings/2026-10-23-product-refinement.md)
**Promise:** "a daily health companion: bring your health information, explore your twin's modeled outlook, and get a practical plan that adapts as you report what really happened."

1. **Upload health documents at entry,** alongside Apple Health and voice/text (codex/c-document-upload).
   - OCR runs on the device; only the recognised text goes to `/api/documents/extract`.
   - Each candidate is confirmed with its value, units, date and source; nothing is stored except confirmed values.
   - Then only the missing inputs are asked.
   - Must handle: decline, an unreadable document (fall back to voice/text without losing confirmed values), and wrong units or date.
2. **Daily health secretary** (`/api/plan` on codex/d-twin-coach). It's stateless: `revision_id`, `based_on`, items with a why plus `source_url`, `changes` and a `trace`.
   - A short cited daily plan of 2–4 items, each with accept / change / dismiss and done / not done with a reason.
   - The next day's plan explains what changed and why, e.g. "You said the walk hurt your knee, so today is a seated routine", or why it stayed the same.
   - A "Why this plan" trace view: input → action and evidence → revision.
   - It's educational habit planning, never prescribing. No invented health score, and no survival number derived from feelings.
   - Animation may acknowledge progress without claiming a medical improvement.
   - Actual logs stay separate from hypothetical experiments.
3. **Plain-language model drivers** on the outlook ("What moves your number"), from `docs/model-sensitivity.md`. Never "predict the day you die", no years gained, no death year.
4. **Target:** time to the first useful result about 60 seconds.

## Age extrapolation (engine commit 2d942ea; Daniel: "okay to extrapolate a bit below and above the age ranges")
- **Ages 30–34 and 80–85** now get numbers flagged `extrapolated: true`, with `caveat` = "Your age is outside the ages this model was checked on (35–79), so treat this as a rough guide."
- **Under 30 or over 85:** no number. The message is "Annual estimates support ages 30–85 only."
- **Display (less-text rule):** when `extrapolated` is true, show a visible "Rough guide" badge (icon plus 2 words) next to the number on the Forecast, the Room outlook card, the Experiment result and the Outlook drivers. Tapping it opens the full caveat text verbatim. The badge must sit beside the number, never hidden in a sub-menu.

## Usability rule from the device test (iPhone, 28/28 typed end-to-end pass)
- Back, Home and close controls are ALWAYS pinned (fixed header or floating), like the Room's Home. They never scroll away with a list.
- The trigger: Outlook's "Back to your look ahead" scrolled off on long lists.

## Change through Mochi: LIVE on main (#50, 6602b58)
- **Start:** `POST /api/change/start {profile, field?, memory_consent}`. Without a field, Mochi asks "What would you like to update?".
- **Turn:** `POST /api/change/turn {action: reply|confirm|cancel|resume, state, profile, memory_consent, text?, input_mode}`.
- **Response:** the check-in shape plus `profile_update` (only on the yes turn), `habit_note` (only with memory consent), `emergency` with the `concerned` mascot event, and `complete`.
- **The sheet:** the conversation may continue after `complete`, so the sheet stays open until the person closes it.
- **Saving:** the app saves through `TwinRepository.saveConversationProfile`. Experiment levers never call it.

## Engine and conversation answers (2026-10-24)
- **Outside-AI consent:** shown once, at the end of intake right before the first recommendations, and only if `/api/capabilities` → `personalize.configured` is true. Settings holds the toggle afterwards.
  - `personalize` is `{provider, display_name, configured}`, and `outside_ai_consent` is keyed by provider id (`{"muse": true}`).
- **Moods:** the latest daily check-in `wellbeing` drives feelingGood and notFeelingGreat. `active` means 30+ min TODAY (today's daily log), not an average.
- **Names:**
  - `memory_consent`.
  - Probes: `current_probe` + `probes_asked`, at most 3. The first probe adds "Or we can move on."
  - Habit notes: `{topic, kind, with, time_of_day, barrier, text}`.
  - Check-ins: `kind: daily|weekly|quick`.
- **STORAGE WORDING (required):** even with outside AI off, intake, check-ins, change and recommendations send answers to LifeTwin's server, which processes them without storing them. Copy: "Saved on this phone. LifeTwin's server reads your answers to understand them, but doesn't keep them." A short form is fine on screen, with the full sentence behind a tap.
- **Change:** `/api/change/start` takes package field names. One conversation can update several fields in turn ("You also mentioned…"). The sheet stays open until the person closes it.
- **Apple Health read-back:** show "Not found in Apple Health" for missing types and never invent them. Sitting always comes from the person.
- **Delete my data:** wipes answers, check-in history, daily logs, habit notes, the twin look and consents, and cancels reminders. The app then returns to first run.
- **History (Daniel):** "Make sure the daily check ins and optional other check ins are logged and recorded and available to users." The read-only history API is coming on TwinRepository.

## Document upload contract (draft PR, branch codex/c-document-upload, docs/document-upload.md)
- **Inputs:** a VisionKit document camera scan, up to 10 photos (JPEG/PNG/HEIC), or a PDF (first 10 pages only; tell the person).
- **Extraction:** OCR runs on the phone, and only the recognised text goes to `POST /api/documents/extract`.
  - Candidates: `{field, use: model_input|information, value, unit, date, date_basis, source_text, page, section, confidence, method}`.
  - Status: `found`, `nothing_found` or `unreadable`, plus `notices` and `provider_status`.
- **Privacy sentence** (exact meaning; can be shortened on screen, with the full sentence behind "How?"): "Your document stays on this phone; only the words are sent to LifeTwin's server to find your numbers, and nothing is kept."
- **Screens:**
  - Entry choice: Upload a document / Use my Apple Health / Talk or type. A Room pill "Upload a document" sits beside "Use my Apple Health".
  - Intro, then progress.
  - "Is this document about you?"
  - Read-back: ONE value per screen, the value and its `source_text` in large print, with Yes / No / Go back. No edit field: "No" drops the value and Mochi asks instead.
  - The Muse help prompt, ONLY when `provider_status` is `consent_required`.
  - Summary, then the hand-off to Mochi.
  - Failures: blurry, handwriting, nothing found, another person's document, server down, and declining.
- **Source label:** "From your document" appears in the forecast, the outlook and History.

## History rules (engine, 2026-10-24)
- **Good week:** at least 4 DIFFERENT DAYS in a Monday–Sunday week with a finished check-in of any kind. It counts days, not check-ins.
- **Working API names:** `history({from, to})`, `dayLogs`, `goodWeeks()`.
- **Changing a past day:** append a CORRECTION through Mochi with a short read-back ("On Tuesday you said 'not great'. What should it be?"), never a direct edit.
  - The original stays visible as "corrected" in the day sheet, and the new value carries the correction's date.
  - Feelings are history only.
  - Daily-log model fields (sleep, activity, sitting) use the corrected value in that day's log, and the forecast window recomputes.
  - Profile fields still go through the profile change conversation.

## Naming (applies to all sets)
- The forecast screen and its number are called the **"Outlook"** ("Your outlook"). "Fortune" is used only for the magic-ball reveal moment. Don't use "look ahead" or "forecast" in user-facing copy.
- Effect levels (drivers):
  - **Big:** 3 or more in 100.
  - **Some:** 1 to under 3.
  - **Small:** 0.3 to under 1.
  - **Tiny:** under 0.3, with no meter fill.
  The plain number is shown on tap ("about 7 in 100", "less than 1 in 100").

## Daily health secretary contract (draft PR, codex/d-twin-coach, contracts/coach.plan*.schema.json)
- **Endpoint:** `POST /api/coach/plan`, refreshed on app open or resume. Nothing runs in the background.
- **Response:**
  - `revision_id` and `based_on`;
  - 2–4 `items {action_id, kind, time_of_day, title, message, why, source_url, minutes, controls: accept|edit|dismiss}`;
  - `changes`, one plain line per item;
  - `trace` (facts → rule → evidence → action);
  - `mood`;
  - `alert`;
  - `notices` and `memory_instruction`;
  - `provider_status`.
- **Feedback per item:** accepted, edited, dismissed, done or not done, plus a reason that can be spoken.
- **Every plan card** shows "Awaiting professional review" (small, but legible at 17px) plus its source link.
- **Mood → sprite:** happy → wave or stand, proud → proud, cozy → sit, waiting → thinking, concerned → concerned, celebrate → jump.
- **`alert: bp_crisis`:** a calm alert screen (concerned pose, no red alarm styling) with two big buttons the person taps, "Call my doctor" and "Call 911" (tel:), plus Continue. Never auto-dial.
- **Forgetting:** "Forget that" needs ONE confirm; "Forget everything" needs TWO.

## Outlook statement: stronger (Daniel, 2026-10-24)
Daniel: "Make the statement of death timeline stronger, but make it clear in the extra info page below that it is an estimate and definitely not a promise."
- **Headline (the Outlook):** say it plainly in direct words, e.g. "In 5 years: about 96 of 100 people like you are still alive." An optional second line gives the other side plainly: "About 4 are not."
- **Timeline:** a simple year-by-year strip for years 1–5 (still alive out of 100 at each year), from `survival_percent_by_year`, rounded as elsewhere.
- **"Still alive":** use these words, not euphemisms like "still here".
- **Extra-info section below the fold** (or a "What this means" sheet), plain and unmissable:
  - "This is an estimate, not a promise."
  - "It comes from a US health survey of people with answers like yours."
  - "It can't tell when any one person will die."
  - "Linked, not proven."
- **Still forbidden** (model card, AGENTS.md): no death date, no age at death, no life expectancy, no years gained. The model only supports years 1–5. Status gating still applies, and so does the Rough guide badge.
  - **Owner override (2026-10-24):** A rough expected year and age range may be shown once as a proof of concept, labelled as an estimate, never as a specific date. Method: [docs/lifespan-estimate.md](../../lifespan-estimate.md) (the CDC 2024 life table plus the model owner's Cox relative risk, adjusted by age band). Scope: this one-time reveal only; the rule still applies everywhere else.

## Answer provenance (engine)
- Every stored answer and every `history()` item carries `source`: you_said | apple_health | document | mochi_change | wristband, plus `estimated: true` for sensor or proxy estimates.
- Labels bind to these fields:
  - "You said"
  - "From Apple Health"
  - "From your document"
  - "Changed with Mochi"
  - "From your band"
  - "≈ Sensor estimate"
- Wristband values are filtered out of outside-AI payloads. A confirmed wristband estimate counts as the person's answer and may change the Outlook (Daniel's ruling).

## Three separate AI consents (confirmed by the engine session)
1. **Per-document yes (S-6):** `outside_ai_consent` is a PER-REQUEST flag on `POST /api/documents/extract`, covering only those pages. `DocumentUploader.retryWithMuse()` resends once. Nothing is persisted or logged.
2. **Voice/conversation AI helper:** `aiHelper`, held in memory for that conversation and sent as `provider_consent` each turn.
3. **Personal suggestions:** a persisted toggle on the phone (name TBD from the integration branch), sent with each request; the server keeps nothing. `repo.outsideAiProfile()` strips wristband values.

Never promise anything about Muse's own retention; it's unverified.

## Product direction: health score is the hero (owner, via dqi26-45, 2026-10-24 late)
1. **Health score leads Home and everything after onboarding.** The outlook is shown ONCE as the reveal at the end of onboarding, then stays reachable behind a quiet "See your estimate" tap. Never front and centre after that.
2. **Healthy habits for all ages.** Tone works for a 25-year-old: habits, gentle consistency, energy, sleep, movement, mood. Keep large text and 48pt targets. Nothing reads "for old people".
3. **Daily check-in is the core loop.** The check-in entry is obvious on Home every day (primary button, not a chip).
- **Health score direction (owner ruling 2026-10-24):** `repo.healthScore` is now higher = better (0 = survey average, typically about −3 to +3); see app/lib/README-model.md.
- `healthScore` is a PLACEHOLDER, assumed 0–100, until Viktor's spec lands. Do not invent a formula, bands, or how many points any habit is worth. "What moves it" shows directions only (up/down), no point values. Trend data is placeholder and labelled so in board notes.
- **Ruled 2026-10-24 (see the owner override above):** the one-time reveal may show the rough expected year and age range from `repo.lifespanEstimate` (ages 18–85, with its caveat; `lifespanRevealSeen` de-emphasises it afterwards). The text below is the earlier pending state, kept for history.
- **Earlier, pending Tier-1 ruling:** the owner asked for a reveal of "You're likely to live to about X" with a range. The on-device Cox model only supports 5-year survival (ages 30–85); it does not produce a lifespan. Until the owner rules, the reveal uses the supported 5-year statement (Outlook framing ruling). A lifespan-layout variant may be drawn with "X–Y" placeholders and a visible "Awaiting Viktor's method, not for build" tag outside the phone frame. (Draft method: PR #52, CDC 2024 life table x Cox relative risk; expected age + 25th–75th range. AGENTS.md conflict stays open until Viktor and the team sign off.) No real-looking lifespan numbers anywhere.
- Body never signals health; the score never reshapes the twin. Experiments stay hypothetical and never change the score.
- **Owner rulings (via dqi26-45, 2026-10-24):**
  1. The score, lifespan, outlook and health advice need age 18 or over. Under 18 gets Mochi, the room, Customize and the quiz only.
  2. Habit ticks and check-in consistency never count toward the health score. Behaviour shows only through measured twin inputs: sleep, activity, sitting, smoking.
  3. Under-30s get both the lifespan estimate (with its caveat) and the score.
  Habits v1 is on `codex/d-habits`, with a pure-Dart `app/lib/habits/` and no screens yet; API names are pending.
- **Check-in flow change (peer, 2026-10-24):** check-ins use ONE read-back at the end, offering "Looks right" or "Change with Mochi". The per-answer "Looks right?" taps are removed, which supersedes those taps in the Z designs. Home shows a "Check in" entry driven by `CheckinScheduler.due()`. The server contract is pending.
- **Voice provider name (peer, verified against `server/lifetwin/app.py:203`):** `/api/capabilities.voice` is only "available" or "unavailable". There is no `voice.display_name`. Voice copy uses the literal "Cartesia" and makes no retention or recording claims. `personalize.display_name` is the only server-driven provider name, and it's for outside-AI consents only.
- **Score next to every outlook (Daniel, in his own words, 2026-10-24):** "The outlook has to have the health score somewhere nearby on the page or the next to show that the health score is more important, like living a healthy and enriching last period of your life."
  - Every screen that shows the outlook also shows the health score on the same screen, ABOVE the outlook and visually stronger: larger, first in reading and screen-reader order. Where that truly can't fit, the outlook screen's primary next step leads straight to the score.
  - The outlook becomes the smaller, secondary block.
  - Framing: the score is about living well, feeling good and having full, healthy years ahead. Copy must suit any adult age (18+), so never write "last period of your life" literally.
  - Score is a placeholder 0–100, with 72 used everywhere. No formula, bands or point values.
  - Applies to: K-1, K-1b, K-6, K-7; R-V4, R-V9-OutlookReady, R-V9-OutlookMissing, R-21; S-19, S-20; Z-17, Z-33, Z-34 (weekly "Outlook updated" cards); and the Flutter Room outlook card.
- **Engine API, final (PR #59 `codex/c-twin-integration`, auto-merges on green):**
  - Scheduler: `CheckinScheduler().due({localNow, history, days, settings, health}) → DueCheckins{QuickPlan? quick, bool weekly}`.
  - Store: `TwinCheckinStore(repo)`. Don't also call `applyCheckin` in `onFinished`, or the check-in is recorded twice.
  - History: `history({from,to})` returns `HistoryEntry` newest first; `HistoryItem` has `source`, `sourceLabel`, `estimated`, `estimateText`. Also `dayLogs`, `goodWeeks()`, `readings()`, `applyDayCorrection(date, field, value)`.
  - Provenance: `provenance(field) → FieldProvenance{source, estimated, at, sourceLabel, estimateText}`.
  - Consent: `outsideAiConsent`, `outsideAiProvider`, `setOutsideAiConsent(bool, {provider})`. Off by default; `deleteMyData()` clears it.
  - ChangeField: age, sex, height_cm, weight_kg, sleep_hours, vigorous_recreation_min_week, moderate_recreation_min_week, sedentary_min_day, exercise_minutes_weekly, smoking_status, alcohol_drinks_weekly, diabetes, hypertension_diagnosed, general_health, systolic_bp.
  - Call `repo.refresh()` on app open.
  - `CheckinRecord` is renamed `CheckinEntry`.
- **Score tagline, final (Daniel, relayed by dqi26-45, 2026-10-24: "keep it"):** "Feeling good now, and healthy years ahead." It is dropped at text scale 1.5x or more.
- **Health score = Viktor's `log_relative_hazard_score` (Daniel, relayed by dqi26-45, 2026-10-24):** "There is not a wellness card. Read what he changed. He added some score between -3 and 3 that was calculated. Follow what he has. default to what he has."
  - The value comes from `LifeTwinModel.predict()` when `survival.status == 'available'` (`model.dart:243`): Σ(input − dataset centre) × coefficient.
  - Range is about −3 to +3. LOWER = lower modelled risk. 0 = the average survey participant. It includes the age and sex terms.
  - Missing below 30 and for incomplete or unsupported profiles. It's present but extrapolated at 30–34 and 80–85.
  - The engine will expose it as `TwinRepository.healthScore`.
  - Show the value with Viktor's sign and scale, and make the direction obvious ("lower is better", a scale from lower risk to higher risk, 0 = "average for the survey"). No bands, no 0–100 mapping, no invented colours by value.
  - This replaces the placeholder 72. Persona Rosa = −0.04 (`z_model/persona_out.json`). Golden vectors in the model package give −1.56, −0.09, +1.10.
  - Open with the owner, via the peer: the sign presentation, and whether age and sex stay in. This also conflicts with "under-30s get both", because there's no score under 30.
- **Health score update (Daniel via peer, 2026-10-24):**
  - Keep Viktor's `log_relative_hazard_score` as the headline, with its sign as is (negative = lower modelled risk than the survey average).
  - ADD `ageGroupPercentile`: "healthier than X of 100 people your age". It compares against the same sex in a ±5-year band from Viktor's reference set, with the age and sex terms excluded. Daniel: "there should be a statistic in the results that basically measures how healthy someone is relative to other people in their age group. that is what we are looking for."
  - Extrapolate down to 18 with the Rough guide badge. Under 18: no number.
  - API (pending): `healthScore`, `healthScoreStatus` (available / extrapolated / missingInputs / unsupportedAge / unsupportedProfile / invalidInput / underAge), `ageGroupPercentile`, `ageGroupBand`, `ageGroupSize`, `nearestBand`, `healthScoreHistory({from,to})`.
- **Documents (peer answers):**
  - Conflicting values follow the engine: the latest dated value wins; equal or missing dates mean both are dropped with a `conflicting_values` notice. There's no picker. Instead: "Your document shows two different weights" → "Tell Mochi which is right".
  - Read-back wording stays Keep / Change with Mochi / Skip, plus Back.
  - Readings: BP, `hba1c` (%) and `ldl_cholesterol` (mg/dL), each with unit, document date and source `document`. They're information only and also appear in History.
  - Entry points: Settings › Health documents, the onboarding pill, Mochi, and a History link from document-sourced entries. No Home row.
- **Outside-AI training disclosure (Daniel via peer, 2026-10-24: "do contributor mode of 1.3"):**
  - The provider becomes `muse-spark-1.3-contributor`, and Meta may train on the content sent to it. `/api/capabilities.personalize.may_train_on_content: true` (PR coming).
  - Every outside-AI consent shows "Meta may use what you share to improve its AI." next to Yes, only when the flag is true, with the company name bound.
  - It applies to Personal suggestions, the AI helper, per-document Muse help, and the coach.
- **Check-in care line (Daniel via peer):**
  - On low mood, Mochi replies with empathy using the person's own words, offers support, shows the soft 911 line, then asks "keep going or stop here for today?".
  - Stopping saves what's confirmed. The flag is `care_line_shown` (PR #64).
  - Warm, no red. The explicit-crisis pause is unchanged.
- **Training-line binding (confirmed by the peer):** company name from `personalize.company` ("Meta" for muse, "Anthropic" for claude); shown only when `personalize.may_train_on_content` is true.
- **Contributor-mode scope (Daniel, own words, 2026-10-24):** "Yes, all answers may still go to Muse with consent; the training line is enough." Name and contact are still never sent.
- **Owner override (2026-10-24), lifespan:** a rough expected YEAR and age range may be shown once at the end of onboarding as a proof of concept, labelled as an estimate (never a day), then reachable only behind "See your estimate". Source: `docs/lifespan-estimate.md` (PR #52). Ages 18–85, with Rough guide outside 35–79. The other no-death-date rules stay.
- **Health score sign (Daniel via peer):** higher is better. Public `healthScore` = −raw (`rawLogRelativeHazard`). Scale reads "Higher risk ‹ Average › Better health". No hard-coded numbers.
- **Quality gate (Daniel, own words, 2026-10-24):** "80 is about 80-82.5 is about fine". A screen passes at a critic score of 8.0 or higher with no blockers. No polish rounds above that.
