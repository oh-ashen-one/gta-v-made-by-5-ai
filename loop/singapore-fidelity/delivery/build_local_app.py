#!/usr/bin/env python3
"""Assemble an immutable local Studio development app, without starting Godot.

This is ordinary file packaging, not an engine export or a runtime test. It
uses the owner's already installed, unmodified Godot app when launched.
"""
import argparse,hashlib,json,os,plistlib,shutil,subprocess,time
from datetime import datetime,timezone
from pathlib import Path

REPO=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True)
a=parser.parse_args();out=a.output.resolve()
if out.exists():raise SystemExit('Refusing an existing delivery directory')
if shutil.disk_usage(out.parent).free<12*1024**3:raise SystemExit('Less than12GiB direct free space; refusing packaging')
engine=Path('/Applications/Godot.app/Contents/MacOS/Godot')
if not engine.is_file():raise SystemExit('Verified installed Studio Godot runtime is unavailable')
out.mkdir(parents=True)
app=out/'Orchard Reach — Fidelity Milestone.app';contents=app/'Contents';mac=contents/'MacOS';res=contents/'Resources'
mac.mkdir(parents=True);res.mkdir();game=res/'game';game.mkdir()
source=REPO/'game'
# Preserve the ready imported resources; exclude editor histories, captures and
# unrelated experimental country datasets. The preview needs only its source
# frame manifest and the existing interior inventory.
for name in ['assets','src']:
 subprocess.run(['/bin/cp','-cR',str(source/name),str(game/name)],check=True)
for name in ['project.godot','main.tscn']:
 shutil.copy2(source/name,game/name)
cache=game/'.godot';cache.mkdir()
for name in ['imported','global_script_class_cache.cfg','uid_cache.bin']:
 p=source/'.godot'/name
 if p.is_dir():subprocess.run(['/bin/cp','-cR',str(p),str(cache/name)],check=True)
 elif p.is_file():shutil.copy2(p,cache/name)
(game/'data/mbs-interior').mkdir(parents=True)
shutil.copy2(source/'data/mbs-interior/inventory.json',game/'data/mbs-interior/inventory.json')
geo=game/'data/geography/osm-2026-10-27';geo.mkdir(parents=True)
shutil.copy2(source/'data/geography/osm-2026-10-27/manifest.json',geo/'manifest.json')
launcher=mac/'Orchard Reach'
subprocess.run(['/usr/bin/xcrun','clang','-O2',str(Path(__file__).with_name('launcher.c')),'-o',str(launcher)],check=True)
plist={'CFBundleDevelopmentRegion':'en','CFBundleExecutable':'Orchard Reach','CFBundleIdentifier':'com.ashenone.orchardreach.fidelitymilestone','CFBundleName':'Orchard Reach — Fidelity Milestone','CFBundleDisplayName':'Orchard Reach — Fidelity Milestone','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.2.0','CFBundleVersion':'20261029.1','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True}
with (contents/'Info.plist').open('wb') as f:plistlib.dump(plist,f)
subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['/usr/bin/codesign','--verify','--strict','--verbose=2',str(app)],check=True)
checkpoint=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
files=[p for p in app.rglob('*') if p.is_file()]
manifest={'built_utc':datetime.now(timezone.utc).isoformat(),'source_checkpoint':checkpoint,'app':str(app),'kind':'local Studio development snapshot using installed Godot4.7.1','engine_path':str(engine),'engine_version_verified_before_task':'4.7.1.stable.official.a13da4feb','self_contained_engine':False,'native_launch_verified':False,'runtime_check_status':'DEFERRED_BY_OWNER_NO_ENGINE_OR_GPU_LAUNCH','private_build_only':True,'source_file_sha256':{str(p.relative_to(game)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (game/'src').rglob('*.gd')},'file_count':len(files),'logical_bytes':sum(p.stat().st_size for p in files),'included_preview_spaces':['public hotel lobby','reconstructed guest-floor layout','Tower2Level5 spa layout'],'unfinished':['complete hotel and resort interiors','all1844source-catalogue keys physically allocated/furnished','full source-coordinate city integration','final native/rendered acceptance']}
(out/'BUILD_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
readme='''# Orchard Reach — Fidelity Milestone

When you are ready to play after the GPU is free, open **Orchard Reach — Fidelity Milestone.app** on this Mac Studio. This is a private development snapshot using the installed Godot4.7.1 runtime; it is not a portable/notarized release. It runs the copied game content, not the live working tree.

The main city retains its missions, driving and helicopter play. This branch includes the police-floor/damage, helicopter camera/descent and supported-roof fixes. Choose **MBS hotel interior · Preview** from the title menu to walk the lobby, a furnished guest floor and the Level5 spa layout. Press Esc in that preview to change area or return to the city menu. The preview does not write the city's save file.

Controls: WASD move, mouse look, Shift run, Space jump, E interact, right mouse aim, left mouse fire, R reload. In flight, Space climbs and Shift descends; E exits only when support/clearance is safe.

The entire source-accurate city and complete hotel are NOT included as finished work. Some interior floors are closed in this preview; the broader source data, room allocations and programme contracts remain preserved on the task branch. These selected interiors are reconstructions, not certified as-built plans.

The owner explicitly deferred all game/engine/GPU launches at this milestone. Native launch and final rendered checks have not run on this snapshot. File packaging/signature verification alone is not gameplay proof; no automatic test or game launch is scheduled.
'''
(out/'START_HERE.md').write_text(readme)
print(json.dumps({'app':str(app),'file_count':manifest['file_count'],'logical_bytes':manifest['logical_bytes'],'native_launch_verified':False}))
