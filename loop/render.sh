#!/bin/bash
# Rendered engine run under the shared GPU lease: gpu_slot.sh capture -> render_gate.py -> bounded_run.py.
#   bash loop/render.sh <label> <seconds> <abs-out-dir> -- <engine args...>
# Engine args are passed to `godot --path <this checkout's game>`; e.g. `-- -- --photos --qa-session DIR`.
set -euo pipefail
[ $# -ge 4 ] && [ "$4" = "--" ] || { echo "usage: $0 <label> <seconds> <abs-out-dir> -- <engine args...>" >&2; exit 2; }
label="opus55-$1"; seconds="$2"; out="$3"; shift 4
root="$(cd "$(dirname "$0")/.." && pwd)"
export GPU_SLOT_DIR="$HOME/.cache/gpu-slot"
# Share the machine (owner rule 2026-10-22): loop/one_at_a_time.py makes our renders wait for each other OUTSIDE the
# shared lease queue, so at most one of ours queues/holds a slot and we never block the shared FIFO; engines run at
# lower CPU priority (bounded_run.py nice 10). Normal 2-slot lease semantics, so we never wait on an unusable slot.
export OPUS55_NICE="${OPUS55_NICE:-10}"
slot="$GPU_SLOT_DIR/bin/gpu_slot.sh"
[ -x "$slot" ] || { echo "Current shared GPU coordinator unavailable" >&2; exit 3; }
startup=()
headless=false
 for engine_arg in "$@"; do
  [ "$engine_arg" != "--" ] || break
  if [ "$engine_arg" = "--headless" ]; then headless=true; fi
 done
 if ! "$headless"; then startup=(--first-frame-seconds 120); fi
mkdir -p "$out"
exec python3 "$root/loop/one_at_a_time.py" -- bash "$slot" capture --label "$label" --json "$out/gpu-slot.json" -- \
  python3 "$root/game/tools/render_gate.py" -- \
  python3 "$root/game/tools/bounded_run.py" --seconds "$seconds" --log "$out/run.log" "${startup[@]}" -- \
  /opt/homebrew/bin/godot --path "$root/game" --log-file "$out/engine.log" "$@"
