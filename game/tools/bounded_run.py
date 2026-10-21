#!/usr/bin/env python3
"""Run a task-owned command with a wall-clock deadline and graceful cleanup."""
import argparse, subprocess, signal, time, json, os, sys, hashlib, re
from pathlib import Path
from datetime import datetime, timezone
p=argparse.ArgumentParser(); p.add_argument('--seconds',type=float,default=180); p.add_argument('--log',required=True); p.add_argument('command',nargs=argparse.REMAINDER)
a=p.parse_args(); cmd=a.command[1:] if a.command and a.command[0]=='--' else a.command
start=time.monotonic(); timed=False
root=Path(__file__).resolve().parents[2]
files=list((root/'game'/'src').rglob('*.gd'))+[root/'game'/'project.godot']
source_hashes={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
try: checkpoint=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
except Exception: checkpoint='unknown'
asset_hashes={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for folder in ['authored','providers'] for f in (root/'game'/'assets'/folder).glob('*.glb')}
try:
 patch=subprocess.check_output(['git','diff','HEAD','--','game/src','game/project.godot','game/assets/authored/shaders'],cwd=root,text=True)
 Path(a.log+'.source.patch').parent.mkdir(parents=True,exist_ok=True)
 Path(a.log+'.source.patch').write_text(patch)
except Exception: pass
meta={'asset_hashes':asset_hashes,'started_utc' :datetime.now(timezone.utc).isoformat(),'checkpoint':checkpoint,'source_hashes':source_hashes,'command':cmd}

os.makedirs(os.path.dirname(os.path.abspath(a.log)),exist_ok=True)
with open(a.log,'w') as f:
 child=subprocess.Popen(cmd,stdout=f,stderr=subprocess.STDOUT,start_new_session=True)
 meta['pid']=child.pid
 Path(a.log+'.meta.json').write_text(json.dumps(meta,indent=2))
 print(json.dumps({'pid':child.pid,'log':a.log,'command':cmd}),flush=True)
 try: code=child.wait(timeout=a.seconds)
 except subprocess.TimeoutExpired:
  timed=True; child.send_signal(signal.SIGTERM)
  try: code=child.wait(timeout=60)
  except subprocess.TimeoutExpired: child.kill(); code=child.wait()
engine_code=code
fatal_patterns=re.findall(r'(?:SCRIPT ERROR|SHADER ERROR|Parse Error|Failed to load script)[^\n]*',Path(a.log).read_text(errors='replace'))
if code==0 and fatal_patterns: code=2
meta['engine_exit_code']=engine_code
meta['fatal_errors']=fatal_patterns
meta.update({'exit_code':code,'timeout':timed,'elapsed_sec':round(time.monotonic()-start,2),'finished_utc':datetime.now(timezone.utc).isoformat(),'child_reaped':True})
Path(a.log+'.meta.json').write_text(json.dumps(meta,indent=2))
print(json.dumps({'pid':child.pid,'exit_code':code,'timeout':timed,'elapsed_sec':meta['elapsed_sec']}),flush=True)
sys.exit(124 if timed else code)
