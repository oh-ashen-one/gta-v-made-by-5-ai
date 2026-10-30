#!/usr/bin/env python3
"""Assemble an immutable local Studio development app, without starting Godot.

This is ordinary file packaging, not an engine export or a runtime test. It
uses the owner's already installed, unmodified Godot app when launched.
"""
import argparse,hashlib,json,os,plistlib,shutil,subprocess,time
from datetime import datetime,timezone
from pathlib import Path
from packaging_metadata import clean

REPO=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--app',type=Path)
a=parser.parse_args();out=a.output.resolve()
if out.exists():raise SystemExit('Refusing an existing delivery directory')
if shutil.disk_usage(out.parent).free<12*1024**3:raise SystemExit('Less than12GiB direct free space; refusing packaging')
engine=Path('/Applications/Godot.app/Contents/MacOS/Godot')
if not engine.is_file():raise SystemExit('Verified installed Studio Godot runtime is unavailable')
out.mkdir(parents=True)
app=a.app.resolve() if a.app else out/'Orchard Reach — Fidelity Milestone.app'
if app.exists():raise SystemExit('Refusing existing app path')
contents=app/'Contents';mac=contents/'MacOS';res=contents/'Resources'
mac.mkdir(parents=True);res.mkdir();game=res/'game';game.mkdir()
source=REPO/'game'
# Preserve the ready imported resources; exclude editor histories, captures and
# unrelated experimental country datasets. The connected interiors need their source
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
for name in ['inventory.json','city_access.json']:
 shutil.copy2(source/'data/mbs-interior'/name,game/'data/mbs-interior'/name)
geo=game/'data/geography/osm-2026-10-27';geo.mkdir(parents=True)
shutil.copy2(source/'data/geography/osm-2026-10-27/manifest.json',geo/'manifest.json')
launcher=mac/'Orchard Reach'
subprocess.run(['/usr/bin/xcrun','clang','-O2',str(Path(__file__).with_name('launcher.c')),'-o',str(launcher)],check=True)
plist={'CFBundleDevelopmentRegion':'en','CFBundleExecutable':'Orchard Reach','CFBundleIdentifier':'com.ashenone.orchardreach.fidelitymilestone','CFBundleName':'Orchard Reach — Fidelity Milestone','CFBundleDisplayName':'Orchard Reach — Fidelity Milestone','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.2.0','CFBundleVersion':'20261029.1','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True}
with (contents/'Info.plist').open('wb') as f:plistlib.dump(plist,f)
removed_metadata=clean(app)
subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['/usr/bin/codesign','--verify','--strict','--verbose=2',str(app)],check=True)
checkpoint=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
files=[p for p in app.rglob('*') if p.is_file()]
manifest={'built_utc':datetime.now(timezone.utc).isoformat(),'source_checkpoint':checkpoint,'app':str(app),'kind':'local Studio development snapshot using installed Godot4.7.1','engine_path':str(engine),'engine_version_verified_before_task':'4.7.1.stable.official.a13da4feb','self_contained_engine':False,'native_launch_verified':False,'runtime_check_status':'DEFERRED_BY_OWNER_NO_ENGINE_OR_GPU_LAUNCH','private_build_only':True,'removed_packaging_metadata':removed_metadata,'source_file_sha256':{str(p.relative_to(game)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (game/'src').rglob('*.gd')},'file_count':len(files),'logical_bytes':sum(p.stat().st_size for p in files),'included_interior_spaces':['public hotel lobby','reconstructed guest-floor layout','Tower2Level5 spa layout'],'unfinished':['complete hotel and resort interiors','all1844source-catalogue keys physically allocated/furnished','full source-coordinate city integration','final native/rendered acceptance']}
(out/'BUILD_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
readme='''# Orchard Reach — MBS Connected candidate

When you are ready to play after the GPU is free, open **Orchard Reach — MBS Connected.app** on this Mac Studio. This is a private development snapshot using the installed Godot4.7.1 runtime, not a portable/notarized release. It runs copied game content.

Start or continue the normal city game. Drive over the Bayfront bridge and along Bayfront Avenue to Marina Bay Sands. Park near the landward hotel frontage, get out, and find the **HOTEL LOBBY** doorway below the southern tower (Tower 1). Walk into the entrance or press E at the doorway. The game loads the existing lobby as an interior region while retaining the same city, player, parked vehicles and mission objects. There is no preview option in the title menu.

Inside the lobby, the hotel lift doors lead to a furnished guest floor and the Level5 spa. The guest-floor/spa lift returns to the lobby. Walk back through the lobby entrance, or use its Exit interaction, to return outside. These are in-game doorway/lift transitions, not a claim that every room is continuously modelled inside the exterior shell.

Normal controls remain: WASD move, mouse look, Shift run, Space jump, E interact, Esc pause/settings. Saving during a completed hotel visit records the selected interior plus a valid exterior recovery position. Loading resumes at that interior's landing; room-door state and exact within-room position are not persisted. Your parked car stays in the retained city for the visit; this does not add vehicle-position persistence across application restarts.

All game/engine/GPU launches are deferred by the owner. Grammar, geometric configuration, static source-contract, copy and signing checks are not native playtest evidence. Entrance approach, door traversal, save/load, death recovery, lighting, animations and performance still require a later native test. No automatic launch or test is scheduled.

The full source-accurate city and complete hotel/resort remain unfinished. This candidate connects the existing selected reconstructed interiors to city gameplay. They are not certified as-built plans.'''
(out/'START_HERE.md').write_text(readme)
print(json.dumps({'app':str(app),'file_count':manifest['file_count'],'logical_bytes':manifest['logical_bytes'],'native_launch_verified':False}))
