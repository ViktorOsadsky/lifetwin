"""Regenerate LifeTwin's master icon and existing iOS asset-catalog images.

Requires Pillow==13.0.0 and resvg-py==0.5.0 (Python 3.11+).
Run from any directory: python tools/art/build_app_icon.py
"""

from io import BytesIO
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image
import resvg_py


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "app/assets/twin/svg/bear/pose/jump.svg"
BRANDING = ROOT / "app/assets/branding"
CATALOG = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
SVG_NS = "http://www.w3.org/2000/svg"


def main():
    ET.register_namespace("", SVG_NS)
    mascot = ET.parse(SOURCE).getroot()
    # Keep all of the source artwork and its viewBox; only place it on the tile.
    mascot.set("x", "181")
    mascot.set("y", "62")
    mascot.set("width", "662")
    mascot.set("height", "864")
    tile = ET.fromstring(f'''<svg xmlns="{SVG_NS}" width="1024" height="1024"
        viewBox="0 0 1024 1024" role="img" aria-labelledby="title description">
      <title id="title">LifeTwin</title>
      <desc id="description">The jumping LifeTwin bear on a lavender tile.</desc>
      <defs>
        <linearGradient id="lavender" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#E6E0FA"/>
          <stop offset="1" stop-color="#B9B4F0"/>
        </linearGradient>
      </defs>
      <rect width="1024" height="1024" fill="url(#lavender)"/>
      <ellipse cx="512" cy="948" rx="144" ry="20" fill="#6D5F9E" opacity="0.16"/>
    </svg>''')
    tile.append(mascot)
    svg = ET.tostring(tile, encoding="unicode") + "\n"
    BRANDING.mkdir(parents=True, exist_ok=True)
    (BRANDING / "app_icon.svg").write_text(svg)
    # Supersample, then downsample every size from the same opaque master.
    rendered = resvg_py.svg_to_bytes(
        svg_string=svg, width=2048, height=2048, skip_system_fonts=True,
    )
    master = Image.open(BytesIO(rendered)).convert("RGB")
    master.resize((1024, 1024), Image.Resampling.LANCZOS).save(
        BRANDING / "app_icon.png", optimize=True,
    )
    entries = json.loads((CATALOG / "Contents.json").read_text())["images"]
    outputs = {}
    for entry in entries:
        width, height = (float(n) for n in entry["size"].split("x"))
        scale = float(entry["scale"].removesuffix("x"))
        size = (round(width * scale), round(height * scale))
        filename = entry["filename"]
        if filename in outputs and outputs[filename] != size:
            raise ValueError(f"Conflicting icon dimensions: {filename}")
        outputs[filename] = size
    for filename, size in outputs.items():
        master.resize(size, Image.Resampling.LANCZOS).save(
            CATALOG / filename, optimize=True,
        )
    print(f"Generated master SVG/PNG and {len(outputs)} iOS icons.")


if __name__ == "__main__":
    main()
