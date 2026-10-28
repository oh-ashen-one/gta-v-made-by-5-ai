#!/usr/bin/env python3
"""Independent static arithmetic of current records; not a Godot runtime pass."""
import hashlib,json,math,re
from datetime import datetime,timezone
from pathlib import Path
root=Path(__file__).resolve().parents[3]
code=(root/'game/src/world/mbs_interior/program_floor.gd').read_text()
inventory=json.loads((root/'game/data/mbs-interior/inventory.json').read_text())
recipes=json.loads(re.search(r'const RECIPES := (\{.*?\})\n',code,re.S)[1])
cores=json.loads(re.search(r'const CORE_PROGRAMS := (\[.*?\])',code,re.S)[1])
# Read only fixed shape declarations; dynamic pool dimensions are handled below.
sizes={}
section=code.split('static func _object_size',1)[1].split('func build',1)[0]
for keys,args in re.findall(r'((?:"[^"]+"(?:,|:|\s))+?) return Vector3\(([^)]+)\)',section):
 for key in re.findall(r'"([^"]+)"',keys): sizes[key]=tuple(float(n.strip()) for n in args.split(','))
kind_recipes={}
section=code.split('static func _recipe_layout',1)[1].split('var u0 :=',1)[0]
for keys,values in re.findall(r'((?:"[^"]+"(?:,|:|\s))+?) kinds.assign\((\[[^\]]+\])\)',section):
 for key in re.findall(r'"([^"]+)"',keys): kind_recipes[key]=json.loads(values)
extras={'back_of_house_parking_loading':['parking','loading_transfer','bulk_stores','plant_service'],'coach_entry':['coach_waiting','luggage_staging','vehicle_loading','ticketing'],'retail_galleria':[],'expo_public_program':['exhibition_hall','meeting_rooms','pre_function','service_store'],'fitness_centre':['gym_floor','exercise_studio','changing','reception'],'casino_gaming':['gaming_floor','cashier','bar_lounge','VIP_lounge'],'casino_public_program':['restaurants','VIP_lounge','kitchen','reception'],'theatre_public_program':['auditorium','stage_backstage','foyer_ticketing','concessions'],'museum_public_program':['exhibition_gallery','interactive_gallery','learning_studio','ticketing']}
profiles={'SHOPPES':(140,76),'EXPO':(128,90),'CASINO':(100,70),'THEATRE':(92,60),'MUSEUM':(100,70)}
records=[r for r in inventory['hotel_floors'] if r['factory']=='program_module']+inventory['resort_program_floors']
rows=[]
for record in records:
 g=record.get('geometry')
 if g is None:
  length,cross=profiles[record['building']]
  g={'length_m':length,'cross_m':cross,'core_bay_m':6.2,'corridor_width_m':3.2,'void_min_z_m':0,'void_max_z_m':0}
 spaces=record.get('program_spaces')
 if spaces is None:
  names=list(record['rooms_required'])
  for name in extras[record['program']]:
   if name not in names:names.append(name)
  spaces=[{'id':record['id']+'-'+name,'program':name} for name in names]
 assert len(spaces)<=24
 assert len({r['id'] for r in spaces})==len(spaces)
 cells=[dict(s,recipe=recipes[s['program']]) for s in spaces if s['program'] not in cores]
 objects=0; minimum_depth=10000; minimum_frontage=10000
 for parity,side in [(0,-1),(1,1)]:
  selected=cells[parity::2]
  total_weight=sum(1.5 if c['recipe'] in ['pool','auditorium'] else 1 for c in selected)
  depth=abs(side*g['cross_m']/2-g['void_min_z_m' if side<0 else 'void_max_z_m'])-g['corridor_width_m']
  assert depth>=7,(record['id'],depth)
  minimum_depth=min(minimum_depth,depth)
  for cell in selected:
   frontage=(g['length_m']-2*g['core_bay_m'])*(1.5 if cell['recipe'] in ['pool','auditorium'] else 1)/total_weight
   minimum_frontage=min(minimum_frontage,frontage)
   assert frontage>=7,(record['id'],cell['program'],frontage)
   kinds=kind_recipes[cell['recipe']]
   width,deep=frontage-2.6,depth-4.5
   shapes=[sizes[k] if k!='pool' else (width-.2,1.1,min(7,deep-.2)) for k in kinds]
   assert all(min(s)>0 for s in shapes),(record['id'],cell['program'])
   max_width,max_depth=max(s[0] for s in shapes),max(s[2] for s in shapes)
   assert max_width<=width and max_depth<=deep,(record['id'],cell['program'],(width,deep),(max_width,max_depth))
   columns=max(1,min(4,math.floor((width+.85)/(max_width+.85))))
   nrows=max(1,min(4,math.floor((deep+.95)/(max_depth+.95))))
   count=1 if cell['recipe']=='pool' else min(max(len(kinds),math.floor(width*deep/18)),columns*nrows)
   assert count>0
   for i in range(count):
    sx,sy,sz=shapes[i%len(shapes)]
    u=-frontage/2+2.2+(i%columns+.5)*width/columns
    v=2.7+(i//columns+.5)*deep/nrows
    assert u-sx/2>=-frontage/2+2.2-1e-5
    assert u+sx/2<=frontage/2-.4+1e-5
    assert v-sz/2>=2.7-1e-5 and v+sz/2<=depth-1.8+1e-5
   objects+=count
 assert objects<=320,(record['id'],objects)
 rows.append({'id':record['id'],'program_spaces':len(spaces),'furnished_rooms':len(cells),'objects':objects,'minimum_room_depth_m':minimum_depth,'minimum_frontage_m':minimum_frontage,'all_private_layouts_reconstructed':True,'engine_runtime_tested':False})
result={'created_utc':datetime.now(timezone.utc).isoformat(),'method':'STATIC_PYTHON_SOURCE_AND_INVENTORY_ARITHMETIC_NOT_GODOT_QA','source_sha256':hashlib.sha256(code.encode()).hexdigest(),'inventory_sha256':hashlib.sha256((root/'game/data/mbs-interior/inventory.json').read_bytes()).hexdigest(),'records':rows,'count':len(rows),'furnished_program_rooms':sum(r['furnished_rooms'] for r in rows),'objects':sum(r['objects'] for r in rows),'engine_tests_run':False,'whole_building_verified':False}
Path(__file__).with_name('STATIC_PLAN_COVERAGE.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='records'}))
