#!/usr/bin/env python3
"""Package only the explicit task-owned private asset folders and signed app ZIP.
No raw provider re-download, credential/config discovery, or public upload.
"""
import argparse,hashlib,json,tarfile,shutil,subprocess
from pathlib import Path
from datetime import datetime,timezone
p=argparse.ArgumentParser();p.add_argument('destination',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[2];destination=a.destination.resolve();assert not destination.exists(),'Refusing to overwrite a transfer directory'
folders=['game/assets/providers','art/source/characters','art/source/helicopter','art/provider-sources']
files=[]
for folder in folders:
 directory=root/folder;assert directory.is_dir(),folder
 for f in directory.rglob('*'):
  if f.is_symlink():raise RuntimeError('Refusing symlink in private transfer: '+str(f))
  if f.is_file() and f.name!='.DS_Store' and not f.name.endswith('.blend1'):files.append(f)
files.sort();assert len(list((root/'game/assets/providers').glob('*.glb')))==26
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
inventory={str(f.relative_to(root)):{'sha256':sha(f),'bytes':f.stat().st_size} for f in files}
source_zip=root/'game/build/mac/OrchardReach-wave02-private.zip';signature=json.loads((root/'docs/wave-02/private-signing.json').read_text());assert sha(source_zip)==signature['archive_sha256']
destination.mkdir(parents=True)
archive=destination/'OrchardReach-wave02-private-assets.tar'
def normalize(info):
 info.uid=info.gid=0;info.uname=info.gname='';info.mtime=0;return info
with tarfile.open(archive,'w') as tar:
 for f in files:tar.add(f,arcname=str(f.relative_to(root)),recursive=False,filter=normalize)
with tarfile.open(archive,'r') as tar:
 assert len(tar.getmembers())==len(inventory)
 for member in tar:
  stream=tar.extractfile(member);assert stream is not None
  h=hashlib.sha256()
  for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
  assert h.hexdigest()==inventory[member.name]['sha256'],member.name
zip_copy=destination/source_zip.name;shutil.copy2(source_zip,zip_copy);assert sha(zip_copy)==signature['archive_sha256']
result={'created_utc':datetime.now(timezone.utc).isoformat(),'implementation_checkpoint':'be6a8aa98b47735eb5b043db0860a0946767d1cd','evidence_head_at_preparation':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'branch':'feature/wave-02-astra','private_only':True,'asset_folders':folders,'files':inventory,'file_count':len(files),'provider_glb_count':26,'archive':str(archive),'archive_sha256':sha(archive),'archive_bytes':archive.stat().st_size,'app_archive':str(zip_copy),'app_archive_sha256':sha(zip_copy),'app_archive_bytes':zip_copy.stat().st_size,'all_tar_members_rehashed':True,'rights':'UNVERIFIED public source and packaged-binary redistribution; private owner-authorized implementation only','raw_sources':'Existing18 originals remain in sibling relay-manager/assets; do not regenerate','documentation':'Pull final origin/feature/wave-02-astra and read HANDOFF.md, NEXT_GOAL.md and docs/EVIDENCE.md'}
(destination/'TRANSFER.json').write_text(json.dumps(result,indent=2));(root/'docs/wave-02/private-transfer.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:result[k] for k in ['file_count','provider_glb_count','archive','archive_sha256','app_archive','app_archive_sha256','created_utc']}))
