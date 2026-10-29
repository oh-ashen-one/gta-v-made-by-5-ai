"""Type and audit every current Premier recipe without mutating source allocation."""
from pathlib import Path
import json,hashlib,datetime
import premier_fitout_v3 as fit
HERE=Path(__file__).resolve().parent

def compile_for(source):
 doc=json.loads(source.read_text());recipes={};rooms={};failures=[]
 for floor in doc['floors'].values():
  for room in floor['rooms']:
   if room['unit']['kind']!='premier':continue
   p=room['profile'];key=json.dumps([p['frontage_m'],p['depth_m'],room['unit']['bed_variant']],separators=(',',':'));identity=hashlib.sha256(key.encode()).hexdigest()[:20]
   if identity not in recipes:
    contract=fit.build(p['frontage_m'],p['depth_m'],room['unit']['bed_variant']);proof=fit.audit(contract);recipes[identity]={'contract':contract,'static_capsule_audit':proof,'room_ids':[]}
   recipes[identity]['room_ids'].append(room['id']);rooms[room['id']]=identity
   if not recipes[identity]['static_capsule_audit']['passed']:failures.append({'room_id':room['id'],'recipe_id':identity,'failures':recipes[identity]['static_capsule_audit']['failures']})
 return {'schema':'mbs_premier_typed_fitout_collection_v3','recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'candidate_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'planner_sha256':hashlib.sha256(Path(fit.__file__).read_bytes()).hexdigest(),'room_count':len(rooms),'unique_recipes':len(recipes),'failed_room_count':len(failures),'failures':failures,'rooms':rooms,'recipes':recipes,'native_door_mesh_or_traversal_verified':False}

if __name__=='__main__':
 r=compile_for(HERE/'SOURCE_FLOOR_LUXURY_REALLOCATED_V3.json');(HERE/'PREMIER_TYPED_FITOUT_COLLECTION_V3.json').write_text(json.dumps(r,indent=2)+'\n');print('rooms',r['room_count'],'recipes',r['unique_recipes'],'failed',r['failed_room_count']);print(r['failures'][:20]);raise SystemExit(bool(r['failed_room_count']))
