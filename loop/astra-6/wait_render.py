#!/usr/bin/env python3
"""Wait for the unchanged shared render gate, then run one normal leased job.

This readiness check does not acquire a slot or replace the last-moment check
inside render.sh. There is no retry after a real engine/test failure.
"""
import argparse, datetime, json, os, signal, subprocess, sys, time
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--until',required=True)
p.add_argument('--state',required=True)
p.add_argument('command',nargs=argparse.REMAINDER)
a=p.parse_args();cmd=a.command[1:] if a.command and a.command[0]=='--' else a.command
root=Path(__file__).resolve().parents[2]
cutoff=datetime.datetime.fromisoformat(a.until.replace('Z','+00:00')).timestamp()
state=Path(a.state);state.parent.mkdir(parents=True,exist_ok=True)
child=None;stopping=False
started=datetime.datetime.now(datetime.timezone.utc).isoformat()
def record(status,**extra):
 data={'driver_pid':os.getpid(),'started_utc':started,'updated_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':status,'until':a.until,'command':cmd,**extra}
 state.write_text(json.dumps(data,indent=2)+'\n');print(json.dumps(data),flush=True)
def stop(sig,_frame):
 global stopping
 stopping=True
 if child is not None and child.poll() is None:child.terminate()
for sig in [signal.SIGTERM,signal.SIGINT,signal.SIGHUP]:signal.signal(sig,stop)
record('waiting_for_capacity')
while not stopping and time.time()<cutoff:
 check=subprocess.run([sys.executable,str(root/'game/tools/render_gate.py'),'--','/usr/bin/true'],cwd=root,capture_output=True,text=True)
 if check.returncode==0:
  # The normal wrapper independently queues/acquires the shared slot,
  # repeats render_gate, and enforces RUN.json's fixed hard deadline.
  child=subprocess.Popen(cmd,cwd=root)
  record('normal_leased_command_running',child_pid=child.pid)
  while child.poll() is None and not stopping:time.sleep(.5)
  if child.poll() is None:
   try:child.wait(timeout=65)
   except subprocess.TimeoutExpired:
    record('owned_command_requires_manager_cleanup',child_pid=child.pid)
    raise SystemExit(2)
  record('command_finished',child_pid=child.pid,exit_code=child.returncode)
  raise SystemExit(child.returncode)
 for _ in range(60):
  if stopping or time.time()>=cutoff:break
  time.sleep(1)
record('stopped_without_launch' if stopping else 'capacity_cutoff_without_launch')
raise SystemExit(0 if stopping else 3)
