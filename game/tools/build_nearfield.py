#!/usr/bin/env python3
"""Nearfield piece (opus55 wave D): original, deterministic street-level maps.

Everything here is drawn procedurally with numpy/PIL; no downloaded or
provider art. Rerun from the repository root:

    python3 game/tools/build_nearfield.py

Outputs (game/assets/authored/surfaces/):
  asphalt_aggregate_albedo.png / _normal.png  2 x 2 m seamless tile of graded
      stone aggregate in bitumen binder (stones 4-22 mm, light granite chips,
      dark binder pits), for a fine grain that survives mip filtering.
  shrub_leaves_albedo.png / _normal.png  RGBA leaf-cluster atlas (4 cells):
      glossy broad-leaf shrub (two tones), small-leaf hedge, flowering sprig.
  street_signs_albedo.png  RGBA sign-face atlas (4 x 2 cells): keep-left,
      no-parking, no-entry, pedestrian crossing, bus stop, no-stopping,
      speed 40, school zone. Pictograms only (no copied sign artwork).
"""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.spatial import cKDTree
from scipy.ndimage import gaussian_filter

ROOT = Path(__file__).resolve().parents[1] / "assets" / "authored" / "surfaces"
ROOT.mkdir(parents=True, exist_ok=True)


def save_normal(height, strength, path):
    gy, gx = np.gradient(height)
    nor = np.stack([-gx * strength, gy * strength, np.ones_like(gx)], -1)
    nor /= np.linalg.norm(nor, axis=2)[..., None]
    Image.fromarray(np.uint8((nor * 0.5 + 0.5) * 255)).save(path)


def blur_wrap(a, radius):
    """Gaussian blur with wrap-around (seamless)."""
    return gaussian_filter(np.asarray(a, dtype=np.float32), radius, mode="wrap")


# --------------------------------------------------------------- asphalt
def asphalt():
    N = 1024              # 2 m tile -> ~2 mm per pixel
    rng = np.random.default_rng(220461)
    y, x = np.mgrid[:N, :N].astype(np.float32)
    # graded aggregate: many small stones, fewer large ones
    sizes = np.concatenate([rng.uniform(2.0, 3.5, 22000), rng.uniform(3.5, 6.0, 6500), rng.uniform(6.0, 10.0, 900)])
    pts = rng.uniform(0, N, (sizes.size, 2))
    # tile the seeds so the Voronoi wraps seamlessly
    offs = np.array([[dx, dy] for dx in (-N, 0, N) for dy in (-N, 0, N)], dtype=np.float32)
    allpts = (pts[None, :, :] + offs[:, None, :]).reshape(-1, 2)
    allsz = np.tile(sizes, 9)
    tree = cKDTree(allpts)
    q = np.stack([x.ravel(), y.ravel()], -1)
    d, idx = tree.query(q, k=2)
    d0 = d[:, 0].reshape(N, N)
    i0 = idx[:, 0].reshape(N, N)
    r = allsz[i0]
    # stone body where the pixel sits within its seed's radius, rounded profile
    inside = np.clip(1.0 - d0 / r, 0.0, 1.0)
    stone = np.clip(inside * 2.6, 0.0, 1.0)
    seed_id = i0 % sizes.size
    tone = rng.uniform(0.0, 1.0, sizes.size)[seed_id]
    # stone colours: mostly mid-grey granite, some light quartz chips, some dark basalt
    st_val = np.where(tone > 0.93, 0.62 + 0.10 * rng.uniform(0, 1, sizes.size)[seed_id],
             np.where(tone < 0.30, 0.20 + 0.10 * tone, 0.30 + 0.16 * tone))
    binder = 0.16 + 0.05 * blur_wrap(rng.normal(0, 1, (N, N)).astype(np.float32), 1.2)
    val = binder * (1.0 - stone) + st_val * stone
    # worn top faces of stones read slightly lighter (polished), edges darker
    val *= 0.88 + 0.16 * inside
    # fine sand/fines in the binder
    val += 0.035 * rng.normal(0, 1, (N, N)) * (1.0 - stone)
    # very gentle broad variation only (the shader adds wear; no mottle here)
    broad = blur_wrap(rng.normal(0, 1, (N, N)).astype(np.float32), 60.0)
    broad = broad / (np.abs(broad).max() + 1e-6)
    val *= 1.0 + 0.04 * broad
    val = np.clip(val, 0.0, 1.0)
    # store relative to a 0.5 mean so the shader tint sets the absolute value
    val = val / val.mean() * 0.5
    rgb = np.stack([val * 1.01, val * 1.0, val * 0.985], -1)
    Image.fromarray(np.uint8(np.clip(rgb, 0, 1) * 255)).save(ROOT / "asphalt_aggregate_albedo.png")
    height = stone * (0.6 + 0.4 * inside) + 0.15 * blur_wrap(rng.normal(0, 1, (N, N)).astype(np.float32), 0.8)
    save_normal(height, 1.6, ROOT / "asphalt_aggregate_normal.png")


# --------------------------------------------------------------- leaves
def leaf_shape(draw, cx, cy, length, width, ang, col, vein):
    # pointed elliptic leaf as a polygon, with a midrib
    pts = []
    for i in range(25):
        t = i / 24.0
        w = width * math.sin(math.pi * t) ** 0.8
        pts.append((t * length, w))
    for i in range(24, -1, -1):
        t = i / 24.0
        w = width * math.sin(math.pi * t) ** 0.8
        pts.append((t * length, -w))
    ca, sa = math.cos(ang), math.sin(ang)
    poly = [(cx + px * ca - py * sa, cy + px * sa + py * ca) for px, py in pts]
    draw.polygon(poly, fill=col)
    draw.line([(cx, cy), (cx + length * 0.92 * ca, cy + length * 0.92 * sa)], fill=vein, width=2)


def leaves():
    S = 1024
    C = S // 2
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hgt = Image.new("L", (S, S), 0)
    rng = np.random.default_rng(5150)
    cells = [(0, 0, "broad_dark"), (C, 0, "broad_light"), (0, C, "small"), (C, C, "flower")]
    for ox, oy, kind in cells:
        layer = Image.new("RGBA", (C, C), (0, 0, 0, 0))
        hl = Image.new("L", (C, C), 0)
        d = ImageDraw.Draw(layer)
        dh = ImageDraw.Draw(hl)
        if kind.startswith("broad"):
            n, L, W = 26, (110, 175), (0.26, 0.36)
        elif kind == "small":
            n, L, W = 70, (55, 85), (0.28, 0.38)
        else:
            n, L, W = 40, (70, 110), (0.25, 0.33)
        base_cols = {
            "broad_dark": [(38, 72, 30), (46, 84, 34), (30, 60, 26), (52, 90, 40)],
            "broad_light": [(70, 108, 40), (84, 120, 46), (60, 98, 36), (96, 128, 52)],
            "small": [(44, 80, 32), (58, 96, 38), (36, 70, 30), (70, 104, 44)],
            "flower": [(40, 76, 30), (52, 88, 36), (34, 66, 28)],
        }[kind]
        # leaves radiate from stems spread over the cell, drawn back to front
        for k in range(n):
            a = rng.uniform(0, 2 * math.pi)
            rr = rng.uniform(0.0, 0.30) * C
            cx = C * 0.5 + math.cos(a) * rr * 0.6
            cy = C * 0.5 + math.sin(a) * rr * 0.6
            length = rng.uniform(*L)
            width = length * rng.uniform(*W)
            ang = a + rng.uniform(-0.6, 0.6)
            # keep leaf tips inside the cell
            ex = cx + math.cos(ang) * length
            ey = cy + math.sin(ang) * length
            if not (8 < ex < C - 8 and 8 < ey < C - 8):
                ang += math.pi
            c = base_cols[rng.integers(len(base_cols))]
            j = rng.uniform(0.85, 1.15)
            col = (int(min(255, c[0] * j)), int(min(255, c[1] * j)), int(min(255, c[2] * j)), 255)
            vein = (int(col[0] * 1.25), int(col[1] * 1.2), int(col[2] * 1.1), 255)
            leaf_shape(d, cx, cy, length, width, ang, col, vein)
            shade = int(120 + 120 * (k / n))
            leaf_shape(dh, cx, cy, length, width, ang, shade, min(255, shade + 30))
        if kind == "flower":
            # Ixora-style clusters of small four-petal florets (red/orange)
            for k in range(7):
                fx, fy = rng.uniform(0.2, 0.8) * C, rng.uniform(0.2, 0.8) * C
                hue = [(205, 44, 30), (226, 86, 30), (196, 30, 40)][k % 3]
                for f in range(24):
                    px = fx + rng.normal(0, 13)
                    py = fy + rng.normal(0, 13)
                    for p in range(4):
                        pa = p * math.pi / 2 + rng.uniform(0, 0.4)
                        qx, qy = px + math.cos(pa) * 5, py + math.sin(pa) * 5
                        d.ellipse([qx - 4, qy - 4, qx + 4, qy + 4], fill=hue + (255,))
                        dh.ellipse([qx - 4, qy - 4, qx + 4, qy + 4], fill=255)
                    d.ellipse([px - 1.5, py - 1.5, px + 1.5, py + 1.5], fill=(250, 210, 80, 255))
        img.paste(layer, (ox, oy), layer)
        hgt.paste(hl, (ox, oy))
    arr = np.asarray(img).astype(np.float32) / 255.0
    # bleed colour into transparent texels so mip levels do not halo dark
    rgb = arr[..., :3]
    a = arr[..., 3:4]
    blurred = np.stack([blur_wrap(rgb[..., c] * a[..., 0], 6.0) for c in range(3)], -1)
    wsum = blur_wrap(a[..., 0], 6.0)[..., None] + 1e-4
    fill = blurred / wsum
    rgb = np.where(a > 0.5, rgb, fill)
    out = np.concatenate([rgb, a], -1)
    Image.fromarray(np.uint8(np.clip(out, 0, 1) * 255), "RGBA").save(ROOT / "shrub_leaves_albedo.png")
    h = np.asarray(hgt).astype(np.float32) / 255.0
    save_normal(blur_wrap(h, 1.5), 3.0, ROOT / "shrub_leaves_normal.png")


# --------------------------------------------------------------- signs
def signs():
    CW = 256
    S = Image.new("RGBA", (CW * 4, CW * 2), (0, 0, 0, 0))
    BLUE = (24, 74, 160, 255)
    RED = (196, 32, 34, 255)
    WHITE = (240, 240, 236, 255)
    BLACK = (24, 24, 26, 255)
    YELLOW = (240, 190, 30, 255)

    def cell(i):
        im = Image.new("RGBA", (CW * 4, CW * 4), (0, 0, 0, 0))
        return im, ImageDraw.Draw(im)

    def put(i, im):
        im = im.resize((CW, CW), Image.Resampling.LANCZOS)
        S.paste(im, ((i % 4) * CW, (i // 4) * CW), im)

    W = CW * 4
    c = W / 2
    # 0 keep-left: blue disc, white rim, white arrow pointing down-left
    im, d = cell(0)
    d.ellipse([8, 8, W - 8, W - 8], fill=WHITE)
    d.ellipse([40, 40, W - 40, W - 40], fill=BLUE)
    ang = math.radians(135.0)   # arrow points down-left
    ux, uy = math.cos(ang), math.sin(ang)
    px, py = -uy, ux
    L, hw, hl, hh = 330, 46, 170, 150
    tip = (c + ux * L, c + uy * L)
    base = (c - ux * L * 0.85, c - uy * L * 0.85)
    neck = (tip[0] - ux * hl, tip[1] - uy * hl)
    d.polygon([(base[0] + px * hw, base[1] + py * hw), (neck[0] + px * hw, neck[1] + py * hw),
               (neck[0] + px * hh, neck[1] + py * hh), tip, (neck[0] - px * hh, neck[1] - py * hh),
               (neck[0] - px * hw, neck[1] - py * hw), (base[0] - px * hw, base[1] - py * hw)], fill=WHITE)
    put(0, im)
    # 1 no parking: blue disc, red ring and one red slash
    im, d = cell(1)
    d.ellipse([8, 8, W - 8, W - 8], fill=RED)
    d.ellipse([110, 110, W - 110, W - 110], fill=BLUE)
    d.line([(190, 190), (W - 190, W - 190)], fill=RED, width=110)
    put(1, im)
    # 2 no entry: red disc, white bar
    im, d = cell(2)
    d.ellipse([8, 8, W - 8, W - 8], fill=RED)
    d.rounded_rectangle([170, c - 70, W - 170, c + 70], radius=20, fill=WHITE)
    put(2, im)
    # 3 pedestrian crossing: blue square, white triangle, black walking figure
    im, d = cell(3)
    d.rounded_rectangle([16, 16, W - 16, W - 16], radius=60, fill=BLUE)
    d.polygon([(c, 150), (W - 150, W - 200), (150, W - 200)], fill=WHITE)
    d.rectangle([250, W - 300, W - 250, W - 270], fill=BLACK)
    d.ellipse([c - 34, 390, c + 34, 458], fill=BLACK)
    d.line([(c, 470), (c - 20, 610)], fill=BLACK, width=44)
    d.line([(c - 20, 610), (c - 90, 720)], fill=BLACK, width=40)
    d.line([(c - 20, 610), (c + 70, 720)], fill=BLACK, width=40)
    d.line([(c - 70, 540), (c + 60, 520)], fill=BLACK, width=34)
    put(3, im)
    # 4 bus stop: white plate, blue band, bus pictogram
    im, d = cell(4)
    d.rounded_rectangle([16, 16, W - 16, W - 16], radius=50, fill=WHITE)
    d.rounded_rectangle([60, 60, W - 60, W - 60], radius=40, fill=BLUE)
    d.rounded_rectangle([210, 300, W - 210, 700], radius=50, fill=WHITE)
    d.rectangle([250, 350, W - 250, 500], fill=BLUE)
    d.ellipse([260, 650, 350, 740], fill=WHITE)
    d.ellipse([W - 350, 650, W - 260, 740], fill=WHITE)
    d.ellipse([272, 662, 338, 728], fill=BLACK)
    d.ellipse([W - 338, 662, W - 272, 728], fill=BLACK)
    put(4, im)
    # 5 no stopping: blue disc, red ring, red cross
    im, d = cell(5)
    d.ellipse([8, 8, W - 8, W - 8], fill=RED)
    d.ellipse([110, 110, W - 110, W - 110], fill=BLUE)
    d.line([(190, 190), (W - 190, W - 190)], fill=RED, width=100)
    d.line([(W - 190, 190), (190, W - 190)], fill=RED, width=100)
    put(5, im)
    # 6 speed limit 40: white disc, red ring, numerals as seven-segment strokes
    im, d = cell(6)
    d.ellipse([8, 8, W - 8, W - 8], fill=RED)
    d.ellipse([120, 120, W - 120, W - 120], fill=WHITE)
    t = 52
    # "4"
    x0, y0, x1, y1 = 290, 330, 480, 700
    d.line([(x0, y0), (x0, 540)], fill=BLACK, width=t)
    d.line([(x0 - 20, 540), (x1 + 20, 540)], fill=BLACK, width=t)
    d.line([(440, y0), (440, y1)], fill=BLACK, width=t)
    # "0"
    d.rounded_rectangle([550, 330, 740, 700], radius=80, outline=BLACK, width=t)
    put(6, im)
    # 7 school zone: yellow diamond-ish plate, two black figures
    im, d = cell(7)
    d.polygon([(c, 20), (W - 20, c), (c, W - 20), (20, c)], fill=BLACK)
    d.polygon([(c, 60), (W - 60, c), (c, W - 60), (60, c)], fill=YELLOW)
    for fx, sc in ((c - 90, 1.0), (c + 80, 0.82)):
        hy = 330 + (1 - sc) * 120
        d.ellipse([fx - 30 * sc, hy, fx + 30 * sc, hy + 60 * sc], fill=BLACK)
        d.line([(fx, hy + 70 * sc), (fx, hy + 230 * sc)], fill=BLACK, width=int(40 * sc))
        d.line([(fx, hy + 230 * sc), (fx - 50 * sc, hy + 340 * sc)], fill=BLACK, width=int(34 * sc))
        d.line([(fx, hy + 230 * sc), (fx + 50 * sc, hy + 340 * sc)], fill=BLACK, width=int(34 * sc))
    put(7, im)
    arr = np.asarray(S).astype(np.float32) / 255.0
    rgb, a = arr[..., :3], arr[..., 3:4]
    blurred = np.stack([blur_wrap(rgb[..., k] * a[..., 0], 4.0) for k in range(3)], -1)
    wsum = blur_wrap(a[..., 0], 4.0)[..., None] + 1e-4
    rgb = np.where(a > 0.5, rgb, blurred / wsum)
    Image.fromarray(np.uint8(np.clip(np.concatenate([rgb, a], -1), 0, 1) * 255), "RGBA").save(ROOT / "street_signs_albedo.png")


if __name__ == "__main__":
    asphalt()
    leaves()
    signs()
    print("nearfield maps written to", ROOT)
