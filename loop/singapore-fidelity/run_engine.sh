#!/bin/bash
# Current-task QA: private single-instance lock, normal shared lease, physical
# renderer gate and owner stream-aware FPS cap. No expired prior-wave clock.
set -euo pipefail
if [ "${1:-}" = "--leased" ]; then
 root="$(cd "$(dirname "$0")/../.." && pwd)"
 seconds="$2"; out="$3"; shift 3
 fps="${GPU_SLOT_FPS_CAP:-60}"
 [ ! -e "$HOME/.cache/gpu-slot/STREAMING" ] || fps=30
 startup=()
 headless=false
 for engine_arg in "$@"; do
  [ "$engine_arg" != "--" ] || break
  if [ "$engine_arg" = "--headless" ]; then headless=true; fi
 done
 if ! "$headless"; then
  # Conservative provisional60s expectation,2x startup bound. Tighten from
  # actual measured cold-frame receipts; process banners never count.
  startup=(--first-frame-seconds 120)
 fi
 exec python3 "$root/game/tools/bounded_run.py" --seconds "$seconds" --log "$out/run.log" "${startup[@]}" -- \
  /opt/homebrew/bin/godot --max-fps "$fps" --path "$root/game" --log-file "$out/engine.log" "$@"
fi
[ $# -ge 4 ] && [ "$4" = "--" ] || { echo "usage: $0 label seconds output -- godot-args..." >&2; exit 2; }
label="$1"; seconds="$2"; out="$3"; shift 4
root="$(cd "$(dirname "$0")/../.." && pwd)"
export GPU_SLOT_DIR="$HOME/.cache/gpu-slot"
export OPUS55_RENDER_LOCK="/private/tmp/singapore-fidelity/engine.lock"
export OPUS55_NICE=10
fps=60
[ ! -e "$GPU_SLOT_DIR/STREAMING" ] || fps=30
export GPU_SLOT_FPS_CAP="$fps"
slot="$GPU_SLOT_DIR/bin/gpu_slot.sh"
[ -x "$slot" ] || { echo "Current installed GPU coordinator unavailable" >&2; exit 3; }
mkdir -p "$out"
exec /usr/sbin/taskpolicy -b python3 "$root/loop/one_at_a_time.py" -- bash "$slot" capture --label "singapore-fidelity-$label" --json "$out/gpu-slot.json" -- \
 python3 "$root/game/tools/render_gate.py" -- bash "$root/loop/singapore-fidelity/run_engine.sh" --leased "$seconds" "$out" "$@"
