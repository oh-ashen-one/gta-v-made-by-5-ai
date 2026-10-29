"""Bounded CPU integer allocation of the corrected catalogue to true perimeter
rows. Each active category keeps its source area and explicit tower restriction.
No game adoption; current geometry fixture awaits public/mixed-use floor review.
"""
from pathlib import Path
import json,math,time,hashlib,collections
import numpy as np
from scipy.optimize import milp,LinearConstraint,Bounds
from scipy.sparse import coo_array
import allocate_catalogue_perimeter_v12 as geo
import plan_source_floors as base
HERE=Path(__file__).resolve().parent

def dimensions(cat,maxdepth):
 area=cat['published_average_area_m2'];beds=cat['advertised_bedrooms'] or 1
 if not cat['is_suite']:
  minimum=5.5 if cat['id']=='sands_studio' else 4.5 if cat['id']=='paiza_club' else 3.75
 else:
  bw=cat.get('published_mattress_width_m',2.0)
  if cat.get('published_bed_widths_m'):bw=cat['published_bed_widths_m'].get('super_king',bw)
  if cat.get('published_bed_width_options_m'):bw=max(cat['published_bed_width_options_m']['super_king'])
  minimum=beds*max(3.75,bw+.56+.90+.15)+(6.4 if cat['id'].startswith('chairman') else 3.2)+(2.4 if cat['separate_kids_room'] else 0)
 width=max(minimum,area/maxdepth);depth=area/width
 if depth<3.75 or cat['is_suite'] and depth<6.2:return None
 return {'width':width,'depth':depth,'area':area,'façade_zone_minimum_m':minimum,'full_size_fitout_and_native_entry_still_required':True}

def solve():
 started=time.monotonic();source=HERE/'OPERATOR_CATALOGUE_INVENTORY_PROPOSAL_V11.json';proposal=json.loads(source.read_text());cats=proposal['catalogue'];records=[r for r in base.INV['hotel_floors'] if r['factory']=='guest_floor_v1'];floors={r['id']:geo.floor_fixture(r,r['id'] in ['T1-L54','T2-L54']) for r in records};bins=[{'floor_id':f['floor_id'],'tower':f['tower'],'row':row,'level':int(f['floor_id'].split('-L')[-1])} for f in floors.values() for row in f['room_rows']];floorids=list(floors);vars=[]
 for ci,c in enumerate(cats):
  for bi,b in enumerate(bins):
   if c['tower_restriction_from_current_category_page'] and b['tower'] not in c['tower_restriction_from_current_category_page']:continue
   if c['paiza_royal'] and b['level']<48:continue # Explicit reconstructed high-level preference, not operator exact floor claim.
   if c['collection']=='Paiza' and b['level']<35:continue # Broad provisional upper zone; review may replace it.
   d=dimensions(c,b['row']['depth_m'])
   if d and d['width']<=b['row']['available_m']+1e-8:vars.append({'cat':ci,'bin':bi,'dims':d})
 m=len(cats)+len(bins)+len(floorids);lower=np.full(m,-np.inf);upper=np.full(m,np.inf);rows=[];cols=[];data=[]
 for i,c in enumerate(cats):lower[i]=upper[i]=c['reconstructed_count']
 for i,b in enumerate(bins):upper[len(cats)+i]=b['row']['available_m']
 for i,fid in enumerate(floorids):lower[len(cats)+len(bins)+i]=1
 cost=[];bounds=[]
 for j,v in enumerate(vars):
  c=cats[v['cat']];b=bins[v['bin']];rows.extend([v['cat'],len(cats)+v['bin'],len(cats)+len(bins)+floorids.index(b['floor_id'])]);cols.extend([j]*3);data.extend([1,v['dims']['width'],1]);bounds.append(math.floor(b['row']['available_m']/v['dims']['width']+1e-8))
  # Prefer less excessive corridor depth and Paiza/Royal upper positions,
  # without changing any category count, required area or true facade.
  cost.append((b['row']['depth_m']-v['dims']['depth'])*.001 + (55-b['level'])*(.01 if c['collection']=='Paiza' else .00001))
 A=coo_array((np.asarray(data,dtype=float),(np.asarray(rows,dtype=np.int32),np.asarray(cols,dtype=np.int32))),shape=(m,len(vars))).tocsc();r=milp(np.zeros(len(cost)),integrality=np.ones(len(vars)),bounds=Bounds(np.zeros(len(vars)),np.asarray(bounds)),constraints=LinearConstraint(A,lower,upper),options={'time_limit':45,'node_limit':100000,'presolve':True,'mip_rel_gap':.001});verified=False;selected=[]
 if r.x is not None:
  rounded=np.rint(r.x);observed=A@rounded;verified=bool(np.max(np.abs(r.x-rounded))<1e-5 and np.all(observed>=lower-1e-6) and np.all(observed<=upper+1e-6));selected=[dict(v,count=int(rounded[i])) for i,v in enumerate(vars) if rounded[i]>.5]
 return {'schema':'mbs_catalogue_perimeter_feasibility_v15','status':int(r.status),'message':r.message,'incumbent_independently_satisfies_constraints':verified,'proposal_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'catalogue':cats,'source_geometry_fixture_floors':floors,'bins':bins,'selected':selected,'integer_variables':len(vars),'elapsed_cpu_seconds':time.monotonic()-started,'floor_registry_status':'LEGACY_GEOMETRY_FIXTURE_PENDING_CURRENT_PUBLIC_MIXED_USE_REVIEW','native_furnishing_window_or_game_adoption':False}

if __name__=='__main__':
 r=solve();(HERE/'CATALOGUE_PERIMETER_FEASIBILITY_V15.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k not in ['catalogue','source_geometry_fixture_floors','bins','selected']},indent=2))
