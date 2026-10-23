#!/usr/bin/env python3
"""2x2 tiling preview of a texture (seams show at the joins): preview_tile.py <in.png> <out.jpg>"""
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); w, h = im.size
s = im.resize((w // 2, h // 2)); t = Image.new("RGB", (w, h))
for x in (0, w // 2):
    for y in (0, h // 2):
        t.paste(s, (x, y))
t.resize((1024, int(1024 * h / w))).save(sys.argv[2], quality=80)
