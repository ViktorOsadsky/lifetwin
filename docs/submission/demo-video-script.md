# LifeTwin demo video: provisional 2:58 shot list

For [#133](https://github.com/ViktorOsadsky/lifetwin/issues/133). Daniel records. **This is a planned recording budget, not a timed simulator result or a recording-ready acceptance claim.** Reviewed main: `d055e26`; Ideas [#127](https://github.com/ViktorOsadsky/lifetwin/pull/127) is merged. Engine [#126](https://github.com/ViktorOsadsky/lifetwin/pull/126), reviewed at `787e71a`, is still open under its explicit owner hold. The 1.0-relative score narration below is conditional on its approved merge and verification. Current main still uses the negative-log score and CDC reveal. Do not bypass the hold to record this as shipped.

Rosa is a fictional returning user with short sleep and long sitting days. Mochi helps her confirm her information, explore a manageable change and return to a daily routine. Use synthetic data throughout; no real account or patient record is required.

## Prepare one continuous capture

1. On a dedicated empty simulator installation, launch with `--dart-define=DEMO_SEED=1`. [The seed](../../app/lib/demo/demo_seed.dart) writes Rosa and relative-date history through the real repository only when no profile exists. It starts in Home with a saved profile; it does not start fresh onboarding, reset an existing account, or supply a hardcoded score. Do not delete anyone's real data. For another take, prepare a fresh disposable simulator installation; app restart alone does not reset check-ins or the one-time reveal.
2. Before capture, use **Add band → Find my band → Try a recorded demo**, then return Home. This enables the built-in synthetic week; do not wait for or imply real Bluetooth pairing. Keep recorded-demo mode on for the entire take. Band state is in memory, so avoid restarting afterward. Do not accept/dismiss its suggestion during preparation.
3. Open Home **Talk**. This opens the same intake screen even on the seeded app. Choose typing, answer the memory/AI choices deliberately, and prepare the earlier answers **off camera**. This is rechecking the demo person's answers, not first-time onboarding. Use the seed's current saved answers: age 64; female; never smoked; 162.6 cm; 66.49 kg; usual sleep 6.9 hours; general health good; no diagnosed hypertension; no diabetes; sitting 420 minutes/day; moderate recreation 120 minutes/week. Skip optional habit follow-ups with “let's move on.” Decline the Apple Health offer for this typed path. Units matter; confirm each read-back.
4. Stop at the final **harder exercise** question (`vigorous_recreation_min_week`), before answering. Its wording may vary: “And harder exercise that makes you breathe hard, like jogging or tennis? How many minutes a week?” The final answer is **None** (0 minutes/week). [Twelve-question order](../../app/lib/onboarding/voice_onboarding_controller.dart), [question text](../../server/lifetwin/onboarding/script.py). The twelve proposed answer strings were checked with the repository's actual parser; this does not establish UI timing.
5. Before recording, verify the same repository has a complete supported profile, no check-in completed **today**, and `lifespanRevealSeen == false`. The seed does not set the reveal-seen flag. Completing this prepared intake saves as a Mochi change, then the ceremony can show the estimate once. [Route and save behavior](../../app/lib/main.dart), [repository semantics](../../app/lib/twin/twin_repository.dart). No hidden profile switch, reset or app relaunch occurs during capture.

Earlier answers are explicitly prepared. This take demonstrates intake completion; it does **not** time a full cold twelve-question onboarding. The supplied [portal document demo](../demo/upload-demo.md) describes a different fictional profile and cannot fill all required answers. For this take, show the import choice and use **Not now**; do not claim an upload/import occurred. A real import recording needs its own consent, candidate review and missing-field completion.

**Home number gate:** #133 asks for **1.65**, but no source sets that score. Use the actual model result after the confirmed re-intake, including any effective weekly inputs. Do not change the profile, overlay a fake number or replace a calculation to match a mockup. Record the verified displayed number in the rehearsal record below; the narration works with any supported result. The proposed 1.0 wording means the median of the same-sex, nearby-age survey reference, not a national average or survival probability.

## Shot list — 2:58 planned, 0:02 spare

Keep one uninterrupted screen capture after the preparation above. Read only the quoted narration; production notes are not spoken. Frame the full phone so disclaimers remain legible. A visible “Synthetic demo persona / recorded band data” caption may identify the setup; it must not cover UI values or warnings.

| Time / duration | Tap or type | Say | Must be visible |
|---|---|---|---|
| 0:00–0:32 / 32s — intake | Start on the prepared final question. Tap **Fill from Apple Health or a document**; show both options, choose **Not now**. Type **none**, send, confirm the read-back, then **Continue** when ready. | “Meet Rosa, our fictional demo person. We've prepared her earlier answers. Talk or type with Mochi, or fill from Apple Health or a document. You check what gets saved.” | Mochi; import sheet with **Use Apple Health** and **Upload a document**; typed answer and actual confirmation. No claim that importing or voice happened in this take. |
| 0:32–0:47 / 15s — reveal | Tap **Ask the ball**, let the ceremony finish; open the estimate info control if needed. | “First, an estimate: a rough guide, not a personal prediction. Then the focus moves to everyday habits.” | Real computed age/year/range and its estimate/caveat text, with any applicable Rough guide or open-ended label intact. Show actual output; never narrate it as validated life expectancy. |
| 0:47–1:04 / 17s — Home | Return **Back to room**. Hold on score, Mochi and **Today**. | “Here's her model-derived health score. One point zero means the middle of people your age in this survey group; higher is better. Today gives us somewhere to start.” | Actual computed score, survey comparison, Mochi and Today. **1.65 is a requested design value, not an asserted seed result.** Do not use this narration on the old score scale. |
| 1:04–1:29 / 25s — daily check-in | Tap **Check in** in Today. Use truthful synthetic quick answers for the questions actually asked; review **Looks right**, finish, then **Back to my room**. | “A quick check-in records what actually happened. Missing days stay unknown. One good day isn't a promise of a changed outlook.” | Daily/quick check-in, read-back and saved acknowledgement. Do not open the longer weekly check-in or claim an overnight model improvement. |
| 1:29–2:02 / 33s — Experiment | Open **Experiment with your twin**. Choose **Moderate**, add one 15-minute step, tap **Use in my what-if**; **See side by side** if time permits. Return to the Experiment hub. | “Rosa has some unhelpful patterns: long sitting days and short sleep. She can try one manageable change with her twin. These differences are linked, not proven. Her saved answers stay the same.” | Today/What-if twins, actual result including a tiny/flat/unsupported result if returned, **What-if only** and **Linked, not proven**. No invented benefit or years gained. |
| 2:02–2:22 / 20s — Ideas | Tap **Ideas for you** on the Experiment hub. Answer the configured provider's consent if it appears. Open one actual idea to show its explanation; back to Experiment, then room. | “Ideas for you turns that curiosity into a practical next step. We can see why it was suggested, and try it without changing the real profile.” | Returned idea and explanation, the modeled-difference disclaimer and any provider disclosure. Do not promise a particular idea or effect level before seeing the response. |
| 2:22–2:48 / 26s — band | Tap **Add band**; the prepared demo opens **Your band**. Tap **Week → Mochi has a suggestion → Use this** to reach its read-back. Leave without saving. | “Our homemade leg band can suggest an activity estimate for you to review. This is recorded demo data, not a live measurement. Nothing becomes an answer just because it's shown.” | **Recorded demo**, **Demo data**, wear coverage, actual estimate and confirmation controls. Do not imply Bluetooth worked, or accept the synthetic offer as a real observation. |
| 2:48–2:58 / 10s — close | Close read-back and return room, holding on Mochi. | “LifeTwin brings scattered health information into a kinder daily loop: confirm, explore, and check in again.” | Mochi and Home. End before 3:00. |

If any interaction exceeds its budget, stop and rehearse again; do not speed past consent, read-backs or limitations to make the clock. Short fallback cut: 22s intake + 7s reveal + 10s Home + 18s check-in + 23s Experiment + 15s Ideas + 18s band + 7s close = **2:00 planned**. Keep all beats, use shorter narration and omit optional info/side-by-side detail; this variant also needs its own measured run.

## Server, Muse and voice

Follow [the backend run guide](../../server/README.md) from the repository root:

```sh
uv sync --locked --python 3.11
uv run uvicorn lifetwin.app:app --host 127.0.0.1 --port 8000 --no-access-log
```

Use a local untracked `.env`, as read by [server settings](../../server/lifetwin/core/config.py), with names from [`.env.example`](../../.env.example). Never show credentials in a recording. `ONBOARDING_DEMO=1` limits optional habit follow-ups; it does not remove required questions. For the simulator, launch from `app/` with the chosen simulator ID:

```sh
flutter run -d <simulator-id> --dart-define=API_BASE_URL=http://localhost:8000 --dart-define=DEMO_SEED=1
```

| Capability | Needs | Recording choice / fallback |
|---|---|---|
| Stored profile/history, Cox score, supported Experiment and recorded-band screens | Bundled assets and local repository; no provider key | Local inference is separate from the server's `/api/predict` engine. Use actual outputs. |
| Intake, daily check-in, Today plan, Ideas | Reachable LifeTwin FastAPI server | Keep local server running even for keyless mode. `/ready` establishes service readiness, not live Muse/voice readiness. |
| Muse optional extraction/wording | `LLM_PROVIDER=chat_completions`, `LLM_BASE_URL`, `LLM_MODEL`, `LLM_API_KEY`; `PERSONALIZE_PROVIDER=muse`; explicit consent | Verify account-available model and endpoint locally. `.env.example` gives `muse-spark-1.3` as an example, not proof of access. Declined/unconfigured wording uses templates on supported server paths. Claude remains unwired. |
| Spoken input/output | Server `CARTESIA_API_KEY`, `CARTESIA_VOICE_ID` and configured voice model/version settings; microphone/provider consent | Optional for this typed take. Use **Type instead** if unavailable; do not narrate typed input as voice. Short-lived tokens reach the app; master keys stay server-side. See [voice setup](../voice-cartesia.md). |
| Apple Health / documents | OS permission or Files/OCR plus the relevant server route; document outside-AI processing additionally needs its consent/configuration | This script shows their chooser only. Simulator Health availability does not establish physical-device import success. See [Apple Health](../apple-health.md) and [document boundaries](../document-upload.md). |

For a physical phone later, bind the server to `0.0.0.0` and use the Mac's reachable local address for `API_BASE_URL`; phone localhost points at the phone. No physical-device check was performed for this script.

If the outside internet/Muse/Cartesia fails while the local server is healthy, choose typing and supported template wording, retaining confirmations. If the LifeTwin server itself fails, intake/check-ins/Ideas cannot be presented as successful offline. Show the calm error once, preserve state, and use a clearly labeled **previously recorded** backup made from an accepted build, or resume after recovery. A backup does not establish a live provider call or satisfy this pending continuous-run check. Never substitute mocked successful screens.

## Rehearsal and handoff — completion pending

Before → review → revision: the older [demo script](../demo-script.md) budgets 3–4 minutes and gives stale signed-score examples. Source review found seeded Home, a separate full intake controller, a one-time reveal and an incomplete document fixture. This version uses a disclosed prepared re-intake on the same repository, an actual-result score gate and an explicit 2:58 budget. No existing UI, seed, prediction or provider contract changed.

Checks actually run: local route/label/state review at main `d055e26`; #127 merged status and #126 held source/body inspected; all twelve synthetic typed answers checked with `parse_reply`; Markdown targets and `git diff --check`. These are source/parser checks, not rendered UI or device acceptance. No simulator run, provider call, cold-start stopwatch or measured read-aloud rehearsal has been claimed.

| Required evidence after the gate | Actual result |
|---|---|
| Approved merged #126 commit and merged #127 verified against recording build | **PENDING — #126 owner hold** |
| Synthetic Rosa Home displayed score after the prepared re-intake; explain any difference from requested 1.65 | **PENDING — accepted-build verification** |
| Intake → reveal → Home continuity; no hidden reset/profile swap | **PENDING — simulator dry run** |
| Exact total and per-beat elapsed times, including waits, consent and confirmation | **PENDING — simulator dry run; target ≤3:00** |
| Leg-band Demo label, suggestion eligibility and read-back visible; no synthetic save | **PENDING — simulator dry run** |
| Internet/provider failure → honest typed/template path; server failure → preserved error state | **PENDING — rehearsal** |
| Readability, cold load, reduced motion, screen recording/reconnect and one fresh repeat | **PENDING — Daniel's recording-build rehearsal** |

PR/merge state: documentation branch only; not published or merged by this author. Next dependency: respect #126's hold, then reconcile against the approved merged code and run/timestamp this exact prepared route on the simulator. Record actual score and total here, revise the budget if needed, and obtain Daniel's final recording acceptance. This document intentionally leaves #133's measured dry-run requirement unfinished until that gate clears.
