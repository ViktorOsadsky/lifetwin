# View-matched hat layers (rev4_hatview)

Problem: the old composite used ONE front-facing Cal hat and only translated, rotated and scaled it per pose, so
walk_side, walk_back and lying poses showed a flat front hat (logo facing the camera) on a turned head.

Fix: one canonical hat per camera view, composited by head fit.

    views/front/          the original front hat (+ under)            -> frontal, tilted or lying heads (sleep)
    views/three_quarter/  hat turned 3/4 to image-right, Cal foreshortened  -> walk_side (mirror for left-facing)
    views/side/           true profile, logo hidden (sliver at edge)     -> generated, no pose needs it yet
    views/back/           back view, NO logo                             -> walk_back
    each folder: {bear,human}_hat_front.png (the visible hat) and _under.png (dark interior, drawn behind the head)
    human_f shares the human layers (identical 195x123 hat).

Layers are scaled so brim width equals the front hat (bear 204 px, human 195 px), so one pose scale still applies.
_raw/ holds the Codex generations (1254 px, magenta key) and prompts; _tools/ holds keyviews.py (key, crop, scale),
viewcomp.py (composite) and params.json (per-pose view, scale s, rotation th, centre x,y, bear ear circles).

Process per view: Codex `gpt-6-sol` low, refs = front canonical hat on magenta + the no-hat head of the pose; one image
per call. Keyed, despilled, cropped, scaled by brim width.

Compositing (viewcomp.py): place the layer by head fit (crown on the head dome, brim following the head angle), clip the
head fur or hair that pokes above the hat (bear ear circles exempt, so ears stay out), soft brim shadow on the head, then
under -> body -> front. Sizes and feet anchors in manifest_v2.json are recomputed; originals are in
_replaced/rev4_hatview/.

Poses fixed: walk_side, walk_back, sleep for bear, human, human_f. Not changed: dizzy, listening, thinking, sleepy, wave
etc. (frontal heads with a small tilt; rotation of the front hat is correct for those).

## Accessories (cosmetics) need the same views
A cosmetic must be rendered per head view, not rotated from the front:
- front: all cosmetics (current art).
- three_quarter (walk_side): hat, glasses (far lens foreshortened, temple arm on near side), headband/bow (knot on side),
  scarf (wraps neck), ear items on bear (near ear only visible), face paint/blush stay on the face layer.
- back (walk_back): hat, headband/bow (back knot), scarf, backpack or cape; glasses show only the temple arms or nothing.
- side profile: hat, glasses (one lens plus arm), bow/headband, scarf; only needed if a pose becomes true profile.
- tilted or lying (sleep): front art rotated plus a per-pose head-fit, as done here; glasses and bow tilt with the head.
Rule: text or logo appears only on the front and, foreshortened, on 3/4; never on back.
