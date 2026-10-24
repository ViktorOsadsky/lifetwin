# Useful interactions, minimal interface copy

Use when the requested visual experience includes a substantial product workflow. For a visual/motion prototype, lightweight representative states are enough: do not build storage, integrations or media pipelines solely to satisfy this reference. Art direction should make the requested task clearer and more satisfying, not replace it with a tour.

## Establish the task contract

Choose the user's meaningful outcome and build the smallest complete path to it. Record authoritative state, visible consequence, persistence, correction and failure. Examples:

| Task | State and visible result | Correction / interruption | Meaningful completion |
|---|---|---|---|
| Make a photo zine | Ordered images, title, crop and layout drive the exact spread | Reorder with drag AND tap/keyboard; edits survive reload; failed save remains visible | Open the exported document and verify its images, pages and print layout |
| Inspect a specimen | Specimen/detail choice drives the photograph crop and attached note target | Switching does not silently retarget a draft; revisit restores the relevant detail | Save a note, reload it, export it and recover the same observed detail |
| Configure a product | Options, media, price and availability derive from the same selection | Rapid input cannot show stale price/media; unavailable choices explain a next action | Real cart/reservation result or clearly scoped local output, not a success toast alone |
| Create work | Draft and committed item are distinct states | Close/Escape/Back has a deliberate draft policy; undo returns a known prior state | Reopen the actual saved item, not just its confirmation message |

At production fidelity, an interaction is not complete merely because a button responds. Export must produce a usable artifact; saving must survive the claimed persistence boundary; search/filter must change meaningful results; validation must stop the bad operation. Do not imply an external booking, purchase, AI inference or cloud save that did not occur. Keep technical provenance in an appropriate colophon/readme rather than surrounding every task with implementation captions.

## Make it feel direct

Keep the manipulated object/result and its controls together. Show selection in the object and the control, rather than repeating explanatory text. Use stable geometry and spatial continuity: a selected thumbnail maps to the edited image; a panel grows from its owning control; a saved note remains beside its passage. Keep focus and user position sensible when panels close or content changes.

Input commits promptly, even when visual interpolation continues. Replace an in-flight transition when the user changes direction; do not queue every tap. Provide clear hover/focus/pressed/disabled feedback without making the interface jitter. Decide whether disabling is useful; where it hides the reason an action is unavailable, show a precise nearby explanation instead.

For draft/import/export flows, choose what survives a reload and test that exact boundary. User data stays visible when saving fails; the failure should provide a useful retry/download/correction path. Use appropriate storage for content size and don't report a save before it succeeds. Avoid storing imported large images in synchronous localStorage merely because it is convenient.

## Spend words where they resolve uncertainty

Keep text that names an action, identifies content, distinguishes a state or explains a recovery. Remove text that merely describes a visible animation, congratulates the design, repeats the heading, or advertises how the implementation works. Do not delete necessary labels and errors in pursuit of a sparse screenshot.

Prefer “Save note,” “Replace photo,” “Move earlier,” “Download zine” over clever ambiguous verbs. Name destinations consistently throughout the flow. Reveal advanced controls when they are relevant; compactness does not justify mystery icons, hover-only labels or placeholder-only forms. A terse toast is suitable for a reversible local action; a consequential failure needs persistent, nearby feedback.

Test understanding through a cold task attempt when an independent agent is available: give the user goal and working site, without a walkthrough. Observe wrong turns, missing feedback and recovery. Agent simulation supports a hypothesis; it is not a substitute for human usability research or proof of consumer adoption.

## Primary reference relationships

- [Linear: creating issues](https://linear.app/docs/creating-issues): interruption and draft behavior are part of the task, not merely modal animation.
- [Shopify: variants](https://shopify.dev/docs/storefronts/themes/product-merchandising/variants): selected option, media and price must agree; use the same principle for a visual configurator's authoritative state.
- [Stripe Checkout](https://stripe.com/payments/checkout): study precise field-level feedback and correction. Responsiveness/features described by the vendor are not independently tested behavior.
- [Locomotive: Lightship](https://locomotive.ca/en/work/lightship-1): its product-first redesign illustrates why navigable layers and contextual 3D can be better than a longer scroll story.

These are original transferable interpretations of official documentation/case studies checked 2026-10-23. Inspect the actual task where accessible before claiming an observed benchmark match.
