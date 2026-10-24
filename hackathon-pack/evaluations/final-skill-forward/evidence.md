# Forward-test evidence

Date: 2026-10-23. Test input arrived as a fresh-context delegated task. No author reports, root evaluations, intended answers or existing checkers were opened. Target skills and their own required reference files were read; those bundled references themselves include prior production lessons. No skill files were edited. No additional agents were created.

## Inputs read

- `hackathon-pack/skills/creative-web-worlds/SKILL.md`; source-atlas, production-lessons, motion-and-mobile, craft-review and real-3d-recipe references.
- `hackathon-pack/skills/sponsor-track-builder/SKILL.md`; track-recipes and selected resource-routes sections.
- `hackathon-pack/skills/hackathon-prize-strategy/SKILL.md`; event-snapshot reference.
- Primary supplied raw text: `design-lab/sponsor-docs/cartesia-source.txt`, `atlassian-source.txt`, `canva-source.txt`.
- Exact inventory: `design-lab/sponsor-docs/hive-starter-packs.json`; 19 sponsor cards / 18 unique pack links, with Canva duplicated. Convex links to general docs; Cartesia/Atlassian/Canva link to their distinct Google documents. No unseen provider pack was substituted.

## Primary-source checks

| Source | Actually inspected | Result / limitation |
|---|---|---|
| https://hive.hackberkeley.org/prizes | Client-rendered article text in Browser after web text fetch returned Loading. | Selected Cartesia, Convex and Atlassian cards saved in `hive-rendered-selected.txt`. Cartesia weights 25% each; hardware TBD. Convex Coming soon. Atlassian links the matching starter brief. |
| https://hive.hackberkeley.org/schedule | Client-rendered Friday and Sunday panels. | `hive-schedule-rendered.txt`, `hive-sunday-rendered.txt`. Sunday explicitly shows 8:50 AM submission, all times Pacific. Friday view does not establish the exact permitted coding start. |
| https://cal-hacks-13-0.devpost.com/ | Current web fetch, requirements and selected prize descriptions. | 9 AM PST wording conflicts with Hive 8:50. Acceptance/check-in, image/repo/demo and all-work-during-event requirements retained. Cash-style labels conflict with hardware descriptions. Rule page mainly code of conduct; no full reuse permission or stacking confirmation found. |
| https://docs.cartesia.ai/calhacks | Web retrieval attempted. | Inaccessible through web tool; supplied event pack remains identified as the source, not silently replaced by general docs. |
| https://docs.cartesia.ai/llms.txt | Current official index via web tool. | Actual Managed Agents and webhook/client-auth pages discovered from this index. Several Markdown URLs failed via web tool; direct read-only curl succeeded. |
| Current Cartesia Managed Agents / webhook tools / client auth | Full Markdown fetched from exact indexed official URLs. | Full working captures were read; packaged `cartesia-managed-current.md`, `cartesia-webhooks-current.md`, `cartesia-auth-current.md` contain source URLs, original hashes and concise original summaries rather than republishing manuals. Supports hosted conversation, webhook API schema, configurable secret auth/timeouts and browser access-token route. No paid endpoint was called. Vendor latency/accuracy claims were not adopted as measured evidence. |
| https://docs.convex.dev/home ; /functions/mutation-functions | Current official web fetch. | Reactive backend capability; mutations transactional/deterministic; external APIs belong in actions. No current event-specific rubric inferred. |
| https://developer.atlassian.com/platform/forge/getting-started/ | Current official overview. | Forge remains an app platform with demo-site/start workflow. Pack provides event requirements; generic platform docs cannot remove the Forge gate. |
| https://www.canva.dev/docs/ | Current official docs. | Editor, REST/platform and assistant surfaces verified; docs distinguish Dev MCP development use. No event award inferred. |
| https://exp-ion.lusion.co/ | Rendered opening desktop still. | `reference-ion-opening.jpg`. Dark centered object, sparse perimeter controls, large cropped product type observed. No full motion/mobile/performance audit. |
| https://lusion.co/projects/infinite_passerella/ | Official case-study text. | Authored texture/model claims support material-production study; no copied assets or stack inference. |

## Produced and inspected

- `creative-output.md`: art direction, medium/fidelity, finite mobile motion score, direct state/controls and implementation boundaries.
- `storyboard.html`: original static three-frame composition. It is a storyboard with SVG illustration, not actual 3D or a working product site.
- `storyboard-rendered.png`: Browser full-page capture at its existing 1280 px width; three fixed 376×814 phone frames. No browser viewport changes were made. Inspecting those frames does not establish actual-device behavior.
- `sponsor-output.md`: ranked roles, exact contract boundaries, access gates, 33-hour plan, failure tests and requirement-to-artifact checklist.

Observed storyboard result: camera silhouette reads first in the opening; the lens collar and separated side shell stay inside the middle frame; final preview and controls are visible together. The vector board lacks bead-blast microtexture and true parallax, so it cannot establish production material fidelity. No revision was justified by a material composition failure at this scope; final appearance remains a design judgment.

No deterministic runtime helper was included, so no unit test was added. Static board inspection is the performed verification. All voice/backend/scroll interaction tests are explicitly planned and unrun. No signup, credit redemption, provider paid run, external write, deployment, message or submission was performed. Local artifact generation and a temporary read-only loopback server were used only to inspect the board.
