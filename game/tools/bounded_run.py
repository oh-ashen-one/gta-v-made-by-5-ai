#!/usr/bin/env python3
"""Task-owned command, source identity, RSS trend, fatal-log check and clean exit."""
import argparse, subprocess, signal, time, json, os, sys, hashlib, re, threading, resource
from pathlib import Path
from datetime import datetime, timezone
p=argparse.ArgumentParser();p.add_argument('--seconds',type=float,default=180);p.add_argument('--log',required=True);p.add_argument('command',nargs=argparse.REMAINDER)
a=p.parse_args();cmd=a.command[1:] if a.command and a.command[0]=='--' else a.command
start=time.monotonic();timed=False;root=Path(__file__).resolve().parents[2];log=Path(a.log);log.parent.mkdir(parents=True,exist_ok=True)
def utc():return datetime.now(timezone.utc).isoformat()
files=list((root/'game'/'src').rglob('*.gd'))+[root/'game'/'project.godot']
source_hashes={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
try:checkpoint=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
except Exception:checkpoint='unknown'
asset_hashes={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for folder in ['authored','providers'] for f in (root/'game'/'assets'/folder).glob('*.glb')}
runtime_art_hashes={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for folder in ['authored','providers'] for f in (root/'game'/'assets'/folder).rglob('*') if f.is_file() and f.suffix.lower() in {'.glb','.png','.jpg','.jpeg','.gdshader','.tres','.tscn'}}
try:
 patch=subprocess.check_output(['git','diff','HEAD','--','game/src','game/project.godot','game/assets/authored/shaders'],cwd=root,text=True)
 Path(a.log+'.source.patch').write_text(patch)
except Exception:pass
meta={'supervisor_pid':os.getpid(),'started_utc':utc(),'checkpoint':checkpoint,'source_hashes':source_hashes,'asset_hashes':asset_hashes,'runtime_art_hashes':runtime_art_hashes,'command':cmd}
samples=[];sampling_errors=[];stop=threading.Event();requested_stop=threading.Event()
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
with log.open('w') as output:
 child=subprocess.Popen(cmd,stdout=output,stderr=subprocess.STDOUT,start_new_session=True,preexec_fn=_lower_priority)
 meta['pid']=child.pid
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
  try:child.wait(timeout=min(.5,max(.001,deadline-time.monotonic())))
  except subprocess.TimeoutExpired:pass
 if child.poll() is None:
  timed=not requested_stop.is_set();child.send_signal(signal.SIGTERM)
  try:code=child.wait(timeout=60)
  except subprocess.TimeoutExpired:child.kill();code=child.wait()
 else:code=child.returncode
 stop.set();monitor.join(timeout=3)
engine_code=code
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
meta.update({'engine_exit_code':engine_code,'exit_code':code,'fatal_errors':fatal,'classified_nonfatal_errors':known,'all_error_lines':errors,'timeout':timed,'elapsed_sec':round(time.monotonic()-start,2),'finished_utc':utc(),'child_reaped':True,'sampling_errors':sampling_errors,'resource_samples':len(samples),'rss_samples_available':bool(samples),'rss_peak_kib_sampled':max((x['rss_kib'] for x in samples),default=None),'child_peak_rss_bytes':peak if sys.platform=='darwin' else peak*1024})
Path(a.log+'.meta.json').write_text(json.dumps(meta,indent=2))
print(json.dumps({'pid':child.pid,'exit_code':code,'timeout':timed,'elapsed_sec':meta['elapsed_sec'],'fatal_error_count':len(fatal),'rss_samples':len(samples)}),flush=True)
sys.exit(124 if timed else code)
