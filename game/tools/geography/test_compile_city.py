"""Renderable source footprint/collision geometry; not full city acceptance."""
import array,json,math,sqlite3,struct,tempfile,unittest,sys
from pathlib import Path
import numpy as np
import osmium
from shapely.geometry import Polygon,box,Point
from compile_city import (CityError,height_policy,building_fragments,_db,_road_record,RoadCollector,
 _mesh_blob,exclusive_or_same,TerrainGrid,sha,YMODE,canonical,SCHEMA,IDENTITY,FRAME)

ROOT=Path(__file__).resolve().parents[3]
def feature(**values):return {'id':'way/1','kind':'building','tags':{},'height_m':None,'height_status':'unknown',**values}
def vertices(surface):return [struct.unpack_from('<8f',surface['vertex_bytes'],i*32) for i in range(surface['vertex_count'])]
def indices(surface):return [struct.unpack_from('<3I',surface['index_bytes'],i*12) for i in range(surface['index_count']//3)]

class CityGeometryTests(unittest.TestCase):
 def test_explicit_game_height_policy_retains_source_facts(self):
  p=height_policy(feature(tags={'building:levels':'8'},height_m=40,height_status='source_tag'),9.6,3.2)
  self.assertEqual(p['game_top_height_m'],40);self.assertTrue(p['height_is_source_fact']);self.assertEqual(p['source_levels_tag'],'8')
  p=height_policy(feature(tags={'building:levels':'8'}),9.6,3.2)
  self.assertEqual(p['game_top_height_m'],25.6);self.assertFalse(p['height_is_source_fact']);self.assertIn('reconstruction',p['height_policy'])
  p=height_policy(feature(),9.6,3.2)
  self.assertEqual(p['game_top_height_m'],9.6);self.assertIsNone(p['source_height_m']);self.assertIn('reconstruction',p['height_policy'])
 def test_minimum_height_and_level_kept_separate(self):
  p=height_policy(feature(tags={'min_height':'12','building:min_level':'2'},height_m=40),9.6,3.2)
  self.assertEqual(p['game_bottom_height_m'],12);self.assertEqual(p['bottom_policy'],'source_min_height_tag')
  p=height_policy(feature(tags={'building:min_level':'2'}),9.6,3.2)
  self.assertEqual(p['game_bottom_height_m'],6.4);self.assertIn('reconstruction',p['bottom_policy'])
 def test_roof_and_bottom_preserve_courtyard_hole(self):
  poly=Polygon([(0,0),(10,0),(10,10),(0,10)],holes=[[(3,3),(7,3),(7,7),(3,7)]])
  fragments=building_fragments(poly,2.,12.,0.)
  roof=next(s for s in fragments[(0,0)] if s['role']=='roof');v=vertices(roof)
  triangles=[Polygon([(v[i][0],v[i][2]) for i in tri]) for tri in indices(roof)]
  self.assertAlmostEqual(sum(t.area for t in triangles),84)
  self.assertTrue(all(t.intersection(box(3,3,7,7)).area==0 for t in triangles))
  self.assertTrue(all(p[1]==14. for p in v))
  bottom=next(s for s in fragments[(0,0)] if s['role']=='underside')
  self.assertTrue(all(p[1]==2. for p in vertices(bottom)))
 def test_mesh_winding_normals_collision_topology_and_local_anchor(self):
  fragments=building_fragments(box(80002,80002,80012,80012),0.,12.,0.)
  self.assertEqual(set(fragments),{(80,80)})
  for surface in fragments[(80,80)]:
   v=vertices(surface)
   self.assertLess(max(abs(p[0]) for p in v),1000)
   for tri in indices(surface):
    a,b,c=[np.array(v[i][:3]) for i in tri];normal=np.cross(b-a,c-a)
    expected=np.array(v[tri[0]][3:6]);self.assertLess(float(np.dot(normal,expected)),0)
   self.assertEqual(surface['topology_sha256'],sha(surface['vertex_bytes']+surface['index_bytes']))
 def test_spanning_feature_has_no_artificial_tile_partition_walls(self):
  poly=box(990,10,1010,30);parts=building_fragments(poly,0.,12.,0.)
  self.assertEqual(set(parts),{(0,0),(1,0)})
  area=0.;partition_walls=0
  for (tx,tz),surfaces in parts.items():
   for surface in surfaces:
    v=vertices(surface)
    if surface['role']=='roof':
     area+=sum(Polygon([(v[i][0]+tx*1000,v[i][2]+tz*1000) for i in tri]).area for tri in indices(surface))
    if surface['role'].endswith('walls'):
     for tri in indices(surface):
      if all(v[i][0]+tx*1000==1000 for i in tri):partition_walls+=1
  self.assertAlmostEqual(area,400.);self.assertEqual(partition_walls,0)
 def test_original_wall_on_boundary_owned_once(self):
  parts=building_fragments(box(990,10,1000,30),0.,10.,0.)
  self.assertEqual(set(parts),{(0,0)})
  walls=next(s for s in parts[(0,0)] if s['role'].endswith('walls'))
  self.assertEqual(walls['index_count']//3,8)
 def test_fragment_binary_offsets_and_exclusive_replay(self):
  surfaces=building_fragments(box(1,1,3,3),0.,10.,0.)[(0,0)];blob,rows=_mesh_blob(surfaces)
  for row,surface in zip(rows,surfaces):
   self.assertEqual(blob[row['vertex_offset_bytes']:row['vertex_offset_bytes']+row['vertex_count']*32],surface['vertex_bytes'])
   self.assertEqual(blob[row['index_offset_bytes']:row['index_offset_bytes']+row['index_count']*4],surface['index_bytes'])
  with tempfile.TemporaryDirectory() as t:
   p=Path(t)/'new';exclusive_or_same(p,b'owned');exclusive_or_same(p,b'owned')
   with self.assertRaises(CityError):exclusive_or_same(p,b'different')
   self.assertEqual(p.read_bytes(),b'owned')
 def test_original_road_nodes_directions_and_grade_not_xy_graph(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t);db=_db(p/'work.sqlite');db.execute("insert into roads(id) values('way/17')");db.commit()
   source=p/'roads.osm.pbf';w=osmium.SimpleWriter(str(source));tags={'highway':'primary','oneway':'-1','bridge':'yes','layer':'2','name:zh':'海湾路'}
   w.add_way(osmium.osm.mutable.Way(id=17,nodes=[10,11,10,12],tags=tags));w.close()
   c=RoadCollector(db,{17});reader=osmium.io.Reader(str(source),osmium.osm.osm_entity_bits.WAY)
   try:osmium.apply(reader,osmium.filter.KeyFilter('highway'),c)
   finally:reader.close()
   f={'id':'way/17','tags':{'highway':'primary','oneway':'-1'},'geometry':{'coordinates':[[1000,0],[1001,0],[1000,0],[1000,1]]}}
   row=_road_record(f,'1_0.json',db,[1000,0,0])
   self.assertEqual(row['original_ordered_node_ids'],[10,11,10,12]);self.assertEqual(row['full_source_tags'],tags)
   self.assertTrue(row['no_xy_merge_or_legal_bidirectional_inference']);self.assertFalse(row['mesh_or_collision_generated'])
   self.assertEqual(row['source_contract_issues'],[])
   # Same-job metadata pass can resume without treating earlier committed rows as new duplicates.
   c=RoadCollector(db,{17});reader=osmium.io.Reader(str(source),osmium.osm.osm_entity_bits.WAY)
   try:osmium.apply(reader,osmium.filter.KeyFilter('highway'),c)
   finally:reader.close()
   db.close()
 def test_native_fixture_uses_production_mesh_offsets_and_safe_outputs(self):
  with tempfile.TemporaryDirectory() as t:
   out=Path(t)/'fixture';receipt=write_native_fixture(out)
   identity=json.loads((out/'identity.json').read_bytes());manifest=json.loads((out/'manifest.json').read_bytes())
   self.assertEqual(receipt['identity_sha256'],sha((out/'identity.json').read_bytes()))
   self.assertEqual(identity['manifest']['sha256'],sha((out/'manifest.json').read_bytes()))
   self.assertEqual(len(manifest['meshes']),2)
   for item in manifest['meshes']:
    raw=(out/item['binary_file']).read_bytes();self.assertEqual(sha(raw),item['binary_sha256'])
    meta=json.loads((out/item['file']).read_bytes())
    for f in meta['features']:
     for surface in f['surfaces']:
      begin=surface['vertex_offset_bytes'];end=surface['index_offset_bytes']+surface['index_count']*4
      self.assertEqual(sha(raw[begin:end]),surface['topology_sha256'])
   with self.assertRaises(CityError):write_native_fixture(out)

 def test_actual_dem_is_separate_explicit_base_input(self):
  d=ROOT/'game/data/geography/terrain/mapzen-skadi-2026-10-28'
  terrain=TerrainGrid(d,'5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841','d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983')
  self.assertAlmostEqual(terrain.sample(500,-1000),5.989349365234375)
  self.assertIsNone(terrain.sample(5e6,5e6))
  self.assertEqual(YMODE,'EGM96_DEM_game_world_reference_not_current_survey')

def write_native_fixture(output):
 if output.exists():raise CityError('Native fixture output already exists')
 (output/'meshes').mkdir(parents=True);(output/'catalogs').mkdir()
 a=Polygon([(80002,80002),(80012,80002),(80012,80012),(80002,80012)],holes=[[(80005,80005),(80009,80005),(80009,80009),(80005,80009)]])
 b=box(80990,80020,81010,80040);by_tile={};catalog=[]
 for id,g,height in [('way/10001',a,12.),('way/10002',b,9.6)]:
  key='building|'+id;frags=building_fragments(g,0.,height,0.)
  catalog.append({'feature_key':key,'id':id,'kind':'building','name':'SYNTHETIC_QA_NOT_SINGAPORE',
   'status':'synthetic_geometry_fixture','source_bounds_xz':list(g.bounds),'mesh_tiles':[f'{t[0]}_{t[1]}' for t in frags],
   'height':{'height_is_source_fact':False,'game_top_height_m':height},'source_feature_sha256':'f'*64})
  for tile,surfaces in frags.items():by_tile.setdefault(tile,[]).append((key,surfaces))
 owner={'schema':SCHEMA,'owner':'80_80','anchor_source_xyz':[80000.,0.,80000.],'features':catalog}
 raw=canonical(owner);(output/'catalogs/80_80.json').write_bytes(raw)
 catalogs=[{'key':'80_80','file':'catalogs/80_80.json','bytes':len(raw),'sha256':sha(raw)}];meshes=[]
 for (tx,tz),records in by_tile.items():
  key=f'{tx}_{tz}';blob=bytearray();entries=[]
  for feature_key,surfaces in records:
   chunk,rows=_mesh_blob(surfaces);offset=len(blob)
   for row in rows:row['vertex_offset_bytes']+=offset;row['index_offset_bytes']+=offset
   blob.extend(chunk);entries.append({'feature_key':feature_key,'catalog_owner':'80_80','surfaces':rows,'logical_feature_source_sha256':'f'*64})
  data=bytes(blob);(output/('meshes/'+key+'.mesh')).write_bytes(data)
  meta={'schema':SCHEMA,'tile_xz':[tx,tz],'anchor_source_xyz':[tx*1000.,0.,tz*1000.],
   'binary':{'file':key+'.mesh','bytes':len(data),'sha256':sha(data)},'features':entries,
   'terrain_reference':{'dataset_identity_sha256':'b'*64,'physical_support_or_dryland':False}}
  raw=canonical(meta);(output/('meshes/'+key+'.json')).write_bytes(raw)
  meshes.append({'key':key,'file':'meshes/'+key+'.json','bytes':len(raw),'sha256':sha(raw),'binary_file':'meshes/'+key+'.mesh','binary_bytes':len(data),'binary_sha256':sha(data),'features':len(entries)})
 manifest={'schema':SCHEMA,'version':1,'bindings':{'snapshot_sha':'a'*64,'dem_identity':'b'*64},'georeference':FRAME,
  'world_y_policy':{'mode':YMODE,'offset_m':0.,'architecture_datum_alignment_verified':False},
  'mesh_format':{'stride_bytes':32,'index_bytes':4,'byte_order':'little','local_anchor_subtracted_before_float':True,'front_face_winding':'godot_clockwise_cross_opposite_outward_normal'},
  'meshes':meshes,'catalogs':catalogs,'counts':{'SYNTHETIC_NOT_NATIONAL':2},'exclusions':[]}
 raw=canonical(manifest);(output/'manifest.json').write_bytes(raw)
 identity={'schema':IDENTITY,'version':1,'snapshot_sha256':'a'*64,'dem_identity_sha256':'b'*64,
  'manifest':{'file':'manifest.json','bytes':len(raw),'sha256':sha(raw)}}
 raw=canonical(identity);(output/'identity.json').write_bytes(raw)
 return {'identity_sha256':sha(raw),'directory':str(output),'scope':'Synthetic native mesh/collision/precision fixture only'}

if __name__=='__main__':
 if len(sys.argv)==3 and sys.argv[1]=='--write-native-fixture':print(json.dumps(write_native_fixture(Path(sys.argv[2]))))
 else:unittest.main()
