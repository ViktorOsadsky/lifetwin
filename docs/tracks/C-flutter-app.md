# Track C: Flutter App

**Owner:** _TBD_ · **Master doc:** §2, §3, §4, §10, §11, §12 phases 2–3, §17 product criteria

Flutter / Dart and LottieFiles are confirmed. Follow [MASTER_PLAN.md](../../MASTER_PLAN.md) for current product requirements and [tech-stack.md](../tech-stack.md) for proposed packages. The latest user direction replaces the scientific dashboard/traditional intake experience with a mostly full-screen pet game inspired by Talking Tom. Charts and comparisons remain accessible as game activities/detail panels.

## Screens (master doc §10)

| Screen | Master doc | Must have |
|---|---|---|
| Game room | Updated §2.1 | Expressive original mascot/twin, playful props, short speech bubbles, minimal navigation chrome; entry points into activities |
| Mascot intake | Updated §2.2 | Offer health-document upload immediately with Apple Health and voice/text alternatives; confirm candidates, then ask only for missing required inputs. Upload is planned; captions/correction and text fallback remain required |
| Twin studio | Expanded §14 | SVG cosmetic layers and accessories independent of medical inputs; Lottie-compatible palette/asset conventions |
| Magic-ball fortune | Updated §3 | Mascot reveals the supported longevity outlook with Lottie motion; readable captions, horizon/model identity, uncertainty and curve details; unsupported results get a limitation instead of invented fortune |
| Experiment / compare | §4 extended | Separate hypothetical profile, explicit plan assumptions, supported controls, overlaid curves and server deltas; reset never mutates the confirmed baseline |
| Plan | §5 extended | Short daily schedule with citations, accept/edit/dismiss and completion feedback; explain revisions and keep apply-to-experiment separate |
| Quiz | New mode | Reviewed food/situation questions, immediate sick/recovery reactions, separate bounded game-health score, explanations and recovery/retry; duplicate submissions count once |

The game shell, voice/text and Apple Health paths now exist. Continue from the current app and master guide; do not replace working paths with the original fixture-flow plan. Upload and autonomous daily planning are follow-up work, not completed UI behavior.

## Rules

- Every personal survival probability/delta comes from the API (§3.1). Local quiz scores are separate deterministic game values; wrong answers never modify a prediction or confirmed medical input.
- `status: "unsupported"` → show `limitation.message`, draw no curve (§3.1).
- `ignored_fields` → show those inputs as informational (§2.2).
- Choose a cohesive accessible pet-game palette; the original spec's scientific palette is reference only. LottieFiles motion and SVG assets share colors and shape conventions.
- Scenarios stay in device memory by default; persistence is opt-in, with deletion; no account (§15).
- Keep confirmed inputs, intake drafts, experimental profiles, cosmetic state, and quiz health separate. Permission denial, unavailable audio, interruption and voice/text switching must preserve confirmed answers.
- Preload quiz reaction assets for immediate local feedback; supply static expressions/captions for reduced motion. Do not copy Talking Tom art or branding.
- API base URL comes from `--dart-define=API_BASE_URL=…`; see [ios-testing.md](../ios-testing.md).

## Work against the current backend

Follow [the backend run guide](../../server/README.md). Guided intake, curated plans and quiz content work keylessly; use the generated schemas and fixtures for parsing. Server predict now serves the installed DeepSurv artifact; compare/sensitivity still return 501/null. The on-device Cox package is a separate boundary with its own support rules. Render the selected model's actual results or unavailable state; never mix model values. Cartesia integration exists with limitations in the voice guide. There is no `contracts/stub_server.py`.

## October 23 product refinement (planned)

Build upload/import → confirm candidates → missing-field follow-up, with decline, unreadable-file and correction paths. Add a short daily schedule, real activity check-in and an explained next-plan revision. An immediate twin reaction acknowledges the log; it must not claim an overnight medical improvement. Preserve actual history separately from hypothetical activity. The existing backend daily check-in never updates the forecast; only explicit supported profile/window mappings may do that. Coordinate contracts and consent/local-history/scheduling decisions with B/D first. See [the meeting decisions](../meetings/2026-10-23-product-refinement.md).
