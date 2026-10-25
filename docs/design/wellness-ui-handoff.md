# Wellness UI implementation handoff

## Scope and authority

This branch implements the FlareYun presentation lane for [Home #54](https://github.com/ViktorOsadsky/lifetwin/issues/54), [quiz/Customize #55](https://github.com/ViktorOsadsky/lifetwin/issues/55), [upload/plan/drivers #56](https://github.com/ViktorOsadsky/lifetwin/issues/56) and [Settings/History/errors #57](https://github.com/ViktorOsadsky/lifetwin/issues/57). These assignments supersede longevity as the returning Home hero; they do not authorize a new health-score formula.

The authenticated [LifeTwin Bear Design canvas](https://claude.ai/artifact/Smu6yoUWwhtuJCvdJsqVne#page-1bbb4611d096) was inspected: Q (17 artboards), R (26) and S (25). The Home K page has zero artboards, so Home follows #54. Existing sprites, scene plates, fonts and painted-card tokens are reused. Design sample measurements, probabilities and plan examples are not personal data or runtime defaults.

## Connected in the app

- Home shows `Getting to know you`, with no fabricated score, and an unknown seven-day trend. The estimate is behind `See your estimate`; it still requires a completed confirmed profile. Onboarding still ends in the existing reveal.
- The Room dock opens a three-question, offline quiz. Choosing an answer does not score until `Check my answer`. A wrong answer immediately changes only bounded game health and a mild tired pose. Reading then acknowledging the explanation recovers once; practice and repeated submissions do not score again. Rounds can be left without resetting game health. The controller is retained across Room visits for the app session.
- Quiz content is the reviewed bank 2.0 from `server/lifetwin/quiz/content/questions.json`, bundled at `app/assets/quiz/questions.json`. IDs include their versions. Update both copies when the reviewed bank changes. The source references remain available in explanations.
- Customize keeps its explicit Save/Back draft behavior and existing Bear/Human and Cal-hat options. The new Room tab applies Cozy/Morning/Twilight lighting to room scenery, never health or prediction state.

## Presentation boundaries ready for integration

| Surface | Inputs and callbacks | Remaining integration |
| --- | --- | --- |
| `HomeWellnessPanel` | `WellnessSnapshot`, local `now`, estimate/history/check-in callbacks | Replace the unknown snapshot with the twin repository's actual history and day logs. Supply the existing scheduler's due check-in callback; do not create a second check-in. |
| `HistoryScreen` | Read-only `WellnessDay` values, provenance, `goodWeeks`, time and change-through-Mochi callback | Map `TwinRepository.history({from, to})`, `dayLogs` and `goodWeeks()` when the engine PR lands. Each supplied value retains its source and estimated flag; unknown provenance is labeled unknown. Day detail is read-only. |
| `WellnessSettingsScreen` | A `ValueListenable<WellnessSettings>` plus route callbacks for memory, suggestions, reminders and My data; optional entries for History/import/band/voice | Wire to PR #58's existing screens and the final protected phone store. This surface performs no consent/deletion confirmation or independent persistence. The boolean suggestions field is display-only; the engine must keep consent keyed by provider ID and send that map on every request. Reminder display defaults to 10:00; scheduling stays with the owner. |
| `DocumentUploadView` | Stage, read-back/source/date and callbacks; includes stop, failure, narrow Muse consent, ownership, confirmation and conflict states | Bind PR #51 `DocumentUploadService` / `DocumentConfirmation`. Only that engine may OCR, retain recognized words temporarily or produce confirmed import candidates. Cancel/No must call its discard/cancel boundary; conflicts go through Mochi or keep the confirmed answer. |
| `DailyPlanScreen` / `HttpCoachClient` | Fresh confirmed context for every request, optional prior plan and persistence callback | Wire `/api/coach/plan` after PR #53. Context must come from confirmed profile/history, with current provider consent and local date/time. No quiz, cosmetic or experiment state belongs in it. |
| `OutlookDriversScreen` | Supported direction/label/reason plus existing Experiment callback | Map real model comparisons. No point values or years gained are rendered; old numerical effect wording is suppressed. Unsupported and flat directions remain explicit. |
| `WellnessErrorScreen` | One of server unavailable, mic denied, rate limited or offline, with one recovery callback | Reuse where the existing owner surfaces those failures. Text switching must preserve the conversation's state. |

The plan UI supports Yes/Change/Skip, Yes to all, Done/Not done with optional reason, source links, professional-review labels, revision explanations and facts → rule → evidence → action. Supplement suggestions and unknown action kinds are excluded. A 409 retains the displayed plan, disables choices and requires a fresh-context refresh; it never silently retries stale feedback. A failure to persist a response leaves the current displayed choice unchanged. Emergency/paused plans do not expose movement actions. Requests run only when this screen is opened or the user chooses an action; no background schedule is claimed.

## Outstanding work — do not close all four issues yet

1. Reconcile with [on-device store #47](https://github.com/ViktorOsadsky/lifetwin/pull/47), the planned `codex/c-twin-integration` history/provenance/reminder APIs, and [agentic UI #58](https://github.com/ViktorOsadsky/lifetwin/pull/58). The currently published #58 still has its own interim scheduler/consent stores and explicitly awaits that reconciliation. Preserve its Room state, check-in entry, Experiment, conversation and consent flows when resolving `main.dart` / `room_screen.dart`. Add the cosmetic `TwinAppearance.room` field to that lane’s appearance serialization; the current shell keeps it only for the app session.
2. Connect document extraction and planner engines after [#51](https://github.com/ViktorOsadsky/lifetwin/pull/51) and [#53](https://github.com/ViktorOsadsky/lifetwin/pull/53) merge. These are still draft dependencies as inspected. No replacement OCR/planner/store was created in this lane.
3. Complete Q's additional outfit/glasses/fur/helper art and pose mappings. The repository currently provides only plain and Cal-hat pose sets; existing unavailable options remain unavailable. Room lighting is not a claim that the full wardrobe is complete. Name/build changes must use the other lane's Mochi entry point, not direct edits.
4. Validate on an iOS simulator/device: OCR/pickers, protected storage, notification permissions, external source/phone links, VoiceOver and large Dynamic Type. Flutter widget renders do not establish native device behavior.

## Handoff record

Branch / PR / merge status: `codex/c-wellness-screens`; draft PR for review, not merged.

Changed files: `app/lib/wellness/`, `app/lib/quiz/`, bundled reviewed quiz content, Room/Home/Customize integration, relevant widget tests, and the master/team-plan documentation.

Contract or model versions affected: no server/model contract or score formula changed. The coach client targets PR #53's 1.0 protocol. Presentation DTOs and callbacks do not implement the promised repository APIs.

Checks run and results:

- `flutter analyze`: no issues in the temporary validation copy.
- Full `flutter test`: 268 passed. After strict coach parsing was tightened, the four coach tests passed again.
- `git diff --check`: passed. Bundled quiz content matches the reviewed server bank.
- Actual Flutter widget renders were inspected with the app fonts and images: Home and quiz at 390×844, Settings at 320×693 with 2× text. A Home card that obscured the bear was compacted; Settings labels now keep words intact.
- Local SDK is Flutter 3.47.0 / Dart 3.13.0; the repo requires Dart ^3.13.7 and CI pins Flutter 3.47.8. Only the temporary copy’s SDK constraint was lowered to run local checks. The repository constraint is unchanged. Its schema test used the original repository contract path in that temporary copy. CI remains the check on the pinned SDK.
- No backend behavior changed; no live provider, iOS OCR, physical device, notification or VoiceOver checks were run.

Real, fixture, or unavailable integrations: real bundled quiz/assets; actual Room navigation and cosmetic lighting. New engine-dependent panels use typed inputs/callbacks and are not yet exposed as connected health-data features.

Known limits / blockers: engine merges, final repository APIs, wardrobe art/pose mappings and native validation as listed above.

Next dependent task: integrate the final store APIs and owner routes, then verify the full Home → check-in → history → plan revision loop before closing #54–57.
