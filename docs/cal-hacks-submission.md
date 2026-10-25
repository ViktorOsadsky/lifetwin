# LifeTwin submission draft

Updated October 24, 2026 for [#76](https://github.com/ViktorOsadsky/lifetwin/issues/76). Writing only: this does not publish to Devpost, create slides, change sharing, or claim the final demo was rehearsed. The user supplied the final public team names and Devpost handles below; Daniel owns stage timings/ratings and final submission. The earlier draft lived on the design-handoff branch; this version brings the updated copy onto main.

Sources of truth: [approved design handoff](design/agentic/agentic-handoff.md), [current demo script](demo-script.md), [packaged model card](../model_handoff/lifetwin_on_device/MODEL_CARD.md), [app model integration](../app/lib/README-model.md), [current centred score and blended reveal](handoffs/hazard-projection-docs.md) and [backend guide](../server/README.md). Design approvals describe the intended experience; the running demo must establish which screens are ready. Main at `9ace866` includes [PR #126](https://github.com/ViktorOsadsky/lifetwin/pull/126)'s blended reveal and [PR #138](https://github.com/ViktorOsadsky/lifetwin/pull/138)'s centred Cox score. The earlier owner hold and 1.0-relative score are superseded; merged code availability does not establish a rehearsed demo. The later Cox v3 handoff at `1a86d9a` replaces the model/reference and sensitivity data and uses history tag `cox_centered_bmi35_v2`. The simulator rehearsal is pinned to the earlier `1a648bd`; it does not validate the replacement model or its displayed values.

## Devpost description

**Project:** LifeTwin

**Tagline:** Meet your bear twin. Understand your health outlook, try a change, and build a daily routine with Mochi.

### The problem

Health information arrives in disconnected places: conversations, medical documents and activity records. A number alone does not help someone decide what to do next. We wanted a kind, approachable way to bring that information together, explore possibilities and return to small everyday habits.

### What LifeTwin does

LifeTwin makes the experience a pet game, led by Mochi and a customizable bear twin. Talk or type, bring supported information from Apple Health or a health document, and confirm what the app understood. Missing information stays missing rather than becoming an invented healthy answer. [Intake and document boundaries](../MASTER_PLAN.md)

The home experience leads with Viktor's centred Cox score: the survey group's median log hazard minus the profile's log hazard, removing age/sex terms from both. **0 is the group middle; positive is healthier and higher is better.** “Healthier than X of 100 people your age” uses the same-sex, nearby-age survey reference, not everyone in the country. The score is not a survival probability and there is no separate lower-is-better hazard-index getter. [Current score](../app/lib/twin/twin_model.dart), [contract](handoffs/hazard-projection-docs.md)

The one-time rough reveal blends CDC life-table ages with repeated one-year Cox projection summaries, advancing age with other inputs fixed: “assuming nothing changes.” Projection weight rises from zero at 35 to one at 45, stays one through 70 and fades to zero at 79. This proof of concept is not validated personal life expectancy; nothing past 79 is validated in the rough guide. [Current method](handoffs/hazard-projection-docs.md)

Daily check-ins capture what actually happened. “Experiment with your twin” explores a hypothetical change without overwriting saved answers. A cited daily plan can adapt to feedback, while the twin responds with a friendly reaction. Game reactions and quiz points stay separate from medical inputs and predictions. [Demo flow](demo-script.md), [game and model boundaries](../MASTER_PLAN.md)

Health documents produce dated candidates for review; a lab reading is not automatically a model input. Our homemade band contributes device estimates through a local file import, with wear coverage and confirmation boundaries. Its unknown time stays unknown, and a recorded demo remains visibly synthetic. Bluetooth is a stretch feature, not a completed integration. [Document intake](document-upload.md), [band intake](wearable-file-format.md)

### How we built it

The app is Flutter/Dart, with locally bundled character art, Lottie motion, native iOS integrations and an on-device Cox survival model. Profile/history storage and model inference run on the phone; a FastAPI/Pydantic server supports conversations, extraction and educational planning. [App dependencies](../app/pubspec.yaml), [bundled app model package](../app/packages/lifetwin_on_device/README.md), [backend guide](../server/README.md)

Muse is the current outside-AI option. Claude is reserved behind the same provider-consent interface and is not wired yet. The app names the configured provider and requests that provider's consent. Typing and deterministic fallbacks cover supported paths when outside AI is declined or unavailable. Provider keys stay server-side, and raw band records are not sent to outside AI. We make no unverified provider retention or training promise. [Provider adapters](../server/lifetwin/personalize/providers.py), [consent and data controls](../MASTER_PLAN.md)

We explored and reviewed screens in Claude Design, kept an export-based handoff in GitHub, used Figma for the character/scene asset library, and implemented the app with Claude Code and Codex. Main keeps displayed score/reveal outputs Cox-based. Its shared lab loads and computes a neural output that the app does not read; “shelved” does not mean neural execution or artifacts were removed. The final interface is led by the model-derived health score, experiments and daily check-ins. [Current approved screen sets](design/agentic/agentic-handoff.md), [Figma asset provenance](design/painted-card-direction.md)

### What we measured and what it means

For the selected Cox v3 refit (`personal-cox-bmi35-v3-20261024`), the later NHANES cycle test recorded a **C-index of 0.7914**. Mean predicted versus observed five-year survival was **94.28% versus 94.67%**. These are measured model-evaluation results, not a claim of 79% accuracy or a result for an individual user. [Model card](../model_handoff/lifetwin_on_device/MODEL_CARD.md)

The Cox model's checked age range is **35–79**. The submission's broader **30–85** framing is a rough guide: ages 30–34 and 80–85 are outside that checked range and require the extrapolation label. Model outputs describe observational associations, not proof that a lifestyle change causes longer life. The model is a hackathon research prototype, has not been externally validated, and does not provide a clinical diagnosis, an exact death date or causal years gained. The selected package supports annual survival horizons one through five. [Model card](../model_handoff/lifetwin_on_device/MODEL_CARD.md), [app extrapolation wrapper](../app/lib/twin/twin_model.dart)

The reveal blends CDC mean/percentile ages with the yearly projection's 50%/75%/25% crossing ages. An unreached projection threshold at 110 keeps its open-ended flag only when the blended value remains at least 110; the headline then shows **110+**, not a measured crossing or guaranteed age. Rough guide applies where CDC has the larger weight (completed ages 18–39 and 75–85); fractional ages floor the projection input while retaining the fractional blend weight. The earlier large method-switch steps are resolved, but remaining years increasing at 35–45 and expected age falling at 70–79 remain an acknowledged known bug. Cox evaluation and arithmetic checks do not validate these lifetime results or trends. [Current contract](handoffs/hazard-projection-docs.md), [yearly recurrence](../model_handoff/lifetwin_on_device/README.md#projection-definitions)

### What comes next

Validate the band classifications and their questionnaire mapping, complete Daniel's final device/UI acceptance, and evaluate usability with real participants. Synthetic personas and demo records help rehearse the flow; they are not evidence from a user study. Extend the experience only when the data, model support and consent boundaries justify it. [Band handoff](handoffs/band-file-intake.md), [synthetic usability disclosure](demo/voice-usability-demo.md)

## Figma-track stage log

Each entry below is under 200 words. Minutes and ratings are intentionally unmeasured placeholders. Confirm the historical tools/process with Daniel before submitting; this log does not claim that the latest Claude Design screens were generated in Figma Make.

### Ideation

**Tools:** Claude Design, Claude Code, GitHub product notes. **Minutes:** [fill in]. **Rating:** [fill in]/5.

We refined a longevity-prediction idea into a daily companion: bring health information, understand a supported outlook, try a hypothetical change and check in again. Early dashboard concepts gave way to a warm pet-game setting with Mochi. We kept uncertainty visible and dropped the promise of predicting a death date. The product refinement and approved design brief carried those decisions into the build. The merged app now uses a centred Cox score: zero is the survey-group middle and positive is healthier. The yearly rough guide remains unvalidated; code availability and demo acceptance stay separate. [Product notes](meetings/2026-10-23-product-refinement.md), [design brief](design/agentic/agentic-brief.md)

### Prototyping

**Tools:** Claude Design; Figma for the asset library. **Minutes:** [fill in]. **Rating:** [fill in]/5.

The approved screen sets explore the health-score home, experiments, check-ins, documents, quiz, customization, history and band experience. Designs use a friendly bear, large controls and progressive disclosure. Reviews address visual consistency, accessibility and honest model language. Figma holds character and scene asset work; the latest approved screen references are the Claude Design exports in GitHub. The centred score uses zero for the survey-group middle, with higher better; open-ended blended ages and unresolved aging trends need clear disclosure. Model integration alone does not establish rendered-screen acceptance. [Approved sets and reviews](design/agentic/agentic-handoff.md), [Figma assets](design/painted-card-direction.md)

### Handoff

**Tools:** GitHub, exported HTML/JPG references, written engine contracts. **Minutes:** [fill in]. **Rating:** [fill in]/5.

We committed screen references, source HTML and sprite layers so implementers could work without private canvas access. The written brief resolves screen conflicts and defines score sourcing, confirmed versus hypothetical data, provider consent and reduced-motion behavior. Design and engine work have distinct owners, with route/data seams documented for integration. The final review checks the rendered Flutter experience against the approved references rather than treating generated code as proof of completion. The handoff follows merged PRs #126 and #138: centred scores, CDC/projection blending, conditional open-ended flags and fractional-age flooring. Aging-trend defects remain unresolved. We inspect the merged contract and keep device/demo acceptance separate. [Handoff](design/agentic/agentic-handoff.md), [engine guide](../app/lib/README-model.md), [transition handoff](handoffs/hazard-projection-docs.md)

### Code generation

**Tools:** Claude Code, Codex, Flutter/Dart, Xcode, GitHub PRs. **Minutes:** [fill in]. **Rating:** [fill in]/5.

Agents implemented the Flutter experience and its data adapters, while the packaged Cox model supplies supported outlooks on-device. Main supplies the centred Cox score, survey percentile and CDC/projection blend with conditional open-ended flags. Its shared lab still computes neural output that the app does not read. FastAPI handles conversations and planning; optional outside-AI wording requires consent. Unit, widget and native integration checks cover data confirmation, game-health separation and failure paths. Code moves through short branches and checked PRs. Final on-device demonstration belongs to Daniel; neither a screen mockup nor synthetic acceptance data establishes a measured user outcome. [Development rules](../AGENTS.md), [demo dependencies](demo-script.md), [engine transition](handoffs/hazard-projection-docs.md)

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
- Use merged #126/#138 semantics: zero is the survey-group score middle, positive is healthier, and no separate hazard-index getter exists. Show conditional open-ended flags rather than treating 110 as a measured crossing; disclose CDC/projection weights, fractional-age flooring and unresolved aging trends. Use actual engine values and measured model-card figures. The yearly guide assumes nothing changes, is not life expectancy, and validates nothing past 79; no exact date or causal years gained.
- Keep seeded history, synthetic usability sessions and fake document uploads labeled as demonstrations. A demo is not a real older-adult study.
- Add the final demo video, Figma Slides deck and design links, verify current track requirements and judge access, and submit from Daniel's account. These artifacts/account actions were not performed here.

Repository: [ViktorOsadsky/lifetwin](https://github.com/ViktorOsadsky/lifetwin). Figma asset file (access for Daniel to verify): [LifeTwin assets](https://www.figma.com/design/m2vIKuVlQQSa9m3ELVRdZc). Final slides: [fill in]. Final video: [fill in].
