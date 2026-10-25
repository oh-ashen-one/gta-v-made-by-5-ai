#!/bin/bash
# Same shared render chain as loop/render.sh, with a final timebox guard.
set -euo pipefail
[ $# -ge 4 ] && [ "$4" = "--" ] || { echo "usage: $0 label seconds out -- engine-args..." >&2; exit 2; }
label="$1"; seconds="$2"; out="$3"; shift 4
root="$(cd "$(dirname "$0")/../.." && pwd)"
export GPU_SLOT_DIR="${GPU_SLOT_DIR:-$HOME/.cache/gpu-slot}"
export OPUS55_RENDER_LOCK="/private/tmp/astra6/render.lock"
export OPUS55_NICE=10
slot="$(ls -td "$HOME"/.config/devin/brain/sources/oh-ashen-one--claude-code-game-builder/*/tools/gpu/gpu_slot.sh | head -1)"
mkdir -p "$out"
exec python3 "$root/loop/one_at_a_time.py" -- bash "$slot" capture --label "astra6-$label" --json "$out/gpu-slot.json" -- \
  python3 "$root/game/tools/render_gate.py" -- python3 "$root/loop/astra-6/deadline_run.py" \
  --seconds "$seconds" --log "$out/run.log" -- /opt/homebrew/bin/godot --path "$root/game" --log-file "$out/engine.log" "$@"
