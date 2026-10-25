# Demo script: a full connected flow (3 to 4 minutes)

Goal for the judges: one connected story of everything we promise. Say what you bring, see your twin's modeled outlook and health score, check in, try a change, get a plan, add a document and a wristband value, see where every number came from, and keep control of your data.

Persona: **Rosa, 64** (never smoked, no diagnoses, sits a lot, walks the dog; the approved design persona, BMI 25.1). Two ways to run it:

- **Seeded (recommended for the judged run):** build with `DEMO_SEED=1`. Rosa already has 16 days of history, so steps 3 to 9 show real data. Do step 1 live on a second, empty phone or simulator if you want to show onboarding.
- **Live from empty:** build without `DEMO_SEED`. Step 1 creates the profile; the history steps are thinner. Use this only for the onboarding segment.

Each step lists: say or tap, what should appear, fallback, and what it depends on. Some screens belong to the UI session and may not be on `main` yet. Those steps are marked **(pending UI)** with a fallback that works today. Check the "Status on main" column in the checklist before the run.

## Setup checklist (do the day before, repeat 30 minutes before)

| Item | Setting | Needed for |
| --- | --- | --- |
| Server env | `ONBOARDING_DEMO=1` | Short onboarding (one habit follow-up) |
| Server env | `LLM_PROVIDER=chat_completions`, `LLM_BASE_URL`, `LLM_MODEL=muse-spark-1.3` (not the `-contributor` variant), `LLM_API_KEY` | Free-form spoken or typed answers, Mochi change chat, outside-AI wording, document help |
| Server env | `PERSONALIZE_PROVIDER=muse` (default) | Personal wording, only after consent |
| Server env | `DOCUMENT_MUSE_ENABLED=true` (default) | Muse reading a document, only with consent. Off: the on-device parser still finds values |
| Server env | `CARTESIA_API_KEY`, `CARTESIA_VOICE_ID` | Voice in and out. Blank: typing only |
| Server env | `APP_ENV=development`, `API_RATE_LIMIT_PER_MINUTE=600` | Avoid rate limits during rehearsal |
| Server run | `uv run uvicorn lifetwin.app:app --host 0.0.0.0 --port 8000 --no-access-log` | Bind to all interfaces so the phone can reach it |
| App build | `--dart-define=API_BASE_URL=http://<mac-name>.local:8000` | Phone must not use `localhost` (that is the phone). Same Wi-Fi as the Mac, accept the Local Network prompt on first launch |
| App build | `--dart-define=DEMO_SEED=1` | Rosa's seeded history. Off by default; with the flag absent the app and store are untouched |
| Phone | `scripts/ios-device.sh --dart-define=API_BASE_URL=... --dart-define=DEMO_SEED=1` | Device run (see `docs/ios-testing.md`) |
| Phone | Apple Health has sample data; allow Health access | Quick-fill in step 1 |
| Phone | Mic permission, volume up, Do Not Disturb on | Voice |
| Phone | A sample lab PDF or photo (fake name, BP 138/86, A1c 5.8 %, no real records) saved in Photos or Files | Step 8 |
| Phone | Wristband charged, or use "Try a recorded demo" | Step 10 |
| Reseed | Delete the app (or My data > Delete my data), then launch again | The seed runs only on an empty store, dated from first launch |

Pre-flight: open `http://<mac-name>.local:8000/api/capabilities` in the phone's browser. It must load. It shows which features are keyless or configured.

Status on main (this PR's branch point): Talk onboarding, Apple Health, outlook, check-in, Try a change (Experiment), document upload, band and My data are in the app. These are **not yet in the UI**: the "Healthier than X of 100 people your age" line, the coach's daily plan screen, a History screen with sources, and a training disclosure screen. Re-check before the run; the steps below say what to do for each.

## Script

### 0. Opening (15 s)
Say: "This is Rosa's twin. LifeTwin is a daily health companion: it turns what you tell it into a modeled outlook, lets you try changes, and adapts as you report what really happened. Everything is stored on the phone."
Show: the Room with the bear.

### 1. Short onboarding with Apple Health quick-fill (50 s)
Needs: server up, `ONBOARDING_DEMO=1`, `LLM_*` for free-form answers, Cartesia for voice. Use a fresh install without the seed.
- Tap **Talk**. Mochi greets you. Agree to the voice prompt (or tap **Type instead**).
- Say or type: "I'm 64." Then "Female." Then "I've never smoked." Confirm each read-back with **Yes**.
- Mochi asks about memory: say "Yes, remember my habits." Say one habit: "I walk the dog in the morning."
- When Mochi offers Apple Health, tap **Use my Apple Health**, allow access, review the values, tap **Yes, that's right** on the read-back.
Should appear: read-backs after each answer, a rough-estimate tag on simple-question answers, the Health values filled in (height, weight, sleep, activity), then Mochi finishing.
Fallback: tap **Type instead** and type the answers; if the server is unreachable, switch to the seeded phone and say "here is Rosa after two weeks". If Health has no data, answer height and weight by voice (162.6 cm, 66.5 kg).

### 2. Outlook reveal (25 s)
The one-time lifespan/outlook reveal is still pending Viktor. Do not claim life expectancy. Use the 5-year statement.
**Owner override (2026-10-24):** A rough expected year and age range may be shown once as a proof of concept, labelled as an estimate, never as a specific date. Method: [lifespan-estimate.md](lifespan-estimate.md) (the CDC 2024 life table plus the model owner's Cox relative risk, adjusted by age band). Scope: this one-time reveal only; the rule still applies everywhere else. Until the reveal screen is built, the demo keeps the 5-year statement.
Tap the outlook card in the Room (or the Fortune ball). Say: "Out of 100 people with answers like Rosa's, about N are modeled to be alive in five years. This is the modeled survival of similar people, not a prediction about Rosa."
Should appear: the "Modeled survival of similar people" title, a 5-year number (about 97 in 100 for Rosa at onboarding), and the drivers in plain words. No death date, no years gained.
Fallback: if the number is missing, read the message on screen (it says what is still needed) and fill that input by Talk. A missing number is the correct behaviour, not a bug.
Depends on: on-device model only. No server.

### 3. Health score hero (25 s) (pending UI for the percentile line)
Say: "This is Viktor's health score for Rosa. It comes from the same model. Lower hazard is healthier, and the app says how she compares with people her age: healthier than X of 100 people her age."
Should appear (seeded): the score and the age-group percentile; the score starts near -0.04 (about 79th percentile for her age group) and ends near -0.13 (about 86th) over the 16 days, following the events, from the real model.
Fallback if the hero is not merged: describe it from the Room outlook card and say the score and percentile exist in the app's engine (`healthScore`, `ageGroupPercentile`). Do not invent a number.
Depends on: on-device only.

### 4. Daily check-in with one read-back (35 s)
Tap **Check in**. Say: "I slept about seven hours. About twenty minutes of walking yesterday. I sat about six and a half hours." Mochi reads it back: tap **Looks right** (or say yes). Optionally say "I feel good".
Should appear: the read-back, then "Got it. That's all", and the twin responding. Missed days are never shown as zero.
Fallback: tap **Type instead**. If the server is down, skip to step 5 and say check-ins use the server for the conversation but all storage is on the phone.
Depends on: server `/api/checkin` and `LLM_*` for free-form speech; Cartesia for voice. Typed quick answers work with no LLM key.

### 5. Experiment with your twin (30 s)
Tap **Try a change**. Move "moderate activity" up (for example 90 to 150 minutes a week). Say: "This is a what-if. It never changes Rosa's real profile."
Should appear: the "Modeled difference between profiles" title, a signed change in modeled survival, then reset leaves the real profile unchanged.
Fallback: use the lever detail screen and **See side by side**. If a lever is greyed out, read its reason (for example smoking category cannot be changed to never).
Depends on: on-device only.

### 6. The coach's daily plan (25 s) (pending UI)
Say: "Mochi turns the check-in into a short plan: a walk, a food pattern, a habit, with sources. Rosa can accept, edit or dismiss, and tomorrow's plan changes with what she reports."
Should appear: 2 to 4 cited items and a revision note after feedback.
Fallback if the screen is not merged: the engine exists (`POST /api/coach/plan`, deterministic, replayable trace). Show the suggestions from Try a change and the Personal suggestions prompt, or show the API response in the browser docs at `/docs`, and say the app screen is next.
Depends on: server `/api/coach/plan`; Muse rewording only with outside-AI consent (OFF in the seed).

### 7. Mochi change (15 s, seeded)
Say: "When Rosa told Mochi she sits less in the evening, the change was saved as a Mochi change, with its source." (Seeded: sitting 480 to 420 minutes a day.) Live option: tap **Talk**, say "I sit less now, about six hours." Confirm the read-back.
Depends on: server change chat and `LLM_*` for the live version; the seeded one needs nothing.

### 8. Health document upload (30 s)
Tap **Upload a document** and pick the sample lab report. Answer the Muse question: tap **No thanks** (outside AI stays off) and show that the on-device reader still finds values. Review the candidates: blood pressure 138/86 and A1c 5.8 %, both dated ten days ago. Tap **Yes, that's right** on each you keep.
Should appear: values to confirm one by one with their units and date; unrelated identifiers are removed first. These are information for Rosa, not model inputs.
Fallback: use the seeded reading (already in history) and say "she did this ten days ago". If OCR fails, use a typed or sharper photo, or type the numbers into Talk.
Depends on: OCR on the phone; `/api/documents/extract` on the server; Muse only with consent and `DOCUMENT_MUSE_ENABLED=true`.

### 9. History with sources (20 s) (pending UI)
Say: "Every value keeps where it came from: You said, Apple Health, Document, Changed with Mochi, From your band." Show the history list: onboarding, check-ins with gaps (days she skipped are not penalised), the weekly check-in marked as the one that fed the forecast, the document readings, the Mochi change, the band value tagged as a sensor estimate.
Fallback if the screen is not merged: show My data and say history is a list of events on the phone, each with its source (labels: "Mochi change", "From your band", "You said").
Depends on: on-device only. The seed supplies every source.

### 10. Wristband confirmation (25 s)
Open the band screen. Tap **Try a recorded demo** if the band is not on hand, or **Find my band** then **Pair**. Mochi suggests a moderate-activity number from the last 7 days (needs 4 valid days). Tap **Use this**, then confirm the read-back with **Yes, save**.
Should appear: "From your band" and an "approximate, sensor estimate" tag. Say: "Band values are estimates, and are never sent to an outside AI."
Fallback: recorded demo data; if even that fails, show the seeded value in history (moderate activity 90 to 120 minutes a week, source band, estimate).
Depends on: on-device only (Bluetooth), or the recorded demo.

### 11. Privacy (25 s)
Open **My data**. Say: "Everything is on this phone. Rosa said no to outside AI, so nothing about her goes to Muse. If she turns it on, the app asks for her consent first, per provider, and band values are never shared. She can turn memory off, which deletes her habit notes, or tap Delete my data to remove everything." Show **AI and privacy** (outside-AI switch OFF) and the **Delete my data** confirmation, then cancel.
Training disclosure: say "We use the Muse model variant that does not train on content. Any outside AI that may train on submitted text will be disclosed before it is switched on." The disclosure screen is pending UI; until then say it, do not show it.
Depends on: on-device only.

### 12. Close (10 s)
Say: "Voice or typing in, a modeled outlook, a score, what-ifs, a plan, documents and a wristband, all with sources, all on the phone."

## Known limitations to say out loud

- The model gives a **5-year** survival only. No lifespan, no death date, no years gained. The lifespan reveal is pending.
  - **Owner override (2026-10-24):** A rough expected year and age range may be shown once as a proof of concept, labelled as an estimate, never as a specific date. Method: [lifespan-estimate.md](lifespan-estimate.md) (the CDC 2024 life table plus the model owner's Cox relative risk, adjusted by age band). Scope: this one-time reveal only; the rule still applies everywhere else.
- It is trained for ages **35 to 79**. Outside that range ages are extrapolated and labeled; above 85 no number.
- Comparisons are modeled differences between profiles, not proof that a change will help.
- **Not medical advice.** Document values (blood pressure, A1c) are information only and are not model inputs. Wristband values are estimates.
- Emergency: if someone describes an emergency, the app stops and shows **Call 911**. That is the only emergency number. It does not handle other countries.
- The coach's plan is educational habit planning, not treatment. It does not recommend supplements.
- Outside AI (Muse) is off unless consent is given, and only reads identifier-stripped text.

## If it all goes wrong

- No network or server down: use the seeded phone. Steps 2, 3, 5, 9, 10 and 11 run on the phone alone.
- Voice fails: tap **Type instead** and say so ("typing is a complete alternative").
- Model shows no number: read the on-screen message. Never fill a number by hand.
- Rosa's dates look old: reseed on a fresh install the morning of the demo.
