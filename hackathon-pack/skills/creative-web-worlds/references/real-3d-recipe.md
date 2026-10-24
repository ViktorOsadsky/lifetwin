# Real 3D production: from asset to useful state

This is implementation guidance, not a claim that the bundled SVG sample uses WebGL. Verify current APIs against the linked official documentation when building.

## Bound the scene

Use Three.js or React Three Fiber when lighting/material response or view-dependent shape actually helps selection. Define the production centerpiece first: an authored mesh, carefully licensed model, custom procedural surface or coherent stylized environment. Primitive blockouts establish scale and camera; they are not the final art direction merely because they render quickly. For a bounded shelf experiment, three original products, a ground plane and one camera can be sufficient if silhouette, material, light and supporting detail sustain the actual viewing scale. For a shopping demo, inventory is ordinary data: ID, name, price in integer cents, stock and selected quantity. A mesh stores a product ID, never the authoritative price.

Compose with one dominant mass and clear negative space. Use a fixed perspective or orthographic camera, a consistent horizon and shadow direction, muted supporting props, and an HTML results panel that cannot overlap a selectable object. Put the camera's initial view and mobile view in named constants. Limited yaw/zoom is optional; unconstrained orbit is rarely appropriate for a short workflow.

## Picking → state → evidence

For a parameter instrument, change the actual property named by its control: frequency, fold density, position or finish must visibly affect the appropriate shape/material parameter. Keep the result in view at the moment of manipulation, including mobile. Shared state in code does not compensate for offscreen feedback. A sticky preview or one canvas moved between scene hosts can preserve that relationship; verify camera, canvas size, focus and restoration on return. Do not imply scientific fidelity for an artistic parameter mapping.


1. Render a product mesh and an equivalent named HTML button/radio for each ID.
2. Three.js raycasting, or an R3F mesh `onClick`, resolves the ID. Stop propagation only where necessary to prevent picking the shelf behind the object.
3. Both mesh and DOM control call `selectProduct(id)` or `changeQuantity(id, delta)` in the shared domain layer. Validate stock, quantity bounds and price there.
4. Derive visible selection, a DOM product description, receipt lines, totals, budget status and export from the same state. A colored outline alone is insufficient evidence.
5. Make correction reversible: decrement, deselect or reset. A chosen product is a selection, not a completed purchase.

A minimal conceptual R3F boundary:

```jsx
function Product({ product, selected, selectProduct, geometry, material }) {
  return (
    <mesh geometry={geometry} material={material}
      onClick={event => { event.stopPropagation(); selectProduct(product.id); }}
      scale={selected ? 1.08 : 1} />
  );
}
// Equivalent button outside Canvas:
// <button aria-pressed={selected} onClick={() => selectProduct(product.id)}>
//   Select {product.name}, {formatMoney(product.priceCents)}
// </button>
```

This excerpt omits imports, positioning, camera and canvas setup; it is not advertised as a runnable standalone application. For a real build, test the shared state actions independently, then verify a mesh pick and its DOM counterpart produce the same observable result.

## Rendering budget

The [R3F scaling guide](https://r3f.docs.pmnd.rs/advanced/scaling-performance) recommends demand rendering for scenes that settle; imperative changes need `invalidate()`. Schedule another frame while a transition is active, then stop. Reuse geometry and materials; instance many repeated background objects. Avoid an arbitrary promise of 60 FPS on all devices. Use a modest pixel-ratio cap, avoid expensive full-screen effects until profiling justifies them, and reserve a loading placeholder with stable dimensions.

The [pitfalls guide](https://r3f.docs.pmnd.rs/advanced/pitfalls) warns against frame-rate React state updates and unnecessary object creation/remounting. Keep high-frequency transforms in refs/frame callbacks using delta time, while meaningful user choices belong in domain state. Dispose resources you own and detach event listeners on teardown. If using GSAP in React, follow [official cleanup guidance](https://gsap.com/resources/React/) and scope/context-safe handlers.

## Fallback and evidence

Detect WebGL creation failure/context loss and switch to an authored SVG/static product image with the same DOM controls and state. Keep the fallback a complete workflow, not a "device unsupported" dead end. On small screens use a fixed camera and vertical details; do not require two-finger gestures. Keep meaningful labels and validation in HTML. Reduced motion retains selected state and camera destination but omits interpolation, idle animation and parallax. Pause incidental updates when hidden.

Before calling it working 3D, record: actual renderer used; screenshot showing the scene; a mesh pick changing the matching DOM selection; correction path; keyboard-equivalent action; no-WebGL and reduced-motion paths; mobile screenshot; and observed render cost on the available device. If any check is unrun, label it unverified. A nice static render is evidence of appearance only.
