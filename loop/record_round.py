#!/usr/bin/env python3
"""Record one critique round under a file lock, then rebuild the progress page.

  python3 loop/record_round.py --json '<verdict json>'     (or --file verdict.json)

The verdict JSON needs: id, piece, round, commit, verdict, wowed, gap, reference_ids, reference_urls, utc,
notes. Images already copied to progress/rounds/<id>/*.jpg are listed automatically (never GTA V images).
Effects: writes progress/rounds/<id>/verdict.json, appends one line to loop/RUN.md, updates the piece's
"Current verdict" and "Open biggest gap" cells in loop/PIECES.md, and runs loop/make_progress.py.
"""
import argparse, fcntl, json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

p = argparse.ArgumentParser()
p.add_argument("--json")
p.add_argument("--file")
a = p.parse_args()
d = json.loads(a.json if a.json else Path(a.file).read_text())
rid = d.get("id") or "%s-r%s" % (d["piece"], d["round"])
d["id"] = rid
out = ROOT / "progress" / "rounds" / rid
out.mkdir(parents=True, exist_ok=True)
d["images"] = sorted("rounds/%s/%s" % (rid, f.name) for f in out.glob("*.jpg"))

with open(ROOT / "loop" / ".lock", "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    (out / "verdict.json").write_text(json.dumps(d, indent=2))
    gap = " ".join(str(d.get("gap") or "").split())
    line = "- %s %s round %s on %s: %s%s. Gap: %s\n" % (
        d.get("utc", "?"), d["piece"], d["round"], str(d.get("commit", ""))[:10], d.get("verdict"),
        " (wowed)" if d.get("wowed") else "", gap or "-")
    with open(ROOT / "loop" / "RUN.md", "a") as run:
        run.write(line)
    pieces = ROOT / "loop" / "PIECES.md"
    if pieces.exists():
        rows = pieces.read_text().splitlines()
        header = next((r for r in rows if r.startswith("| Piece")), None)
        if header:
            cols = [c.strip() for c in header.strip().strip("|").split("|")]
            for i, r in enumerate(rows):
                cells = [c.strip() for c in r.strip().strip("|").split("|")]
                if r.startswith("|") and cells and cells[0] == d["piece"] and len(cells) == len(cols):
                    if "Current verdict" in cols:
                        cells[cols.index("Current verdict")] = "r%s %s%s (%s)" % (
                            d["round"], d.get("verdict"), ", wowed" if d.get("wowed") else "",
                            str(d.get("commit", ""))[:7])
                    if "Open biggest gap" in cols:
                        cells[cols.index("Open biggest gap")] = gap.replace("|", "/")[:400] or "-"
                    rows[i] = "| " + " | ".join(cells) + " |"
            pieces.write_text("\n".join(rows) + "\n")
    subprocess.run([sys.executable, str(ROOT / "loop" / "make_progress.py")], check=False)
print(out / "verdict.json")
