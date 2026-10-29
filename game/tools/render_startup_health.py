"""First-frame evidence and machine-wide wedge pause for owned captures.

No GPU work is performed here. A marker must come from this exact child/run,
with a completed viewport readback; a log banner or process launch is not proof.
"""
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path

PREFIX = 'SINGAPORE_RENDER_FIRST_FRAME '
ANSI = re.compile(r'\x1b\[[0-9;]*m')


def valid_frame(line, pid, nonce):
    line = ANSI.sub('', line).strip()
    if not line.startswith(PREFIX):
        return None
    try:
        row = json.loads(line[len(PREFIX):])
    except (ValueError, TypeError):
        return None
    if not isinstance(row, dict) or row.get('pid') != pid or row.get('nonce') != nonce:
        return None
    for key in ('width', 'height', 'frames_drawn'):
        if type(row.get(key)) is not int or row[key] <= 0:
            return None
    if row.get('gpu_readback_completed') is not True or row.get('display_server') in (None, '', 'headless'):
        return None
    return row


class FirstFrameProbe:
    def __init__(self, log, pid, nonce):
        self.path = Path(log)
        self.pid, self.nonce = pid, nonce
        self.offset, self.pending = 0, b''
        self.confirmed = None

    def poll(self):
        if self.confirmed is not None:
            return self.confirmed
        try:
            with self.path.open('rb') as source:
                source.seek(self.offset)
                chunk = source.read(1024 * 1024)
        except OSError as error:
            self.last_read_error = str(error)
            return None
        self.offset += len(chunk)
        lines = (self.pending + chunk).split(b'\n')
        self.pending = lines.pop()
        if len(self.pending) > 16384:
            self.pending = b''  # Overlong unrelated diagnostics cannot grow memory.
        for line in lines:
            if len(line) > 16384:
                continue
            row = valid_frame(line.decode('utf-8', errors='replace'), self.pid, self.nonce)
            if row is not None:
                self.confirmed = row
                return row
        return None


def pause_shared(root, child_pid, reason):
    """Create the existing shared protocol's PAUSED switch; never overwrite/resume."""
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    record = {'since': time.time(), 'since_iso': datetime.now(timezone.utc).isoformat(),
              'by': 'singapore-bounded-run', 'reason': reason,
              'owned_driver_pid': os.getpid(), 'owned_child_pid': child_pid}
    destination = root / 'PAUSED'
    try:
        fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return {'paused': True, 'created': False, 'path': str(destination)}
    with os.fdopen(fd, 'w') as target:
        json.dump(record, target, indent=2)
        target.write('\n')
        target.flush()
        os.fsync(target.fileno())
    return {'paused': True, 'created': True, 'path': str(destination), 'reason': reason}


def stop_owned(child, rendered, pause, grace_seconds=60, check_health=None):
    """Stop exactly the Popen-owned child. A possible renderer wedge is never killed."""
    import signal
    import subprocess
    if child.poll() is not None:
        return child.returncode, True
    child.send_signal(signal.SIGTERM)
    deadline = time.monotonic() + grace_seconds
    while child.poll() is None and time.monotonic() < deadline:
        if check_health is not None:
            check_health()
        try:
            return child.wait(timeout=min(.5, max(.001, deadline-time.monotonic()))), True
        except subprocess.TimeoutExpired:
            pass
    if check_health is not None:
        check_health()
    if child.poll() is not None:
        return child.returncode, True
    if rendered:
        pause('Owned rendered process failed to exit after SIGTERM and the shutdown grace period')
        return 78, False
    # Only non-rendering jobs retain the existing last-resort kill policy.
    child.kill()
    try:
        return child.wait(timeout=grace_seconds), True
    except subprocess.TimeoutExpired:
        pause('Owned non-rendering process could not be reaped after bounded shutdown')
        return 78, False
