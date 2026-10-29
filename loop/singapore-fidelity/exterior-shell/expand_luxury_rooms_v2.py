"""Grow contiguous real room area into unused source geometry; frozen v1 unchanged.

A partial improvement pass, never a certificate that all category targets fit.
"""
from __future__ import annotations
import json,copy,math,hashlib,collections
from pathlib import Path
import audit_core_layout as g
HERE=Path(__file__).resolve().parent
BASE=HERE/'SOURCE_FLOOR_ALLOCATION_CANDIDATE.json'
TARGETS=json.loads((HERE/'LUXURY_TYPE_REFERENCES.json').read_text())['types']

def area(r):return abs(g.signed_area(r['footprint_own_xz']))
def target(r):return TARGETS[r['unit']['kind']]['target_area_m2']
def shift_room(r,axis,delta):
 for key in ['footprint_own_xz']:
  for p in r[key]:p[axis]+=delta
 for key in ['room_origin_own_xz','threshold_own_xz','approach_own_xz']:r[key][axis]+=delta

def clear(candidate,f,room):
 if not g.contains(f['source_floor_polygon'],candidate) or not g.contains(f['source_ceiling_polygon'],candidate):return False
 obstacles=[f['core_bank_polygon']]+[c['polygon'] for c in f['corridors']]+([f['bank_connector']] if f['bank_connector'] else [])+([f['lower_public_atrium_void']] if f['lower_public_atrium_void'] else [])+[r['footprint_own_xz'] for r in f['rooms'] if r['id']!=room['id']]
 return not any(g.convex_intersection_area(candidate,o)>1e-7 for o in obstacles)

def expand():
 document=json.loads(BASE.read_text());baseline_area=sum(area(r) for f in document['floors'].values() for r in f['rooms']);document['schema']='mbs_source_floor_luxury_expansion_v2';document['frozen_minimum_plan_sha256']=hashlib.sha256(BASE.read_bytes()).hexdigest();document['category_targets']=TARGETS
 for f in document['floors'].values():
  # Put the largest area deficit next to each row's actual unused tail.
  for row in f['room_rows']:
   members=[r for r in f['rooms'] if r['row_id']==row['id']];members.sort(key=lambda r:(max(0,target(r)-area(r)),r['id']))
   cursor=row['span_x'][0];axis=0 if row['axis']=='x' else 1
   for r in members:
    bounds=g.axis_bounds(r['footprint_own_xz']);delta=cursor-bounds[axis];shift_room(r,axis,delta);cursor+=r['profile']['frontage_m']+.15
   row['rooms']=[r['id'] for r in members]
  for r in f['rooms']:
   r['frozen_minimum_footprint_after_row_reorder']=copy.deepcopy(r['footprint_own_xz']);r['luxury_target_area_m2']=target(r);r['contiguous_expansions']=[]
  for r in sorted(f['rooms'],key=lambda r:(-(target(r)-area(r)),r['id'])):
   for iteration in range(4):
    deficit=target(r)-area(r)
    if deficit<=.05:break
    b=g.axis_bounds(r['footprint_own_xz']);options=[]
    for side in range(4):
     edge=(b[3]-b[1]) if side in [0,2] else (b[2]-b[0]);maximum=min(35.0,deficit/edge);lo=0.;hi=maximum
     for _ in range(24):
      mid=(lo+hi)/2;test=b[:];test[side]+=mid*(-1 if side<2 else 1)
      if clear(g.rectangle(*test),f,r):lo=mid
      else:hi=mid
     if lo>=.10:options.append((lo*edge,side,lo))
    if not options:break
    gain,side,distance=max(options);new=b[:];new[side]+=distance*(-1 if side<2 else 1)
    if side==0:annex=g.rectangle(new[0],b[1],b[0],b[3]);shared=[[b[0],b[1]],[b[0],b[3]]]
    elif side==2:annex=g.rectangle(b[2],b[1],new[2],b[3]);shared=[[b[2],b[1]],[b[2],b[3]]]
    elif side==1:annex=g.rectangle(b[0],new[1],b[2],b[1]);shared=[[b[0],b[1]],[b[2],b[1]]]
    else:annex=g.rectangle(b[0],b[3],b[2],new[3]);shared=[[b[0],b[3]],[b[2],b[3]]]
    r['footprint_own_xz']=g.rectangle(*new);r['contiguous_expansions'].append({'polygon':annex,'shared_existing_wall_segment':shared,'area_m2':gain,'program':'living_dining_or_walkin_wardrobe_annex' if distance>=1.6 else 'existing_room_clearance_enlargement','furnishing_scale':1.0,'internal_connection_native_tested':False,'factory_must_open_internal_partition_and_supply_real_furnishing':True})
   r['reserved_area_m2']=area(r);r['remaining_area_deficit_m2']=max(0,target(r)-area(r));r['final_luxury_acceptance']=False
 statistics={}
 for kind,reference in TARGETS.items():
  rooms=[r for f in document['floors'].values() for r in f['rooms'] if r['unit']['kind']==kind]
  statistics[kind]={'count':len(rooms),'published_average_target_m2':reference['target_area_m2'],'reserved_total_m2':sum(area(r) for r in rooms),'reserved_average_m2':sum(area(r) for r in rooms)/len(rooms),'target_total_m2':sum(target(r) for r in rooms),'sum_positive_per_room_deficits_m2':sum(max(0,target(r)-area(r)) for r in rooms),'rooms_reaching_target':sum(area(r)>=target(r)-.05 for r in rooms),'url':reference['url']}
 document['area_progress']={'frozen_minimum_total_m2':baseline_area,'new_reserved_total_m2':sum(s['reserved_total_m2'] for s in statistics.values()),'type_statistics':statistics,'all_category_targets_met':False,'actual_internal_annex_openings_or_furniture_verified':False}
 return document

if __name__=='__main__':
 result=expand();path=HERE/'SOURCE_FLOOR_LUXURY_EXPANSION_V2.json';path.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result['area_progress'],indent=2))
