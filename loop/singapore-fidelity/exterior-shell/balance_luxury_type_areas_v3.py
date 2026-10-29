"""Close published type-average deficits with contiguous bounded larger variants.

The operator publishes averages, not identical per-room sizes. All individual
reconstructions keep their full programme. Each enlarged Signature/Paiza unit is
capped at1.5x the published type average; no target or room count is reduced.
"""
from pathlib import Path
import json,copy,hashlib
import audit_core_layout as g
import expand_luxury_rooms_v2 as growth
HERE=Path(__file__).resolve().parent

def balance(doc):
 added=[]
 for kind in ['signature_suite','paiza_suite']:
  rooms=[(f,r) for f in doc['floors'].values() for r in f['rooms'] if r['unit']['kind']==kind];target=growth.TARGETS[kind]['target_area_m2'];deficit=target*len(rooms)-sum(growth.area(r) for f,r in rooms)
  for f,r in sorted(rooms,key=lambda fr:(-growth.area(fr[1]),fr[1]['id'])):
   if deficit<=.01:break
   for _ in range(4):
    allowance=min(deficit,target*1.5-growth.area(r))
    if allowance<=.01:break
    b=g.axis_bounds(r['footprint_own_xz']);options=[]
    for side in range(4):
     edge=b[3]-b[1] if side in [0,2] else b[2]-b[0];lo=0.;hi=min(35,allowance/edge)
     for step in range(24):
      d=(lo+hi)/2;q=b[:];q[side]+=d*(-1 if side<2 else 1)
      if growth.clear(g.rectangle(*q),f,r):lo=d
      else:hi=d
     if lo>=.10:options.append((lo*edge,side,lo))
    if not options:break
    gain,side,d=max(options);q=b[:];q[side]+=d*(-1 if side<2 else 1)
    if side==0:annex=g.rectangle(q[0],b[1],b[0],b[3]);shared=[[b[0],b[1]],[b[0],b[3]]]
    elif side==2:annex=g.rectangle(b[2],b[1],q[2],b[3]);shared=[[b[2],b[1]],[b[2],b[3]]]
    elif side==1:annex=g.rectangle(b[0],q[1],b[2],b[1]);shared=[[b[0],b[1]],[b[2],b[1]]]
    else:annex=g.rectangle(b[0],b[3],b[2],q[3]);shared=[[b[0],b[3]],[b[2],b[3]]]
    r['footprint_own_xz']=g.rectangle(*q);r['contiguous_expansions'].append({'polygon':annex,'shared_existing_wall_segment':shared,'area_m2':gain,'program':'larger_type_variant_living_wardrobe_annex','furnishing_scale':1.0,'internal_connection_native_tested':False,'factory_must_open_internal_partition_and_supply_real_furnishing':True,'type_average_balancing_not_asbuilt_size':True});deficit-=gain;added.append({'room_id':r['id'],'kind':kind,'added_m2':gain})
    r['reserved_area_m2']=growth.area(r);r['remaining_area_deficit_m2']=max(0,target-growth.area(r))
 stats={}
 for kind,ref in growth.TARGETS.items():
  rooms=[r for f in doc['floors'].values() for r in f['rooms'] if r['unit']['kind']==kind];areas=[growth.area(r) for r in rooms];total=sum(areas)
  stats[kind]={'count':len(rooms),'published_average_target_m2':ref['target_area_m2'],'reserved_average_m2':total/len(rooms),'reserved_total_m2':total,'target_total_m2':ref['target_area_m2']*len(rooms),'minimum_reserved_m2':min(areas),'maximum_reserved_m2':max(areas),'remaining_aggregate_deficit_m2':max(0,ref['target_area_m2']*len(rooms)-total),'url':ref['url']}
 doc['schema']='mbs_source_floor_luxury_average_balanced_v3';doc['category_average_expansion_records']=added;doc['area_progress']={'new_reserved_total_m2':sum(x['reserved_total_m2'] for x in stats.values()),'type_statistics':stats,'all_category_targets_met':all(x['remaining_aggregate_deficit_m2']<=.01 for x in stats.values()),'individual_areas_are_reconstructed_not_surveyed':True,'actual_internal_annex_openings_or_furniture_verified':False}
 return doc

if __name__=='__main__':
 source=HERE/'SOURCE_FLOOR_LUXURY_EXPANSION_V3.json';doc=json.loads(source.read_text());doc['pre_balance_sha256']=hashlib.sha256(source.read_bytes()).hexdigest();doc=balance(doc);path=HERE/'SOURCE_FLOOR_LUXURY_BALANCED_V3.json';path.write_text(json.dumps(doc,indent=2)+'\n');print(json.dumps(doc['area_progress'],indent=2))
