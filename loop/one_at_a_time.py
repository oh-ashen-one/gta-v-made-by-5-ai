#!/usr/bin/env python3
"""Hold this loop's private render lock, then exec the command (the lock is held until it exits).

  python3 loop/one_at_a_time.py -- CMD...

Owner rule 2026-10-22: share the Studio. At most one of this loop's rendered runs is in the shared GPU lease
queue at a time, so we never hold both shared slots and never park an unsatisfiable request at the head of the
shared FIFO queue (which would block other sessions). Waiting happens here, outside the shared queue.
"""
import fcntl, os, sys
lock_path = os.environ.get("OPUS55_RENDER_LOCK", "/private/tmp/opus55/render.lock")
os.makedirs(os.path.dirname(lock_path), exist_ok=True)
fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)          # blocks while another of our renders runs or queues
os.set_inheritable(fd, True)            # keep the lock across exec until the render exits
cmd = sys.argv[1:]
cmd = cmd[1:] if cmd and cmd[0] == "--" else cmd
os.execvp(cmd[0], cmd)
