"""Bounded HiGHS CPU capacity/assignment solver for real perimeter strips.
No source envelope, room ID, object scale, corridor width or target is relaxed.
"""
from pathlib import Path
import json,math,time,hashlib,collections,copy
import numpy as np
from scipy.optimize import milp,LinearConstraint,Bounds
from scipy.sparse import coo_array
import perimeter_floor_plan_v7 as perimeter
import plan_source_floors as base
import plan_source_floors_luxury_v3 as legacy
HERE=Path(__file__).resolve().parent

def width_profile(kind,depth):
 if kind=='suite':return max(140.0/depth,6.95) if depth>=8.0 else None
 if kind=='queen':return max(45.0/depth,5.2) if depth>=7.2 else None
 if depth>=6.2:return max(45.0/depth,3.75)
 if depth>=3.75:return 45.0/depth # Rigidly rotated full-size long/narrow King fitout, separate entry contract needed.
 return None

def prepare():
 records=[r for r in base.INV['hotel_floors'] if r['factory']=='guest_floor_v1'];floors={r['id']:perimeter.floor(r) for r in records};units=[u for f in records for u in f['units']];large=[u for u in units if u['is_suite'] and u['bedrooms']>1];old=legacy.wanted_profile;legacy.wanted_profile=perimeter.profile;unplaced=[]
 try:
  for u in sorted(large,key=lambda u:(-legacy.TARGETS[u['kind']]['target_area_m2'],u['id'])):
   if legacy.place(floors[u['floor_id']],u):continue
   own=u['floor_id'].split('-')[0];elev=next(f['elevation_m'] for f in records if f['id']==u['floor_id'])
   choices=sorted(floors.values(),key=lambda f:(f['tower']!=own,abs(f['elevation_m']-elev),f['floor_id']))
   if not any(legacy.place(f,u) for f in choices):unplaced.append(u)
 finally:legacy.wanted_profile=old
 bins=[]
 for f in floors.values():
  for row in f['room_rows']:
   gap=.15 if row['rooms'] else 0.0;start=row['cursor']+gap;length=row['available_m']-gap
   if length>0:bins.append({'floor_id':f['floor_id'],'row_id':row['id'],'start':start,'length':length,'depth':row['depth_m'],'axis':row['axis'],'already_large_count':len(row['rooms'])})
 return floors,units,large,unplaced,bins

def solve():
 start=time.monotonic();floors,units,large,unplaced,bins=prepare()
 if unplaced:return {'status':'large_units_unplaced','unplaced':unplaced,'actual_complete_allocation':False}
 small=[u for u in units if u not in large];counts={'suite':sum(u['is_suite'] for u in small),'queen':sum(not u['is_suite'] and u['bed_variant']=='twin_queen' for u in small),'king':sum(not u['is_suite'] and u['bed_variant']=='king' for u in small)}
 patterns=[]
 for index,b in enumerate(bins):
  widths={k:width_profile(k,b['depth']) for k in ['suite','queen','king']};L=b['length'];patterns.append({'bin':index,'counts':[0,0,0],'widths':widths,'used':0})
  ms=int(L/widths['suite']) if widths['suite'] else 0;mq=int(L/widths['queen']) if widths['queen'] else 0
  for s in range(ms+1):
   for q in range(mq+1):
    n=s+q;used=s*(widths['suite'] or 0)+q*(widths['queen'] or 0)
    if used>L+1e-8:continue
    rest=L-used;k=max(0,int((rest+1e-8)/widths['king'])) if widths['king'] else 0
    if not(s+q+k):continue
    total=s*(widths['suite'] or 0)+q*(widths['queen'] or 0)+k*(widths['king'] or 0)
    if total<=L+1e-7:patterns.append({'bin':index,'counts':[s,q,k],'widths':widths,'used':total})
 floor_ids=list(floors);m=len(bins)+3+len(floor_ids);rows=[];cols=[];data=[];lower=np.zeros(m);upper=np.full(m,np.inf);lower[:len(bins)]=1;upper[:len(bins)]=1
 for i,k in enumerate(['suite','queen','king']):lower[len(bins)+i]=counts[k]
 for i,id in enumerate(floor_ids):lower[len(bins)+3+i]=0 if floors[id]['rooms'] else 1
 for j,p in enumerate(patterns):
  i=p['bin'];rows.append(i);cols.append(j);data.append(1)
  for k,value in enumerate(p['counts']):
   if value:rows.append(len(bins)+k);cols.append(j);data.append(value)
  rows.append(len(bins)+3+floor_ids.index(bins[i]['floor_id']));cols.append(j);data.append(sum(p['counts']))
 A=coo_array((np.asarray(data,dtype=float),(np.asarray(rows,dtype=np.int32),np.asarray(cols,dtype=np.int32))),shape=(m,len(patterns))).tocsc()
 c=np.asarray([sum(p['counts'])+max(0,bins[p['bin']]['length']-p['used'])*.0001 for p in patterns])
 result=milp(c,integrality=np.ones(len(patterns)),bounds=Bounds(np.zeros(len(patterns)),np.ones(len(patterns))),constraints=LinearConstraint(A,lower,upper),options={'time_limit':45,'node_limit':100000,'presolve':True,'mip_rel_gap':.00001})
 chosen=[];verified=False;capacities=None
 if result.x is not None:
  rounded=np.rint(result.x);v=A@rounded;verified=bool(np.max(np.abs(result.x-rounded))<1e-5 and np.all(v>=lower-1e-7) and np.all(v<=upper+1e-7));chosen=[patterns[i] for i,x in enumerate(rounded) if x>.5];capacities=[sum(p['counts'][i] for p in chosen) for i in range(3)]
 return {'schema':'mbs_perimeter_pattern_solver_v8','status':int(result.status),'message':result.message,'exact_incumbent_constraints_verified':verified,'required_counts':counts,'capacity_counts':capacities,'large_units_preplaced':len(large),'bins':bins,'pattern_count':len(patterns),'chosen_patterns':chosen,'floor_plans_with_large_units':floors,'elapsed_cpu_seconds':time.monotonic()-start,'actual_complete_allocation':False,'native_furnishing_or_window_verified':False,'solver_is_CPU_optimization_not_GPU_or_local_AI_inference':True}

if __name__=='__main__':
 r=solve();(HERE/'PERIMETER_PATTERN_SOLVER_V8.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k not in ['bins','chosen_patterns','floor_plans_with_large_units']},indent=2))
