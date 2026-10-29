"""Terrain surface support admissions; not surveyed ground/hydrology proof."""
import json,math,struct,tempfile,unittest
from pathlib import Path
import numpy as np
from shapely.geometry import Polygon,box,mapping,Point
from compile_terrain_scene import (TerrainSceneError,root_masks,clip_support,mesh_tile,HaloHeights,sha)

class Plane:
 def h(self,tx,tz,x,z):return 5+x*.01+z*.02
 def normal(self,tx,tz,x,z):
  length=math.sqrt(1+.01*.01+.02*.02);return [-.01/length,1/length,-.02/length]

def triangles(blob,surface,anchor=(0,0)):
 out=[]
 for n in range(surface['index_count']//3):
  ix=struct.unpack_from('<3I',blob,surface['index_offset_bytes']+n*12)
  positions=[struct.unpack_from('<3f',blob,i*32) for i in ix]
  out.append((positions,Polygon([(p[0]+anchor[0],p[2]+anchor[1]) for p in positions])))
 return out

class TerrainSceneTests(unittest.TestCase):
 def test_country_is_not_land_only_actual_coast_enclosure_admitted(self):
  tile=box(0,0,1000,1000);support=clip_support([box(0,0,100,100)],[],[],tile)
  self.assertEqual(support.area,10000);self.assertFalse(support.covers(Point(500,500)))
 def test_canonical_water_and_root_hollow_holes_excluded(self):
  support=clip_support([box(0,0,100,100)],[box(10,10,20,20)],[box(40,40,60,60)],box(0,0,1000,1000))
  self.assertAlmostEqual(support.area,9500)
  self.assertFalse(support.covers(Point(15,15)));self.assertFalse(support.covers(Point(50,50)))
  data,detail=mesh_tile(0,0,support,Plane(),0.)
  self.assertIsNotNone(data);blob,surface=data
  tris=triangles(blob,surface)
  self.assertAlmostEqual(sum(p.area for _,p in tris),support.area,places=3)
  for _,p in tris:
   self.assertLess(p.intersection(box(10,10,20,20)).area,1e-6)
   self.assertLess(p.intersection(box(40,40,60,60)).area,1e-6)
 def test_height_normals_clockwise_and_anchor_before_float(self):
  support=box(80000,80000,80050,80050);data,detail=mesh_tile(80,80,support,Plane(),0.)
  blob,surface=data
  for points,_ in triangles(blob,surface,(80000,80000)):
   for p in points:
    self.assertLessEqual(abs(p[0]),50);self.assertLessEqual(abs(p[2]),50)
    self.assertAlmostEqual(p[1],5+(p[0]+80000)*.01+(p[2]+80000)*.02,places=3)
   a,b,c=[np.array(v) for v in points];self.assertLess(np.cross(b-a,c-a)[1],0)
  self.assertEqual(sha(blob),surface['topology_sha256'])
 def test_neighbor_seam_height_and_normal_identity(self):
  a,_=mesh_tile(0,0,box(975,0,1000,50),Plane(),0.);b,_=mesh_tile(1,0,box(1000,0,1025,50),Plane(),0.)
  def seam(data,tx):
   blob,s=data;out={}
   for i in range(s['vertex_count']):
    p=struct.unpack_from('<8f',blob,i*32)
    if p[0]+tx*1000==1000:out[p[2]]=p[1:2]+p[3:6]
   return out
  self.assertEqual(seam(a,0),seam(b,1))
 def test_unknown_dem_or_normal_never_zero_plane(self):
  class Unknown(Plane):
   def h(self,tx,tz,x,z):return None
  prepared,detail=mesh_tile(0,0,box(0,0,25,25),Unknown(),0.)
  self.assertIsNone(prepared);self.assertTrue(detail['unknown_grid_cells'])
  class UnknownNormal(Plane):
   def normal(self,tx,tz,x,z):return None
  prepared,detail=mesh_tile(0,0,box(0,0,25,25),UnknownNormal(),0.)
  self.assertIsNone(prepared)
 def test_root_masks_explicit_bound_and_provenanced(self):
  root={'schema':'terrain_root_holes_v1','snapshot_manifest_sha256':'a'*64,'masks':[{'mask_id':'source/test','geometry':mapping(box(1,1,2,2)),'source_feature_ids':['way/1'],'provenance':'Rootexplicitfixture'}]}
  self.assertEqual(len(root_masks(root,'a'*64)),1)
  with self.assertRaises(TerrainSceneError):root_masks(root,'b'*64)
  del root['masks'][0]['provenance']
  with self.assertRaises(TerrainSceneError):root_masks(root,'a'*64)
 def test_real_root_source_masks_and_real_dem_reference(self):
  root=Path(__file__).resolve().parents[3]
  doc=json.loads((root/'game/data/geography/mbs-root-holes.json').read_bytes());masks=root_masks(doc,'d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983')
  self.assertEqual(len(masks),5)
  union=__import__('shapely').ops.unary_union([g for _,g in masks])
  self.assertTrue(union.covers(Point(540,-1000)))
  dem=HaloHeights(root/'game/data/geography/terrain/mapzen-skadi-2026-10-28','5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841','d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983')
  self.assertAlmostEqual(dem.h(0,-1,500,-1000),5.989349365234375)
  self.assertTrue(all(math.isfinite(v) for v in dem.normal(0,-1,500,-1000)))

if __name__=='__main__':unittest.main()
