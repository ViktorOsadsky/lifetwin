# Track C: Flutter App

**Owner:** _TBD_ · **Master doc:** §2, §3, §4, §10, §11, §12 phases 2–3, §17 product criteria

Flutter / Dart and LottieFiles are confirmed. Follow [MASTER_PLAN.md](../../MASTER_PLAN.md) for current product requirements and [tech-stack.md](../tech-stack.md) for proposed packages. The latest user direction replaces the scientific dashboard/traditional intake experience with a mostly full-screen pet game inspired by Talking Tom. Charts and comparisons remain accessible as game activities/detail panels.

## Screens (master doc §10)

| Screen | Master doc | Must have |
|---|---|---|
| Game room | Updated §2.1 | Expressive original mascot/twin, playful props, short speech bubbles, minimal navigation chrome; entry points into activities |
| Mascot intake | Updated §2.2 | Voice-first questions and equally capable text conversation; captions, explicit candidate-value confirmation/correction, progress and unit clarification; no traditional multi-screen health form. Voice provider deferred |
| Twin studio | Expanded §14 | SVG cosmetic layers and accessories independent of medical inputs; Lottie-compatible palette/asset conventions |
| Magic-ball fortune | Updated §3 | Mascot reveals the supported longevity outlook with Lottie motion; readable captions, horizon/model identity, uncertainty and curve details; unsupported results get a limitation instead of invented fortune |
| Experiment / compare | §4 extended | Separate hypothetical profile, explicit plan assumptions, supported controls, overlaid curves and server deltas; reset never mutates the confirmed baseline |
| Plan | §5 extended | Cited suggestions, evidence/model distinction, optional research items, explicit apply-to-experiment action |
| Quiz | New mode | Reviewed food/situation questions, immediate sick/recovery reactions, separate bounded game-health score, explanations and recovery/retry; duplicate submissions count once |

First ship the text conversation → confirmed profile → fixture fortune → experiment loop in the game shell. Then connect the real model, plan, quiz and selected voice integration according to the master guide's gates. Labeled text/audio stubs are scaffolding, not completed voice support.

## Rules

- Every personal survival probability/delta comes from the API (§3.1). Local quiz scores are separate deterministic game values; wrong answers never modify a prediction or confirmed medical input.
- `status: "unsupported"` → show `limitation.message`, draw no curve (§3.1).
- `ignored_fields` → show those inputs as informational (§2.2).
- Choose a cohesive accessible pet-game palette; the original spec's scientific palette is reference only. LottieFiles motion and SVG assets share colors and shape conventions.
- Scenarios stay in device memory by default; persistence is opt-in, with deletion; no account (§15).
- Keep confirmed inputs, intake drafts, experimental profiles, cosmetic state, and quiz health separate. Permission denial, unavailable audio, interruption and voice/text switching must preserve confirmed answers.
- Preload quiz reaction assets for immediate local feedback; supply static expressions/captions for reduced motion. Do not copy Talking Tom art or branding.
- API base URL comes from `--dart-define=API_BASE_URL=…`; see [ios-testing.md](../ios-testing.md).

## Work against the stub

After Contract Zero lands, run `python3 contracts/stub_server.py` and build the flow on its visibly fake numbers (`model_version: "stub-0"`). The planned sample
responses in `contracts/fixtures/` cover every state you need to render: a typical profile, risk factors, a minor, an
out-of-range age and the §4.1 demo futures.
