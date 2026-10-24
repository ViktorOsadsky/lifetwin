#!/bin/sh
# Render the Flutter room layers from the approved three.js prototype.
# usage: render_layers.sh <prototype index.html> <out dir> [cam hash: az,pitchDeg,halfWidth,tx,ty,tz]
# The Flutter assets use cam 0.5,35,2.3,0.34,0.35,0.34 (target lowered so the floor clears the dock).
# Writes <out>/{room_bg,room_noball,room_noapple}.png, room_fg_bed.png, room_fg_table.png (transparent)
# and room_calibration.json, at 1170x2532 (390x844 CSS px at 3x). Needs Google Chrome and uv (Pillow).
# The prototype loads three.js r128 from cdnjs, so the first run needs the network.
set -e
SRC=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); OUT=$(mkdir -p "$2" && cd "$2" && pwd); CAM=${3:+&cam=$3}
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
# The prototype ships without a document skeleton (see build-preview.sh); wrap it.
{ printf '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body>\n'; cat "$SRC"; printf '\n</body></html>\n'; } > "$WORK/room.html"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FLAGS="--headless=new --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader --allow-file-access-from-files --hide-scrollbars --window-size=500,900 --force-device-scale-factor=3 --default-background-color=00000000 --virtual-time-budget=8000"
for L in bg noball noapple fg_bed fg_table; do
  "$CHROME" $FLAGS --screenshot="$WORK/$L.png" "file://$WORK/room.html#layer=$L&dpr=3$CAM" >/dev/null 2>&1
  # The window is 500x900 CSS px; the stage is pinned to 390x844 at its top left.
  uv run -q --with pillow python -c "import sys;from PIL import Image;Image.open(sys.argv[1]).crop((0,0,1170,2532)).save(sys.argv[2])" "$WORK/$L.png" "$OUT/room_$L.png"
done
"$CHROME" $FLAGS --dump-dom "file://$WORK/room.html#layer=calib&dpr=3$CAM" 2>/dev/null \
  | python3 -I -c "import sys,re,html,json;m=re.findall(r'<pre id=\"calib\">(\{.*?)</pre>',sys.stdin.read(),re.S)[-1];print(json.dumps(json.loads(html.unescape(m)),indent=1))" > "$OUT/room_calibration.json"
ls -la "$OUT"
