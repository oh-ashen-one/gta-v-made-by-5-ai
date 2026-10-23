#!/usr/bin/env python3
"""Nearfield props (opus55 wave R): original chalkboard menu faces for the
five-foot-way A-frame boards. Deterministic; no downloaded art. Text is set in
Pillow's bundled Aileron font (CC0) and roughened to read as chalk.

    python3 game/tools/build_nearfield_props.py

Output: game/assets/authored/surfaces/chalk_menu_albedo.png (1024 x 768,
two board faces side by side: kopitiam drinks / hawker dishes). Fictional
items and prices only.
"""
from pathlib import Path
import random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parents[1] / "assets" / "authored" / "surfaces" / "chalk_menu_albedo.png"
W, H = 512, 768

MENUS = [
    ("KOPI & TEH", (236, 196, 92), [("Kopi O", "1.40"), ("Kopi C", "1.60"), ("Teh Tarik", "1.80"),
                                     ("Lime Juice", "2.20"), ("Bandung", "2.00"), ("Barley Ice", "1.80")]),
    ("TODAY", (120, 196, 226), [("Nasi Lemak", "4.50"), ("Mee Goreng", "5.00"), ("Chicken Rice", "4.80"),
                                ("Laksa", "5.50"), ("Kaya Toast", "2.40"), ("Soft Eggs", "1.80")]),
]


def chalk_layer(draw_fn, seed):
    """Draw white text/lines on a mask, then break it up like dry chalk."""
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    draw_fn(d)
    rng = np.random.default_rng(seed)
    m = np.asarray(mask, dtype=np.float32) / 255.0
    grain = rng.random((H, W)).astype(np.float32)
    m = m * np.clip(0.45 + grain * 0.9, 0.0, 1.0)
    img = Image.fromarray(np.uint8(np.clip(m, 0, 1) * 255)).filter(ImageFilter.GaussianBlur(0.7))
    return np.asarray(img, dtype=np.float32) / 255.0


def board(menu, seed):
    title, accent, items = menu
    rnd = random.Random(seed)
    rng = np.random.default_rng(seed)
    # slate: dark green-black with wiped, ghosted old chalk
    base = np.zeros((H, W, 3), np.float32) + np.array([0.075, 0.095, 0.085], np.float32)
    smear = Image.fromarray(np.uint8(rng.random((H // 16, W // 16)) * 255)).resize((W, H), Image.BICUBIC)
    smear = np.asarray(smear.filter(ImageFilter.GaussianBlur(18)), np.float32) / 255.0
    base += (smear[..., None] - 0.5) * 0.06 + 0.02
    f_title = ImageFont.load_default(size=64)
    f_item = ImageFont.load_default(size=38)

    def white(d):
        y = 150
        for name, price in items:
            dx = rnd.randint(-4, 4)
            d.text((44 + dx, y), name, font=f_item, fill=255)
            d.text((W - 150 + dx, y), price, font=f_item, fill=255)
            y += 92
        # border doodle
        d.rectangle((14, 14, W - 14, H - 14), outline=255, width=3)

    def colour(d):
        tw = d.textlength(title, font=f_title)
        d.text(((W - tw) / 2, 40), title, font=f_title, fill=255)
        d.line((60, 124, W - 60, 128), fill=255, width=5)

    wm = chalk_layer(white, seed + 1)
    cm = chalk_layer(colour, seed + 2)
    acc = np.array(accent, np.float32) / 255.0
    col = base * (1 - wm[..., None] * 0.85) + wm[..., None] * 0.85 * np.array([0.92, 0.92, 0.88], np.float32)
    col = col * (1 - cm[..., None] * 0.9) + cm[..., None] * 0.9 * acc
    return np.clip(col, 0, 1)


def main():
    out = np.concatenate([board(MENUS[0], 11), board(MENUS[1], 23)], axis=1)
    Image.fromarray(np.uint8(out * 255)).save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
