# Interactive prototypes

Two self-contained pages, published as claude.ai artifacts (private; ask Daniel for access):

| Prototype | Live | What it shows |
|---|---|---|
| `room/` | https://claude.ai/artifact/8gnCttycAT9ZCjJ9MhDQuP | A toon 3D room seen from slightly above, with the painted bear as camera-facing sprites. It wanders and does Exercise, Eat, Sleep and Fortune, with a personal 5-year outlook built from real model output. |
| `swoosh/` | https://claude.ai/artifact/Hjrci8B6BwLk3PXN48NWJo | The Room ↔ Onboarding transition, with slow-mo and reduced-motion toggles. The spec is in `../motion-swoosh.md`; the Flutter sketch is in `app/lib/ui/swoosh_route.dart`. |

The pages omit `<html>`/`<head>` because the artifact host adds them. To run one locally, serve the folder (`python3 -m http.server`) and open `index.html`. Sprites load by relative path.
