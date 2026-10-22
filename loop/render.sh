#!/bin/bash
# Rendered engine run under the shared GPU lease: gpu_slot.sh capture -> render_gate.py -> bounded_run.py.
#   bash loop/render.sh <label> <seconds> <abs-out-dir> -- <engine args...>
# Engine args are passed to `godot --path <this checkout's game>`; e.g. `-- -- --photos --qa-session DIR`.
set -euo pipefail
[ $# -ge 4 ] && [ "$4" = "--" ] || { echo "usage: $0 <label> <seconds> <abs-out-dir> -- <engine args...>" >&2; exit 2; }
label="opus55-$1"; seconds="$2"; out="$3"; shift 4
root="$(cd "$(dirname "$0")/.." && pwd)"
export GPU_SLOT_DIR="${GPU_SLOT_DIR:-$HOME/.cache/gpu-slot}"
# Share the machine (owner rule 2026-10-22): our renders only ever take shared capture slot 0, so at most one of
# ours runs at a time and the second slot always stays free for other sessions; engines run at lower CPU priority.
export GPU_SLOT_CAPTURE_SLOTS="${GPU_SLOT_CAPTURE_SLOTS:-1}"
export OPUS55_NICE="${OPUS55_NICE:-10}"
slot="$(ls -td "$HOME"/.config/devin/brain/sources/oh-ashen-one--claude-code-game-builder/*/tools/gpu/gpu_slot.sh 2>/dev/null | head -1)"
[ -n "$slot" ] || { echo "gpu_slot.sh not found in the shared-brain catalog" >&2; exit 3; }
mkdir -p "$out"
exec bash "$slot" capture --label "$label" --json "$out/gpu-slot.json" -- \
  python3 "$root/game/tools/render_gate.py" -- \
  python3 "$root/game/tools/bounded_run.py" --seconds "$seconds" --log "$out/run.log" -- \
  /opt/homebrew/bin/godot --path "$root/game" --log-file "$out/engine.log" "$@"
