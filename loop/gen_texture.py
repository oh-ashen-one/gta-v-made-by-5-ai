#!/usr/bin/env python3
"""Turn one generated image into game-ready private texture files (owner-approved Higgsfield images).

  python3 loop/gen_texture.py <name> <image_url> [--tile] [--maps] [--alpha] [--job JOB_ID] [--prompt TEXT]

Raw download  -> art/provider-sources/higgsfield/<name>_raw.<ext>     (git-ignored)
Game files    -> game/assets/providers/higgsfield/<name>_albedo.png   (git-ignored; linked into every worktree)
  --tile   make it wrap seamlessly (half-offset copy cross-blended over the seams)
  --maps   also derive <name>_normal.png (from luminance) and <name>_rough.png
  --grid   for regular patterns (pavers, tiles, window grids): crop to whole repeat periods found by
           autocorrelation instead of cross-blending, so joints line up across the wrap
  --alpha  keep the alpha channel (cut-out cards, signs); implies no --tile
  --crop x0,y0,x1,y1  crop the raw image to whole repeat periods measured by hand (e.g. mullion to mullion,
           floor band to floor band) before any other step; the output keeps the crop's aspect
Appends one record per output to loop/generated_assets.jsonl (paths, job id, prompt, sha256). The images
themselves are never committed: they are provider outputs, not MIT, not cleared for public redistribution.
"""
import argparse, hashlib, json, urllib.request
from datetime import datetime, timezone
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "art/provider-sources/higgsfield"
OUT = ROOT / "game/assets/providers/higgsfield"


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def seamless(a):
    h, w = a.shape[:2]
    rolled = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)
    yy, xx = np.mgrid[0:h, 0:w]
    # 1 in the middle (original kept), 0 at the borders (wrapped copy, which is continuous across edges)
    dx = 1.0 - np.abs(xx - (w - 1) / 2) / ((w - 1) / 2)
    dy = 1.0 - np.abs(yy - (h - 1) / 2) / ((h - 1) / 2)
    m = np.clip(np.minimum(dx, dy) * 2.2, 0, 1)[..., None] ** 1.5
    return a * m + rolled * (1 - m)


def period(profile, lo=64):
    """Strongest repeat (autocorrelation peak) between lo px and a third of the image."""
    x = profile - profile.mean()
    ac = np.correlate(x, x, "full")[len(x) - 1:]
    ac /= ac[0] + 1e-9
    hi = len(ac) // 3
    peaks = [k for k in range(lo, hi) if ac[k] > ac[k - 1] and ac[k] >= ac[k + 1]]
    best = max(peaks, key=lambda k: ac[k], default=None)
    return best if best is not None and ac[best] > 0.15 else None


def grid_crop(a):
    lum = a @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    h, w = lum.shape
    px, py = period(lum.mean(axis=0)), period(lum.mean(axis=1))
    # two periods per axis covers running-bond offsets; keep the largest whole multiple
    cw = (w // (2 * px)) * 2 * px if px else w
    ch = (h // (2 * py)) * 2 * py if py else h
    print("grid periods px=%s py=%s -> crop %dx%d" % (px, py, cw, ch))
    out = Image.fromarray((a[:ch, :cw] * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)
    return np.asarray(out).astype(np.float32) / 255.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name"); ap.add_argument("url")
    ap.add_argument("--tile", action="store_true"); ap.add_argument("--maps", action="store_true")
    ap.add_argument("--alpha", action="store_true"); ap.add_argument("--grid", action="store_true")
    ap.add_argument("--crop", default="")
    ap.add_argument("--job", default=""); ap.add_argument("--prompt", default="")
    a = ap.parse_args()
    RAW.mkdir(parents=True, exist_ok=True); OUT.mkdir(parents=True, exist_ok=True)
    ext = ".png" if ".png" in a.url.lower() else ".jpg" if (".jpg" in a.url.lower() or ".jpeg" in a.url.lower()) else ".img"
    raw = RAW / f"{a.name}_raw{ext}"
    req = urllib.request.Request(a.url, headers={"User-Agent": "Mozilla/5.0"})
    raw.write_bytes(urllib.request.urlopen(req, timeout=120).read())
    img = Image.open(raw)
    if a.crop:
        img = img.crop(tuple(int(v) for v in a.crop.split(",")))
    outputs = []
    if a.alpha:
        img = img.convert("RGBA")
        p = OUT / f"{a.name}.png"; img.save(p, optimize=True); outputs.append(p)
    else:
        arr = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
        if a.grid:
            arr = grid_crop(arr)
        elif a.tile:
            arr = seamless(arr)
        alb = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
        p = OUT / f"{a.name}_albedo.png"; alb.save(p, optimize=True); outputs.append(p)
        if a.maps:
            lum = arr @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
            gx = (np.roll(lum, -1, 1) - np.roll(lum, 1, 1)) * 0.5
            gy = (np.roll(lum, -1, 0) - np.roll(lum, 1, 0)) * 0.5
            strength = 6.0
            n = np.dstack([-gx * strength, gy * strength, np.ones_like(lum)])  # OpenGL-style (Godot)
            n /= np.linalg.norm(n, axis=2, keepdims=True)
            p = OUT / f"{a.name}_normal.png"
            Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(p, optimize=True); outputs.append(p)
            rough = np.clip(0.95 - (lum - lum.mean()) * 0.6, 0.55, 1.0)
            p = OUT / f"{a.name}_rough.png"
            Image.fromarray((rough * 255).astype(np.uint8)).save(p, optimize=True); outputs.append(p)
    utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(ROOT / "loop/generated_assets.jsonl", "a") as log:
        for p in outputs:
            log.write(json.dumps({"path": str(p.relative_to(ROOT)), "raw": str(raw.relative_to(ROOT)),
                                  "provider": "Higgsfield (GPT Image 2.5)", "job_id": a.job, "prompt": a.prompt,
                                  "size": list(Image.open(p).size), "sha256": sha(p), "raw_sha256": sha(raw),
                                  "created_utc": utc}) + "\n")
    for p in outputs:
        print(p.relative_to(ROOT), Image.open(p).size)


if __name__ == "__main__":
    main()
