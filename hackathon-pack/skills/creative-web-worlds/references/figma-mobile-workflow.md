# Figma design and Flutter handoff

Use when Figma is requested or supplied. A Flutter implementation alone does not require a Figma file. Preserve the selected artifact: editable Design, prototype, runnable Code/Make and verified Flutter are different outputs.

## Choose and inspect the actual surface

For editable screens load the available official `figma-use` and `figma-generate-design` skills; for any reusable component/variant also load `figma-generate-library`. For implementation from Figma load `figma-design-to-code` before `get_design_context`. Follow their current tool contracts rather than assuming a particular plugin version. If these tools are unavailable, prepare local assets/handoff and report that no live Figma result was verified.

Use the supplied file/node. If a new file is authorized, follow `figma-create-new-file` for its plan/editor choice. Once its key is known, create a session before the first read/edit and reuse the returned session ID. Inspect existing hierarchy, fonts, component instances, variables and styles; inspect matching Dart/theme/assets when present. Resolve component reuse through Code Connect where supported, existing instances, then scoped library discovery. Empty local variables do not establish that no library tokens exist. In a blank file, record absent context and create only the original foundation the slice needs.

## Build editable design, with bounded scope

Start with one screen wrapper and the requested state/sheet. Use auto-layout for related text, status and controls; keep illustrated coordinates within a bounded layered stage. Reuse compatible tokens/components rather than importing a generic kit that erases the chosen direction. Bind recurring colors/spacing/radii with scoped variables, use actual text styles, and create repeated controls once as components with instances. Small variant axes such as pressed/idle and selected/unselected are enough when they match real behavior; do not build an entire library for one visual study.

Keep the creature, face, prop and environment as meaningful editable vector parts when that is the requested medium. Import exact existing SVG source, or author original SVG paths with explicit dimensions/viewBox and resolved colors; inspect stroke, clipping and transparency after import. Verify small instances scale their internal art: resizing a wrapper can leave child vectors unchanged and clipped. Correct asset bounds/constraints before compensating in the screen layout. Labels remain text. Discrete raster art is valid when intended, but a full-UI screenshot is never an editable screen. Do not place a few text layers over a flattened screenshot and claim Design fidelity.

Use official API guidance for execution: verified/loadable fonts before edits, wrapper before children, append before fill/hug sizing, awaited operations and returned affected IDs. Retain state outside the document, and inspect partial writes before a retry when required. Do not copy a second API manual into this skill.

## Translate intent between design and code

Existing Flutter → editable Design: inspect the Dart, fonts/assets and actual capture, then compose native layers semantically. Flutter Web canvas output does not expose a recoverable widget tree. Web capture tools may supply a reference; do not promise semantic Flutter import. A separate HTML sketch is not native implementation.

Figma → Flutter: use high-fidelity design context plus its screenshot/assets and the actual source project. Map auto-layout to Row/Column/Wrap/Flexible according to parent constraints; bounded art to Stack/CustomPainter or verified SVG; tokens to ThemeData/extensions/constants; variants to widget parameters and state ownership. Preserve font metrics, crop, contact anchors, touch targets and safe insets. Do not mechanically translate every x/y or claim generated reference code is tested Dart. No native Flutter Code Connect support or DART variable-code-syntax platform is assumed.

Runnable Code/Make imports follow the available official `figma-code-workflows` skill and supported runtimes; they do not produce native Design layers or establish Dart execution. Resolve editable versus runnable output when an import request leaves it ambiguous; do not ask again when already chosen.

## Prove design and runtime separately

Return structural evidence: editable node types, image-filled nodes, component instances/variants and relevant variable bindings. Confirm product fonts, frame bounds and meaningful layer names. Inspect a full-screen screenshot at actual phone scale, then fix the largest observed defect and capture the changed result. Check palette role, object scale, type hierarchy, silhouette, selected preview, narrow layout and large text. Node counts and successful writes do not certify craft.

Prototype links demonstrate intended navigation/transitions only when actually exercised; otherwise label them proposed. Flutter still requires actual root/theme/assets, responsive and enlarged-text captures, meaningful state/semantic actions, cancellation/interruption and runtime inspection as appropriate. Compare the Figma design, exported art and runtime separately. Deliver the actual file/node link, editable states/assets and specific verified/untested limits.
