#!/usr/bin/env python3
"""Last-moment timebox guard, inside the shared renderer lease.

Leaves 65 seconds for the existing supervisor's graceful engine shutdown.
Does not replace the shared GPU lease or render_gate safety checks.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import sys

p = argparse.ArgumentParser()
p.add_argument("--seconds", type=float, required=True)
p.add_argument("--log", required=True)
p.add_argument("command", nargs=argparse.REMAINDER)
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
state = json.loads((root / "loop/astra-6/RUN.json").read_text())
deadline = datetime.datetime.fromisoformat(state["deadline_utc"].replace("Z", "+00:00"))
remaining = (deadline - datetime.datetime.now(datetime.timezone.utc)).total_seconds()
limit = min(a.seconds, remaining - 65.0)
if limit <= 0:
    raise SystemExit("Astra timebox is ending; no new engine command launched.")
command = a.command[1:] if a.command and a.command[0] == "--" else a.command
if not command:
    raise SystemExit("No command supplied")
print(json.dumps({"timebox_deadline": state["deadline_utc"], "bounded_seconds": limit}), flush=True)
os.execv(sys.executable, [sys.executable, str(root / "game/tools/bounded_run.py"),
    "--seconds", str(limit), "--log", a.log, "--", *command])
