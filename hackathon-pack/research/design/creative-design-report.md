# Creative web design research and worked sample

Completed 2026-10-23. Scope: a reusable skill for original useful 2D/2.5D/3D compositions, plus an original runnable shopping workflow. It is not a clone of any reference.

## Research output

The [primary-source atlas](../../skills/creative-web-worlds/references/source-atlas.md) contains 13 useful creative references spanning Bruno Simon, Lusion, 14islands, Manoela Ilic, Tom Miller, Dogstudio, Active Theory, and Resn; official R3F/GSAP documentation supplements implementation guidance. There are seven [composition grammars](../../skills/creative-web-worlds/references/visual-grammars.md), each covering layout, type, materials, motion, state, accessibility and estimated hackathon cost. The [real 3D recipe](../../skills/creative-web-worlds/references/real-3d-recipe.md) specifies picking → shared domain state → DOM evidence, camera constraints, resource reuse/instancing, rendering cost and complete fallback paths. That recipe has not been implemented as a real WebGL sample.

## Original sample: Pocket Market

[Open the source entry](../../skills/creative-web-worlds/assets/pocket-market/index.html). Serve its folder over a local HTTP server for ES modules. It has no package dependencies, remote assets or third-party data calls. The sample is **SVG/CSS 2.5D, not real WebGL 3D**. All scene geometry and product illustrations are original code-native shapes.

The entire page uses a market-island concept: stalls are placed along a path, labels and quantity controls accompany products, a hand-held receipt retains selections and exact costs, and the budget determines headroom. This is a local shopping-list workflow, with no payment/order submission. Real interactions update integer-cent totals, expose over-budget states, validate budget input and generate shopping-list text. Native buttons also supply keyboard operation; list and quiet controls provide alternate presentation. Mobile CSS uses a vertical shopping arrangement rather than shrinking the desktop camera.

The UI/UX skill search returned an immersive/spatial direction with skip, keyboard, reduced-motion and mobile fallback advice. Its generic glass/Inter palette did not fit this market; the implemented design instead uses blue water, warm paper, illustrated produce, sign-like Trebuchet typography and a serif receipt. This was an intentional subject-based change, not an application of every database recommendation.

## Actual evaluation and iteration

Evaluation was self-review, not independent blind testing. Root subsequently inspected the revised screenshot and confirmed that the composition was clear and useful.

**Realistic prompt used for the sample:** Make an original creative shopping workflow beyond a standard UI with a decorative component. Let someone build a priced basket within a budget and obtain a useful list; preserve keyboard, small-screen and reduced-motion paths.

**First output:** implemented a full original SVG island, three priced stalls, receipt, quantity actions, budget parsing, list/quiet views and export generation. Node tests passed. [First desktop screenshot](screenshots/desktop-before.jpg) exposed a material defect: the receipt obscured the bread stall and part of its controls.

**Feedback:** spatial composition must reserve the receipt's space; the useful path cannot be sacrificed to depth/overlap. The first scene occupied 72% of the page width and ran behind the receipt.

**Concrete revision:** narrowed the desktop scene to 60% and adjusted its origin/top; added a distinct tablet arrangement. The product control state and receipt remained connected to the same data. [Revised screenshot with changed basket](screenshots/desktop-after.jpg) shows all three stalls and the receipt separately. Browser actions could select each product after the correction. The skill's composition guidance now explicitly requires a result panel that cannot overlap a selectable object.

**Rerun evidence:** browser selected one peach item ($4.50), one loaf ($6.50, activated with Enter) and one flower bunch ($9.00). DOM showed total **$20.00**, remaining **$0.00**, each quantity 1, and the download control enabled. Adding another peach item produced total **$24.50** and **$4.50 over budget**, with the changed quantity reflected in the DOM and receipt. This changed state is saved in desktop-after.jpg.

**Unit test command:** `node --test hackathon-pack/skills/creative-web-worlds/assets/pocket-market/basket.test.mjs`.

Result: **4 tests passed, 0 failed**. Covered independent quantities and exact total arithmetic; 0–9 bounds and unknown products; malformed/negative/out-of-range budget values; actual selected export lines, total and no-order disclosure. These are domain invariants, not screenshot/string-matching tests of implementation structure.

## Verification limits and interruption

A subsequent browser call attempted invalid-budget UI, quiet/list mode, and a real download. The download event wait hung for about 16 minutes and was interrupted. The preceding actions may have executed but their tool result was not returned; **those browser checks are not counted as passes**. Export content generation was tested in Node; an actual completed browser file download is unverified. Do not infer a successful download from the screenshot's enabled button.

Narrow mobile screenshots, browser-emulated OS reduced motion, full keyboard tab order, real screen-reader use, no-WebGL handling and automated contrast testing were not run. Mobile/list/reduced-motion paths exist in the source; that is implementation evidence, not completed QA. There is no WebGL renderer to test in this sample. Root can perform the remaining mobile/quiet checks without changing the research claim.

The initial loopback server bind was denied by the sandbox, then a loopback-only server was allowed through the normal escalation. A first failed `127.0.0.1` browser tab required a fresh `localhost` tab; the successful browser sample was served from `http://localhost:8769`. No public upload or deployment occurred.

## Additional root verification

After this worker's interrupted browser call, root completed responsive QA independently. At 390px there was no horizontal overflow. At 320px root found the introductory description overlapping the absolutely positioned budget: description right 234/bottom 441 versus budget left 188/top 385. Root added a narrow-screen rule at 374px and below to stack the budget, reduce the headline to 56px, and maintain 44px mobile buttons; the stylesheet URL was versioned to prevent stale cache. This is a second demonstrated revision, not a planned test.

The 320px rerun measured budget top 392.45 below description bottom 372.45, leaving 20px separation, and document scroll width equaled viewport width 320. Product clicks produced an $11 total; a $10 budget produced a $1-over-budget warning. Quiet view reported pressed and the inspected transition duration was 0s. Evidence is in `screenshots/mobile-root.jpg`, `screenshots/narrow-before-root.jpg`, and `screenshots/narrow-after-root.jpg`. These root checks supersede the earlier unverified-mobile limitation for the specific checked widths and quiet-view state; OS media-query emulation, screen-reader use and completed download remain unverified.

Skill validation was attempted with the bundled `quick_validate.py`; the system Python lacked the `yaml` module. Root is handling the pack-wide validator in its configured environment. This is a validation environment issue, not a reported successful validator pass.
