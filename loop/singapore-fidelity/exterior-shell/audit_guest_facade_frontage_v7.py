"""Do not mistake an interior packed cell for a view-bearing hotel room.
Reports candidate real source-facade contact at window height; no fake window
or as-built positioning is inferred from a label or a room-area pass.
"""
from pathlib import Path
import math,json,hashlib,collections
import plan_source_floors as source
import annex_luxury_type_areas_v3 as annex
HERE=Path(__file__).resolve().parent

def frontage(poly,edge,tolerance=.45):
 a,b=edge;dx=b[0]-a[0];dz=b[1]-a[1];length=math.hypot(dx,dz)
 if length<1e-8:return []
 ux,uz=dx/length,dz/length;out=[]
 for p,q in zip(poly,poly[1:]+poly[:1]):
  vx=q[0]-p[0];vz=q[1]-p[1];l=math.hypot(vx,vz)
  if l<1e-8 or abs((vx*ux+vz*uz)/l)<math.cos(math.radians(5)):continue
  projections=[(point[0]-a[0])*ux+(point[1]-a[1])*uz for point in [p,q]];lo=max(0,min(projections));hi=min(length,max(projections))
  if hi-lo<.10:continue
  distances=[abs((point[0]-a[0])*uz-(point[1]-a[1])*ux) for point in [p,q]]
  if max(distances)<=tolerance:out.append([lo,hi])
 return out

def union_length(intervals):
 total=0;end=-1e30
 for lo,hi in sorted(intervals):total+=max(0,hi-max(lo,end));end=max(end,hi)
 return total

def audit(doc):
 rows=[];missing=[]
 for floor in doc['floors'].values():
  exterior=source.profile(floor['tower'],floor['elevation_m']+1.5)
  for room in floor['rooms']:
   edges=[];length=0
   for i,(a,b) in enumerate(zip(exterior,exterior[1:]+exterior[:1])):
    intervals=[span for p in annex.patches(room) for span in frontage(p,(a,b))];value=union_length(intervals)
    if value>0:edges.append({'source_edge':i,'candidate_window_frontage_m':value,'intervals_m':intervals});length+=value
   ok=length>=2.4
   row={'room_id':room['id'],'floor_id':floor['floor_id'],'kind':room['unit']['kind'],'bedrooms':room['unit']['bedrooms'],'candidate_real_facade_frontage_m':length,'construction_reveal_tolerance_m':.45,'source_edges':edges,'minimum_unit_view_frontage_candidate':ok,'actual_window_opening_furnishing_view_or_native_verified':False};rows.append(row)
   if not ok:missing.append(row)
 return {'schema':'mbs_guest_source_facade_frontage_audit_v7','rooms':len(rows),'minimum_frontage_candidate_passed':len(rows)-len(missing),'missing_real_frontage':len(missing),'missing_by_type':dict(collections.Counter(r['kind'] for r in missing)),'missing_rooms':missing,'all_rooms':rows,'scope':'Actual source-envelope segments at floor+1.5m, parallel room-patch edges within0.45m construction reveal and at least2.4m aggregate unit frontage. Candidate geometry only; bedroom-specific views, real glazed apertures and rendered sightlines still unverified. Windowless rooms cannot be accepted by their area checks.'}

if __name__=='__main__':
 p=HERE/'SOURCE_FLOOR_LUXURY_CANDIDATE_V5.json';doc=json.loads(p.read_text());r=audit(doc);r['candidate_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();(HERE/'LUXURY_V7_FACADE_AUDIT.json').write_text(json.dumps(r,indent=2)+'\n');print({k:r[k] for k in ['rooms','minimum_frontage_candidate_passed','missing_real_frontage','missing_by_type']})
