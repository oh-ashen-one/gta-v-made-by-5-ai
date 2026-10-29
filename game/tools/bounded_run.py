#!/usr/bin/env python3
"""Task-owned command, source identity, RSS trend, fatal-log check and clean exit."""
import argparse, subprocess, signal, time, json, os, sys, hashlib, re, threading, resource, uuid, math
from pathlib import Path
from datetime import datetime, timezone
from snapshot_hashes import snapshot
from render_startup_health import FirstFrameProbe, pause_shared, stop_owned
from render_launch_guard import is_engine_command, is_rendering_command, engine_arguments
p=argparse.ArgumentParser();p.add_argument('--seconds',type=float,default=180);p.add_argument('--log',required=True);p.add_argument('--first-frame-seconds',type=float,default=0);p.add_argument('command',nargs=argparse.REMAINDER)
a=p.parse_args();cmd=a.command[1:] if a.command and a.command[0]=='--' else a.command
if not math.isfinite(a.first_frame_seconds) or not 0<=a.first_frame_seconds<=300:
 p.error('first-frame-seconds must be finite and within 0..300')
if a.first_frame_seconds and '--headless' in engine_arguments(cmd):
 p.error('A headless run cannot claim a rendered first frame')
if any(arg=='--qa-render-health' or arg.startswith('--qa-render-health=') for arg in cmd):
 p.error('The supervisor owns the startup nonce; remove any replayed --qa-render-health argument')
frame_nonce=uuid.uuid4().hex if a.first_frame_seconds else None
potential_renderer=bool(frame_nonce) or is_rendering_command(cmd)
if potential_renderer and not frame_nonce:
 p.error('Rendered captures require an explicit supported first-frame health protocol; legacy uninstrumented packages are refused before launch')
if frame_nonce:
 if '--' not in cmd:cmd.append('--')
 cmd.append('--qa-render-health='+frame_nonce)
start=time.monotonic();timed=False;root=Path(__file__).resolve().parents[2];log=Path(a.log);log.parent.mkdir(parents=True,exist_ok=True)
def utc():return datetime.now(timezone.utc).isoformat()
files=list((root/'game'/'src').rglob('*.gd'))+[root/'game'/'project.godot']
source_hashes={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
try:checkpoint=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
except Exception:checkpoint='unknown'
runtime_art_files=[f for folder in ['authored','providers'] for f in (root/'game'/'assets'/folder).rglob('*') if f.is_file() and f.suffix.lower() in {'.glb','.png','.jpg','.jpeg','.gdshader','.tres','.tscn'}]
cache_key=hashlib.sha256(str(root).encode()).hexdigest()[:20]
art_snapshot,art_snapshot_validation=snapshot(runtime_art_files,Path('/private/tmp/orchard-build-hashes')/(cache_key+'.json'))
runtime_art_hashes={str(f.relative_to(root)):value for f,value in art_snapshot.items()}
asset_hashes={str(f.relative_to(root)):art_snapshot[f] for folder in ['authored','providers'] for f in (root/'game'/'assets'/folder).glob('*.glb')}
try:
 patch=subprocess.check_output(['git','diff','HEAD','--','game/src','game/project.godot','game/assets/authored/shaders'],cwd=root,text=True)
 Path(a.log+'.source.patch').write_text(patch)
except Exception:pass
meta={'supervisor_pid':os.getpid(),'started_utc':utc(),'checkpoint':checkpoint,'source_hashes':source_hashes,'asset_hashes':asset_hashes,'runtime_art_hashes':runtime_art_hashes,'art_snapshot_validation':art_snapshot_validation,'command':cmd}
samples=[];sampling_errors=[];stop=threading.Event();requested_stop=threading.Event()
wedge=False;frame_probe=None;child_reaped=False
shared_root=Path(os.environ.get('GPU_SLOT_DIR',str(Path.home()/'.cache/gpu-slot')))
def pause_for_wedge(reason):
 global wedge
 wedge=True;meta['wedge_reason']=reason
 try:meta['shared_pause']=pause_shared(shared_root,child.pid,reason)
 except Exception as error:meta['shared_pause_error']=str(error)
 print(json.dumps({'wedge':True,'owned_child_pid':child.pid,'reason':reason,'shared_pause':meta.get('shared_pause'),'shared_pause_error':meta.get('shared_pause_error')}),flush=True)

def check_startup_health():
 if not frame_probe or meta['render_startup']['confirmed']:return
 first=frame_probe.poll()
 if first:
  meta['render_startup'].update(confirmed=True,evidence=first,observed_elapsed_seconds=round(time.monotonic()-child_started,3))
 elif not wedge and time.monotonic()-child_started>=a.first_frame_seconds:
  pause_for_wedge('Owned rendered capture did not confirm its first frame within the declared startup deadline')
  requested_stop.set()

def sample_process(pid):
 with open(a.log+'.resources.jsonl','w') as out:
  while not stop.is_set():
   try:
    r=subprocess.run(['ps','-p',str(pid),'-o','rss=,pcpu='],capture_output=True,text=True,timeout=2)
    parts=r.stdout.split()
    if len(parts)==2:
     row={'seconds':round(time.monotonic()-start,3),'utc':utc(),'pid':pid,'rss_kib':int(parts[0]),'cpu_percent':float(parts[1])}
     samples.append(row);out.write(json.dumps(row)+'\n');out.flush()
    elif r.stderr.strip() and len(sampling_errors)<3: sampling_errors.append(r.stderr.strip())
   except Exception as error:
    if len(sampling_errors)<3: sampling_errors.append(str(error))
   stop.wait(5)
def _lower_priority():
 # Share the Studio (owner rule): lower CPU priority, but never fail the launch (e.g. already at the max niceness).
 try:
  want=int(os.environ.get('OPUS55_NICE','10'))
  if os.getpriority(os.PRIO_PROCESS,0)<want:os.setpriority(os.PRIO_PROCESS,0,want)
 except Exception:pass
# The source/art snapshot can take time. Recheck capacity AFTER that work,
# within the existing lease and in the exact child PID that execs the engine.
launch_cmd=([sys.executable,str(root/'game/tools/render_gate.py'),'--',*cmd]
            if is_engine_command(cmd) else cmd)
meta['launch_command']=launch_cmd
with log.open('w') as output:
 child=subprocess.Popen(launch_cmd,stdout=output,stderr=subprocess.STDOUT,start_new_session=True,preexec_fn=_lower_priority)
 meta['pid']=child.pid
 child_started=time.monotonic()
 if frame_nonce:
  frame_probe=FirstFrameProbe(log,child.pid,frame_nonce)
  meta['render_startup']={'nonce':frame_nonce,'first_frame_deadline_seconds':a.first_frame_seconds,'confirmed':False,'expected_first_frame_seconds':a.first_frame_seconds/2,'baseline_status':'provisional declared expectation, not a measured cold-start baseline','proof':'Actual GPU viewport readback; not gameplay/quality/performance acceptance'}
 def request_stop(signum,_frame):
  meta['requested_stop_signal']=signum
  requested_stop.set()
  if child.poll() is None:child.send_signal(signal.SIGTERM)
 for sig in [signal.SIGTERM,signal.SIGINT,signal.SIGHUP]:signal.signal(sig,request_stop)
 Path(a.log+'.meta.json').write_text(json.dumps(meta,indent=2))
 print(json.dumps({'pid':child.pid,'log':a.log,'command':cmd}),flush=True)
 monitor=threading.Thread(target=sample_process,args=(child.pid,),daemon=True);monitor.start()
 deadline=time.monotonic()+a.seconds
 while child.poll() is None and not requested_stop.is_set() and time.monotonic()<deadline:
  check_startup_health()
  if requested_stop.is_set():break
  try:child.wait(timeout=min(.5,max(.001,deadline-time.monotonic())))
  except subprocess.TimeoutExpired:pass
 if child.poll() is None:
  timed=not requested_stop.is_set()
  code,child_reaped=stop_owned(child,potential_renderer,lambda reason: pause_for_wedge(reason) if not wedge else None,check_health=check_startup_health)
 else:code=child.returncode
 stop.set();monitor.join(timeout=3)
child_reaped=child.poll() is not None
engine_code=child.returncode if child_reaped else None
if frame_probe:
 first=frame_probe.poll()
 if first and not meta['render_startup']['confirmed']:
  meta['render_startup'].update(confirmed=True,evidence=first,observed_elapsed_seconds=round(time.monotonic()-child_started,3))
 if not meta['render_startup']['confirmed'] and code==0:code=2
if wedge:code=78
content=re.sub(r'\x1b\[[0-9;]*m','',log.read_text(errors='replace'))
errors=[line for line in content.splitlines() if 'ERROR:' in line or 'Parse Error:' in line or 'Failed to load script' in line]
known=[];fatal=[]
for line in errors:
 if 'Condition "ret != noErr"' in line and 'get_system_ca_certificates' in content:
  known.append({'line':line,'qualification':'macOS system CA lookup denied in sandbox; preserved diagnostic'})
 elif any(flag in cmd for flag in ['--editor','--export-release','--export-debug']) and ('editor_settings-' in line or 'Error saving editor settings' in line):
  known.append({'line':line,'qualification':'global editor settings write blocked by sandbox; project import checked separately'})
 else:fatal.append(line)
if code==0 and fatal:code=2
peak=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
meta.update({'engine_exit_code':engine_code,'exit_code':code,'fatal_errors':fatal,'classified_nonfatal_errors':known,'all_error_lines':errors,'timeout':timed,'elapsed_sec':round(time.monotonic()-start,2),'finished_utc':utc(),'child_reaped':child_reaped,'sampling_errors':sampling_errors,'resource_samples':len(samples),'rss_samples_available':bool(samples),'rss_peak_kib_sampled':max((x['rss_kib'] for x in samples),default=None),'child_peak_rss_bytes':peak if sys.platform=='darwin' else peak*1024})
Path(a.log+'.meta.json').write_text(json.dumps(meta,indent=2))
print(json.dumps({'pid':child.pid,'exit_code':code,'timeout':timed,'elapsed_sec':meta['elapsed_sec'],'fatal_error_count':len(fatal),'rss_samples':len(samples)}),flush=True)
sys.exit(78 if wedge else 124 if timed else code)
