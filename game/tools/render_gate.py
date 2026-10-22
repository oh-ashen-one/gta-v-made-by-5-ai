#!/usr/bin/env python3
"""Last-moment shared-engine safety check; used inside the common GPU lease."""
import os,sys,subprocess,json
from pathlib import Path
root=Path(os.environ.get('GPU_SLOT_DIR',os.path.expanduser('~/.cache/gpu-slot')))
if (root/'PAUSED').exists():raise SystemExit('Shared GPU coordinator is PAUSED; renderer not launched.')
lines=subprocess.check_output(['ps','-axo','pid=,stat=,comm='],text=True).splitlines();engines=[]
for line in lines:
 parts=line.strip().split(None,2)
 if len(parts)!=3:continue
 pid,state,exe=parts
 if Path(exe).name not in {'Godot','UnrealEditor','Unity','Blender','blender','Orchard Reach'}:continue
 args=subprocess.check_output(['ps','-p',pid,'-o','command='],text=True)
 if state.startswith(('E','Z')):raise SystemExit('Engine stuck exiting: '+pid+' '+exe)
 if '--headless' not in args:engines.append({'pid':int(pid),'state':state,'executable':exe})
print(json.dumps({'renderer_preflight':engines,'shared_root':str(root)}),flush=True)
if len(engines)>=2:raise SystemExit('Mixed renderer cap2 already occupied; no launch.')
cmd=sys.argv[1:];cmd=cmd[1:] if cmd and cmd[0]=='--' else cmd
if not cmd:raise SystemExit('No command')
os.execvp(cmd[0],cmd)
