#!/usr/bin/env python3
"""Task-owned bounded wait outside the shared GPU FIFO, then normal driver.

This is a conservative early observation, never a replacement for gpu_slot or
the last-moment render_gate inside its lease. Foreign processes are read only.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

REPO = Path(__file__).resolve().parents[2]
PRIVATE = Path('/private/tmp/singapore-fidelity')
GPU = Path.home()/'.cache/gpu-slot'
active = None
stopping = False

def stop(_signal, _frame):
    global stopping
    stopping = True
    # Only the verified subprocess this queue started. Its normal driver owns
    # descendant cleanup and releases its lease. Never signal a foreign engine.
    if active is not None and active.poll() is None:
        active.terminate()

def snapshot():
    if (GPU/'PAUSED').exists() or (GPU/'STREAMING').exists():
        return False, 'shared coordinator paused or streaming', []
    found = []
    try:
        lines = subprocess.check_output(['ps','-axo','pid=,stat=,comm='],text=True).splitlines()
        for line in lines:
            parts = line.strip().split(None,2)
            if len(parts)!=3: continue
            pid,state,exe = parts
            if Path(exe).name not in {'Godot','godot','UnrealEditor','Unity','Blender','blender','Orchard Reach'}: continue
            args = subprocess.check_output(['ps','-p',pid,'-o','command='],text=True).strip()
            if state.startswith(('E','Z')): return False, 'engine still exiting', found
            if str(REPO/'game') in args: return False, 'task engine already live', found
            if '--headless' not in args: found.append({'pid':int(pid),'state':state,'executable':exe})
    except (OSError,subprocess.CalledProcessError):
        return False, 'process observation incomplete', found
    return len(found)<2, 'capacity observed' if len(found)<2 else 'mixed renderer cap occupied', found

def owned(path):
    path = Path(path)
    if not path.is_absolute() or path != Path(os.path.normpath(path)) or PRIVATE not in path.parents:
        raise ValueError('Queue evidence must be an explicit task-private child path')
    for parent in [path,*path.parents]:
        if parent.is_symlink(): raise ValueError('Symlink evidence path refused')
    return path

def validate(job):
    if set(job)!={'label','seconds','output','args','required_hashes'}: raise ValueError('Unknown queue job fields')
    if not isinstance(job['seconds'],int) or not 30<=job['seconds']<=1200: raise ValueError('Unbounded engine duration')
    if not isinstance(job['label'],str) or not job['label'].replace('-','').replace('_','').isalnum(): raise ValueError('Invalid job label')
    owned(job['output'])
    if not isinstance(job['args'],list) or not all(isinstance(v,str) for v in job['args']) or '--headless' not in job['args'] or '--qa-session' not in job['args']:
        raise ValueError('Only isolated headless QA jobs may use this queue')
    if not isinstance(job['required_hashes'],dict) or not job['required_hashes']: raise ValueError('Frozen source identities required')
    for name,digest in job['required_hashes'].items():
        source = REPO/name
        if REPO not in source.resolve().parents or hashlib.sha256(source.read_bytes()).hexdigest()!=digest:
            raise ValueError('Frozen source changed: '+name)

def main():
    global active
    parser=argparse.ArgumentParser()
    parser.add_argument('--plan',type=Path,required=True)
    parser.add_argument('--state',type=Path,required=True)
    parser.add_argument('--max-wait-seconds',type=int,default=1800)
    args=parser.parse_args()
    if not 15<=args.max_wait_seconds<=3600: raise ValueError('Bounded resource wait required')
    state=owned(args.state)
    if state.exists(): raise ValueError('Fresh queue state required')
    jobs=json.loads(args.plan.read_text())
    if not isinstance(jobs,list) or not 1<=len(jobs)<=4: raise ValueError('One to four explicit jobs required')
    for job in jobs: validate(job)
    # A fresh owned directory prevents journal/driver-log collisions with a
    # different invocation. Never clean or reuse another queue's state.
    state.parent.mkdir(parents=False,exist_ok=False)
    lock=(PRIVATE/'validation-queue.lock').open('a')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    record={'pid':os.getpid(),'started_unix':time.time(),'status':'waiting','jobs':[]}
    def publish():
        temporary=state.with_suffix('.json.part')
        with temporary.open('x') as output: output.write(json.dumps(record,indent=2)+'\n')
        temporary.replace(state)
    publish()
    for job in jobs:
        deadline=time.monotonic()+args.max_wait_seconds
        while not stopping:
            allowed,reason,engines=snapshot()
            record.update(status='waiting',current_job=job['label'],reason=reason,observed_engines=engines)
            publish()
            if allowed: break
            if time.monotonic()>=deadline:
                record.update(status='wait_expired');publish();return 3
            time.sleep(15)
        if stopping: record.update(status='stopped');publish();return 143
        validate(job)
        output=owned(job['output'])
        if output.exists(): raise ValueError('Refusing existing engine evidence directory')
        driver_log=state.parent/(job['label']+'.driver.log')
        with driver_log.open('x') as log:
            command=['bash',str(REPO/'loop/singapore-fidelity/run_engine.sh'),job['label'],str(job['seconds']),str(output),'--',*job['args']]
            active=subprocess.Popen(command,cwd=REPO,stdout=log,stderr=subprocess.STDOUT)
            entry={'label':job['label'],'driver_pid':active.pid,'output':str(output),'started_unix':time.time()}
            record['jobs'].append(entry);record.update(status='running');publish()
            code=active.wait()
            entry.update(exit_code=code,finished_unix=time.time())
            active=None;publish()
        # A real failed/native or last-moment denial needs root inspection.
        # Never silently relaunch, reset clocks, or overwrite its evidence.
        if code!=0: record.update(status='needs_review');publish();return code
    record.update(status='complete');publish();return 0

if __name__=='__main__': raise SystemExit(main())
