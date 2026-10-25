# Synthetic voice-usability demo

**All observations and numbers here are invented for a demo. No people were recruited, no sessions took place, and no live Cartesia measurements were made.** The user requested fake demo data instead of actual participant results in this run. This does not meet or replace the real-user acceptance criteria in [#13](https://github.com/ViktorOsadsky/lifetwin/issues/13).

The files [synthetic-sessions.csv](../../demo/voice-usability/synthetic-sessions.csv) and [synthetic-summary.json](../../demo/voice-usability/synthetic-summary.json) illustrate how the team can record five fictional personas aged 67–85 across the seven issue tasks. Every CSV row carries `synthetic_demo=true`; the summary records zero real participants/sessions and no provider measurements. Ages, setups, observations, completion times and ease ratings are simulated. The scripted setups do not imply that age, accents or hearing aids cause failures.

## Demo script

1. State aloud that this is a synthetic reporting example, not a completed usability study.
2. Show one fictional persona's seven rows: onboarding, loose answers, correction, interruption, repeat, switching modes and denying the microphone.
3. Use the scripted lines as sample inputs, never as quotes from a real participant. For a correction, offer an invented height, change it and require a fresh read-back. Confirmed values must survive voice/text switching.
4. Show the two **simulated** failures and three **simulated** hint cases as examples of triage entries. They are not evidence of actual product defects.
5. End with the real validation still needed: 3–5 adults aged 65+ using invented health answers, observed without coaching, with actual completion, timing, recognition/correction, accessibility and ease results. Keep real results in a separate file with consent and no identifying health records.

The simulated report has 30 tasks completed alone, three with a hint and two failures, out of 35. The simulated mean ease rating is 4.0/5. **Do not use these numbers as a product-quality claim, pass bar, pitch metric or user-study finding.** The existing fixture's zero wrong values saved is scripted, not measured evidence that the real confirmation boundary works.

This work changes no UI, speech provider or health data. Native behavior and actual older-adult usability remain unverified.
