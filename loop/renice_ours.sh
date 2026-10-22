#!/bin/bash
# Keep this loop's own engine/tool processes at lower CPU priority so other sessions on the Studio get room.
# Touches ONLY processes whose command line contains this checkout's path (.../wave-05-opus) or "opus55".
# Usage: nohup bash loop/renice_ours.sh >/dev/null 2>&1 &   (stop: kill the pid in /private/tmp/opus55/renice.pid)
mkdir -p /private/tmp/opus55; echo $$ > /private/tmp/opus55/renice.pid
while true; do
  ps -axo pid=,ni=,command= | awk '($0 ~ /wave-05-opus|opus55/) && ($0 ~ /godot|Blender|bounded_run|render_gate|gpu_slot|ffmpeg/) && $2 < 10 {print $1}' \
    | while read -r pid; do renice -n 10 -p "$pid" >/dev/null 2>&1; done
  sleep 15
done
