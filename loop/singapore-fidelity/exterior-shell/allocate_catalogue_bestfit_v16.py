"""Global rather than old-floor-biased perimeter placement; full catalogue
areas/counts and source tower constraints stay unchanged. CPU prototype only.
"""
from pathlib import Path
import json,math,hashlib,time,copy,collections
import allocate_catalogue_perimeter_v12 as geo
import plan_source_floors as base
HERE=Path(__file__).resolve().parent


def profile(unit,cat,maxdepth):
 area=float(unit['published_average_area_target_m2']);beds=unit['advertised_bedrooms'] or 1
 if not unit['is_suite']:
  queen=unit['legacy_record'].get('bed_variant')=='twin_queen' and 'two_queen' in cat.get('bed_options',[])
  minimum=5.5 if cat['id']=='sands_studio' else 4.5 if cat['id']=='paiza_club' else 5.2 if queen else 3.75
 else:
  bed=cat.get('published_mattress_width_m',2.0)
  if cat.get('published_bed_widths_m'):bed=cat['published_bed_widths_m'].get('super_king',bed)
  if cat.get('published_bed_width_options_m'):bed=max(cat['published_bed_width_options_m']['super_king'])
  minimum=beds*max(3.75,bed+.56+.90+.15)+(6.4 if cat['id'].startswith('chairman') else 3.2)+(2.4 if cat['separate_kids_room'] else 0)
 width=max(minimum,area/maxdepth);depth=area/width
 if depth<3.75 or unit['is_suite'] and depth<6.2:return None
 return {'frontage_m':width,'depth_m':depth,'target_area_m2':area,'area_is_published_category_average_not_individual_survey':True,'minimum_source_facing_zones_m':minimum,'full_size_fitout_pending_native_validation':True,'furniture_scale':1.0,'published_category_id':cat['id']}


def allocate():
 start=time.monotonic();p=HERE/'OPERATOR_CATALOGUE_INVENTORY_PROPOSAL_V11.json';doc=json.loads(p.read_text());cats={c['id']:c for c in doc['catalogue']};records=[r for r in base.INV['hotel_floors'] if r['factory']=='guest_floor_v1'];floors={r['id']:geo.floor_fixture(r,r['id'] in ['T1-L54','T2-L54']) for r in records};remaining=[];old=geo.profile;geo.profile=profile
 try:
  # Hard source-zoned and high-level residence groups reserve their valid
  # capacity before flexible ordinary keys; no old invented floor claim.
  units=sorted(doc['active_units'],key=lambda u:(not u['paiza_royal'],not bool(u['allowed_towers_from_current_page']),u['collection']!='Paiza',-u['published_average_area_target_m2'],u['id']))
  for unit in units:
   if time.monotonic()-start>60:raise RuntimeError('Bounded CPU60s allocation budget exceeded')
   cat=cats[unit['catalogue_category_id']];options=[]
   for f in floors.values():
    level=int(f['floor_id'].split('-L')[-1])
    if unit['allowed_towers_from_current_page'] and f['tower'] not in unit['allowed_towers_from_current_page']:continue
    if unit['paiza_royal'] and level<48:continue
    if unit['collection']=='Paiza' and level<35:continue
    for row in f['room_rows']:
     d=profile(unit,cat,row['depth_m'])
     if not d or d['frontage_m']>row['available_m']+1e-8:continue
     residue=row['available_m']-d['frontage_m'];options.append((residue,f['floor_id'],f))
   if not options:remaining.append(unit);continue
   _,_,floor=min(options,key=lambda v:v[:2])
   if not geo.place(floor,unit,cat):raise RuntimeError('Selected actual row changed before placement')
 finally:geo.profile=old
 placed=[r for f in floors.values() for r in f['rooms']]
 return {'schema':'mbs_catalogue_global_bestfit_prototype_v16','proposal_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'adoption_status':'NOT_ADOPTED_PENDING_COMPLETE_SOURCE_GEOMETRY_AND_PROGRAMME_VALIDATION','floor_registry_status':'LEGACY_GEOMETRY_FIXTURE_NOT_OPERATOR_GUEST_FLOOR_SCHEDULE','floors':floors,'active_key_target':1844,'assigned':len(placed),'assigned_suites':sum(r['unit']['is_suite'] for r in placed),'unplaced_units':remaining,'legacy_mapping':doc['legacy_mapping'],'published_area_preserved':all(abs(abs(geo.g.signed_area(r['footprint_own_xz']))-r['profile']['target_area_m2'])<1e-5 for r in placed),'elapsed_cpu_seconds':time.monotonic()-start,'native_or_actual_furniture_verified':False}

if __name__=='__main__':
 d=allocate();p=HERE/'CATALOGUE_GLOBAL_BESTFIT_PROTOTYPE_V16.json';p.write_text(json.dumps(d,indent=2)+'\n');print('assigned',d['assigned'],'suites',d['assigned_suites'],'unplaced',len(d['unplaced_units']),'areas',d['published_area_preserved']);print(collections.Counter(u['catalogue_category_id'] for u in d['unplaced_units']))
