"""Coverage/source-schema audit, not a substitute for independent fact critique."""
from pathlib import Path
import json,hashlib,collections
from urllib.parse import urlparse
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]

def audit(proposal):
 old=json.loads((ROOT/'game/data/mbs-interior/inventory.json').read_text());original={u['id']:u for f in old['hotel_floors'] for u in f['units']};checks=0;failures=[]
 def check(name,condition):
  nonlocal checks;checks+=1
  if not condition:failures.append(name)
 active=proposal['active_units'];legacy=proposal['legacy_mapping'];cats={c['id']:c for c in proposal['catalogue']};active_ids=[r['id'] for r in active];legacy_ids=[r['id'] for r in legacy];retired=[r for r in legacy if r['status']=='SUPERSEDED_ROUNDING_PLACEHOLDER']
 check('exact1844 active keys',len(active)==1844 and len(set(active_ids))==1844)
 check('exact775 active suites',sum(r['is_suite'] for r in active)==775)
 check('all1850 legacy IDs retained exactly once',set(legacy_ids)==set(original) and len(legacy_ids)==1850)
 check('six explicit superseded normalization placeholders',len(retired)==6 and all(not r['legacy_record']['is_suite'] for r in retired))
 check('no original record rewritten',all(r['legacy_record']==original[r['id']] for r in legacy))
 check('active plus retired is exact legacy partition',set(active_ids).isdisjoint(r['id'] for r in retired) and set(active_ids)|{r['id'] for r in retired}==set(original))
 counts=collections.Counter(r['catalogue_category_id'] for r in active)
 for id,c in cats.items():
  check(id+' selected count preserved',counts[id]==c['reconstructed_count'] and counts[id]>0)
  check(id+' per-type count explicitly reconstructed',c['count_status']=='RECONSTRUCTED_MIX_NOT_OPERATOR_PER_TYPE_INVENTORY')
  check(id+' primary category URL',urlparse(c['source_url']).hostname=='www.marinabaysands.com' and '/hotel/rooms-suites/' in c['source_url'])
  check(id+' real type area and bedrooms',c['published_average_area_m2']>0 and 1<=c['advertised_bedrooms']<=4)
  check(id+' retains actual required programme',bool(c['required_programs']) and 'sleeping' in c['required_programs'] and 'bath_with_two_person_tub' in c['required_programs'])
 for r in active:
  c=cats[r['catalogue_category_id']]
  check(r['id']+' exact source category binding',r['published_average_area_target_m2']==c['published_average_area_m2'] and r['advertised_bedrooms']==c['advertised_bedrooms'] and r['source_url']==c['source_url'])
  check(r['id']+' named programme not lost',set(c['required_programs'])<=set(r['required_programs']))
  check(r['id']+' no invented asbuilt room position',r['physical_floor_assignment'] is None and not r['physical_room_number_verified'])
  if c['variant']:check(r['id']+' published selected variant',r['selected_variant'] in c['variant'] and r['selected_variant'] in r['required_programs'])
 check('Paiza370 represented separately',sum(r['collection']=='Paiza' for r in active)==370)
 check('Paiza mostly suites',sum(r['collection']=='Paiza' and r['is_suite'] for r in active)==320)
 check('both Chairman bedroom-specific areas',cats['chairman_3b']['published_average_area_m2']==520 and cats['chairman_4b']['published_average_area_m2']==630)
 check('larger Royal residences retained',all(counts.get(k,0)>0 for k in ['harbour','marina','skyline','merlion','straits','horizon','presidential','chairman_3b','chairman_4b']))
 check('current source tower constraints retained',cats['sands_bay']['tower_restriction_from_current_category_page']==['T3'] and cats['sands_premier_1b']['tower_restriction_from_current_category_page']==['T1','T2'] and cats['sands_premier_2b']['tower_restriction_from_current_category_page']==['T3'] and cats['paiza_family']['tower_restriction_from_current_category_page']==['T3'])
 return {'schema':'mbs_catalogue_inventory_coverage_audit_v9','checks':checks,'failed':len(failures),'failures':failures,'active_keys':len(active),'suites':sum(r['is_suite'] for r in active),'legacy_ids_retained':len(legacy),'retired_rounding_placeholders':len(retired),'catalogue_variants':len(cats),'collection_counts':dict(collections.Counter(r['collection'] for r in active)),'required_reference_room_area_m2':sum(r['published_average_area_target_m2'] for r in active),'independent_fact_critique_complete':False,'physical_allocation_or_furnishing_verified':False,'scope':'Exact key/suite/legacy coverage, source-binding schema, explicit reconstruction counts and complete selected programme propagation. Does not independently certify every website claim or any physical room.'}

if __name__=='__main__':
 p=HERE/'OPERATOR_CATALOGUE_INVENTORY_PROPOSAL_V9.json';d=json.loads(p.read_text());r=audit(d);r['proposal_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();(HERE/'CATALOGUE_INVENTORY_COVERAGE_AUDIT_V9.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2));raise SystemExit(bool(r['failed']))
