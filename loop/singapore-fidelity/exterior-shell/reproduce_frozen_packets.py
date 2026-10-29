"""Re-run the frozen CPU packets in an isolated standard-library staging tree.
No engine, network, live-output overwrite or in-flight proposal is required.
"""
from pathlib import Path
import json,hashlib,gzip,shutil,tempfile,subprocess,sys,argparse
ROOT=Path(__file__).resolve().parents[3]
MANIFEST=Path(__file__).with_name('FROZEN_PACKET_REPRODUCTION_CLOSURE.json')

def sha(data):return hashlib.sha256(data).hexdigest()
def comparable(value,ignored):
 if not isinstance(value,dict):return value
 return {k:v for k,v in value.items() if k not in ignored}

def main():
 m=json.loads(MANIFEST.read_text());results=[]
 for item in m['frozen_references']:
  if sha((ROOT/item['repository_path']).read_bytes())!=item['sha256']:raise RuntimeError('Frozen output reference changed: '+item['repository_path'])
 with tempfile.TemporaryDirectory(prefix='mbs-frozen-packets-') as temporary:
  stage=Path(temporary)
  for item in m['files']:
   source=ROOT/item['repository_path'];payload=source.read_bytes()
   if sha(payload)!=item['sha256']:raise RuntimeError('Frozen dependency changed: '+item['repository_path'])
   destination=stage/item.get('staging_path',item['repository_path']);destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(payload)
  for item in m['compressed_inputs']:
   source=ROOT/item['repository_path'];raw=source.read_bytes()
   if sha(raw)!=item['compressed_sha256']:raise RuntimeError('Compressed input changed: '+str(source))
   payload=gzip.decompress(raw)
   if sha(payload)!=item['payload_sha256']:raise RuntimeError('Frozen fixture payload changed: '+str(source))
   destination=stage/item['staging_path'];destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(payload)
  for command in m['checks']:
   process=subprocess.run([sys.executable,*command['python_args']],cwd=stage,capture_output=True,text=True,timeout=command['timeout_seconds'])
   result={'name':command['name'],'exit_code':process.returncode,'stdout':process.stdout[-2000:],'stderr':process.stderr[-2000:]}
   if process.returncode:results.append(result);raise RuntimeError(json.dumps(result))
   for comparison in command.get('compare_json',[]):
    observed=json.loads((stage/comparison['generated_path']).read_text());expected=json.loads((ROOT/comparison['frozen_reference_path']).read_text());ignored=comparison.get('ignore_top_level_fields',[])
    equal=comparable(observed,ignored)==comparable(expected,ignored);result.setdefault('semantic_comparisons',[]).append({'reference':comparison['frozen_reference_path'],'equal':equal,'ignored_volatile_fields':ignored})
    if not equal:raise RuntimeError('Frozen semantic output mismatch: '+comparison['frozen_reference_path'])
   results.append(result)
 return {'schema':'mbs_frozen_cpu_packet_reproduction_result_v1','all_passed':True,'checks':results,'used_only_frozen_hash_closure':True,'engines_network_or_live_outputs_touched':False}

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--report');args=p.parse_args();result=main();text=json.dumps(result,indent=2)+'\n'
 if args.report:Path(args.report).write_text(text)
 print(text)
