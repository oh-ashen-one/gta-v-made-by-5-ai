#!/bin/bash
# Task-owned packaged validation through the shared lease and fixed clock.
set -euo pipefail
[ $# -ge 5 ] && [ "$5" = "--" ] || { echo "usage: $0 label seconds out app-binary -- user-args..." >&2; exit 2; }
label="$1"; seconds="$2"; out="$3"; app="$4"; shift 5
[ -x "$app" ] || { echo "Package executable missing: $app" >&2; exit 2; }
root="$(cd "$(dirname "$0")/../.." && pwd)"
export GPU_SLOT_DIR="${GPU_SLOT_DIR:-$HOME/.cache/gpu-slot}"
export OPUS55_RENDER_LOCK="/private/tmp/astra6/render.lock"
export OPUS55_NICE=10
slot="$(ls -td "$HOME"/.config/devin/brain/sources/oh-ashen-one--claude-code-game-builder/*/tools/gpu/gpu_slot.sh | head -1)"
mkdir -p "$out"
exec python3 "$root/loop/one_at_a_time.py" -- bash "$slot" capture --label "astra6-$label" --json "$out/gpu-slot.json" -- \
  python3 "$root/game/tools/render_gate.py" -- python3 "$root/loop/astra-6/deadline_run.py" \
  --seconds "$seconds" --log "$out/run.log" -- "$app" --log-file "$out/engine.log" -- "$@"
