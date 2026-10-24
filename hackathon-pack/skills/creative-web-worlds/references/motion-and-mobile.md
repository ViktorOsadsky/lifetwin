# Motion, scroll and mobile production

Use when the brief asks for animated scrolling or a polished interactive product. Preserve the subject's art direction; motion and compactness are not excuses to make information hard to reach.

## Design a sequence, not a bag of effects

For each important moment record: user intent → trigger and interval → changing subject → endpoint → interruption/reversal → narrow-screen equivalent → reduced-motion state. Distinguish:

- **Progress-linked:** scroll reveals a construction, changes a viewpoint, or opens a physical spread. Its visible state follows scroll in both directions. Give it a finite useful interval and a stable endpoint.
- **Triggered:** entry begins a brief emphasis or transition. Repeated crossing must not queue animations or flash content. Avoid applying the same fade-up to every section.
- **Input-driven:** selecting, adding, editing, opening and saving show what changed. The state commits immediately; animation follows that state and can be interrupted by the next action.

Keep native scrolling and direct task navigation. Do not intercept wheel/touch scrolling, force spectators through every chapter, or make a long pin wall merely to extend a short effect. Pin only while changing views explain the subject. Mobile may use an ordinary flowing section, shorter scene or sticky result preview instead of the desktop pin. Do not shrink the desktop scene and keep its travel distance unchanged.

One shared object can connect narrative and operation: a book opens into the same editable spread; a specimen moves from exhibition to inspection; a product view settles beside its options. Preserve selected state across the handoff. Avoid a scene teleport when an intersection threshold flips; compare the frames on either side and the reverse journey. Redundant captions such as “scroll to see the animation” do not repair unclear staging.

## Choose an implementation that can settle

Use CSS scroll/view timelines for simple supported DOM effects, an IntersectionObserver for coarse entry state, or GSAP ScrollTrigger when sequencing/pinning/cleanup warrants it. Verify current support against the actual browsers; do not install a polyfill or smooth-scroll library by reflex.

- [CSS scroll-driven animations](https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Scroll-driven_animations): scroll and view progress are different timelines. Use a readable, complete base style and feature-detected enhancement. Set `animation-timeline` after any `animation` shorthand that would reset it.
- [GSAP ScrollTrigger](https://gsap.com/docs/v3/Plugins/ScrollTrigger/): `scrub:true` follows progress; numeric scrub deliberately adds catch-up lag. Decide whether that lag helps or makes manipulation feel detached. Refresh after relevant font/image/layout changes. Do not animate the same structural element used to measure a trigger without understanding the geometry.
- [gsap.matchMedia](https://gsap.com/docs/v3/GSAP/gsap.matchMedia()/): scope breakpoint and motion variants; revert owned animations/triggers before rebuilding. Do not stack old desktop pins when rotating/resizing.
- [Reduced motion](https://web.dev/articles/prefers-reduced-motion): remove spatial travel/parallax and keep the resolved information and working task. Freezing a scrub at an intermediate frame is not a fallback. Listen for preference changes where runtime motion is continuous.

Cache geometry outside hot scroll paths; update transforms/opacity or scene parameters in a scheduled frame. Stop unnecessary rendering when hidden/settled. Avoid unbounded layers, full-screen filters and device-pixel-ratio multiplication without profiling. Measure before reporting performance. Native CSS alone does not establish that an experience feels good.

## Mobile is a primary interaction design

Choose the order and position of the useful result, controls and next action for a narrow hand-held viewport. Recompose image crops and type; prioritize direct tasks over decorative navigation. Use comfortable targets (often 44px as a design target), spacing, safe-area insets and room for the keyboard. Do not claim this one number establishes WCAG compliance; [AA target-size minimum](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html) has its own 24px rule and exceptions.

Offer a tap/click path for any drag, reorder, hover or spatial pick. Keyboard equivalence alone does not satisfy the [dragging alternative](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html). Controls need clear names and visible selection; not everything needs a caption. A bottom tool strip can help reach, but must not hide the preview, form field, error, export action or dialog controls. Preserve browser zoom. Avoid hover transforms that become stuck on touch.

Test long content, the on-screen keyboard where available, fast repeated taps, browser Back, rotation/resize and focus return. Desktop viewport emulation is useful layout evidence; label it separately from actual touch-device testing.

## Judge time as well as still frames

Observe initial, middle, settled, reversed and interrupted states. Use real scrolling through the UI, not injected scroll-state variables. Inspect three or more meaningful progress positions and direct navigation into a lower section after reload. Test reduced motion and the unenhanced base where possible. Capture a sequence or clip when the tool supports it; screenshots alone cannot prove timing or continuity.

Compare an equivalent task/transition with a primary industry reference at a comparable size: hierarchy, control-to-response distance, action count, latency/feedback, interruption, content density and recovery. Identify the specific gap and revise it. Do not infer usability from a studio's awards or give an aesthetic score without a defensible measure.

## Observed refinement: accept the middle composition

A mobile shared-sculpture trial had polished endpoints and reversible interpolation, yet its midpoint crossed the wordmark and the next heading while leaving an empty slab before the controls. Endpoint correctness was insufficient. At each important intermediate mobile position, judge subject size/crop, type collisions, empty travel and the next useful view together. Recompose or choose a different mobile sequence instead of merely adjusting easing. A normal-flow poster followed by a live inspection view can be stronger than transporting one object across every layout.

A useful industry detail change also supplies a purpose-composed close-up: it reveals the relevant structure with the minimum necessary context in the same frame. Enlarging the same image and reporting a zoom factor does not automatically improve understanding. Compare the changed composition, not just whether the hotspot works.
