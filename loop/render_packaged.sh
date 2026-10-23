#!/bin/bash
# Rendered run of an EXPORTED (packaged) build under the same shared GPU lease as loop/render.sh:
# one_at_a_time.py -> gpu_slot.sh capture -> render_gate.py -> bounded_run.py -> <app binary>.
#   bash loop/render_packaged.sh <label> <seconds> <abs-out-dir> <abs-app-binary> -- <game args...>
# e.g. .../OrchardReach.app/Contents/MacOS/Orchard Reach -- --capture --qa-session DIR
set -euo pipefail
[ $# -ge 5 ] && [ "$5" = "--" ] || { echo "usage: $0 <label> <seconds> <abs-out-dir> <abs-app-binary> -- <game args...>" >&2; exit 2; }
label="opus55-$1"; seconds="$2"; out="$3"; app="$4"; shift 5
[ -x "$app" ] || { echo "not executable: $app" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
export GPU_SLOT_DIR="${GPU_SLOT_DIR:-$HOME/.cache/gpu-slot}"
export OPUS55_NICE="${OPUS55_NICE:-10}"
slot="$(ls -td "$HOME"/.config/devin/brain/sources/oh-ashen-one--claude-code-game-builder/*/tools/gpu/gpu_slot.sh 2>/dev/null | head -1)"
[ -n "$slot" ] || { echo "gpu_slot.sh not found in the shared-brain catalog" >&2; exit 3; }
mkdir -p "$out"
exec python3 "$root/loop/one_at_a_time.py" -- bash "$slot" capture --label "$label" --json "$out/gpu-slot.json" -- \
  python3 "$root/game/tools/render_gate.py" -- \
  python3 "$root/game/tools/bounded_run.py" --seconds "$seconds" --log "$out/run.log" -- \
  "$app" --log-file "$out/engine.log" -- "$@"
