# LifeTwin app icon

`app_icon.svg` and the opaque 1024 × 1024 `app_icon.png` are generated from
`../twin/svg/bear/pose/jump.svg`. The original bear paths, colors, pose and hat
are preserved. The lavender tile uses the room palette (`#E6E0FA`, `#B9B4F0`)
from `lib/ui/theme.dart`; the subtle oval beneath the bear emphasizes its jump.
Artwork provenance is recorded in the existing twin manifest at
`../twin/manifest.json`; no external artwork was added.

The square tile deliberately has no transparent corners or baked-in rounded
mask. iOS applies its own icon shape. All 15 PNGs referenced by the existing
`ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` are generated from
the same supersampled master, including the App Store image. This project
currently includes only the iOS platform target.

To regenerate from the repository root with Python 3.11 or newer:

```sh
python3 -m venv /tmp/lifetwin-icon-tools
/tmp/lifetwin-icon-tools/bin/pip install Pillow==13.0.0 resvg-py==0.5.0
/tmp/lifetwin-icon-tools/bin/python tools/art/build_app_icon.py
```

These are build/source assets; they do not need to be bundled through
`pubspec.yaml`. The Runner target already selects the `AppIcon` asset catalog.
