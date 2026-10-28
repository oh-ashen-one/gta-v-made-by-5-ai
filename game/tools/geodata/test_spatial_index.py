"""Analytic dependency fixtures; not physical city/gameplay acceptance."""
import hashlib,json,tempfile,unittest
from pathlib import Path
from shapely.geometry import box,LineString,MultiPolygon,Polygon,mapping
from build_spatial_index import build_index,read_owners,IndexErrorDetail
FRAME={'source_crs':'EPSG:4326','origin_easting':30000.0,'origin_northing':30000.0,'metres_per_unit':1.0,'distance_compression':False,'survey_crs':'EPSG:3414','world_axes':{'x':'south','y':'up','z':'west'}}
def feature(identifier,geometry,kind='road'):
 return {'id':identifier,'kind':kind,'tags':{},'geometry':mapping(geometry)}
def source(names):
 return {'georeference':FRAME,'tile_metres':1000,'tiles':[{'file':n} for n in names]}
def make(owners,country=box(-500,-500,3500,3500)):
 return build_index(source([n for n,_ in owners]),owners,country,manifest_sha256='a'*64,boundary_sha256='b'*64)
class IndexTests(unittest.TestCase):
 def test_long_crossing_far_from_centroid_owner(self):
  r=make([('1_0.json',[feature('way/1',LineString([(-100,100),(3100,100)]))])])
  for k in ['-1_0','0_0','1_0','2_0','3_0']:self.assertEqual(r['cells'][k],['1_0.json'])
 def test_country_hole_is_not_bbox_substitute(self):
  country=Polygon([(-100,-100),(3100,-100),(3100,3100),(-100,3100)],holes=[[(900,900),(2100,900),(2100,2100),(900,2100)]])
  r=make([('1_1.json',[feature('way/1',LineString([(1200,1500),(1800,1500)]))])],country)
  self.assertNotIn('1_1',r['cells'])
 def test_geometry_crossing_country_with_outside_centroid(self):
  r=make([('-10_0.json',[feature('way/1',LineString([(-20000,100),(100,100)]))])],box(0,0,1000,1000))
  self.assertEqual(r['cells']['0_0'],['-10_0.json']);self.assertNotIn('-1_0',r['cells'])
 def test_multipart_footprint_references_both_islands_not_gap(self):
  r=make([('1_0.json',[feature('relation/2',MultiPolygon([box(10,10,30,30),box(3010,10,3030,30)]),'building')])])
  self.assertIn('0_0',r['cells']);self.assertIn('3_0',r['cells']);self.assertNotIn('1_0',r['cells'])
 def test_same_owner_is_not_duplicated_per_cell(self):
  r=make([('0_0.json',[feature('way/1',box(0,0,50,50),'building'),feature('way/1',LineString([(0,0),(50,50)]))])])
  self.assertEqual(r['cells']['0_0'],['0_0.json']);self.assertEqual(r['features_indexed'],2)
 def test_invalid_source_geometry_is_not_silently_repaired(self):
  g=Polygon([(0,0),(100,100),(100,0),(0,100),(0,0)])
  r=make([('0_0.json',[feature('way/3',g,'building')])]);self.assertEqual(len(r['invalid_source_geometries']),1)
  self.assertIn('0_0',r['cells'])
 def test_unsafe_owner_path_refused(self):
  with self.assertRaises(IndexErrorDetail):make([('../0_0.json',[])])
 def test_compressed_frame_refused(self):
  m=source(['0_0.json']);m['georeference']={**FRAME,'distance_compression':True}
  with self.assertRaises(IndexErrorDetail):build_index(m,[('0_0.json',[])],box(0,0,1,1),manifest_sha256='x',boundary_sha256='y')
 def test_shifted_origin_refused(self):
  m=source(['0_0.json']);m['georeference']={**FRAME,'origin_easting':0.0}
  with self.assertRaises(IndexErrorDetail):build_index(m,[('0_0.json',[])],box(0,0,1,1),manifest_sha256='x',boundary_sha256='y')
 def test_missing_owner_not_partial_success(self):
  with self.assertRaises(IndexErrorDetail):build_index(source(['0_0.json']),[],box(0,0,1,1),manifest_sha256='x',boundary_sha256='y')
 def test_actual_tile_hash_and_count_validation(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t);data=json.dumps({'tile':'0_0','features':[]}).encode();(p/'0_0.json').write_bytes(data)
   m={'tiles':[{'file':'0_0.json','sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'features':0}]}
   self.assertEqual(list(read_owners(p,m)),[('0_0.json',[])])
   (p/'0_0.json').write_text('{}')
   with self.assertRaises(IndexErrorDetail):list(read_owners(p,m))
 def test_symlink_tile_refused(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t);(p/'other').write_text('{}');(p/'0_0.json').symlink_to(p/'other')
   with self.assertRaises(IndexErrorDetail):list(read_owners(p,{'tiles':[{'file':'0_0.json'}]}))
if __name__=='__main__':unittest.main()
