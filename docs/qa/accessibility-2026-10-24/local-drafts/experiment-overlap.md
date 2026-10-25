[P2][Experiment] Large text name badge overlaps Today / What-if labels

Pinned main: 1a648bd405df4c76b5c1dea3339194c31201913c. iPhone 18 Pro simulator, iOS 27.0 / Xcode 27.0. Light appearance, system Large text, temporary app-only TextScaler.linear(1.6). Runtime read-back: 17→27.2 pt, 20→32 pt, 48→76.8 pt. Synthetic DEMO_SEED=1 profile; no production UI edits.

Reproduce: open Home → Experiment with your twin; inspect the comparison plate after navigation settles.

Actual: the centered { My twin } name badge covers the upper portions of both Today and What-if labels. The main content and footer caveat remain readable. This does not claim controls are unreachable.

Expected: the name and both mode labels remain fully readable without overlap at large text sizes.

Source context: app/lib/experiment/experiment_screen.dart:174 at the pinned commit positions mode pills at a fixed top offset within ExperimentPlate. Design owner chooses the fix.

Evidence: final-scale16-readable/scale16-experiment-hub.png plus font-readback.json and native tree. Two independent reviewers confirmed the overlap. Original-pixel evidence will be committed with #134. After the initial automatic-review rejection, the user explicitly approved publication and root filed #147: https://github.com/ViktorOsadsky/lifetwin/issues/147 . This is the retained local draft; no duplicate filing is needed.
