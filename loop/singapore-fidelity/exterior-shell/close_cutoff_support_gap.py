"""Close the measured150mm access-floor gap in the frozen partial allocation.
No unit, category, area, core pose or optimizer assignment changes.
"""
from pathlib import Path
import copy,json,hashlib
HERE=Path(__file__).resolve().parent

def repair(doc):
 fixes=[]
 for floor in doc['floors'].values():
  rooms={r['id']:r for r in floor['rooms']};spur_rooms=set()
  for corridor in floor['corridors']:
   if not corridor['id'].endswith('-actual-access-spur'):continue
   id=corridor['id'].removesuffix('-actual-access-spur');room=rooms[id];v=room['into_room_own_axis'];before=copy.deepcopy(corridor['polygon'])
   # Last two corners are the original gallery end, not the room end.
   for i in [2,3]:corridor['polygon'][i]=[corridor['polygon'][i][j]-v[j]*.20 for j in range(2)]
   corridor['support_gap_repair_m']=.20;spur_rooms.add(id);fixes.append({'floor_id':floor['floor_id'],'room_id':id,'kind':'extend_existing_spur_to_actual_hall','before':before,'after':corridor['polygon']})
  for id,room in rooms.items():
   if id in spur_rooms:continue
   p=room['threshold_own_xz'];u=room['frontage_own_axis'];v=room['into_room_own_axis'];outside=[p[j]-v[j]*.20 for j in range(2)];poly=[[p[j]+u[j]*s*1.3 for j in range(2)] for s in [-1,1]]+[[outside[j]+u[j]*s*1.3 for j in range(2)] for s in [1,-1]]
   floor['corridors'].append({'id':id+'-explicit-threshold-floor-support','polygon':poly,'clear_width_m':2.6,'role':'actual_small_floor_connection_not_teleport_or_clearance_override'});fixes.append({'floor_id':floor['floor_id'],'room_id':id,'kind':'explicit_threshold_support','after':poly})
 doc['schema']='mbs_owner_cutoff_partial_allocation_with_connected_support';doc['support_gap_corrections']=fixes;doc['no_unit_or_area_reallocation']=True;return doc

if __name__=='__main__':
 source=HERE/'CATALOGUE_FRONTAGE_EFFICIENT_PROTOTYPE_V17.json';d=json.loads(source.read_text());d['before_support_fix_sha256']=hashlib.sha256(source.read_bytes()).hexdigest();d=repair(d);p=HERE/'OWNER_CUTOFF_PARTIAL_ALLOCATION_SUPPORT_FIXED.json';p.write_text(json.dumps(d,indent=2)+'\n');print('support fixes',len(d['support_gap_corrections']),'assigned',d['assigned'],'unresolved',len(d['unplaced_units']))
