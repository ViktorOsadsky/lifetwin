# Twin sprite layers

These are the painted v2 twin sprites and their layers, for Customize (#55), Home (#54) and anything else that draws the twin. The app already bundles the base set in `app/assets/twin/`. This folder adds the layers that aren't in the app yet.

## Folders
- **`twins/{bear,human,human_f}/{hat,nohat}/*.png`:** full poses, with the Cal hat composited (`hat`) and without it (`nohat`).
  - Poses: stand, wave, walk_front, walk_side, walk_back, sit, sleep, eat, stretch, jump, proud, think, thinking, listening, concerned, sleepy, dizzy, shrug, hold_ball.
  - `twins/manifest.json` lists every sprite with its size and feet anchor. Anchor every pose on the feet so the twin doesn't jump between poses or sink into the bed.
  - `human_f/nohat_anchors.json` holds the female human's anchors.
- **`hats/`:** the Cal hat as separate layers.
  - `*_hat_front.png` is the visible hat. `*_hat_under.png` is the dark inside, drawn behind the head. Draw order is under, then body, then front.
  - `hats/views/{front,three_quarter,side,back}/` holds one hat per camera angle, so the hat turns with the head. Walk_side uses three_quarter (mirror it for left-facing), walk_back uses back, and frontal or tilted heads use front.
  - `hats/views/params.json` gives the per-pose view, scale, rotation and centre.
  - `hats/views/README.md` explains the compositing.
- **`age-build/`:** body variants that follow confirmed age and build only, never health, score or experiments.
  - Human male and female: adult, middle and older, each in regular and larger.
  - Bear: default (regular and larger), middle (grey muzzle) and older (cardigan).
  - Each folder holds the poses plus `anchors_poses.json`. `variants_matrix.png` is the approved overview.
  - The owner approved the stands. The extra poses are still being drawn (Phase 2), so some folders are incomplete. Fall back to the default twin's pose until they land.
  - Larger builds change by the same measured amount for every sex.
- **`cosmetics/`:** the drafted wardrobe as slot layers.
  - Hats: beanie, cal_hat, cap, straw_hat, visor.
  - Tops: cal_tee, cardigan, hoodie, rain_jacket.
  - Plus glasses, scarf, fur, aids (access aids) and human items.
  - Each item has `item.json` (its slot contract), vector `.svg` and painted `.p.png` layers, and a thumbnail in `thumbs/`.
  - `index.json` lists every item. `cosmetics-sheet.png` and `hat-fit-sheet.png` show them on the twin. `cosmetics/README.md` documents the slot contract.

## Rules
- Hair, skin and access aids are always the user's choice.
- Cosmetics are separate from health. Quiz results never change the twin's body, only its game-health reactions.
- Hats on turned heads use the matching view layer; a front hat on a side-facing head looks wrong.
- These are the design masters. Copy what you need into `app/assets/` and declare the folders in `pubspec.yaml`.
