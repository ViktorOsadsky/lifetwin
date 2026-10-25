[P2][Check-in] Large text sleep question is clipped while the keyboard is open

Pinned main: 1a648bd405df4c76b5c1dea3339194c31201913c. iPhone 18 Pro simulator, iOS 27.0 / Xcode 27.0. Light appearance, system Large text with temporary TextScaler.linear(1.6). Runtime read-back: 20→32 pt, 17→27.2 pt. Synthetic seeded profile, keyless local template server on localhost 8134, no production UI edits.

Reproduction: from Home choose Check in. Wait for the actual sleep question and answer field/keyboard. Inspect the mascot question bubble above the fixed Skip/input dock, then attempt to scroll the conversation up.

Observed: “How did you” is readable while the ending “sleep?” is visibly cropped behind the dock. The initial and two attempted scroll captures retain the same crop. This reports clipped prompt text during answer entry; keyboard-dismissal recovery and other device sizes are not yet established. It does not claim permanent loss or unreachable input.

Expected: the full current question remains readable while entering an answer, or can be scrolled fully into view without losing the answer.

Evidence: final-scale16-readable/scale16-daily-checkin.png and scale16-daily-checkin-scroll2.png. Both independently reviewed. AX5 native Dynamic Type also reproduces clipping (only “How” visible). The attempted background tap did not dismiss the keyboard; native tree still says Keyboard Focused. Therefore keyboard-dismissal recovery remains unverified. Extra evidence: final-ax5-readable/ax5-daily-checkin-after-background-tap.png, native20=62.35294117647059 pt with no override. Separate screen/cause from Home speech interruption and Experiment badge overlap. Published as [#149](https://github.com/ViktorOsadsky/lifetwin/issues/149).
