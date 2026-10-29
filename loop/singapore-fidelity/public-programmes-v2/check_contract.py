"""Read-only closure verification; no engine or physical acceptance claim."""
from pathlib import Path
import json,hashlib,collections
from shapely.geometry import shape
P=Path(__file__).resolve().parent; ROOT=P.parents[2]
checks=[]
def check(name,condition):checks.append({'name':name,'passed':bool(condition)})
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def stable(v):return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':')).encode()).hexdigest()
b=json.loads((P/'SOURCE_BUILDING_BINDINGS.json').read_text());c=json.loads((P/'PUBLIC_PROGRAMME_CONTRACT_V2.json').read_text());r=json.loads((P/'RELATION_MEMBER_EVIDENCE.json').read_text())
tile=json.loads((ROOT/'game/data/geography/osm-2026-10-27/0_-1.json').read_text());fs={x['id']:x for x in tile['features']}
check('registry_hash_exact',sha(ROOT/c['registry_input']['path'])==c['registry_input']['sha256'])
check('binding_artifact_hash_exact',sha(P/c['source_binding_artifact']['path'])==c['source_binding_artifact']['sha256'])
check('four_registry_floor_ids_only',{x['floor_id'] for x in c['levels']}=={'EXPO-L3','MUSEUM-B2','MUSEUM-L4','MUSEUM-B1'})
check('all_legacy_registry_floors_preserved',c['registry_input']['retained_legacy_floor_count']==216)
check('MuseumL4_preserved_as_new',c['registry_input']['new_documented_level_ids']==['MUSEUM-L4'])
keys=[]
for building in b['buildings']:
 rel=next(x for x in r['relations'] if x['building_key']==building['building_key'])
 check(building['building_key']+'_all_relation_members_present',{x['source_id'] for x in building['parts']}=={x['source_id'] for x in rel['members']})
 check(building['building_key']+'_exact_collision_replacement_set',set(building['generic_city_replacement_feature_keys'])=={x['feature_key'] for x in building['parts']})
 for f in building['parts']:
  keys.append(f['feature_key']);original=fs[f['source_id']];g=shape(f['geometry_world_xz'])
  check(f['source_id']+'_exact_frozen_polygon',f['geometry_world_xz']==original['geometry'] and stable(original)==f['source_record_sha256'])
  check(f['source_id']+'_valid_metric_source_polygon',g.is_valid and not g.is_empty and g.area>0)
  check(f['source_id']+'_not_promoted_to_slab',f['geometry_role']=='outline_or_building_part_NOT_floor_slab')
check('82_unique_members',len(keys)==82 and len(set(keys))==82)
for f in c['levels']:
 check(f['floor_id']+'_not_claimed_native',not f['native_build_ready'] and f['world_slab_polygon'] is None)
 check(f['floor_id']+'_no_rectangle_fallback',f['do_not_spawn_old_rectangle_fallback'])
 ids=[z['id'] for z in f['zones']];check(f['floor_id']+'_all_zone_ids_unique',len(ids)==len(set(ids)))
 counts=collections.Counter(z['group'] for z in f['zones'])
 for group,n in c['required_programme_groups'].get(f['floor_id'],{}).items():check(f['floor_id']+'_'+group+'_count',counts[group]==n)
 for z in f['zones']:
  check(z['id']+'_source_and_programmes',bool(z['source_url']) and bool(z['required_programmes']))
  check(z['id']+'_unknown_position_honest',z['world_polygon'] is None and not z['world_position_verified'])
check('B1_unknown_retained',c['levels'][-1]['zones'][0]['source_status']=='CURRENT_2026_PROGRAMME_UNRESOLVED')
check('no_hotel_mutation',not c['hotel_coordination']['existing_guest_inventory_mutated'])
failed=[x for x in checks if not x['passed']]
report={'schema':'public_programme_cpu_closure_v2','checks':len(checks),'failed':len(failed),'failures':failed,'positive_contract':'82 exact frozen source members, four registry levels and31 programme/support requirements retained.','physical_geometry_or_native_acceptance':False,'checks_detail':checks}
(P/'CPU_CLOSURE_CHECK.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='checks_detail'}));raise SystemExit(bool(failed))
