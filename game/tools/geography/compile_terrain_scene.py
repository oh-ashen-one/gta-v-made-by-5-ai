#!/usr/bin/env python3
"""Prepared real DEM terrain meshes, coast/water/root-hole separated.

Data preparation only; Root calls the new TerrainScene for main-thread commit.
No territory-as-land, water columns, terrain under declared hollow basements,
world authority, source repair, invented zero ground, engine or Git actions.
"""
import argparse,json,math,struct,sys
from pathlib import Path
from collections import Counter
import numpy as np
from shapely.geometry import Polygon,MultiPolygon,box,mapping,shape
from shapely.ops import unary_union
from shapely.strtree import STRtree
import compile_city as city
from compile_city import TerrainGrid,canonical,sha,digest,SCHEMA,IDENTITY,YMODE,FRAME
import compile_geometry as verified
from build_spatial_index import read_owners

OUTER_SCHEMA='singapore_source_terrain_scene_identity_v1'
MAX_TILES=2000
MAX_MASKS=256
MAX_VERTICES=250000
WATER_POLICY='exclude_canonical_water_horizontal_footprints_from_terrain_support_not_3d_hydrology'

class TerrainSceneError(ValueError):pass

def geometry_from_flat(polygons):
 return [Polygon(list(zip(p['rings'][0][::2],p['rings'][0][1::2])),[list(zip(r[::2],r[1::2])) for r in p['rings'][1:]]) for p in polygons]
def polys(g):return city.parts(g)
def checked_geometry(value):
 g=shape(value)
 if g.geom_type not in ('Polygon','MultiPolygon') or g.is_empty or not g.is_valid:raise TerrainSceneError('Root/canonical mask must be valid nonempty Polygon/MultiPolygon; no repair')
 return g

def root_masks(document,snapshot):
 if document.get('schema')!='terrain_root_holes_v1' or document.get('snapshot_manifest_sha256')!=snapshot or not isinstance(document.get('masks'),list) or len(document['masks'])>MAX_MASKS:
  raise TerrainSceneError('Explicit bound root hole-mask document required')
 out=[];seen=set()
 for item in document['masks']:
  if not isinstance(item,dict) or not isinstance(item.get('mask_id'),str) or not item['mask_id'] or item['mask_id'] in seen or not isinstance(item.get('provenance'),str) or not item['provenance'] or not isinstance(item.get('source_feature_ids'),list):raise TerrainSceneError('Root hole-mask identity/provenance invalid')
  seen.add(item['mask_id']);out.append((item,checked_geometry(item['geometry'])))
 return out

class HaloHeights(TerrainGrid):
 def tile(self,tx,tz):
  key=(tx,tz);item=self.inventory.get(key)
  if item is None:return None
  if key not in self.cache:
   path=self.directory/item['file'];raw=path.read_bytes()
   if path.is_symlink() or len(raw)!=7396 or sha(raw)!=item['sha256']:raise TerrainSceneError('Terrain input tile integrity failure')
   self.cache[key]=np.frombuffer(raw,dtype='<f4').reshape(43,43)
   if len(self.cache)>16:self.cache.popitem(last=False)
  self.cache.move_to_end(key);return self.cache[key]
 def h(self,tx,tz,x,z):
  a=self.tile(tx,tz)
  if a is None:return None
  gx=x/25-(tx*40-1);gz=z/25-(tz*40-1)
  if not 0<=gx<=42 or not 0<=gz<=42:return None
  ix=min(math.floor(gx),41);iz=min(math.floor(gz),41);u=gx-ix;v=gz-iz;total=0.
  for dr,dc,w in ((0,0,(1-u)*(1-v)),(0,1,u*(1-v)),(1,0,(1-u)*v),(1,1,u*v)):
   if w==0:continue
   h=float(a[iz+dr,ix+dc])
   if not math.isfinite(h):return None
   total+=h*w
  return total
 def normal(self,tx,tz,x,z):
  xp,xm,zp,zm=[self.h(tx,tz,a,b) for a,b in ((x+25,z),(x-25,z),(x,z+25),(x,z-25))]
  if any(v is None for v in (xp,xm,zp,zm)):return None
  dx=(xp-xm)/50;dz=(zp-zm)/50;length=math.sqrt(dx*dx+1+dz*dz)
  return [-dx/length,1/length,-dz/length]

def clip_support(coast,water,holes,tile):
 coast_parts=[p.intersection(tile) for p in coast if p.intersects(tile)]
 if not coast_parts:return Polygon()
 enclosure=unary_union(coast_parts)
 water_parts=[p.intersection(tile) for p in water if p.intersects(tile)]
 hole_parts=[p.intersection(tile) for p in holes if p.intersects(tile)]
 if water_parts:enclosure=enclosure.difference(unary_union(water_parts))
 if hole_parts:enclosure=enclosure.difference(unary_union(hole_parts))
 if not enclosure.is_valid:raise TerrainSceneError('Support overlay invalid; no repair')
 return enclosure

def mesh_tile(tx,tz,support,heights,offset):
 """25m grid cells clipped before true hole-aware CDT. No skirts/caps."""
 anchor=(tx*1000.,tz*1000.);vertices=[];indices=[];lookup={};unknown=[];area=0.
 for iz in range(40):
  for ix in range(40):
   x=tx*1000+ix*25;z=tz*1000+iz*25;cell=box(x,z,x+25,z+25)
   if not support.intersects(cell):continue
   for polygon in polys(support.intersection(cell)):
    flat=verified.surface_geometry(polygon,anchor);local=[];invalid=False
    for lx,_,lz in flat['vertices_local_xyz']:
     sx,sz=anchor[0]+lx,anchor[1]+lz;h=heights.h(tx,tz,sx,sz);normal=heights.normal(tx,tz,sx,sz)
     if h is None or normal is None:invalid=True;break
     # UV phase uses source global grid metres, never active-origin values.
     key=(sx,sz)
     if key not in lookup:
      lookup[key]=len(vertices);vertices.append([lx,h+offset,lz,*normal,sx/25.,sz/25.])
     local.append(lookup[key])
    if invalid:unknown.append([ix,iz]);continue
    for a,b,c in flat['triangles']:
     # Verified flat triangles are standard cross+Y. Godot front faces are
     # clockwise, so final heightfield indices have standard cross Y<0.
     indices.append([local[a],local[c],local[b]])
    area+=polygon.area
 if len(vertices)>MAX_VERTICES:raise TerrainSceneError('Prepared terrain tile vertex budget exceeded')
 if not indices:return None,{'unknown_grid_cells':unknown,'prepared_area_m2':0.}
 raw=b''.join(struct.pack('<8f',*v) for v in vertices);flat_i=[v for tri in indices for v in tri]
 ib=struct.pack('<'+'I'*len(flat_i),*flat_i)
 # Exact engine-facing geometric convention, independent of smoothed normals.
 vv=np.frombuffer(raw,dtype='<f4').reshape(-1,8);ii=np.asarray(indices,dtype=np.int64)
 cross=np.cross(vv[ii[:,1],:3].astype(float)-vv[ii[:,0],:3],vv[ii[:,2],:3].astype(float)-vv[ii[:,0],:3])
 if not np.isfinite(cross).all() or np.any(cross[:,1]>=0):raise TerrainSceneError('Float32 terrain triangle winding/area invalid; no repair')
 surface={'role':'coarse_dem_conservative_terrain_support','vertex_count':len(vertices),'index_count':len(flat_i),'vertex_offset_bytes':0,'index_offset_bytes':len(raw),'topology_sha256':sha(raw+ib)}
 return (raw+ib,surface),{'unknown_grid_cells':unknown,'prepared_area_m2':area,'source_coast_water_hole_area_m2':support.area}

def load_water(snapshot):
 mr=(snapshot/'manifest.json').read_bytes();manifest=json.loads(mr)
 if len(manifest['tiles'])>2000 or any(t['bytes']>32*1024*1024 for t in manifest['tiles']):raise TerrainSceneError('Canonical water source work bounds exceeded')
 records=[];geometries=[]
 for owner,features in read_owners(snapshot,manifest):
  for f in features:
   if f['kind']!='water':continue
   g=checked_geometry(f['geometry']);geometries.append(g)
   records.append({'source_id':f['id'],'source_owner':owner,'source_record_sha256':sha(canonical(f)),
    'source_tags':f['tags'],'geometry_world_xz':f['geometry'],'vertical_water_column':'UNKNOWN; horizontal footprint only'})
 if len(records)>5000:raise TerrainSceneError('Water registry exceeds bound')
 return manifest,mr,records,geometries

def prepare(snapshot,domain,dem,root_holes,output,tiles,expected_snapshot,expected_domain,expected_dem,expected_masks,offset):
 if output.exists():raise TerrainSceneError('Refusing to overwrite terrain preparation')
 mi,mraw,water_records,water=load_water(snapshot)
 if sha(mraw)!=expected_snapshot:raise TerrainSceneError('Canonical source snapshot differs')
 iraw=(domain/'identity.json').read_bytes();identity=json.loads(iraw);raw=(domain/'domain.json').read_bytes();data=json.loads(raw)
 if sha(iraw)!=expected_domain or sha(raw)!=identity['dataset']['sha256'] or data['bindings']['snapshot_manifest_sha256']!=expected_snapshot:raise TerrainSceneError('Domain identity/snapshot mismatch')
 masks_raw=root_holes.read_bytes();mask_doc=json.loads(masks_raw)
 if sha(masks_raw)!=expected_masks:raise TerrainSceneError('Explicit root masks hash mismatch')
 masks=root_masks(mask_doc,expected_snapshot);coast=geometry_from_flat(data['coast_enclosure']);holes=[g for _,g in masks]
 heights=HaloHeights(dem,expected_dem,expected_snapshot)
 if not tiles:tiles=sorted(heights.inventory)
 if len(tiles)>MAX_TILES or len(set(tiles))!=len(tiles):raise TerrainSceneError('Terrain preparation batch/tile identity budget exceeded')
 water_raw=canonical({'schema':'canonical_water_horizontal_registry_v1','snapshot_manifest_sha256':expected_snapshot,'records':water_records,'not_water_elevation_or_hydrology':True})
 bindings={'snapshot_sha':expected_snapshot,'dem_identity':expected_dem,'domain_identity':expected_domain,'root_holes_sha256':expected_masks,
  'canonical_water_registry_sha256':sha(water_raw),'compiler_sha256':digest(__file__),'world_y_mode':YMODE,'world_y_offset_m':offset}
 prep_sha=sha(canonical(bindings));bindings['preparation_sha256']=prep_sha
 output.mkdir(parents=True);(output/'meshes').mkdir();(output/'catalogs').mkdir();(output/'water-registry.json').write_bytes(water_raw)
 mesh_inventory=[];catalog_inventory=[];stats=Counter();terrain_details=[]
 water_tree=STRtree(water) if water else None
 for tx,tz in tiles:
  cell=box(tx*1000,tz*1000,(tx+1)*1000,(tz+1)*1000);key=f'{tx}_{tz}'
  water_indices=[int(i) for i in water_tree.query(cell,predicate='intersects')] if water_tree is not None else []
  relevant_water=[water[i] for i in water_indices];mask_ids=[item['mask_id'] for item,g in masks if g.intersects(cell)]
  support=clip_support(coast,relevant_water,holes,cell)
  prepared,detail=mesh_tile(tx,tz,support,heights,offset)
  stats['requested_tiles']+=1;stats['unknown_grid_cells']+=len(detail['unknown_grid_cells'])
  terrain_details.append({'tile':key,'status':'prepared' if prepared else 'no_known_terrain_area','root_masks':mask_ids,'water_ids':[water_records[i]['source_id'] for i in water_indices],**detail})
  if prepared is None:continue
  blob,surface=prepared;feature='terrain|'+key
  provenance={'schema':OUTER_SCHEMA,'preparation_sha256':prep_sha,'root_holes_sha256':expected_masks,'water_registry_sha256':sha(water_raw),
   'water_policy':WATER_POLICY,'root_mask_ids':mask_ids,'water_ids':[water_records[i]['source_id'] for i in water_indices],
   'height_reference':'Older/coarse EGM96 game surface, not current survey/MBSL1/dryland/3D water','unknown_grid_cells':detail['unknown_grid_cells']}
  catalog={'schema':SCHEMA,'owner':key,'features':[{'feature_key':feature,'kind':'terrain_derivative','provenance':provenance,'source_bounds_xz':list(cell.bounds)}]}
  cr=canonical(catalog);(output/'catalogs'/f'{key}.json').write_bytes(cr)
  catalog_inventory.append({'key':key,'file':f'catalogs/{key}.json','bytes':len(cr),'sha256':sha(cr)})
  meta={'schema':SCHEMA,'tile_xz':[tx,tz],'anchor_source_xyz':[tx*1000.,0.,tz*1000.],
   'binary':{'file':key+'.mesh','bytes':len(blob),'sha256':sha(blob)},
   'features':[{'feature_key':feature,'catalog_owner':key,'surfaces':[surface],'logical_feature_source_sha256':prep_sha}],
   'terrain_reference':provenance}
  meta_raw=canonical(meta);(output/'meshes'/f'{key}.json').write_bytes(meta_raw);(output/'meshes'/f'{key}.mesh').write_bytes(blob)
  mesh_inventory.append({'key':key,'file':f'meshes/{key}.json','bytes':len(meta_raw),'sha256':sha(meta_raw),
   'binary_file':f'meshes/{key}.mesh','binary_bytes':len(blob),'binary_sha256':sha(blob),'features':1})
  stats['prepared_tiles']+=1;stats['vertices']+=surface['vertex_count'];stats['triangles']+=surface['index_count']//3
 manifest={'schema':SCHEMA,'version':1,'bindings':bindings,'georeference':FRAME,'geometry_role':'source_dem_terrain_with_explicit_root_holes',
  'world_y_policy':{'mode':YMODE,'offset_m':offset,'architecture_datum_alignment_verified':False},
  'mesh_format':{'stride_bytes':32,'index_bytes':4,'byte_order':'little','local_anchor_subtracted_before_float':True,'front_face_winding':'godot_clockwise_cross_opposite_outward_normal'},
  'catalogs':catalog_inventory,'meshes':mesh_inventory,'counts':dict(stats),'exclusions':[],
  'terrain_tile_details':terrain_details,'terrain_admission_policy':WATER_POLICY,
  'limitations':['Terrain collision is an explicit coarse game surface policy, not independently surveyed dry ground or water hydrology.',
   'Canonical mapped water footprints are conservatively unsupported regardless unknown vertical meaning; root resolves elevated/indoor water separately.',
   'Root hole masks prevent plugging hollow basements; the coordinator must commit corresponding architecture and residency before actor motion.',
   'No terrain under unknown/void cells, no skirts/walls closing holes, no administrative territory or DEMzero treated as land/water.',
   '25m triangulated surface approximates the resampled DEM; triangle interpolation is not a new measured resolution or a source architectural floor.']}
 mr=canonical(manifest);(output/'manifest.json').write_bytes(mr)
 inner={'schema':IDENTITY,'version':1,'snapshot_sha256':expected_snapshot,'dem_identity_sha256':expected_dem,'manifest':{'file':'manifest.json','bytes':len(mr),'sha256':sha(mr)}}
 inner_raw=canonical(inner);(output/'identity.json').write_bytes(inner_raw)
 outer={'schema':OUTER_SCHEMA,'version':1,'geometry_identity':{'file':'identity.json','bytes':len(inner_raw),'sha256':sha(inner_raw)},
  'bindings':bindings,'water_registry':{'file':'water-registry.json','sha256':sha(water_raw),'bytes':len(water_raw)},
  'root_mask_count':len(masks),'water_policy':WATER_POLICY,'world_y_policy':manifest['world_y_policy'],'counts':dict(stats)}
 outer_raw=canonical(outer);(output/'terrain-identity.json').write_bytes(outer_raw)
 return {'terrain_identity_sha256':sha(outer_raw),'geometry_identity_sha256':sha(inner_raw),'manifest_sha256':sha(mr),'root_masks_sha256':expected_masks,'counts':dict(stats),'water_records':len(water_records),'prepared_details':terrain_details}

def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ('snapshot','domain','dem','root-holes','output'):p.add_argument('--'+name,type=Path,required=True)
 for name in ('expected-snapshot','expected-domain','expected-dem','expected-masks'):p.add_argument('--'+name,required=True)
 p.add_argument('--tile',type=int,nargs=2,action='append',default=[]);p.add_argument('--world-y-offset',type=float,required=True)
 a=p.parse_args()
 try:print(json.dumps(prepare(a.snapshot,a.domain,a.dem,a.root_holes,a.output,[tuple(t) for t in a.tile],a.expected_snapshot,a.expected_domain,a.expected_dem,a.expected_masks,a.world_y_offset)));return 0
 except Exception as e:print(json.dumps({'status':'failed','reason':str(e) if isinstance(e,TerrainSceneError) else type(e).__name__+': source/clip/preparation failure; no private source path emitted'}));return 2
if __name__=='__main__':raise SystemExit(main())
