# Turn the rendered layers (render_layers.sh) into Flutter assets.
# usage: uv run --with pillow python make_assets.py <render dir> <app/assets/scene/room>
# Writes 1x / 2.0x / 3.0x variants (3.0x = the native 1170x2532 render), crops the
# foreground layers and the empty-shelf and empty-bowl patches to their bounds, and writes room_layers.json
# (camera matrix, floor calibration, walkable floor, and each layer's rect in 390x844 px).
import json, os, sys
from PIL import Image, ImageChops, ImageFilter

src, out = sys.argv[1], sys.argv[2]
S = 3  # render scale
cal = json.load(open(os.path.join(src, 'room_calibration.json')))
W, H = cal['viewport']

def save(img, name, rect_css=None):
    """Save native (3.0x), 2.0x and 1x. rect_css is the layer's rect in 1x px."""
    for sub, f in (('3.0x', 1.0), ('2.0x', 2 / 3), ('', 1 / 3)):
        d = os.path.join(out, sub); os.makedirs(d, exist_ok=True)
        w, h = max(1, round(img.width * f)), max(1, round(img.height * f))
        im = img if f == 1.0 else img.resize((w, h), Image.LANCZOS)
        p = os.path.join(d, name)
        if name.endswith('.jpg'): im.convert('RGB').save(p, quality=86, optimize=True, progressive=True)
        else: im.save(p, optimize=True)
    return rect_css

layers = {}
bg = Image.open(os.path.join(src, 'room_bg.png')).convert('RGB')
save(bg, 'room_bg.jpg'); layers['bg'] = {'asset': 'assets/scene/room/room_bg.jpg', 'rect': [0, 0, W, H]}

def cropped(name, key, pad=6):
    im = Image.open(os.path.join(src, name)).convert('RGBA')
    x0, y0, x1, y1 = im.getchannel('A').point(lambda a: 255 if a > 4 else 0).getbbox()
    # snap to the 3x grid so 1x/2x crops stay pixel-aligned
    x0, y0 = max(0, (x0 - pad) // S * S), max(0, (y0 - pad) // S * S)
    x1, y1 = min(im.width, -(-(x1 + pad) // S) * S), min(im.height, -(-(y1 + pad) // S) * S)
    asset = name.replace('.png', '.png')
    save(im.crop((x0, y0, x1, y1)), asset)
    layers[key] = {'asset': 'assets/scene/room/' + asset, 'rect': [x0 / S, y0 / S, (x1 - x0) / S, (y1 - y0) / S]}

cropped('room_fg_bed.png', 'fgBed')
cropped('room_fg_table.png', 'fgTable')

# Empty-shelf patch: the no-ball render around the ball, laid over the bg while the twin holds it.
nb = Image.open(os.path.join(src, 'room_noball.png')).convert('RGB')
bx, by = cal['shelfBallScreen']
half = 30
x0, y0 = int(max(0, bx - half)) * S, int(max(0, by - half)) * S
x1, y1 = int(min(W, bx + half)) * S, int(min(H, by + half)) * S
save(nb.crop((x0, y0, x1, y1)), 'room_shelf_empty.png')
layers['shelfEmpty'] = {'asset': 'assets/scene/room/room_shelf_empty.png', 'rect': [x0 / S, y0 / S, (x1 - x0) / S, (y1 - y0) / S]}

# Empty-bowl patch (Eat): the no-apple render around the apple, feathered so only the bowl changes,
# and the apple alone (cut from the bg) for the refill pop.
ax, ay = cal['bowlAppleScreen']
half = 14
x0, y0 = int(max(0, ax - half)) * S, int(max(0, ay - half)) * S
x1, y1 = int(min(W, ax + half)) * S, int(min(H, ay + half)) * S
na = Image.open(os.path.join(src, 'room_noapple.png')).convert('RGB').crop((x0, y0, x1, y1))
full = bg.crop((x0, y0, x1, y1))
diff = ImageChops.difference(full, na).convert('L').point(lambda v: 255 if v > 6 else 0)
assert diff.getbbox() and diff.getbbox() != (0, 0, x1 - x0, y1 - y0), 'apple must sit inside the patch'
rect = [x0 / S, y0 / S, (x1 - x0) / S, (y1 - y0) / S]
empty = na.convert('RGBA'); empty.putalpha(diff.filter(ImageFilter.MaxFilter(13)).filter(ImageFilter.GaussianBlur(4)))
save(empty, 'room_bowl_empty.png')
layers['bowlEmpty'] = {'asset': 'assets/scene/room/room_bowl_empty.png', 'rect': rect}
apple = full.convert('RGBA'); apple.putalpha(diff.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1)))
save(apple, 'room_bowl_apple.png')
layers['bowlApple'] = {'asset': 'assets/scene/room/room_bowl_apple.png', 'rect': rect}

cal['layers'] = layers
cal['$comment'] = ('Pre-rendered room (owner ruling 2026-10-24). Rendered from tools/art/room3d/room3d_prototype.html '
                   'by render_layers.sh + make_assets.py. Screen units are logical px of the 390x844 render; '
                   'viewProjection is three.js column-major (projection * view). Copy changes into lib/room/room_layout.dart.')
json.dump(cal, open(os.path.join(out, 'room_layers.json'), 'w'), indent=1)
print(json.dumps(layers))
