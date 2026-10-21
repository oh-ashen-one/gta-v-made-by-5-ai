#!/usr/bin/env python3
"""Last-moment shared-engine safety check; used inside the common GPU lease.

Wave 3 adds the missing piece of the documented slot protocol: the capture
lease itself. Earlier waves relied on a coordinator script that is no longer
present in the catalog, so this gate now takes `locks/capture.0.lock` with an
exclusive flock, re-checks PAUSED and the mixed-renderer cap of two, and only
then execs the owned command. A foreign renderer already holding the lease
delays us instead of being pre-empted.
"""
import fcntl, json, os, subprocess, sys, time
from pathlib import Path

root = Path(os.environ.get('GPU_SLOT_DIR', '/Users/midir/sm2-n1/_scratch/gpu'))
if (root / 'PAUSED').exists():
    raise SystemExit('Shared GPU coordinator is PAUSED; renderer not launched.')

ENGINE_NAMES = {'Godot', 'UnrealEditor', 'Unity', 'Blender', 'blender', 'Orchard Reach'}


def renderers():
    found = []
    for line in subprocess.check_output(['ps', '-axo', 'pid=,stat=,comm='], text=True).splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) != 3:
            continue
        pid, state, exe = parts
        if Path(exe).name not in ENGINE_NAMES:
            continue
        args = subprocess.check_output(['ps', '-p', pid, '-o', 'command='], text=True)
        if state.startswith(('E', 'Z')):
            raise SystemExit('Engine stuck exiting: ' + pid + ' ' + exe)
        if '--headless' not in args:
            found.append({'pid': int(pid), 'state': state, 'executable': exe})
    return found


active = renderers()
print(json.dumps({'renderer_preflight': active, 'shared_root': str(root)}), flush=True)
if len(active) >= 2:
    raise SystemExit('Mixed renderer cap2 already occupied; no launch.')

cmd = sys.argv[1:]
cmd = cmd[1:] if cmd and cmd[0] == '--' else cmd
if not cmd:
    raise SystemExit('No command')

lock_path = root / 'locks' / 'capture.0.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
lock = open(lock_path, 'a+')
deadline = time.monotonic() + float(os.environ.get('GPU_SLOT_WAIT_S', '900'))
while True:
    try:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except OSError:
        if time.monotonic() > deadline:
            raise SystemExit('Shared capture lease busy for %ss; renderer not launched.' % os.environ.get('GPU_SLOT_WAIT_S', '900'))
        time.sleep(2.0)

print(json.dumps({'capture_lease': 'acquired', 'path': str(lock_path)}), flush=True)
started = time.monotonic()
child = subprocess.Popen(cmd)
try:
    code = child.wait()
finally:
    fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
    lock.close()
print(json.dumps({'capture_lease': 'released', 'hold_sec': round(time.monotonic() - started, 2), 'exit': code}), flush=True)
sys.exit(code)
