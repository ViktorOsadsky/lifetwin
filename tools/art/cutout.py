# Cut a sprite out of a plain light background: flood-fill from the image
# border through near-background pixels, then feather the edge.
# usage: python3 -I cutout.py in.png out.png [tolerance]
import struct, sys, zlib
from collections import deque


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    i, idat = 8, b''
    while i < len(data):
        n = struct.unpack('>I', data[i:i + 4])[0]
        kind, body = data[i + 4:i + 8], data[i + 8:i + 8 + n]
        if kind == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', body[:10])
            assert depth == 8 and ctype in (2, 6), (depth, ctype)
        elif kind == b'IDAT':
            idat += body
        i += 12 + n
    bpp = 3 if ctype == 2 else 4
    raw, stride = zlib.decompress(idat), w * bpp
    out, prev, pos = bytearray(), bytearray(stride), 0
    for _ in range(h):
        f, line = raw[pos], bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out += line
        prev = line
    px = [tuple(out[k:k + 3]) for k in range(0, len(out), bpp)]
    return w, h, px


def write_png(path, w, h, rgba):
    raw = b''.join(b'\x00' + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    chunk = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def main():
    src, dst = sys.argv[1], sys.argv[2]
    tol = int(sys.argv[3]) if len(sys.argv) > 3 else 38
    w, h, px = read_png(src)
    # background colour = median of the four corners' 8x8 patches
    corners = [px[y * w + x] for y0, x0 in ((0, 0), (0, w - 8), (h - 8, 0), (h - 8, w - 8))
               for y in range(y0, y0 + 8) for x in range(x0, x0 + 8)]
    bg = tuple(sorted(c[k] for c in corners)[len(corners) // 2] for k in range(3))
    dist = lambda c: max(abs(c[0] - bg[0]), abs(c[1] - bg[1]), abs(c[2] - bg[2]))
    outside = bytearray(w * h)
    q = deque(i for i in range(w * h) if (i < w or i >= w * (h - 1) or i % w in (0, w - 1)) and dist(px[i]) <= tol)
    for i in q: outside[i] = 1
    while q:
        i = q.popleft()
        x, y = i % w, i // w
        for j in ((i - 1) if x else -1, (i + 1) if x < w - 1 else -1, i - w, i + w):
            if 0 <= j < w * h and not outside[j] and dist(px[j]) <= tol:
                outside[j] = 1
                q.append(j)
    # enclosed background-coloured regions (e.g. ear holes in a hat) larger than
    # a highlight are cleared too; tiny ones like eye glints stay
    seen = bytearray(outside)
    for s in range(w * h):
        if seen[s] or dist(px[s]) > tol:
            continue
        region, q2 = [s], deque([s])
        seen[s] = 1
        while q2:
            i = q2.popleft()
            x = i % w
            for j in ((i - 1) if x else -1, (i + 1) if x < w - 1 else -1, i - w, i + w):
                if 0 <= j < w * h and not seen[j] and dist(px[j]) <= tol:
                    seen[j] = 1
                    region.append(j)
                    q2.append(j)
        if len(region) > w * h // 2500:
            for i in region: outside[i] = 1
    rgba = bytearray(w * h * 4)
    for i, (r, g, b) in enumerate(px):
        a = 0 if outside[i] else 255
        if not outside[i]:
            # feather: pixels touching the background fade by how background-like they are
            x, y = i % w, i // w
            edge = any(0 <= j < w * h and outside[j] for j in (i - 1, i + 1, i - w, i + w))
            if edge:
                a = max(0, min(255, int(255 * min(1.0, dist((r, g, b)) / (tol * 2.5)))))
        rgba[i * 4:i * 4 + 4] = bytes((r, g, b, a))
    write_png(dst, w, h, rgba)
    print(f'{dst}: bg={bg} transparent={sum(outside) * 100 // (w * h)}%')


main()
