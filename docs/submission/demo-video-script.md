# LifeTwin demo video: 2:58 shot list and measured rehearsal

For [#133](https://github.com/ViktorOsadsky/lifetwin/issues/133). Daniel records the spoken submission. Rehearsed build source: main `1a648bd`, with merged Ideas [#127](https://github.com/ViktorOsadsky/lifetwin/pull/127), projection [#126](https://github.com/ViktorOsadsky/lifetwin/pull/126), centred score [#138](https://github.com/ViktorOsadsky/lifetwin/pull/138), and score/range UI [#141](https://github.com/ViktorOsadsky/lifetwin/pull/141). The engine hold is resolved. **#138 supersedes #133's older 1.0-middle/1.65 copy: zero is now the survey-group middle.** The timeline below supplies the planned speaking pace. The actual silent simulator route measured **178.005 seconds**; Daniel's spoken recording remains pending.

**Later model-sync gate:** main `1a86d9a` subsequently changed the app Cox artifact/support reference, sensitivity and lifespan data, and `TwinModelService`. The measured run and screenshots below apply only to `1a648bd`; they do **not** establish demo acceptance, displayed score or timings for that newer model build. Keep the actual-score gate below and recheck the recording build after its model review/CI gate. The harness's +0.59 assertion is specific to the rehearsed pin. No new-model run is claimed.

Rosa is a fictional returning user with short sleep and long sitting days. Mochi helps her confirm her information, explore a manageable change and return to a daily routine. Use synthetic data throughout; no real account or patient record is required.

## Prepare one continuous capture

1. On a dedicated empty simulator installation, launch with `--dart-define=DEMO_SEED=1`. [The seed](../../app/lib/demo/demo_seed.dart) writes Rosa and relative-date history through the real repository only when no profile exists. It starts in Home with a saved profile; it does not start fresh onboarding, reset an existing account, or supply a hardcoded score. Do not delete anyone's real data. For another take, prepare a fresh disposable simulator installation; app restart alone does not reset check-ins or the one-time reveal.
2. Before capture, use **Add band → Find my band → Try a recorded demo**, then return Home. This enables the built-in synthetic week; do not wait for or imply real Bluetooth pairing. Keep recorded-demo mode on for the entire take. Band state is in memory, so avoid restarting afterward. Do not accept/dismiss its suggestion during preparation.
3. Open Home **Talk**. This opens the same intake screen even on the seeded app. Choose typing, keep the optional AI helper off for this template take, and answer the memory choice deliberately. Prepare the earlier answers **off camera**. This is rechecking the demo person's answers, not first-time onboarding. Use the seed's current saved answers: age 64; female; never smoked; 162.6 cm; 66.49 kg; usual sleep 6.9 hours; general health good; no diagnosed hypertension; no diabetes; sitting 420 minutes/day; moderate recreation 120 minutes/week. Skip optional habit follow-ups with “let's move on.” Decline the Apple Health offer for this typed path. Units matter; confirm each read-back.
4. Stop at the final **harder exercise** question (`vigorous_recreation_min_week`), before answering. Its wording may vary: “And harder exercise that makes you breathe hard, like jogging or tennis? How many minutes a week?” The final answer is **None** (0 minutes/week). [Twelve-question order](../../app/lib/onboarding/voice_onboarding_controller.dart), [question text](../../server/lifetwin/onboarding/script.py). The twelve proposed answer strings were checked with the repository's actual parser; this does not establish UI timing.
5. Before recording, verify the same repository has a complete supported profile, no check-in completed **today**, and `lifespanRevealSeen == false`. The seed does not set the reveal-seen flag. Completing this prepared intake saves as a Mochi change, then the ceremony can show the estimate once. [Route and save behavior](../../app/lib/main.dart), [repository semantics](../../app/lib/twin/twin_repository.dart). No hidden profile switch, reset or app relaunch occurs during capture.

Earlier answers are explicitly prepared. This take demonstrates intake completion; it does **not** time a full cold twelve-question onboarding. The supplied [portal document demo](../demo/upload-demo.md) describes a different fictional profile and cannot fill all required answers. For this take, show the import choice and use **Not now**; do not claim an upload/import occurred. A real import recording needs its own consent, candidate review and missing-field completion.

**Home number gate:** #133 asks for **1.65**, but no source sets that score. Use the actual model result after the confirmed re-intake, including any effective weekly inputs. Do not change the profile, overlay a fake number or replace a calculation to match a mockup. Record the verified displayed number in the rehearsal record below; the narration works with any supported result. Current zero-centred wording means the median of the same-sex, nearby-age survey reference, not a national average or survival probability.

A historical host preview at `787e71a` produced ratio 1.81 for Rosa, but #138 replaced that scale. The normal merged app at recording pin `1a648bd` renders **+0.59**, with “Healthier than 86 of 100 people your age,” on iOS 26.4. The rendered tested-pin Home and reveal screenshots confirm this value after the prepared re-intake. No number was edited to match 1.65.

## Shot list — 2:58 planned, 0:02 spare

Keep one uninterrupted screen capture after the preparation above. Read only the quoted narration; production notes are not spoken. Frame the full phone so disclaimers remain legible. A visible “Synthetic demo persona / recorded band data” caption may identify the setup; it must not cover UI values or warnings.

| Time / duration | Tap or type | Say | Must be visible |
|---|---|---|---|
| 0:00–0:25 / 25s — intake | Start on the prepared final question. Tap **Fill from Apple Health or a document**; show both options, choose **Not now**. Type **none**, send, confirm the read-back, then **Continue** when ready. | “Meet Rosa, our fictional demo person. We've prepared her earlier answers. Talk or type with Mochi, or fill from Apple Health or a document. You check what gets saved.” | Mochi; import sheet with **Use Apple Health** and **Upload a document**; typed answer and actual confirmation. No claim that importing or voice happened in this take. |
| 0:25–0:55 / 30s — reveal | Tap **Ask the ball**, let the ceremony finish; open **About this estimate** and hold the caveat for about 23 seconds before **Close**. | “First, an estimate: a rough guide, not a personal prediction. Then the focus moves to everyday habits.” | Real computed age/year/range and its estimate/caveat text, with its caveat. Any open-ended range retains **110+**, with the proof-of-concept caveat. A sentinel is not a reached threshold. Never narrate validated life expectancy. |
| 0:55–1:12 / 17s — Home | Tap the top **Back** control. Hold on score, Mochi and **Today**. | “Here's her actual model score. Zero is the middle of people her age in this survey group; positive is healthier. Today gives us somewhere to start.” | Actual computed score, survey comparison, Mochi and Today. **1.65 is a requested design value, not an asserted seed result.** Use the merged centred scale; the earlier 1.0-middle narration is superseded. |
| 1:12–1:37 / 25s — daily check-in | Tap **Check in** in Today. Use the prepared synthetic day: **7 hours**, **0 minutes hard and 20 minutes easy**, then **420 minutes** sitting. Hold the complete read-back for eight seconds before **Looks right**, finish, then **Back to my room**. | “A quick check-in records what actually happened. Missing days stay unknown. One good day isn't a promise of a changed outlook.” | Daily/quick check-in, read-back and saved acknowledgement. Do not open the longer weekly check-in or claim an overnight model improvement. |
| 1:37–2:02 / 25s — Experiment | Open **Experiment with your twin**. Choose **Moderate**, add one 15-minute step, tap **Use in my what-if**. Return to the Experiment hub. | “Rosa has some unhelpful patterns: long sitting days and short sleep. She can try one manageable change with her twin. These differences are linked, not proven. Her saved answers stay the same.” | Today/What-if twins, actual result including a tiny/flat/unsupported result if returned, **What-if only** and **Linked, not proven**. No invented benefit or years gained. |
| 2:02–2:28 / 26s — Ideas | Tap **Ideas for you** on the Experiment hub. Decline outside-AI wording if its provider consent appears (see #124 below). Hold the list for two seconds; open one actual idea and hold its explanation for fourteen seconds, then back to Experiment and room. | “Ideas for you turns that curiosity into a practical next step. We can see why it was suggested, and try it without changing the real profile.” | Returned idea and explanation, the modeled-difference disclaimer and any provider disclosure. Do not promise a particular idea or effect level before seeing the response. |
| 2:28–2:48 / 20s — band | Tap **Add band**; the prepared demo opens **Your band**. Tap **Week → Mochi has a suggestion → Use this** to reach its read-back. Leave without saving. | “Our homemade leg band can suggest an activity estimate for you to review. This is recorded demo data, not a live measurement. Nothing becomes an answer just because it's shown.” | **Recorded demo**, **Demo data**, wear coverage, actual estimate and confirmation controls. Do not imply Bluetooth worked, or accept the synthetic offer as a real observation. |
| 2:48–2:58 / 10s — close | Close read-back and return room, holding on Mochi. | “LifeTwin makes health information a kinder daily loop: confirm, explore, and check in again.” | Mochi and Home. End before 3:00. |

If any interaction exceeds its budget, stop and rehearse again; do not speed past consent, read-backs or limitations to make the clock. The 195-word narration has not yet been timed aloud; the silent UI result does not establish spoken-recording length.

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

**Known recording gate — [#124](https://github.com/ViktorOsadsky/lifetwin/issues/124):** the consented Muse rephrasing guard has a reproduced failure that can insert an unsupported weight-gain benefit into an unrelated recommendation. Until fixed and rechecked, use the verified template path for this take (decline outside-AI wording or leave its provider unconfigured). Do not present that claim as valid, silently skip a bad idea and call the run a pass, or imply this typed/template take demonstrates working live Muse wording. A future provider-backed take must verify the returned ideas and this regression first. The reproduction used a fake provider, not a live Muse call.

For a physical phone later, bind the server to `0.0.0.0` and use the Mac's reachable local address for `API_BASE_URL`; phone localhost points at the phone. No physical-device check was performed for this script.

If the outside internet/Muse/Cartesia fails while the local server is healthy, choose typing and supported template wording, retaining confirmations. If the LifeTwin server itself fails, intake/check-ins/Ideas cannot be presented as successful offline. Show the calm error once, preserve state, and use a clearly labeled **previously recorded** backup made from an accepted build, or resume after recovery. A backup does not establish a live provider call or replace a measured continuous run. Never substitute mocked successful screens.

## Measured rehearsal and handoff

**Passed: 178.005 seconds** for one continuous, readability-paced silent native XCTest UI route at main `1a648bd405df4c76b5c1dea3339194c31201913c`, on iPhone 17 Pro / iOS 26.4. Timer start: `2026-10-25T06:01:42Z` (October 24 Pacific). The complete native test passed in **221.267 seconds**, including off-camera UI preparation. Its eight measured beats include actual UI waits and reading holds. Explicit visible holds measured reveal-caveat 23.005s, daily-readback 8.004s, ideas-list 2.005s, idea-detail 14.004s. This was a paced machine-driven rehearsal with templates, not a spoken recording or continuous video. [Evidence, reproduction and limitations](../qa/demo-rehearsal-2026-10-24/README.md), [raw monotonic timings](../qa/demo-rehearsal-2026-10-24/timing.json), [route verification](../qa/demo-rehearsal-2026-10-24/route.json).

| Beat | Measured start → end (seconds) |
|---|---|
| intake | 0.004 → 25.003 |
| reveal | 25.003 → 55.005 |
| home | 55.005 → 72.004 |
| daily-checkin | 72.004 → 97.004 |
| experiment | 97.004 → 122.005 |
| ideas | 122.005 → 148.001 |
| band-demo | 148.001 → 168.004 |
| close | 168.004 → 178.005 |

The same repository continued from the disclosed final intake question through reveal, Home, confirmed daily check-in, a moderate-activity what-if, Ideas, recorded-band read-back and Home again. No profile swap, app restart or hidden reset occurred inside the timed segment. Home rendered **+0.59**, “Healthier than 86 of 100 people your age,” after re-intake and at close. The requested 1.65 and older 1.0-middle scale are not used. The one-step what-if honestly returned **About the same**; no benefit was fabricated.

The actual reveal screenshot retains **110+** and the separate full caveat is readable. The current caveat says “110+” means “at least 110”; this evidence records that UI wording, without interpreting it as guaranteed survival or validated life expectancy. The daily read-back visibly confirms 7 hours sleep, no out-of-breath activity, 20 minutes easy activity and 7 hours sitting before **Looks right**. The band week and read-back visibly label **Recorded demo / Demo data / Sensor estimate**. The synthetic band offer was closed without saving; final Home still shows +0.59.

Before → review → revision: the earlier script budgeted 3–4 minutes and used stale score examples. Source review exposed seeded Home, the one-time reveal and an incomplete document fixture. This script discloses earlier answers prepared off camera, uses the actual centred score and measures one continuous prepared route. Earlier attempts found harness selector/guard mistakes and two native-session interruptions; [the evidence notes](../qa/demo-rehearsal-2026-10-24/README.md#earlier-attempts-and-limits) preserve these separately from the passing take. No failed attempt is counted as a complete pass. An earlier mechanical take passed in 178.006 seconds, but held spare time on Home after leaving the daily read-back and Ideas detail. The final take moves that time onto the actual reading screens; it still does not establish human spoken timing.

Checks actually run: pinned source/route review; synthetic parser/protocol checks; one passing readability-paced tested-pin native UI route, plus the earlier mechanical pass recorded separately; visual inspection of selected synthetic screenshots; helper syntax, JSON and local Markdown targets; `git diff --check`. The app/server use the same pin. Only the disposable app copy lowers its SDK floor for installed Dart 3.13.0; repository SDK and all product code stay unchanged. The optional AI helper/provider is off and server keys are blank. Template Ideas returned and the cited detail opened; this does not recheck the #124 provider-backed claim guard.

Still pending: Daniel's spoken recording and actual read-aloud timing; live Muse/Cartesia; actual Health/document import; provider/server-failure recovery; cold full-intake timing; reduced motion, reconnect and continuous video capture. No physical phone was used. The 195 narration words fit a proposed pace only; no estimated reading allowance is reported as measured speech.

Delivery: earlier script [PR #135](https://github.com/ViktorOsadsky/lifetwin/pull/135) is merged; this rehearsal follow-up is committed locally for review, with PR/merge pending. Contracts affected: documentation and optional native QA instrumentation only; no app/API/model change. [#133](https://github.com/ViktorOsadsky/lifetwin/issues/133) now has measured dry-run evidence for this prepared typed/template route. Next dependency: review the later model sync and its CI, recheck the actual score and this route on the chosen recording build, then Daniel records the spoken take with the disclosed setup and limitations.
