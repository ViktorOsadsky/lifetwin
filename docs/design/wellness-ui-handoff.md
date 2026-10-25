# Wellness UI implementation handoff

## Scope and authority

This branch implements the FlareYun presentation lane for [Home #54](https://github.com/ViktorOsadsky/lifetwin/issues/54), [quiz/Customize #55](https://github.com/ViktorOsadsky/lifetwin/issues/55), [upload/plan/drivers #56](https://github.com/ViktorOsadsky/lifetwin/issues/56) and [Settings/History/errors #57](https://github.com/ViktorOsadsky/lifetwin/issues/57). These assignments supersede longevity as the returning Home hero; they do not authorize a new health-score formula.

The authenticated [LifeTwin Bear Design canvas](https://claude.ai/artifact/Smu6yoUWwhtuJCvdJsqVne#page-1bbb4611d096) was inspected: Q (17 artboards), R (26) and S (25). The later GitHub export in [agentic/agentic-handoff.md](agentic/agentic-handoff.md), merged in #61, now includes approved K, Q, R and S screenshots and HTML; use those checked-in sources for further work. Home initially followed #54 while K was empty on the canvas. Existing sprites, scene plates, fonts and painted-card tokens are reused. Design sample measurements, probabilities and plan examples are not personal data or runtime defaults.

## Connected in the app

- Home shows `Getting to know you`, with no fabricated score. Its seven-day trend now reads real `TwinRepository.history()` and `dayLogs()` through `RepositoryWellness`; unrecorded days stay unknown. The estimate is behind `See your estimate`; it still requires a completed confirmed profile. Onboarding still ends in the existing reveal.
- `My history` opens the real repository history. Mixed per-value sources, estimated flags, confirmation times, previous values and later-corrected markers remain visible. Changes open the existing Mochi conversation. The good-week count comes from `goodWeeks()` and is not recomputed by the UI. Cosmetic room lighting is now included in the phone-store appearance serialization.
- The Room dock opens a three-question, offline quiz. Choosing an answer does not score until `Check my answer`. A wrong answer immediately changes only bounded game health and a mild tired pose. Reading then acknowledging the explanation recovers once; practice and repeated submissions do not score again. Rounds can be left without resetting game health. The controller is retained across Room visits for the app session.
- Quiz content is the reviewed bank 2.0 from `server/lifetwin/quiz/content/questions.json`, bundled at `app/assets/quiz/questions.json`. IDs include their versions. Update both copies when the reviewed bank changes. The source references remain available in explanations.
- Upload now runs the merged #51 OCR/extraction/confirmation engine in the shared painted UI. Muse consent uses the exact one-document wording. Stopped reads cannot send late OCR text or advance the screen. Conflicts with an existing confirmed value offer Mochi or keeping that value; they cannot overwrite it. Confirmed supported fields enter the existing conversation, which asks for missing inputs. Additional BP/A1c/LDL readings are explicitly not saved yet.
- `Today’s plan` opens the merged #53 coach for a confirmed adult profile. `coachContext()` reads fresh confirmed profile, recent day logs and wellbeing, BP readings, memory-authorized habit notes and scoped outside-AI consent on every request. `outsideAiProfile()` excludes band-derived profile values. The current visit retains choices/revisions; no persistent plan API, unattended schedule or cross-launch revision history is claimed.
- Customize keeps its explicit Save/Back draft behavior and existing Bear/Human and Cal-hat options. The new Room tab applies Cozy/Morning/Twilight lighting to room scenery, never health or prediction state.

## Presentation boundaries ready for integration

| Surface | Inputs and callbacks | Remaining integration |
| --- | --- | --- |
| `HomeWellnessPanel` / `HealthScoreSummary` | `WellnessSnapshot` (repository `healthScore`, `healthScoreStatus`, `ageGroupPercentile`, `healthScoreMessage`), estimate/history callbacks | Connected in `codex/c-ui-finish`: the score is the model's `log_relative_hazard_score` as is (signed, one decimal, lower is better), with "Healthier than X of 100 people your age", a Rough guide badge when `extrapolated`, and no number under 18. No day-dots or weekly counts near it. The same summary leads the estimate screen above the outlook. The check-in is #58's `CheckInEntry`, mounted by the Room. |
| `HistoryScreen` | Read-only `WellnessDay` values, provenance, `goodWeeks`, time and change-through-Mochi callback | Connected through `RepositoryWellness.historyDays()` to `TwinRepository.history({from, to})`, `dayLogs()` and `goodWeeks()`. Each supplied value retains its source and estimated flag; unknown provenance is labeled unknown. Day detail is read-only. |
| `WellnessSettingsScreen` | A `ValueListenable<WellnessSettings>` plus route callbacks for memory, suggestions, reminders and My data; optional entries for History/import/band/voice | Wire to PR #58's existing screens and the final protected phone store. This surface performs no consent/deletion confirmation or independent persistence. The boolean suggestions field is display-only; the engine must keep consent keyed by provider ID and send that map on every request. Reminder display defaults to 10:00; scheduling stays with the owner. |
| `DocumentUploadScreen` | The existing `DocumentUploadService` / `DocumentConfirmation`, optional current confirmed values, and the existing conversation import callback | Connected after #51. Cancellation uses generation guards in the existing service; no second OCR engine or health store. Persisting informational readings needs the repository owner’s API. `DocumentUploadView` remains an isolated presentation fixture, not the live route. |
| `DailyPlanScreen` / `HttpCoachClient` | Fresh confirmed context for every request, optional prior plan and persistence callback | Connected to merged #53 through `coachContext()` and the Room entry. Memory/provider changes are read afresh. Current-visit plans only; durable plan/feedback storage still needs a coordinated repository API. No quiz, cosmetic or experiment state belongs in the request. |
| `OutlookDriversScreen` | Supported direction/label/reason plus existing Experiment callback | Map real model comparisons. No point values or years gained are rendered; old numerical effect wording is suppressed. Unsupported and flat directions remain explicit. |
| `WellnessErrorScreen` | One of server unavailable, mic denied, rate limited or offline, with one recovery callback | Reuse where the existing owner surfaces those failures. Text switching must preserve the conversation's state. |

The plan UI supports Yes/Change/Skip, Yes to all, Done/Not done with optional reason, source links, professional-review labels, revision explanations and facts → rule → evidence → action. Supplement suggestions and unknown action kinds are excluded. A 409 retains the displayed plan, disables choices and requires a fresh-context refresh; it never silently retries stale feedback. A failure to persist a response leaves the current displayed choice unchanged. Emergency/paused plans do not expose movement actions. Requests run only when this screen is opened or the user chooses an action; no background schedule is claimed.

## Outstanding work — do not close all four issues yet

1. [On-device store #47](https://github.com/ViktorOsadsky/lifetwin/pull/47) and [twin integration #59](https://github.com/ViktorOsadsky/lifetwin/pull/59) merged and are incorporated here. The Home/History read adapter is connected. Finish the check-in entry and Settings routes when [agentic UI #58](https://github.com/ViktorOsadsky/lifetwin/pull/58) reconciles its interim scheduler/consent stores with #59. Preserve its Room state, Experiment, conversation and consent flows when resolving shared files.
2. #51 and #53 have merged and their live routes are connected. Coordinate an API for informational document readings and durable plan/feedback storage with the repository owner before writing either. The current UI does not create a parallel store.
3. Complete Q's additional outfit/glasses/fur/helper art and pose mappings. The new GitHub #61 export provides [cosmetic layers and their slot contract](agentic/sprite-layers/cosmetics/README.md). It arrived after the original asset search. Wire those layers rather than requesting another upload. The exported set is a draft: its README references a separate `rig.json` and sliced body parts that are not included, and non-front accessory views are incomplete. Whole-pose v2 sprites do not carry clothing slots. Correct body/arm compositing and palette mapping remain implementation work; do not paste front-view layers onto turned heads. Room lighting is not a claim that the full wardrobe is complete. Name/build changes must use the other lane's Mochi entry point, not direct edits.
4. Validate on an iOS simulator/device: OCR/pickers, protected storage, notification permissions, external source/phone links, VoiceOver and large Dynamic Type. Flutter widget renders do not establish native device behavior.

## Handoff record

Branch / PR / merge status: `codex/c-wellness-screens`; [draft PR #60](https://github.com/ViktorOsadsky/lifetwin/pull/60), not merged.

Changed files: `app/lib/wellness/`, `app/lib/quiz/`, bundled reviewed quiz content, Room/Home/Customize integration, relevant widget tests, and the master/team-plan documentation.

Contract or model versions affected: no server/model contract or score formula changed. The coach client targets PR #53's 1.0 protocol. Presentation DTOs and callbacks do not implement the promised repository APIs.

Checks run and results:

- `flutter analyze`: no issues in the temporary validation copy.
- Full `flutter test` after incorporating #51/#53/#61, the coach context adapter and pinned panel navigation: 433 passed. Targeted upload/coach adapter checks passed 23 tests. The live upload render capture passed. The adapter tests cover real day logs, mixed provenance/estimates, retained corrections, notification/deletion refresh, provider-scoped consent display and app navigation to History.
- `git diff --check`: passed. Bundled quiz content matches the reviewed server bank.
- Actual Flutter widget renders were inspected with the app fonts and images: the live upload choice/read-back routes after #51; Home, quiz, plan, populated History and document consent at 390×844; Settings at 320×693 with 2× text. A Home card that obscured the bear was compacted; Settings labels now keep words intact. Plan choices use readable ink and at least 48-point targets; a widget check verifies the text contrast is at least 4.5:1. Quiz confirmation and recovery return the viewport to Mochi’s response.
- Local SDK is Flutter 3.47.0 / Dart 3.13.0; the repo requires Dart ^3.13.7 and CI pins Flutter 3.47.8. Only the temporary copy’s SDK constraint was lowered to run local checks. The repository constraint is unchanged. Its schema and day-log model tests use the original repository contract/model paths in that temporary copy. CI remains the check on the pinned SDK.
- No backend behavior changed; no live provider, iOS OCR, physical device, notification or VoiceOver checks were run.

Real, fixture, or unavailable integrations: real bundled quiz/assets; actual Room navigation and cosmetic lighting. Home and History use the real phone repository and refresh on repository notifications. Upload and the stateless coach now use their real engines; live provider and native OCR behavior remain unverified. Settings and due check-in still await #58 integration.

Known limits / blockers: #58 entry-point reconciliation, coordinated reading/plan persistence APIs, wardrobe rig/pose mapping and native validation as listed above.

Next dependent task: integrate the remaining owner routes, then verify the full Home → check-in → history → plan revision loop before closing #54–57.
