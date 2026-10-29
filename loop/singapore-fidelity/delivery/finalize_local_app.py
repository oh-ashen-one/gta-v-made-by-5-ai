#!/usr/bin/env python3
"""Verify the completed local file snapshot and record owner-deferred native QA.
Never starts the engine. Requires build_local_app.py to have completed first.
"""
import argparse,ast,hashlib,json,re,shutil,subprocess
from datetime import datetime,timezone
from pathlib import Path
from packaging_metadata import clean
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--recover-assembled',action='store_true');parser.add_argument('--app',type=Path);a=parser.parse_args()
repo=Path(__file__).resolve().parents[3];out=a.output.resolve();manifest_path=out/'BUILD_MANIFEST.json'
if manifest_path.is_file():
 manifest=json.loads(manifest_path.read_text())
elif a.recover_assembled:
 manifest={'app':str(a.app.resolve() if a.app else out/'Orchard Reach — Fidelity Milestone.app'),'kind':'local Studio development snapshot using installed Godot4.7.1','engine_path':'/Applications/Godot.app/Contents/MacOS/Godot','self_contained_engine':False,'private_build_only':True,'recovery':'Initial assembly completed; signing failed on copied FinderInfo. No engine was launched.','included_preview_spaces':['public hotel lobby','reconstructed guest-floor layout','Tower2Level5 spa layout'],'unfinished':['complete source-coordinate city integration','complete hotel/resort interiors','native/rendered acceptance']}
else:raise SystemExit('Missing completed manifest; use explicit assembled-package recovery only')
app=Path(manifest['app']);game=app/'Contents/Resources/game'
assert (app/'Contents/Info.plist').is_file() and (app/'Contents/MacOS/Orchard Reach').is_file(), 'Assembly is incomplete'
assert (app.parent==out or (a.app and app==a.app.resolve())) and game.is_dir(), 'Unexpected delivery path'
import plistlib
assert plistlib.loads((app/'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier')=='com.ashenone.orchardreach.fidelitymilestone', 'Not our milestone app'
# The only source edit during the file snapshot was smoke-test audio teardown.
# Refresh this exact task-owned file before final identity and signature.
p=Path('src/scenes/hotel_preview.gd');shutil.copy2(repo/'game'/p,game/p)
issues=[];gd_hashes={}
for source in (repo/'game/src').rglob('*.gd'):
 rel=source.relative_to(repo/'game');target=game/rel
 if not target.is_file():issues.append('missing '+str(rel));continue
 expected=hashlib.sha256(source.read_bytes()).hexdigest();actual=hashlib.sha256(target.read_bytes()).hexdigest()
 if actual!=expected:issues.append('source mismatch '+str(rel))
 gd_hashes[str(rel)]=actual
counts={}
for directory in ['assets','.godot/imported']:
 source_root=repo/'game'/directory;target_root=game/directory
 source_sizes={str(p.relative_to(source_root)):p.stat().st_size for p in source_root.rglob('*') if p.is_file()}
 target_sizes={str(p.relative_to(target_root)):p.stat().st_size for p in target_root.rglob('*') if p.is_file()}
 if source_sizes!=target_sizes:issues.append('path/size copy mismatch '+directory)
 counts[directory]={'files':len(source_sizes),'logical_bytes':sum(source_sizes.values()),'verification':'relative paths and byte sizes; not independent asset content hashes'}
missing_remaps=[]
for importer in (game/'assets').rglob('*.import'):
 for target in re.findall(r'"(res://\.godot/imported/[^"\n]+)"',importer.read_text()):
  if not (game/target[6:]).is_file():missing_remaps.append(target)
if missing_remaps:issues.append('missing imported remaps '+repr(sorted(set(missing_remaps))))
if issues:raise SystemExit(json.dumps(issues,indent=2))
removed_metadata=clean(app)
subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['/usr/bin/codesign','--verify','--strict','--verbose=2',str(app)],check=True)
checkpoint=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
manifest.update({'finalized_utc':datetime.now(timezone.utc).isoformat(),'source_checkpoint':checkpoint,'source_file_sha256':gd_hashes,'copy_verification':counts,'missing_import_remaps':[],'native_launch_verified':False,'runtime_check_status':'DEFERRED_BY_OWNER_NO_ENGINE_OR_GPU_LAUNCH','automatic_test_or_launch_scheduled':False,'removed_packaging_metadata':removed_metadata,'signature_verification':'ad-hoc signature strict verification passed; not notarization or launch proof'})
files=[p for p in app.rglob('*') if p.is_file()]
manifest['file_count']=len(files);manifest['logical_bytes']=sum(p.stat().st_size for p in files)
manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
# Use the current reviewed README from the builder without executing it.
tree=ast.parse(Path(__file__).with_name('build_local_app.py').read_text())
readme=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='readme' for t in n.targets))
(out/'START_HERE.md').write_text(readme)
print(json.dumps({'app':str(app),'source_checkpoint':checkpoint,'gd_files_hash_matched':len(gd_hashes),'counts':counts,'signature':'verified','native_launch_verified':False}))
