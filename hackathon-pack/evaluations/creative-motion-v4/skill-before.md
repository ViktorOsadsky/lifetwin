---
name: creative-web-worlds
description: Art-direct and build distinctive, highly crafted 2D and real 3D websites, then critique rendered compositions and iterate. Use for ambitious creative websites, interactive editorial, portfolios, product theaters and visual hackathon entries, beyond routine component styling.
---

# Creative web worlds

Deliver a specific visual point of view with production-quality execution. A working interface, an unconventional metaphor and a long source list do not establish visual excellence. Assess the rendered website against the brief and the craft of selected references. Never call a result award-winning or a masterpiece because local tests pass.

## Establish an art direction

Identify subject, audience, purpose and content. For open-ended design experiments, choose a concrete subject and explain the choice; do not stall an explicitly authorized experiment for optional preferences. Preserve the user's chosen style when provided.

Study relevant primary works, not just inspiration thumbnails. Use [source-atlas.md](references/source-atlas.md) for starting points, then inspect current rendered examples where possible. Use [production-lessons.md](references/production-lessons.md) for additional primary works, original design-skill sources and observed trial failures. Record the relationship to study: image crop versus type, grid versus interruption, light versus material, pacing between sections, or manipulation versus feedback. Distinguish visual inspection from a case-study claim. Collect a reference for composition, type/art assets and interaction; they may be the same work. Reputation is not evidence of a particular visual technique.

Compare two genuinely different directions before coding. Define each with actual content, a rough composition, type family and role, scale relationships, palette, hero asset, page rhythm and a useful interaction. Select because the direction belongs to the subject. Large heading/object on right/card grid below is not distinctive by itself. Neither is changing the default palette, rotating a receipt or naming a page a world.

## Produce the visual material

Treat hero imagery, modeling, lighting, typography and copy as design work. Use an authored illustration, licensed photograph, generated bitmap, well-made model or intentionally designed typographic composition appropriate to the brief. Inspect resolution, crop, silhouette, edges, light and relation to type at actual display size. If the asset cannot sustain the composition, improve or replace it before adding animation. Do not approximate ambitious art direction with crude geometry merely to avoid asset work.

Use suitable actual font files or a dependable font service, with a considered fallback. Adjust tracking, optical size, line breaks, line-height, weight and width for each role. A huge heading in a default face is scale, not typographic authorship. Give controls, icons, dividers, radii and surfaces a subject-specific grammar rather than one rounded-card treatment for everything.

Compose the whole page: hero, content/evidence, secondary interaction and ending should have distinct relationships. Carry motifs through sections without repeating identical rows. Give sections different jobs and typographic intensity: explanation, exploration, comparison and ending should not all be slogans. Check the complete first-screen invitation at the actual viewport, without forcing every story into one screen. Every label, mark and metadata line needs a reason. Do not invent prestigious clients, reviews, availability or performance claims as decoration. Fictional concepts may use clearly fictional content without cluttering the product with implementation details.

## Choose the medium deliberately

Use HTML/CSS/SVG for precise editorial and graphic work. Use actual Three.js/R3F when shape, camera, light or spatial manipulation is part of the design; [real-3d-recipe.md](references/real-3d-recipe.md) covers shared state and fallback. CSS depth and SVG projection are 2.5D, not real 3D. Prefer coherent materials, camera and lighting to arbitrary primitive count or bloom. A sophisticated 2D composition can be appropriate; do not silently substitute it when real 3D is requested.

Keep essential text and controls semantic. Scene picks and DOM controls share state. Keep essential visual feedback visible while its controls are used, including narrow mobile; an offscreen object does not demonstrate the control’s effect. Motion should establish hierarchy, spatial continuity or a visible response; write its score as trigger → subject/action → visual endpoint → useful feedback → interruption/reduced variant, instead of revealing every element identically. Preserve complete information and task access under reduced motion. Provide keyboard/touch equivalents, loading/error/fallback states and recoverable interactions. Respect the project's stack; verify current external APIs before using them.

## Review the picture, then the experience

Read [craft-review.md](references/craft-review.md). Inspect a static desktop composition before polishing motion. Compare at actual viewport size with the references: what is the weakest visible element, why does it look less resolved, and what production decision fixes it? A screenshot proves appearance, not behavior. A successful click proves behavior, not appearance.

Test the whole page at desktop and narrow mobile, plus a changed state. Inspect wrapping, crop, overlays, contrast, focus, loading, feedback and the ending. Run tests for consequential domain behavior. Measure performance when claiming it; do not invent FPS or accessibility passes. If an independent reviewer is available and authorized, show the rendered result with the brief without supplying flattering scores or the intended verdict.

Revise the weakest high-impact element, render again and preserve evidence. If refinement stalls, change art direction or asset approach instead of accumulating effects. To evaluate the skill, use a fresh subject and different composition after revision; reusing one template is insufficient. Audit the trial set for repeated font pairs, hero formulas and section rhythms; a new subject alone does not prove aesthetic range. The retired Pocket Market example records an inadequate visual benchmark, not a default to copy.

Deliver working pages, screenshots, concise source/asset record, observed improvements and remaining weaknesses. Exceptional visual quality is a critical judgment to support with the work, not a claim to manufacture in a report.
