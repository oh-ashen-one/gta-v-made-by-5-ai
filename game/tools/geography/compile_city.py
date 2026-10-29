#!/usr/bin/env python3
"""Whole-country source-footprint building meshes with explicit game policies.

No scene authority, legal road graph, dryland assertion, survey-height claim or
MBS duplicate. Footprints/holes survive, tile cuts create no artificial walls.
"""
import argparse,array
from collections import Counter,OrderedDict,defaultdict
from copy import deepcopy
import json,math,os,resource,sqlite3,struct,subprocess,sys,time
from pathlib import Path
import numpy as np
import osmium
import shapely
from shapely.geometry import Polygon,MultiPolygon,LineString,box,shape,mapping
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'geodata'))
import compile_geometry as verified
from build_spatial_index import read_owners,projected_country,validate_frame,safe_tile_name
from compile_terrain import FRAME

SCHEMA='singapore_source_city_geometry_v1'
IDENTITY='singapore_source_city_identity_v1'
YMODE='EGM96_DEM_game_world_reference_not_current_survey'
MAX_META=32*1024*1024
MAX_BLOB=64*1024*1024
MAX_FRAGMENTS_PER_FEATURE=256
MAX_TRIANGLES=2000000
MAX_OWNERS=2000

def canonical(v):return verified.canonical_bytes(v)
def sha(b):return verified.sha(b)
def digest(p):
 import hashlib
 h=hashlib.sha256()
 with Path(p).open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
class CityError(ValueError):pass

def exclusive_or_same(path,data):
 if path.is_symlink():raise CityError('Symlink output refused')
 if path.exists():
  if path.read_bytes()!=data:raise CityError('Existing owned job output differs; no overwrite')
  return
 with path.open('xb') as f:f.write(data)

def parts(g,kind='Polygon'):
 if g.is_empty:return []
 if g.geom_type==kind:return [g]
 return [p for x in getattr(g,'geoms',[]) for p in parts(x,kind)]

class TerrainGrid:
 def __init__(self,directory,expected_identity,snapshot):
  self.directory=directory;iraw=(directory/'identity.json').read_bytes();i=json.loads(iraw)
  if sha(iraw)!=expected_identity or i.get('schema')!='singapore_skadi_terrain_identity_v1' or i.get('snapshot_manifest_sha256')!=snapshot:raise CityError('DEM identity/snapshot mismatch')
  raw=(directory/'manifest.json').read_bytes();m=json.loads(raw)
  if sha(raw)!=i['manifest']['sha256'] or len(raw)!=i['manifest']['bytes'] or m.get('vertical_reference')!='EGM96 geoid metres':raise CityError('DEM manifest/datum mismatch')
  if m['grid'].get('spacing_metres')!=25 or m['grid'].get('stored_samples')!=43:raise CityError('Unsupported DEM grid')
  self.inventory={tuple(c['chunk_xz']):c for c in m['chunks']};self.cache=OrderedDict();self.identity=expected_identity;self.manifest_sha=sha(raw)
 def sample(self,x,z):
  tx,tz=math.floor(x/1000),math.floor(z/1000);key=(tx,tz);item=self.inventory.get(key)
  if item is None:return None
  if key not in self.cache:
   path=self.directory/item['file']
   if path.is_symlink():raise CityError('DEM source symlink refused')
   raw=path.read_bytes()
   if len(raw)!=7396 or sha(raw)!=item['sha256']:raise CityError('DEM tile integrity failure')
   self.cache[key]=np.frombuffer(raw,dtype='<f4').reshape(43,43)
   if len(self.cache)>16:self.cache.popitem(last=False)
  self.cache.move_to_end(key);values=self.cache[key]
  gx=x/25-(tx*40-1);gz=z/25-(tz*40-1);ix=min(math.floor(gx),41);iz=min(math.floor(gz),41);u=gx-ix;v=gz-iz
  result=0.
  for dr,dc,w in ((0,0,(1-u)*(1-v)),(0,1,u*(1-v)),(1,0,(1-u)*v),(1,1,u*v)):
   if w==0:continue
   h=float(values[iz+dr,ix+dc])
   if not math.isfinite(h):return None
   result+=h*w
  return result

def height_policy(feature,unknown_height,story_height):
 tags=feature['tags'];source=feature.get('height_m');known=isinstance(source,(int,float)) and not isinstance(source,bool) and math.isfinite(source) and source>0
 levels=verified.metre_tag(tags.get('building:levels'),positive=True)
 if known:top=float(source);status='source_height_tag'
 elif levels is not None:top=levels*story_height;status='game_story_height_from_source_levels_reconstruction'
 else:top=unknown_height;status='game_unknown_height_fallback_reconstruction'
 minimum=verified.metre_tag(tags.get('min_height'))
 min_levels=verified.metre_tag(tags.get('building:min_level'))
 if minimum is not None and minimum>=0:bottom=minimum;bottom_status='source_min_height_tag'
 elif min_levels is not None and min_levels>=0:bottom=min_levels*story_height;bottom_status='game_story_height_from_source_min_level_reconstruction'
 else:bottom=0.;bottom_status='game_bottom_zero_relative_to_DEM_reference'
 return {'source_height_m':float(source) if known else None,'source_height_status':feature.get('height_status','unknown'),
  'source_height_tag':tags.get('height'),'source_levels_tag':tags.get('building:levels'),'source_min_height_tag':tags.get('min_height'),'source_min_level_tag':tags.get('building:min_level'),
  'game_top_height_m':top,'game_bottom_height_m':bottom,'height_policy':status,'bottom_policy':bottom_status,
  'unknown_height_fallback_m':unknown_height,'story_height_game_estimate_m':story_height,'height_is_source_fact':known,
  'actual_roof_shape_reconstructed':False,'roof_model':'flat game extrusion; source roof tags retained separately'}

def _surface(vertices,indices,role):
 # Interleaved local position/normal/UV, LE float32; shared index topology is
 # the only collision candidate. No body/physics residency is created here.
 if len(indices)>MAX_TRIANGLES*3:raise CityError('Mesh triangle budget exceeded')
 raw=b''.join(struct.pack('<8f',*v) for v in vertices)
 # Godot's clockwise front face (also used by native trimesh collision) has
 # geometric cross product OPPOSITE the intended outward shader normal.
 # R1 incorrectly equated cross(normal) with outwardness; native rays hit its
 # underside instead of roof. Normalize the indices here, not culling flags.
 godot_indices=[]
 for original_tri in indices:
  tri=list(original_tri)
  a,b,c=[struct.unpack_from('<3f',raw,i*32) for i in tri]
  ab=[b[j]-a[j] for j in range(3)];ac=[c[j]-a[j] for j in range(3)]
  cross=(ab[1]*ac[2]-ab[2]*ac[1],ab[2]*ac[0]-ab[0]*ac[2],ab[0]*ac[1]-ab[1]*ac[0])
  if not all(math.isfinite(v) for v in cross) or sum(v*v for v in cross)==0:raise CityError('Float32 triangle degenerates; source geometry not enlarged/repaired')
  normal=struct.unpack_from('<3f',raw,tri[0]*32+12)
  dot=sum(cross[j]*normal[j] for j in range(3))
  if dot==0:raise CityError('Mesh face has no consistent outward normal')
  if dot>0:tri[1],tri[2]=tri[2],tri[1]
  godot_indices.append(tri)
 flat=[i for tri in godot_indices for i in tri]
 ib=struct.pack('<'+'I'*len(flat),*flat) if flat else b''
 return {'role':role,'vertex_count':len(vertices),'index_count':len(flat),'vertex_bytes':raw,'index_bytes':ib,'topology_sha256':sha(raw+ib)}

def building_fragments(geometry,base_y,top_relative,bottom_relative):
 if int(shapely.get_num_coordinates(geometry))>50000:raise CityError('Feature coordinate work budget exceeded before tessellation')
 x0,z0,x1,z1=geometry.bounds;cells={}
 sx0,sz0,sx1,sz1=math.floor(x0/1000),math.floor(z0/1000),math.ceil(x1/1000),math.ceil(z1/1000)
 if (sx1-sx0)*(sz1-sz0)>4096:raise CityError('Feature candidate-cell work budget exceeded before iteration')
 for tx in range(math.floor(x0/1000),math.ceil(x1/1000)):
  for tz in range(math.floor(z0/1000),math.ceil(z1/1000)):
   cell=box(tx*1000,tz*1000,(tx+1)*1000,(tz+1)*1000)
   clipped=geometry.intersection(cell)
   if clipped.area>0:cells[(tx,tz)]=cell
 if len(cells)>MAX_FRAGMENTS_PER_FEATURE:raise CityError('Feature exceeds256 spatial mesh fragments; retained unresolved')
 results={};roof_area=0.;wall_length=0.
 uv_origin=geometry.bounds[:2]
 for (tx,tz),cell in sorted(cells.items()):
  anchor=(tx*1000.,tz*1000.);surfaces=[]
  for polygon in parts(geometry.intersection(cell)):
   flat=verified.surface_geometry(polygon,anchor);roof_area+=polygon.area
   roof=[];bottom=[]
   for x,_,z in flat['vertices_local_xyz']:
    uv=((x+anchor[0]-uv_origin[0])/4,(z+anchor[1]-uv_origin[1])/4)
    roof.append([x,base_y+top_relative,z,0.,1.,0.,*uv]);bottom.append([x,base_y+bottom_relative,z,0.,-1.,0.,*uv])
   surfaces.append(_surface(roof,flat['triangles'],'roof'))
   surfaces.append(_surface(bottom,[[a,c,b] for a,b,c in flat['triangles']],'underside'))
  walls=[];wall_indices=[]
  for original in parts(geometry):
   rings=[verified._ring(original.exterior.coords,(0,0),True)]+[verified._ring(r.coords,(0,0),False) for r in original.interiors]
   for ring in rings:
    line=LineString(ring)
    for piece in verified._path_fragments(line,cell,tx,tz,1000,cells):
     positions=piece['points'];distance=piece['start']
     for a,b in zip(positions,positions[1:]):
      dx=b[0]-a[0];dz=b[1]-a[1];length=math.hypot(dx,dz)
      if length<=0:continue
      wall_length+=length;normal=(-dz/length,0.,dx/length);start=len(walls)
      for p,y,u in ((a,base_y+bottom_relative,distance/4),(b,base_y+bottom_relative,(distance+length)/4),(b,base_y+top_relative,(distance+length)/4),(a,base_y+top_relative,distance/4)):
       walls.append([p[0]-anchor[0],y,p[1]-anchor[1],*normal,u,(y-base_y-bottom_relative)/3.2])
      wall_indices.extend([[start,start+1,start+2],[start,start+2,start+3]]);distance+=length
  if walls:surfaces.append(_surface(walls,wall_indices,'exterior_and_courtyard_walls'))
  results[(tx,tz)]=surfaces
 if abs(roof_area-geometry.area)>max(1e-7,geometry.area*1e-9):raise CityError('Country/tile roof area lost or duplicated')
 if abs(wall_length-geometry.boundary.length)>max(1e-7,geometry.boundary.length*1e-9):raise CityError('Original wall boundary lost/doubled at tile cut')
 return results

class RoadCollector(osmium.SimpleHandler):
 def __init__(self,db,targets):super().__init__();self.db=db;self.targets=targets;self.found=0;self.seen=set()
 def way(self,w):
  if w.id not in self.targets:return
  key='way/'+str(w.id)
  if w.id in self.seen:raise CityError('Duplicate original road way observation')
  self.seen.add(w.id)
  existing=self.db.execute('select refs,fulltags,version from roads where id=?',(key,)).fetchone()
  if existing is None:return
  refs=array.array('q',[int(n.ref) for n in w.nodes])
  if sys.byteorder!='little':refs.byteswap()
  fulltags=json.dumps(dict(w.tags),ensure_ascii=False);version=int(w.version) if w.version>0 else None
  if existing[0] is not None:
   if existing!=(refs.tobytes(),fulltags,version):raise CityError('Resumed road source record differs')
   return
  self.db.execute('update roads set refs=?, fulltags=?, version=? where id=?',(refs.tobytes(),fulltags,version,key));self.found+=1
  if self.found%1000==0:self.db.commit()

def _db(path):
 db=sqlite3.connect(path);db.execute('pragma cache_size=-65536');db.execute('pragma temp_store=FILE');db.execute('pragma mmap_size=0')
 db.executescript('create table if not exists roads(id text primary key,refs blob,fulltags text,version integer);create table if not exists owners(name text primary key,sha text,catalogsha text);create table if not exists fragments(tile text,key text,owner text,meta text,vb blob,ib blob,primary key(tile,key));create table if not exists features(key text primary key,owner text);create table if not exists stages(name text primary key);')
 return db

def _road_record(feature,owner,db,anchor):
 observed=db.execute('select refs,fulltags,version from roads where id=?',(feature['id'],)).fetchone()
 refs=None;tags=None;version=None;issues=[]
 if observed and observed[0] is not None:
  a=array.array('q');a.frombytes(observed[0])
  if sys.byteorder!='little':a.byteswap()
  refs=a.tolist();tags=json.loads(observed[1]);version=observed[2]
  if len(refs)!=len(feature['geometry']['coordinates']):issues.append('original_node_coordinate_count_mismatch')
  if any(tags.get(k)!=v for k,v in feature['tags'].items()):issues.append('canonical_source_tag_conflict')
 else:issues.append('missing_original_node_reference_source')
 return {'original_ordered_node_ids':refs,'full_source_tags':tags,'source_version':version,'source_contract_issues':issues,
  'centerline_local_xz_double':[[p[0]-anchor[0],p[1]-anchor[2]] for p in feature['geometry']['coordinates']],
  'status':'unresolved_road_width_elevation_access_grade_plan','mesh_or_collision_generated':False,
  'node_coordinate_projection_validation':'canonical pipeline/order count only; existing regional independent node audit remains separate',
  'no_xy_merge_or_legal_bidirectional_inference':True}

def _mesh_blob(surfaces):
 data=bytearray();rows=[]
 for surface in surfaces:
  row={k:v for k,v in surface.items() if k not in ('vertex_bytes','index_bytes')}
  row['vertex_offset_bytes']=len(data);data.extend(surface['vertex_bytes']);row['index_offset_bytes']=len(data);data.extend(surface['index_bytes']);rows.append(row)
 if len(data)>MAX_BLOB:raise CityError('Feature fragment binary budget exceeded')
 return bytes(data),rows

_OWNED_JOB_LOCK=None

def _worker(args):
 global _OWNED_JOB_LOCK
 start=time.monotonic();resource.setrlimit(resource.RLIMIT_CPU,(args.max_cpu_seconds,args.max_cpu_seconds+30))
 mr=(args.snapshot/'manifest.json').read_bytes();m=json.loads(mr);br=(args.snapshot/'singapore-boundary.geojson').read_bytes()
 if sha(mr)!=args.expected_snapshot_sha256:raise CityError('Canonical snapshot mismatch')
 validate_frame(m['georeference']);country=projected_country(json.loads(br));terrain=TerrainGrid(args.terrain,args.expected_dem_identity,sha(mr))
 config={'snapshot_sha':sha(mr),'country_sha':sha(br),'dem_identity':args.expected_dem_identity,'ymode':args.world_y_mode,'yoffset':args.world_y_offset,
  'unknown_height':args.unknown_height,'story_height':args.story_height,'skip_ids':sorted(args.skip_id),'skip_envelopes':args.skip_envelope,'source_compiler_sha256':digest(__file__),'verified_compiler_sha256':digest(verified.__file__)}
 job=canonical({'schema':SCHEMA,'config':config});output=args.output_dir
 if output.exists():
  if not args.resume or (output/'identity.json').exists() or (output/'job.json').read_bytes()!=job:raise CityError('Existing output is not this unfinished exact job; no overwrite')
 else:output.mkdir(parents=True);(output/'job.json').write_bytes(job)
 lock=output/'.job.lock'
 if lock.exists():
  if not args.resume:raise CityError('Owned city job lock exists; no takeover')
  previous=json.loads(lock.read_bytes())
  if previous.get('job_sha256')!=sha(job):raise CityError('Existing job lock belongs to different configuration')
  try:os.kill(int(previous['pid']),0)
  except ProcessLookupError:lock.unlink()
  else:raise CityError('Existing city job process still active; no duplicate run')
 with lock.open('xb') as f:f.write(canonical({'pid':os.getpid(),'job_sha256':sha(job)}))
 _OWNED_JOB_LOCK=lock
 for folder in ('catalogs','meshes'):(output/folder).mkdir(exist_ok=True)
 db=_db(output/'.work.sqlite');counts=Counter();all_owners=m['tiles']
 if len(all_owners)>MAX_OWNERS or sum(t.get('features',0) for t in all_owners)>500000:raise CityError('Owner/feature count exceeds bounded work inventory')
 for t in all_owners:
  if not safe_tile_name(t.get('file')) or not isinstance(t.get('bytes'),int) or not 0<t['bytes']<=32*1024*1024:raise CityError('Unsafe or oversized source owner before iteration')
 if not db.execute("select 1 from stages where name='road_targets'").fetchone():
  for owner,features in read_owners(args.snapshot,m):
   for f in features:
    if f['kind']=='road':db.execute('insert or ignore into roads(id) values(?)',(f['id'],))
   db.commit()
  db.execute("insert into stages values('road_targets')");db.commit()
 if not db.execute("select 1 from stages where name='road_refs'").fetchone():
  if digest(args.pbf)!=m['pbf_sha256']:raise CityError('Exact private PBF differs from canonical snapshot')
  targets={int(row[0].split('/')[1]) for row in db.execute('select id from roads')};handler=RoadCollector(db,targets)
  reader=osmium.io.Reader(str(args.pbf),osmium.osm.osm_entity_bits.WAY)
  try:
   if reader.header().get('osmosis_replication_timestamp')!=m['source_snapshot_utc']:raise CityError('PBF header time differs')
   osmium.apply(reader,osmium.filter.KeyFilter('highway'),handler)
  finally:reader.close()
  db.execute("insert into stages values('road_refs')");db.commit()
 skip_boxes=[box(*b) for b in args.skip_envelope]
 for owner,features in read_owners(args.snapshot,m):
  key=owner[:-5];tx,tz=map(int,key.split('_'));anchor=[tx*1000.,0.,tz*1000.];path=output/'catalogs'/owner
  prior=db.execute('select sha,catalogsha from owners where name=?',(owner,)).fetchone()
  source_sha=next(t['sha256'] for t in all_owners if t['file']==owner)
  if prior:
   if prior[0]!=source_sha or digest(path)!=prior[1]:raise CityError('Resume owner source/output checksum differs')
   continue
  catalog=[]
  for f in features:
   feature_key=verified.identity(f);db.execute('insert into features values(?,?)',(feature_key,key))
   g=shape(f['geometry']);clipped=g.intersection(country)
   if f['kind']=='building':
    polygons=parts(clipped)
    clipped=polygons[0] if len(polygons)==1 else MultiPolygon(polygons)
   row={'feature_key':feature_key,'id':f['id'],'kind':f['kind'],'name':f['tags'].get('name'),'source_tags':deepcopy(f['tags']),
    'source_owner_file':owner,'source_feature_sha256':sha(canonical(f)),'source_geometry_sha256':sha(canonical(f['geometry'])),
    'source_bounds_xz':list(g.bounds),'catalog_owner':key,'canonical_anchor_source_xyz':anchor,'source_height_m':f.get('height_m'),'source_height_status':f.get('height_status')}
   if f['kind']=='road':row['road']=_road_record(f,owner,db,anchor)
   elif f['kind']!='building':row['status']='unresolved_water_or_other_geometry_no_support_generated'
   else:
    policy=height_policy(f,args.unknown_height,args.story_height);row['height']=policy
    if f['id'] in args.skip_id or any(g.intersects(b) for b in skip_boxes):row['status']='excluded_root_special_complex';row['exclusion_reason']='explicit_source_id' if f['id'] in args.skip_id else 'explicit_source_site_envelope'
    elif clipped.area<=0:row['status']='no_polygon_area_after_country_clip'
    elif not clipped.is_valid:row['status']='unresolved_invalid_source_geometry_no_repair'
    elif policy['game_top_height_m']<=policy['game_bottom_height_m'] or policy['game_top_height_m']>1500:row['status']='unresolved_height_order_or_range'
    else:
     point=clipped.representative_point();height=terrain.sample(point.x,point.y)
     row['base']={'sample_source_xz':[point.x,point.y],'egm96_dem_m':height,'world_y_mode':args.world_y_mode,'game_world_y_offset_m':args.world_y_offset,'current_ground_surveyed':False,'flat_per_feature_base_is_game_policy':True}
     if height is None:row['status']='unresolved_dem_base_void_or_coverage'
     else:
      try:
       fragments=building_fragments(clipped,height+args.world_y_offset,policy['game_top_height_m'],policy['game_bottom_height_m'])
       encoded=[]
       for tile,surfaces in fragments.items():
        blob,mesh_rows=_mesh_blob(surfaces);encoded.append((tile,blob,mesh_rows))
       row['status']='game_extrusion_render_and_collision_candidate';row['mesh_tiles']=[f'{t[0]}_{t[1]}' for t,_,_ in encoded]
       row['clipped_footprint_area_m2']=clipped.area;row['source_building_role']='part' if 'building:part' in f['tags'] else 'outline'
       row['overlapping_distinct_source_outline_part_volumes']='unresolved architectural composition; no source-ID/XY merge'
       for tile,blob,mesh_rows in encoded:
        meta={'feature_key':feature_key,'catalog_owner':key,'surfaces':mesh_rows,'logical_feature_source_sha256':row['source_feature_sha256'],'physical_support_verified':False}
        db.execute('insert into fragments values(?,?,?,?,?,?)',(f'{tile[0]}_{tile[1]}',feature_key,key,json.dumps(meta,separators=(',',':')),blob,b''))
      except (CityError,verified.GeometryCompileError,ValueError) as e:
       row['status']='unresolved_tessellation_or_precision';row['error_kind']=type(e).__name__
   catalog.append(row)
  document={'schema':SCHEMA,'owner':key,'anchor_source_xyz':anchor,'source_owner_sha256':source_sha,'features':catalog}
  raw=canonical(document)
  if len(raw)>MAX_META:raise CityError('Catalog page exceeds32MiB')
  exclusive_or_same(path,raw);db.execute('insert into owners values(?,?,?)',(owner,source_sha,sha(raw)));db.commit()
  if db.execute('select count(*) from owners').fetchone()[0]%25==0:(output/'progress.json').write_bytes(canonical({'stage':'source_owners','completed_owners':db.execute('select count(*) from owners').fetchone()[0],'total_owners':len(all_owners)}))
 mesh_inventory=[]
 for (tile,) in db.execute('select distinct tile from fragments order by tile').fetchall():
  tx,tz=map(int,tile.split('_'));blob=bytearray();entries=[]
  for key,owner,meta,vb in db.execute('select key,owner,meta,vb from fragments where tile=? order by key',(tile,)):
   entry=json.loads(meta);offset=len(blob)
   for surface in entry['surfaces']:surface['vertex_offset_bytes']+=offset;surface['index_offset_bytes']+=offset
   blob.extend(vb);entries.append(entry)
   if len(blob)>MAX_BLOB:raise CityError('Spatial mesh tile exceeds64MiB budget')
  data=bytes(blob);binary=tile+'.mesh';metadata=tile+'.json'
  doc={'schema':SCHEMA,'tile_xz':[tx,tz],'anchor_source_xyz':[tx*1000.,0.,tz*1000.],
   'binary':{'file':binary,'bytes':len(data),'sha256':sha(data),'encoding':'LEfloat32_position3_normal3_uv2_then_LEuint32_indices_per_surface'},
   'features':entries,'collision_topology':'same vertex/index buffers; root must explicitly commit physics and provenance',
   'terrain_reference':{'dataset_identity_sha256':args.expected_dem_identity,'chunk_key':tile,'dryland_or_physical_support':False}}
  raw=canonical(doc)
  if len(raw)>MAX_META:raise CityError('Spatial mesh metadata exceeds32MiB budget')
  exclusive_or_same(output/'meshes'/binary,data);exclusive_or_same(output/'meshes'/metadata,raw)
  mesh_inventory.append({'key':tile,'file':'meshes/'+metadata,'bytes':len(raw),'sha256':sha(raw),'binary_file':'meshes/'+binary,'binary_bytes':len(data),'binary_sha256':sha(data),'features':len(entries)})
 catalog_inventory=[];totals=Counter();excluded=[]
 for name,source_sha,catalogsha in db.execute('select name,sha,catalogsha from owners order by name'):
  p=output/'catalogs'/name;doc=json.loads(p.read_bytes())
  for f in doc['features']:
   totals[f['kind']]+=1;totals[f.get('status','road_record')]+=1
   if f['kind']=='building':totals[f['height']['height_policy']]+=1
   if f.get('status')=='excluded_root_special_complex':excluded.append({'feature_key':f['feature_key'],'owner':name[:-5],'reason':f['exclusion_reason'],'source_bounds_xz':f['source_bounds_xz']})
  catalog_inventory.append({'key':name[:-5],'file':'catalogs/'+name,'bytes':p.stat().st_size,'sha256':catalogsha,'source_sha256':source_sha})
 usage=resource.getrusage(resource.RUSAGE_SELF)
 manifest={'schema':SCHEMA,'version':1,'bindings':config,'georeference':FRAME,'world_y_policy':{'mode':args.world_y_mode,'offset_m':args.world_y_offset,'architecture_datum_alignment_verified':False},
  'height_game_policy':{'unknown_height_m':args.unknown_height,'source_levels_story_height_m':args.story_height,'estimates_are_not_source_facts':True},
  'mesh_format':{'stride_bytes':32,'position_offset':0,'normal_offset':12,'uv_offset':24,'index_bytes':4,'byte_order':'little','local_anchor_subtracted_before_float':True,'front_face_winding':'godot_clockwise_cross_opposite_outward_normal'},
  'catalogs':catalog_inventory,'meshes':mesh_inventory,'exclusions':excluded,'counts':dict(totals),
  'road_source_audit':{'targets':db.execute('select count(*) from roads').fetchone()[0],'found':db.execute('select count(*) from roads where refs is not null').fetchone()[0],'vehicle_graph_or_mesh':False},
  'terrain_reference':{'dataset_identity_sha256':args.expected_dem_identity,'physical_support_or_dryland':False},
  'attribution':{'footprints_names_roads':'© OpenStreetMap contributors, ODbL1.0','dem':'Mapzen/USGS/NOAA; terrain dataset attribution applies separately'},
  'limits':{'max_metadata_bytes':MAX_META,'max_binary_bytes':MAX_BLOB,'max_cached_mesh_tiles':8,'max_cached_catalogs':8},
  'resources':{'wall_seconds':round(time.monotonic()-start,3),'cpu_seconds':round(usage.ru_utime+usage.ru_stime,3),'peak_rss_bytes':int(usage.ru_maxrss if sys.platform=='darwin' else usage.ru_maxrss*1024)},
  'limitations':['Actual horizontal source footprints/holes with explicit approximate game extrusions, not finished source-correct3D architecture/materials/interiors.',
   'No terrain/water/country support is assumed; DEMreference is older coarse EGM96, not current surveyed building base or MBSL1.',
   'Road original node order/tags preserved; width/elevation/grade/access/legal direction planning remains unresolved. No XY-derived connectivity or bidirectional expansion.',
   'Distinct overlapping source building outlines/parts remain annotated; root architectural composition/landmark overrides are not inferred.',
   'Root alone owns geometry/material/physics commit, global feature registry, residency, traffic/AI, source poses/rebases/saves and normal game bootstrap.']}
 raw=canonical(manifest);exclusive_or_same(output/'manifest.json',raw)
 identity={'schema':IDENTITY,'version':1,'manifest':{'file':'manifest.json','bytes':len(raw),'sha256':sha(raw)},'snapshot_sha256':sha(mr),'dem_identity_sha256':args.expected_dem_identity}
 iraw=canonical(identity);exclusive_or_same(output/'identity.json',iraw)
 db.close()
 for suffix in ('','.sqlite-journal','.sqlite-wal','.sqlite-shm'):
  p=output/('.work.sqlite' if not suffix else '.work'+suffix)
  if p.exists():p.unlink()
 if _OWNED_JOB_LOCK is not None:_OWNED_JOB_LOCK.unlink();_OWNED_JOB_LOCK=None
 (output/'worker.json').write_bytes(canonical({'status':'complete','identity_sha256':sha(iraw),'manifest_sha256':sha(raw),'counts':dict(totals),'mesh_tiles':len(mesh_inventory),'catalog_pages':len(catalog_inventory),'resources':manifest['resources']}))
 return 0


def _supervise(args):
 started=time.monotonic();reason=None;peak=0
 proc=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),*sys.argv[1:],'--worker'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 try:
  while proc.poll() is None:
   text=subprocess.run(['/bin/ps','-o','rss=','-p',str(proc.pid)],capture_output=True,text=True).stdout.strip()
   if text:peak=max(peak,int(text)*1024)
   if peak>args.max_rss_mib*1024*1024:reason='Owned compiler exceeded2GiB supervised RSS';break
   if time.monotonic()-started>args.max_wall_seconds:reason='Owned compiler exceeded wall budget';break
   time.sleep(1)
 finally:
  if proc.poll() is None:
   proc.terminate()
   try:proc.wait(timeout=30)
   except subprocess.TimeoutExpired:proc.kill();proc.wait()
 receipt={'status':'complete' if proc.returncode==0 and reason is None else 'incomplete','reason':reason,'worker_exit':proc.returncode,'sampled_peak_rss_bytes':peak,'wall_seconds':round(time.monotonic()-started,3)}
 if (args.output_dir/'worker.json').exists():receipt['worker']=json.loads((args.output_dir/'worker.json').read_bytes())
 failure=args.output_dir/('failure-'+str(proc.pid)+'.json')
 if failure.exists():receipt['failure']=json.loads(failure.read_bytes())
 if args.output_dir.is_dir():(args.output_dir/('supervisor-'+str(os.getpid())+'.json')).write_bytes(canonical(receipt))
 print(json.dumps(receipt),flush=True);return 0 if receipt['status']=='complete' else 1

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--snapshot',type=Path,required=True);p.add_argument('--expected-snapshot-sha256',required=True)
 p.add_argument('--terrain',type=Path,required=True);p.add_argument('--expected-dem-identity',required=True);p.add_argument('--pbf',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True)
 p.add_argument('--world-y-mode',choices=[YMODE],required=True);p.add_argument('--world-y-offset',type=float,required=True);p.add_argument('--unknown-height',type=float,required=True);p.add_argument('--story-height',type=float,required=True)
 p.add_argument('--skip-id',action='append',default=[]);p.add_argument('--skip-envelope',type=float,nargs=4,action='append',default=[])
 p.add_argument('--resume',action='store_true');p.add_argument('--max-rss-mib',type=int,default=2048);p.add_argument('--max-cpu-seconds',type=int,default=3600);p.add_argument('--max-wall-seconds',type=int,default=7200);p.add_argument('--worker',action='store_true',help=argparse.SUPPRESS)
 args=p.parse_args()
 try:
  if not 64<=args.max_rss_mib<=2048 or not 60<=args.max_cpu_seconds<=7200 or not 60<=args.max_wall_seconds<=14400 or not 1<=args.unknown_height<=1000 or not .5<=args.story_height<=10 or not math.isfinite(args.world_y_offset) or abs(args.world_y_offset)>10000:raise CityError('Invalid explicit bounded city policy')
  if any(not all(math.isfinite(v) for v in b) or b[0]>=b[2] or b[1]>=b[3] for b in args.skip_envelope):raise CityError('Invalid explicit exclusion envelope')
  return _worker(args) if args.worker else _supervise(args)
 except Exception as e:
  receipt={'status':'incomplete','reason':str(e) if isinstance(e,CityError) else type(e).__name__+': source/compiler failure; no private input path emitted'}
  if args.worker and _OWNED_JOB_LOCK is not None:(args.output_dir/('failure-'+str(os.getpid())+'.json')).write_bytes(canonical(receipt))
  else:print(json.dumps(receipt))
  return 2
if __name__=='__main__':raise SystemExit(main())
