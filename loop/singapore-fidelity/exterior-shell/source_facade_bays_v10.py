"""Actual source-facing reveal geometry and window descriptors, no fake panes.
Each bay preserves distinct floor/ceiling/standing contours under sloped facades.
It is refused if it crosses another room, core, public corridor or atrium void.
"""
from pathlib import Path
import math,json,hashlib
import plan_source_floors as base
import annex_luxury_type_areas_v3 as room_patches
import audit_core_layout as geom
HERE=Path(__file__).resolve().parent

def cross(a,b):return a[0]*b[1]-a[1]*b[0]
def ray_hit(point,direction,ring):
 best=None
 for i,(a,b) in enumerate(zip(ring,ring[1:]+ring[:1])):
  e=[b[0]-a[0],b[1]-a[1]];delta=[a[0]-point[0],a[1]-point[1]];den=cross(direction,e)
  if abs(den)<1e-12:continue
  t=cross(delta,e)/den;u=cross(delta,direction)/den
  if t>=-1e-6 and -1e-7<=u<=1+1e-7:
   hit={'distance_m':max(0,t),'edge_index':i,'edge_u':max(0,min(1,u)),'point':[point[0]+max(0,t)*direction[0],point[1]+max(0,t)*direction[1]]}
   if best is None or hit['distance_m']<best['distance_m']:best=hit
 return best

def local_point(room,u,v):
 p=room['room_origin_own_xz'];a=room['frontage_own_axis'];b=room['into_room_own_axis'];return [p[i]+a[i]*u+b[i]*v for i in range(2)]

def plan_room(floor,room,maximum_reveal_depth=2.0):
 record=next((r for r in base.INV['hotel_floors'] if r['id']==floor['floor_id']),None)
 if record is None or record['factory']!='guest_floor_v1':return {'room_id':room['id'],'bays':[],'total_source_window_frontage_m':0,'minimum_unit_view_frontage_candidate':False,'rejected_intervals':[{'reason':'This adapter requires an explicit current guest-floor geometry record.'}]}
 clear_height=float(record['geometry']['clear_height_m']);y=floor['elevation_m'];level=base.profile(floor['tower'],y);ceiling=base.profile(floor['tower'],y+clear_height);standing=base.profile(floor['tower'],y+2.0);window=base.profile(floor['tower'],y+1.5);width=room['profile']['frontage_m'];depth=room['profile']['depth_m'];direction=room['into_room_own_axis'];origin=room['room_origin_own_xz'];tangent=room['frontage_own_axis'];splits=[0.,width]
 expected=[local_point(room,0,0),local_point(room,width,0),local_point(room,width,depth),local_point(room,0,depth)]
 actual=room['footprint_own_xz']
 if abs(abs(geom.signed_area(actual))-abs(geom.signed_area(expected)))>.001 or geom.convex_intersection_area(actual,expected)<abs(geom.signed_area(expected))-.001 or room.get('private_annex_patches'):
  return {'room_id':room['id'],'bays':[],'total_source_window_frontage_m':0,'minimum_unit_view_frontage_candidate':False,'rejected_intervals':[{'reason':'Expanded/annex room needs an explicit outer-union boundary adapter; refusing duplicate reveal support.'}]}
 for ring in [level,ceiling,standing,window]:
  for point in ring:
   u=sum((point[i]-origin[i])*tangent[i] for i in range(2))
   if .001<u<width-.001:splits.append(u)
 splits=sorted(set(round(v,9) for v in splits));static=[floor['core_bank_polygon']]+[c['polygon'] for c in floor['corridors']]+([floor['bank_connector']] if floor['bank_connector'] else [])+([floor['lower_public_atrium_void']] if floor['lower_public_atrium_void'] else [])+[p for other in floor['rooms'] if other['id']!=room['id'] for p in room_patches.patches(other)]
 bays=[];reasons=[]
 for i,(u0,u1) in enumerate(zip(splits,splits[1:])):
  if u1-u0<.20:continue
  inside=[local_point(room,u,depth) for u in [u0+.00001,u1-.00001]];hits={};valid=True
  for name,ring in [('floor',level),('ceiling',ceiling),('standing',standing),('window',window)]:
   pair=[ray_hit(p,direction,ring) for p in inside];hits[name]=pair
   if any(p is None or p['distance_m']>maximum_reveal_depth for p in pair):valid=False
  if not valid:reasons.append({'interval':[u0,u1],'reason':'No bounded same-direction source facade; needs full private-layout redesign, not a fake interior window.'});continue
  polygons={name:[inside[0],pair[0]['point'],pair[1]['point'],inside[1]] for name,pair in hits.items()}
  poly=polygons['floor']
  if not geom.contains(level,poly):reasons.append({'interval':[u0,u1],'reason':'Floor reveal exits actual source polygon'});continue
  if any(geom.convex_intersection_area(poly,o)>1e-7 for o in static):reasons.append({'interval':[u0,u1],'reason':'Another room/core/corridor/void occludes facade'});continue
  wh=hits['window'];normal_extent=[max(p['distance_m'] for p in hits[k]) for k in ['floor','standing','ceiling']]
  if wh[0]['edge_index']!=wh[1]['edge_index']:reasons.append({'interval':[u0,u1],'reason':'Window interval crosses an unsplit source edge'});continue
  bays.append({'id':room['id']+'-source-reveal-'+str(i),'room_id':room['id'],'floor_id':floor['floor_id'],'floor_ring_own_xz':poly,'ceiling_ring_own_xz':polygons['ceiling'],'standing_headroom2m_ring_own_xz':polygons['standing'],'relative_floor_y_m':0.0,'relative_ceiling_y_m':clear_height,'source_window':{'source_edge_index':wh[0]['edge_index'],'edge_u0':min(p['edge_u'] for p in wh),'edge_u1':max(p['edge_u'] for p in wh),'relative_y0_m':1.0,'relative_y1_m':min(2.4,clear_height-.15),'source_segment_at_eye_height':[p['point'] for p in wh]},'maximum_reveal_depth_floor_standing_ceiling_m':normal_extent,'facade_frontage_m':math.dist(wh[0]['point'],wh[1]['point']),'requires_real_floor_sloped_outer_glass_and_reveal_side_walls':True,'must_not_register_whole_bay_as_uniform3_08m_dry_box':True,'standing_volume_requires_actual_headroom_query':True,'native_glazing_or_sightline_verified':False})
 return {'room_id':room['id'],'bays':bays,'total_source_window_frontage_m':sum(b['facade_frontage_m'] for b in bays),'minimum_unit_view_frontage_candidate':sum(b['facade_frontage_m'] for b in bays)>=2.4,'rejected_intervals':reasons,'scope':'Source-geometric reveal proposal, not installed window or bedroom/living sightline proof.'}

if __name__=='__main__':
 source=HERE/'SOURCE_FLOOR_PERIMETER_CANDIDATE_V7.json';doc=json.loads(source.read_text());rows=[plan_room(f,r) for f in doc['floors'].values() for r in f['rooms']];out={'schema':'mbs_real_source_facade_reveals_v10','fixture_candidate_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'candidate_status':'HISTORICAL_INCOMPLETE_PERIMETER_FIXTURE_NOT_NEW_CATALOGUE_ALLOCATION','rooms_tested':len(rows),'rooms_with_minimum_candidate_frontage':sum(r['minimum_unit_view_frontage_candidate'] for r in rows),'rooms_without_candidate_frontage':sum(not r['minimum_unit_view_frontage_candidate'] for r in rows),'rooms':rows,'native_glazing_or_render_acceptance':False};(HERE/'SOURCE_FACADE_REVEAL_PROPOSAL_V10.json').write_text(json.dumps(out,indent=2)+'\n');print({k:v for k,v in out.items() if k!='rooms'})
