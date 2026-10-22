#!/usr/bin/env python3
"""Regenerate progress/index.html from the loop's on-disk state. Idempotent; any agent may run it.

Inputs (all optional):
  loop/RUN.md                         START / DEADLINE lines and the run log
  loop/PIECES.md                      markdown table of pieces
  progress/rounds/<id>/verdict.json   one critique round: piece, round, commit, verdict, wowed, gap,
                                      reference_ids, reference_urls, images (paths relative to progress/),
                                      utc, notes
  progress/img/baseline/*.jpg         wave-5 inheritance captures (rendered on the loop's base commit)
  progress/img/integration/<n>/*.jpg  standard view set after each integration
GTA V reference images are never copied here; only their IDs and URLs appear.
"""
import html, json, re, subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROG = ROOT / "progress"


def esc(s):
    return html.escape(str(s if s is not None else ""))


def run_times():
    text = (ROOT / "loop/RUN.md").read_text() if (ROOT / "loop/RUN.md").exists() else ""
    def grab(key):
        m = re.search(r"%s:\s*(\S+Z)" % key, text)
        return datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc) if m else None
    log = [l[2:] for l in text.split("## Log", 1)[-1].splitlines() if l.startswith("- ")] if "## Log" in text else []
    return grab("START"), grab("DEADLINE"), log


def pieces_table():
    path = ROOT / "loop/PIECES.md"
    if not path.exists():
        return ""
    rows = [l for l in path.read_text().splitlines() if l.startswith("|")]
    if len(rows) < 2:
        return ""
    out = ["<table>"]
    for i, row in enumerate(rows):
        if i == 1 and set(row.replace("|", "").strip()) <= set("-: "):
            continue
        cells = [c.strip() for c in row.strip().strip("|").split("|")]
        tag = "th" if i == 0 else "td"
        out.append("<tr>" + "".join("<%s>%s</%s>" % (tag, esc(c), tag) for c in cells) + "</tr>")
    out.append("</table>")
    return "\n".join(out)


def rounds():
    items = []
    for f in sorted((PROG / "rounds").glob("*/verdict.json")):
        try:
            d = json.loads(f.read_text())
        except Exception:
            continue
        d["_dir"] = f.parent.name
        items.append(d)
    items.sort(key=lambda d: (str(d.get("utc", "")), d["_dir"]), reverse=True)
    return items


def gallery(folder, title):
    imgs = sorted(folder.glob("*.jpg")) if folder.exists() else []
    if not imgs:
        return ""
    cells = "".join('<figure><a href="%s"><img loading="lazy" src="%s"></a><figcaption>%s</figcaption></figure>'
                    % (esc(p.relative_to(PROG)), esc(p.relative_to(PROG)), esc(p.stem)) for p in imgs)
    return "<h3>%s</h3><div class=grid>%s</div>" % (esc(title), cells)


def git_log():
    try:
        return subprocess.check_output(["git", "log", "--oneline", "-20"], cwd=ROOT, text=True)
    except Exception:
        return ""


def main():
    start, deadline, log = run_times()
    now = datetime.now(timezone.utc)
    remaining = ""
    if deadline:
        secs = int((deadline - now).total_seconds())
        remaining = "%dh %02dm left" % (secs // 3600, (secs % 3600) // 60) if secs > 0 else "DEADLINE reached"
    verdict_class = {"OURS WINS": "win", "INDISTINGUISHABLE": "win", "OURS LOSES": "lose"}
    round_html = []
    for d in rounds():
        refs = ", ".join('<a href="%s">%s</a>' % (esc(u), esc(i)) if u else esc(i)
                         for i, u in zip(d.get("reference_ids", []),
                                         list(d.get("reference_urls", [])) + [""] * 50))
        imgs = "".join('<figure><a href="%s"><img loading="lazy" src="%s"></a><figcaption>%s</figcaption></figure>'
                       % (esc(p), esc(p), esc(Path(p).stem)) for p in d.get("images", []))
        round_html.append(
            '<article class="%s"><h3>%s — round %s <span class=badge>%s%s</span></h3>'
            '<p class=meta>%s · commit <code>%s</code> · refs: %s</p>'
            '<p><b>Biggest gap:</b> %s</p><p class=notes>%s</p><div class=grid>%s</div></article>'
            % (verdict_class.get(d.get("verdict"), ""), esc(d.get("piece")), esc(d.get("round")),
               esc(d.get("verdict")), " · wowed" if d.get("wowed") else "", esc(d.get("utc")),
               esc(str(d.get("commit", ""))[:10]), refs or "—", esc(d.get("gap") or "—"),
               esc(d.get("notes", "")), imgs))
    integ = ""
    idir = PROG / "img/integration"
    if idir.exists():
        for sub in sorted([p for p in idir.iterdir() if p.is_dir()], reverse=True):
            integ += gallery(sub, "Integration " + sub.name)
    page = """<!doctype html><html lang=en><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1"><meta http-equiv=refresh content=120>
<title>Opus 5.5 Loop</title><style>
:root{--bg:#101114;--fg:#e9e7e2;--mute:#9a978f;--card:#191b20;--win:#3fd9a6;--lose:#e0685a;--line:#2a2d34}
body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:1200px;margin:0 auto}h1{margin:.2em 0}h2{margin-top:1.6em;border-bottom:1px solid var(--line)}
.meta,.notes,figcaption{color:var(--mute);font-size:13px}code{font-size:13px}
table{border-collapse:collapse;width:100%%;font-size:13px;display:block;overflow-x:auto}
td,th{border:1px solid var(--line);padding:4px 6px;vertical-align:top;text-align:left}
article{background:var(--card);border-left:4px solid var(--line);padding:8px 12px;margin:10px 0;border-radius:4px}
article.win{border-left-color:var(--win)}article.lose{border-left-color:var(--lose)}
.badge{font-size:12px;padding:1px 6px;border-radius:3px;background:var(--line)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:8px}
figure{margin:0}img{width:100%%;height:auto;display:block;border-radius:3px}pre{white-space:pre-wrap;font-size:12px}
</style></head><body><main>
<h1>Orchard Reach — Opus 5.5 enhancement loop</h1>
<p class=meta>Bar: Grand Theft Auto V (GTA V references are linked by ID, never shown here). START %s · DEADLINE %s · <b>%s</b> · page built %s</p>
<p class=meta>Honest status: "best build so far" is not "north star accepted". A piece is accepted only when a blind critic prefers it to its GTA V reference and is wowed.</p>
<p class=meta><b>Final result (2026-10-22 run):</b> all 23 blind critic rounds returned OURS LOSES and none was wowed &mdash; no piece is preferred over GTA V. Merged: water, skyline, lighting, materials, on-foot, helicopter, driving; street-life not merged (headless route deadlocks). Final checks: headless --test 140/140, headless and rendered --capture route 13/13. Next biggest gaps: traffic/crowd density at junctions, close-range character fidelity, aerial sun/shadow contrast and glass specular, near-field kerb/planter/asphalt materials, hero-car paint and collisions, helicopter rotor visibility. Details in HANDOFF.md.</p>
<h2>Pieces</h2>%s
<h2>Critique rounds (latest first)</h2>%s
<h2>Integrations</h2>%s
<h2>Baseline (inherited wave-5 build, rendered at loop start)</h2>%s
<h2>Commits</h2><pre>%s</pre>
<h2>Run log</h2><pre>%s</pre>
</main></body></html>""" % (
        esc(start.isoformat() if start else "?"), esc(deadline.isoformat() if deadline else "?"), esc(remaining),
        esc(now.strftime("%Y-%m-%dT%H:%M:%SZ")), pieces_table() or "<p>Decomposing…</p>",
        "".join(round_html) or "<p>No critique rounds yet.</p>", integ or "<p>None yet.</p>",
        gallery(PROG / "img/baseline", "") or "<p>Capturing…</p>", esc(git_log()), esc("\n".join(log[-60:])))
    PROG.mkdir(exist_ok=True)
    tmp = PROG / ".index.html.tmp"
    tmp.write_text(page)
    tmp.replace(PROG / "index.html")
    print(PROG / "index.html")


if __name__ == "__main__":
    main()
