#!/usr/bin/env python3
"""Final safety check inside the shared lease, immediately before owned launch."""
import json
import os
import sys
from pathlib import Path
from render_launch_guard import snapshot, safe_public_rows, engine_arguments
from render_startup_health import pause_shared


def main():
    root = Path(os.environ.get('GPU_SLOT_DIR', str(Path.home()/'.cache/gpu-slot')))
    command = sys.argv[1:]
    command = command[1:] if command and command[0] == '--' else command
    if not command:
        raise SystemExit('No command')
    if os.environ.get('GPU_SLOT_HELD') not in {'capture','perf'}:
        raise SystemExit('A verified normal shared GPU lease is required')
    state = snapshot(root)
    print(json.dumps({'renderer_preflight': safe_public_rows(state['clients']),
                      'shared_root': str(root), 'utilization': state['utilization'],
                      'headless_command': '--headless' in engine_arguments(command)}), flush=True)
    if state['stuck']:
        pause_shared(root, None, 'A GPU client is stuck exiting: '+','.join(str(row['pid']) for row in state['stuck']))
        raise SystemExit('GPU client stuck exiting; shared launches paused, no process killed')
    if state['paused'] or state['streaming']:
        raise SystemExit('Shared coordinator is paused or streaming; no launch')
    # Until a clean recovery hour is explicitly established, this task renders
    # alone with no concurrent GPU training. Headless QA still obeys the shared
    # mixed cap/headroom gate and never launches through another route.
    cap = 2 if '--headless' in engine_arguments(command) else 1
    if len(state['clients']) >= cap:
        raise SystemExit('GPU client capacity is occupied; no launch')
    if state['utilization'] is None or state['utilization'] >= 85:
        raise SystemExit('GPU headroom disappeared after shared admission; no launch')
    os.execvp(command[0], command)


if __name__ == '__main__':
    main()
