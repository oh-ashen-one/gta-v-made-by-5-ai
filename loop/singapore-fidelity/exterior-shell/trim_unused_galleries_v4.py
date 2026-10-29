"""Remove only unused gallery tails, preserving full2.6m routes at every actual
room approach and every corridor/core connection. This is a layout redesign,
not a clearance reduction. Reclaimed space remains unavailable until assigned.
"""
from pathlib import Path
import json,copy,hashlib
import audit_core_layout as g
import plan_source_floors as base
from audit_source_floor_allocation import connected
HERE=Path(__file__).resolve().parent

def trim(doc):
 records=[]
 for f in doc['floors'].values():
  bank=base.BANKS[f['tower']];hall=g.shifted(g.rectangle(-13.75,-3.5,13.75,-.9),bank)
  # Connections are evaluated against the original graph in this pass, so
  # independently trimmed neighbours cannot retract past each other's joint.
  original=copy.deepcopy(f['corridors']);extra=[hall]+([f['bank_connector']] if f['bank_connector'] else [])
  for i,c in enumerate(f['corridors']):
   b=g.axis_bounds(c['polygon']);axis=0 if b[2]-b[0]>=b[3]-b[1] else 1;other=1-axis
   if abs((b[other+2]-b[other])-2.6)>.001:continue
   required=[]
   for room in f['rooms']:
    point=room['approach_own_xz']
    if g.inside(point,c['polygon']):required.extend([point[axis]-1.3,point[axis]+1.3])
   for j,n in enumerate([o['polygon'] for o in original]+extra):
    if j==i:continue
    if not connected(c['polygon'],n):continue
    nb=g.axis_bounds(n);lo=max(b[axis],nb[axis]);hi=min(b[axis+2],nb[axis+2])
    # Maintain a whole2.6m turning region at a T-junction/end connection.
    middle=(lo+hi)*.5;required.extend([min(lo,middle-1.3),max(hi,middle+1.3)])
   if not required:continue
   new=b[:];new[axis]=max(b[axis],min(required));new[axis+2]=min(b[axis+2],max(required))
   if new[axis+2]-new[axis]<2.6-.001:continue
   oldarea=(b[2]-b[0])*(b[3]-b[1]);newarea=(new[2]-new[0])*(new[3]-new[1])
   if oldarea-newarea>.05:
    c['original_untrimmed_polygon']=c['polygon'];c['polygon']=g.rectangle(*new);c['trim_policy']='Full2.6m width and every existing door/core/galley joint retained; remove unused length only';records.append({'floor_id':f['floor_id'],'corridor_id':c['id'],'old_polygon':g.rectangle(*b),'new_polygon':c['polygon'],'released_planning_area_m2':oldarea-newarea})
 doc['schema']='mbs_source_luxury_gallery_redesign_v4';doc['gallery_tail_reclamation']=records;doc['gallery_tail_total_reclaimed_m2']=sum(r['released_planning_area_m2'] for r in records);return doc

if __name__=='__main__':
 p=HERE/'SOURCE_FLOOR_LUXURY_REALLOCATED_V3.json';d=json.loads(p.read_text());d['before_gallery_redesign_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();d=trim(d);o=HERE/'SOURCE_FLOOR_LUXURY_GALLERIES_V4.json';o.write_text(json.dumps(d,indent=2)+'\n');print('corridor tails',len(d['gallery_tail_reclamation']),'released',d['gallery_tail_total_reclaimed_m2'])
