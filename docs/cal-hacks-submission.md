# LifeTwin submission draft

Updated October 24, 2026 for [#76](https://github.com/ViktorOsadsky/lifetwin/issues/76). Writing only: this does not publish to Devpost, create slides, change sharing, or claim the final demo was rehearsed. The user supplied the final public team names and Devpost handles below; Daniel owns stage timings/ratings and final submission. The earlier draft lived on the design-handoff branch; this version brings the updated copy onto main.

Sources of truth: [approved design handoff](design/agentic/agentic-handoff.md), [current demo script](demo-script.md), [packaged model card](../model_handoff/lifetwin_on_device/MODEL_CARD.md), [app model integration](../app/lib/README-model.md), [one-time lifespan method and owner override](lifespan-estimate.md) and [backend guide](../server/README.md). Design approvals describe the intended experience; the running demo must establish which screens are ready.

## Devpost description

**Project:** LifeTwin

**Tagline:** Meet your bear twin. Understand your health outlook, try a change, and build a daily routine with Mochi.

### The problem

Health information arrives in disconnected places: conversations, medical documents and activity records. A number alone does not help someone decide what to do next. We wanted a kind, approachable way to bring that information together, explore possibilities and return to small everyday habits.

### What LifeTwin does

LifeTwin makes the experience a pet game, led by Mochi and a customizable bear twin. Talk or type, bring supported information from Apple Health or a health document, and confirm what the app understood. Missing information stays missing rather than becoming an invented healthy answer. [Intake and document boundaries](../MASTER_PLAN.md)

The home experience leads with a health score based on Viktor's model and “Healthier than X of 100 people your age.” That comparison comes from the model's survey reference group; it is not a ranking of everyone in the country. The outlook explains modeled survival of similar people. X and every displayed outlook value come from the engine. [Model integration and comparison reference](../app/lib/twin/twin_model.dart)

A separate on-device engine supports a one-time rough expected age and age range, with an optional rounded calendar year. This is a labeled proof of concept that then recedes behind the daily companion experience; final reveal UI/device acceptance remains Daniel's check. [Lifespan reveal and method](lifespan-estimate.md)

Daily check-ins capture what actually happened. “Experiment with your twin” explores a hypothetical change without overwriting saved answers. A cited daily plan can adapt to feedback, while the twin responds with a friendly reaction. Game reactions and quiz points stay separate from medical inputs and predictions. [Demo flow](demo-script.md), [game and model boundaries](../MASTER_PLAN.md)

Health documents produce dated candidates for review; a lab reading is not automatically a model input. Our homemade band contributes device estimates through a local file import, with wear coverage and confirmation boundaries. Its unknown time stays unknown, and a recorded demo remains visibly synthetic. Bluetooth is a stretch feature, not a completed integration. [Document intake](document-upload.md), [band intake](wearable-file-format.md)

### How we built it

The app is Flutter/Dart, with locally bundled character art, Lottie motion, native iOS integrations and an on-device Cox survival model. Profile/history storage and model inference run on the phone; a FastAPI/Pydantic server supports conversations, extraction and educational planning. [App dependencies](../app/pubspec.yaml), [model package](../model_handoff/lifetwin_on_device/README.md), [backend guide](../server/README.md)

Muse is the current outside-AI option. Claude is reserved behind the same provider-consent interface and is not wired yet. The app names the configured provider and requests that provider's consent. Typing and deterministic fallbacks cover supported paths when outside AI is declined or unavailable. Provider keys stay server-side, and raw band records are not sent to outside AI. We make no unverified provider retention or training promise. [Provider adapters](../server/lifetwin/personalize/providers.py), [consent and data controls](../MASTER_PLAN.md)

We explored and reviewed screens in Claude Design, kept an export-based handoff in GitHub, used Figma for the character/scene asset library, and implemented the app with Claude Code and Codex. The final interface is led by the model-derived health score, experiments and daily check-ins. [Current approved screen sets](design/agentic/agentic-handoff.md), [Figma asset provenance](design/painted-card-direction.md)

### What we measured and what it means

For the selected Cox model, the later NHANES cycle test recorded a **C-index of 0.790 versus 0.727** for an age/sex baseline. Mean predicted versus observed five-year survival was **94.27% versus 94.67%**. These are measured model-evaluation results, not a claim of 79% accuracy or a result for an individual user. [Model card](../model_handoff/lifetwin_on_device/MODEL_CARD.md)

The Cox model's checked age range is **35–79**. The submission's broader **30–85** framing is a rough guide: ages 30–34 and 80–85 are outside that checked range and require the extrapolation label. Model outputs describe observational associations, not proof that a lifestyle change causes longer life. The model is a hackathon research prototype, has not been externally validated, and does not provide a clinical diagnosis, an exact death date or causal years gained. The selected package supports annual survival horizons one through five. [Model card](../model_handoff/lifetwin_on_device/MODEL_CARD.md), [app extrapolation wrapper](../app/lib/twin/twin_model.dart)

Separately, the one-time lifespan wrapper combines the CDC/NCHS *United States Life Tables, 2024* with the Cox model's relative risk, adjusted by assessment-age band and attenuated after five years. Its expected age, age range and optional rounded calendar year are rough extrapolations under the owner override. The five-year evaluation above does not validate these lifetime estimates, and calculation checks do not establish personal predictive validity. This proof of concept makes no exact-date, clinical or causal years-gained claim. [Method, assumptions and limitations](lifespan-estimate.md), [owner override](../AGENTS.md)

### What comes next

Validate the band classifications and their questionnaire mapping, complete Daniel's final device/UI acceptance, and evaluate usability with real participants. Synthetic personas and demo records help rehearse the flow; they are not evidence from a user study. Extend the experience only when the data, model support and consent boundaries justify it. [Band handoff](handoffs/band-file-intake.md), [synthetic usability disclosure](demo/voice-usability-demo.md)

## Figma-track stage log

Each entry below is under 200 words. Minutes and ratings are intentionally unmeasured placeholders. Confirm the historical tools/process with Daniel before submitting; this log does not claim that the latest Claude Design screens were generated in Figma Make.

### Ideation

**Tools:** Claude Design, Claude Code, GitHub product notes. **Minutes:** [fill in]. **Rating:** [fill in]/5.

We refined a longevity-prediction idea into a daily companion: bring health information, understand a supported outlook, try a hypothetical change and check in again. Early dashboard concepts gave way to a warm pet-game setting with Mochi. We kept uncertainty visible and dropped the promise of predicting a death date. The product refinement and approved design brief carried those decisions into the build. [Product notes](meetings/2026-10-23-product-refinement.md), [design brief](design/agentic/agentic-brief.md)

### Prototyping

**Tools:** Claude Design; Figma for the asset library. **Minutes:** [fill in]. **Rating:** [fill in]/5.

The approved screen sets explore the health-score home, experiments, check-ins, documents, quiz, customization, history and band experience. Designs use a friendly bear, large controls and progressive disclosure. Reviews address visual consistency, accessibility and honest model language. Figma holds character and scene asset work; the latest approved screen references are the Claude Design exports in GitHub. [Approved sets and reviews](design/agentic/agentic-handoff.md), [Figma assets](design/painted-card-direction.md)

### Handoff

**Tools:** GitHub, exported HTML/JPG references, written engine contracts. **Minutes:** [fill in]. **Rating:** [fill in]/5.

We committed screen references, source HTML and sprite layers so implementers could work without private canvas access. The written brief resolves screen conflicts and defines score sourcing, confirmed versus hypothetical data, provider consent and reduced-motion behavior. Design and engine work have distinct owners, with route/data seams documented for integration. The final review checks the rendered Flutter experience against the approved references rather than treating generated code as proof of completion. [Handoff](design/agentic/agentic-handoff.md), [engine guide](../app/lib/README-model.md)

### Code generation

**Tools:** Claude Code, Codex, Flutter/Dart, Xcode, GitHub PRs. **Minutes:** [fill in]. **Rating:** [fill in]/5.

Agents implemented the Flutter experience and its data adapters, while the packaged Cox model supplies supported outlooks on-device. FastAPI handles conversations and planning; optional outside-AI wording requires consent. Unit, widget and native integration checks cover data confirmation, game-health separation and failure paths. Code moves through short branches and checked PRs. Final on-device demonstration belongs to Daniel; neither a screen mockup nor synthetic acceptance data establishes a measured user outcome. [Development rules](../AGENTS.md), [demo dependencies](demo-script.md)

## Team

Public names, membership and Devpost handles were supplied by the user on October 24, including explicit confirmation of Shivam's hardware contribution. The other summaries describe documented work, rather than assigning new responsibilities: [product-refinement meeting](meetings/2026-10-23-product-refinement.md), [model track](tracks/A-data-model.md) and [design handoff](design/agentic/agentic-handoff.md).

| Public name | Devpost handle | Contribution |
|---|---|---|
| Justin Wu | [@justin-wu-ok](https://devpost.com/justin-wu-ok) | Product vision refinement |
| Viktor Osadsky | [@viktor-osadsky](https://devpost.com/viktor-osadsky) | Survival model and model evaluation |
| Daniel Qi | [@d-q222](https://devpost.com/d-q222) | Flutter app, UI and design integration |
| Shivam Vishal Patel | [@shivamp795](https://devpost.com/shivamp795) | Activity-band hardware prototyping |

## Final review for Daniel

- Review the contribution summaries with the team and fill stage minutes and ratings.
- Confirm the submission age wording: #76 requests the 30–85 rough-guide frame, while current app code also extrapolates ages 18–29. Neither extends the model's checked 35–79 range.
- Check every demo step against the merged app. The demo script includes pending-screen fallbacks; the band handoff separately records simulator Inbox, real Files-picker and cold Share success, with final designed-route/device acceptance still pending.
- Use the model card's measured figures verbatim and the demo engine's actual values on screen; do not reuse an illustrative personal number. Keep the selected package's one-to-five-year survival results separate from the one-time life-table wrapper. Label that reveal as a rough proof of concept with its caveat, never an exact date or a validated personal lifespan.
- Keep seeded history, synthetic usability sessions and fake document uploads labeled as demonstrations. A demo is not a real older-adult study.
- Add the final demo video, Figma Slides deck and design links, verify current track requirements and judge access, and submit from Daniel's account. These artifacts/account actions were not performed here.

Repository: [ViktorOsadsky/lifetwin](https://github.com/ViktorOsadsky/lifetwin). Figma asset file (access for Daniel to verify): [LifeTwin assets](https://www.figma.com/design/m2vIKuVlQQSa9m3ELVRdZc). Final slides: [fill in]. Final video: [fill in].
