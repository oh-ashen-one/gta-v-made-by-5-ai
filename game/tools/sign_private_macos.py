#!/usr/bin/env python3
"""Create a task-local ad-hoc-signed private macOS copy; no identity or notarization.
The source app is never changed. Keep public asset redistribution gates separate.
"""
import argparse,hashlib,json,subprocess
from pathlib import Path
from datetime import datetime,timezone
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('destination',type=Path);p.add_argument('archive',type=Path);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
assert a.source.is_dir() and a.source.suffix=='.app'
assert not a.destination.exists() and not a.archive.exists(),'Refusing to overwrite an existing artifact'
a.destination.parent.mkdir(parents=True,exist_ok=True);a.archive.parent.mkdir(parents=True,exist_ok=True)
def digest(f):return hashlib.sha256(f.read_bytes()).hexdigest()
def inventory(folder):return {str(f.relative_to(folder)):{'sha256':digest(f),'bytes':f.stat().st_size} for f in folder.rglob('*') if f.is_file()}
started=datetime.now(timezone.utc).isoformat();before=inventory(a.source)
subprocess.run(['/usr/bin/ditto',str(a.source),str(a.destination)],check=True)
# Remove only cosmetic metadata rejected by codesign. Preserve quarantine,
# provenance, ACLs and every other security-related attribute.
removed_cosmetic_attributes=[]
for file in [a.destination,*a.destination.rglob('*')]:
 names=subprocess.check_output(['/usr/bin/xattr',str(file)],text=True).splitlines()
 for name in names:
  if name in {'com.apple.FinderInfo','com.apple.ResourceFork'}:
   subprocess.run(['/usr/bin/xattr','-d',name,str(file)],check=True)
   removed_cosmetic_attributes.append({'path':str(file.relative_to(a.destination)),'attribute':name})
subprocess.run(['/usr/bin/codesign','--force','--deep','--sign','-',str(a.destination)],check=True)
verified=subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict','--verbose=2',str(a.destination)],capture_output=True,text=True,check=True)
inspected=subprocess.run(['/usr/bin/codesign','-dv',str(a.destination)],capture_output=True,text=True,check=True)
after=inventory(a.destination)
pck=[f for f in before if f.endswith('.pck')];assert pck and all(before[f]==after[f] for f in pck),'Game PCK changed unexpectedly'
assert inventory(a.source)==before,'Source app changed unexpectedly'
subprocess.run(['/usr/bin/ditto','-c','-k','--keepParent',str(a.destination),str(a.archive)],check=True)
report={'started_utc':started,'finished_utc':datetime.now(timezone.utc).isoformat(),'source':str(a.source),'destination':str(a.destination),'archive':str(a.archive),'archive_sha256':digest(a.archive),'archive_bytes':a.archive.stat().st_size,'before':before,'after':after,'pck_identical':True,'source_unchanged':True,'strict_verify_exit':verified.returncode,'strict_verify_output':verified.stdout+verified.stderr,'signature_description':inspected.stdout+inspected.stderr,'qualification':'Local ad-hoc signature only; no Developer ID, notarization, Finder/Gatekeeper or public redistribution certification.'}
report['removed_cosmetic_attributes']=removed_cosmetic_attributes
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2));print(json.dumps({k:report[k] for k in ['archive','archive_sha256','archive_bytes','strict_verify_exit','pck_identical','source_unchanged','finished_utc']}))
