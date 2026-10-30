#!/usr/bin/env python3
"""Clone the owned previous local app and replace source/data only. No engine.
The prior candidate is preserved; destination paths must not exist.
"""
import argparse,json,plistlib,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('--base-app',type=Path,required=True);p.add_argument('--app',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
base=a.base_app.resolve();app=a.app.resolve();out=a.output.resolve()
assert not app.exists() and not out.exists(), 'Refusing existing destination'
assert plistlib.loads((base/'Contents/Info.plist').read_bytes())['CFBundleIdentifier']=='com.ashenone.orchardreach.fidelitymilestone', 'Not the owned preceding milestone'
subprocess.run(['/bin/cp','-cR',str(base),str(app)],check=True)
game=app/'Contents/Resources/game'
# Only the new copied app is modified; the source checkout and prior app stay.
shutil.rmtree(game/'src');shutil.copytree(ROOT/'game/src',game/'src')
for rel in ['project.godot','main.tscn','data/mbs-interior/inventory.json','data/mbs-interior/city_access.json']:
 target=game/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'game'/rel,target)
plist_path=app/'Contents/Info.plist';data=plistlib.loads(plist_path.read_bytes());data['CFBundleName']='Orchard Reach — MBS Connected';data['CFBundleDisplayName']=data['CFBundleName'];data['CFBundleVersion']='20261029.2';plist_path.write_bytes(plistlib.dumps(data))
out.mkdir(parents=True)
manifest={'app':str(app),'kind':'local Studio development snapshot using installed Godot4.7.1','engine_path':'/Applications/Godot.app/Contents/MacOS/Godot','self_contained_engine':False,'private_build_only':True,'city_doorway_connected_in_source':True,'preview_menu_present':False,'included_interior_spaces':['public hotel lobby','T3-L24 guest floor','T2-L5 spa'],'native_launch_verified':False,'unfinished':['native validation of this integration','complete hotel/resort','full geographic city replacement']}
(out/'BUILD_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
subprocess.run([sys.executable,str(ROOT/'loop/singapore-fidelity/delivery/finalize_local_app.py'),'--app',str(app),'--output',str(out)],check=True)
