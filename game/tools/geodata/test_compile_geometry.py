"""Metre geometry/compiler contracts; no rendered city acceptance implied."""
import json
import math
from pathlib import Path
import tempfile
import unittest
from shapely.geometry import LineString, MultiLineString, MultiPolygon, Polygon, box, mapping
from shapely.ops import unary_union
from compile_geometry import (GeometryCompileError, canonical_bytes, compile_patch,
    explicit_measurements, region_source, sha, write_patch)
from build_spatial_index import SCHEMA as INDEX_SCHEMA, IndexErrorDetail

FRAME={'source_crs':'EPSG:4326','survey_crs':'EPSG:3414','origin_easting':30000.0,
       'origin_northing':30000.0,'metres_per_unit':1.0,'distance_compression':False,
       'world_axes':{'x':'south','y':'up','z':'west'}}

def feature(id,g,kind='building',tags=None,**extra):
    return {'id':id,'kind':kind,'geometry':mapping(g),'tags':tags or {},**extra}
def record(f,owner='0_0.json'):return {'feature':f,'owners':[owner]}
def run(features,region=None,chunk=100):
    return compile_patch({'georeference':FRAME},[record(f) for f in features],
                         region if region is not None else box(0,0,300,300),chunk_metres=chunk)
def fragments(compiled):
    return [(chunk,fragment) for chunk in compiled['chunks'].values() for fragment in chunk['fragments']]
def surface_triangles_world(chunk,surface):
    x,_,z=chunk['world_offset_xyz'];v=surface['vertices_local_xyz']
    return [Polygon([(v[i][0]+x,v[i][2]+z) for i in tri]) for tri in surface['triangles']]

def seal_fixture_index(base,index):
    """Publish only labeled synthetic test metadata; corruption remains unsealed."""
    data=canonical_bytes(index);(base/'index.json').write_bytes(data)
    descriptor={'schema':'singapore_country_dependency_identity_v1',
        'index_sha256':sha(data),'index_bytes':len(data),
        'snapshot_manifest_sha256':sha((base/'manifest.json').read_bytes()),
        'boundary_sha256':sha((base/'singapore-boundary.geojson').read_bytes()),
        **{k:index[k] for k in ('indexed_cells','owner_files','features_indexed')}}
    (base/'spatial-index.identity.json').write_bytes(canonical_bytes(descriptor))

class CompilerTests(unittest.TestCase):
    def test_holes_triangulated_without_filled_void_or_lost_area(self):
        p=Polygon([(10,10),(90,10),(90,90),(10,90)],holes=[[(30,30),(70,30),(70,70),(30,70)]])
        compiled=run([feature('way/1',p)])
        tris=[t for c,f in fragments(compiled) for t in surface_triangles_world(c,f['surface'])]
        self.assertAlmostEqual(sum(t.area for t in tris),p.area,places=8)
        self.assertTrue(unary_union(tris).equals(p))
        for t in tris:self.assertLess(t.intersection(box(30,30,70,70)).area,1e-9)
        s=fragments(compiled)[0][1]['surface'];self.assertEqual(len(s['rings_local_xz']),2)

    def test_multipart_footprint_retains_parts_and_single_source_identity(self):
        p=MultiPolygon([box(10,10,30,30),box(210,10,240,40)])
        compiled=run([feature('relation/2',p)])
        self.assertEqual(len(compiled['catalog']),1)
        self.assertEqual({f['source_part'] for _,f in fragments(compiled)},{0,1})
        self.assertEqual(compiled['catalog'][0]['source_geometry_world_xz'],mapping(p))
        self.assertAlmostEqual(compiled['report']['integrity']['compiled_surface_area_m2'],p.area)
        self.assertNotIn('1_0.json',compiled['chunks'])

    def test_cell_seam_crossing_has_no_area_or_feature_duplication(self):
        p=box(75,10,125,90);f=feature('way/3',p)
        compiled=run([f,f])
        self.assertEqual(len(compiled['catalog']),1)
        self.assertEqual(set(compiled['chunks']),{'0_0.json','1_0.json'})
        tris=[t for c,f in fragments(compiled) for t in surface_triangles_world(c,f['surface'])]
        self.assertAlmostEqual(sum(t.area for t in tris),p.area)
        self.assertTrue(unary_union(tris).equals(p))
        seam_positions=[]
        for c,frag in fragments(compiled):
            seam_positions.append({(v[0]+c['world_offset_xyz'][0],v[2]+c['world_offset_xyz'][2])
                for v in frag['surface']['vertices_local_xyz'] if v[0]+c['world_offset_xyz'][0]==100})
        self.assertEqual(seam_positions[0],seam_positions[1])

    def test_upward_winding_normals_and_collision_share_exact_topology(self):
        compiled=run([feature('way/4',box(10,10,80,80))])
        for _,f in fragments(compiled):
            s=f['surface'];v=s['vertices_local_xyz']
            self.assertEqual(s['normal_local_xyz'],[0.,1.,0.])
            for a,b,c in s['triangles']:
                a,b,c=v[a],v[b],v[c]
                normal_y=(b[2]-a[2])*(c[0]-a[0])-(b[0]-a[0])*(c[2]-a[2])
                self.assertGreater(normal_y,0)
            collision=s['collision_topology']
            self.assertEqual(collision['vertices_ref'],'vertices_local_xyz')
            self.assertEqual(collision['triangles_ref'],'triangles')
            self.assertEqual(collision['topology_sha256'],s['topology_sha256'])
            self.assertFalse(s['reference_plane_is_world_elevation'])

    def test_offsets_only_no_distance_scaling(self):
        p=box(-245.25,-180.5,-202.75,-111.25)
        compiled=run([feature('way/5',p)],box(-300,-200,-100,0))
        tris=[t for c,f in fragments(compiled) for t in surface_triangles_world(c,f['surface'])]
        self.assertTrue(unary_union(tris).equals(p))
        self.assertAlmostEqual(unary_union(tris).bounds[2]-unary_union(tris).bounds[0],42.5)
        for chunk in compiled['chunks'].values():self.assertEqual(chunk['scale_applied'],1.0)

    def test_centreline_crossing_and_direction_semantics_preserved(self):
        g=LineString([(220,40),(140,70),(10,20)])
        tags={'name':'Bayfront fixture','highway':'primary','bridge':'yes','tunnel':'no',
              'layer':'2','access':'permissive','oneway':'yes','width':'12.5 m'}
        f=feature('way/6',g,'road',tags)
        compiled=run([f]);catalog=compiled['catalog'][0]
        self.assertEqual(catalog['source_geometry_world_xz'],mapping(g))
        self.assertEqual(catalog['tags'],tags)
        self.assertEqual(catalog['semantic_tags']['bridge'],'yes')
        self.assertEqual(catalog['semantic_tags']['layer'],'2')
        self.assertEqual(catalog['explicit_measurements']['width_m'],12.5)
        self.assertAlmostEqual(compiled['report']['integrity']['compiled_path_length_m'],g.length)
        for _,frag in fragments(compiled):
            path=frag['path'];self.assertLess(path['source_distance_start_m'],path['source_distance_end_m'])
            self.assertTrue(path['road_surface_not_inferred'])

    def test_seam_aligned_path_owned_once_and_outer_edge_not_dropped(self):
        for x in (100,300):
            g=LineString([(x,10),(x,290)])
            compiled=run([feature('way/7',g,'road')])
            self.assertAlmostEqual(compiled['report']['integrity']['compiled_path_length_m'],280.)
            self.assertEqual(len(compiled['catalog']),1)
            self.assertEqual(len(compiled['chunks']),3)

    def test_partly_seam_aligned_and_retraced_paths_preserve_length_once(self):
        for points in [[(50,50),(100,50),(100,150),(150,150)],
                       [(10,50),(200,50),(10,50)]]:
            g=LineString(points);compiled=run([feature('way/77',g,'road')])
            self.assertAlmostEqual(compiled['report']['integrity']['compiled_path_length_m'],g.length)
            self.assertAlmostEqual(compiled['report']['integrity']['selected_source_path_length_m'],g.length)

    def test_boundary_path_survives_a_missing_positive_side_hole_cell(self):
        region=Polygon([(0,0),(300,0),(300,300),(0,300)],
                       holes=[[(100,100),(200,100),(200,200),(100,200)]])
        path=LineString([(100,110),(100,190)])
        c=run([feature('way/78',path,'road')],region)
        self.assertAlmostEqual(c['report']['integrity']['compiled_path_length_m'],80.)
        self.assertEqual(set(c['chunks']),{'0_1.json'})

    def test_boundary_ownership_splits_a_partially_present_neighbor_edge(self):
        region=Polygon([(0,0),(300,0),(300,300),(0,300)],
                       holes=[[(100,125),(200,125),(200,175),(100,175)]])
        path=LineString([(100,110),(100,190)])
        c=run([feature('way/79',path,'road')],region)
        lines=[]
        for chunk,fragment in fragments(c):
            x,_,z=chunk['world_offset_xyz']
            lines.append(LineString([(px+x,pz+z) for px,pz in fragment['path']['points_local_xz']]))
        self.assertAlmostEqual(sum(g.length for g in lines),80.)
        self.assertTrue(unary_union(lines).equals(path))
        # GEOS may preserve the hole boundary as a line component of the
        # positive-side clip. Either adjacent owner is valid; coverage and
        # lack of duplicated length, rather than a chosen filename, matter.
        self.assertTrue(all(region.covers(g) for g in lines))

    def test_region_clip_keeps_full_canonical_source_shape(self):
        g=LineString([(-1000,50),(1000,50)])
        compiled=run([feature('way/8',g,'road')],box(0,0,100,100))
        self.assertEqual(compiled['catalog'][0]['source_geometry_world_xz'],mapping(g))
        self.assertAlmostEqual(compiled['report']['integrity']['compiled_path_length_m'],100.)

    def test_unknown_heights_width_and_vertical_profile_not_inferred(self):
        f=feature('way/9',box(10,10,90,90),tags={'building:levels':'55'},height_m=None,height_status='unknown')
        compiled=run([f]);m=compiled['catalog'][0]
        self.assertIsNone(m['explicit_measurements']['height_m'])
        self.assertIsNone(m['explicit_measurements']['terrain_base_elevation_m'])
        self.assertEqual(m['renderer_assumptions'],[])
        self.assertEqual(compiled['report']['counts']['building_height_unknown'],1)
        tags={'width':'two lanes','lanes':'4','layer':'3','ele':'6.5','height':'30'}
        m=explicit_measurements(feature('way/10',LineString([(1,1),(2,2)]),'road',tags))
        self.assertIsNone(m['width_m']);self.assertIsNone(m['height_m'])
        self.assertEqual(m['elevation_tag_m'],6.5)

    def test_invalid_geometry_reported_without_silent_repair(self):
        g=Polygon([(10,10),(90,90),(90,10),(10,90),(10,10)])
        c=run([feature('way/11',g)])
        self.assertEqual(c['catalog'],[]);self.assertEqual(len(c['report']['issues']),1)
        self.assertEqual(c['chunks'],{})

    def test_deterministic_order_and_output_bytes(self):
        fs=[feature('way/13',box(110,10,190,90)),feature('way/12',box(10,10,90,90))]
        a=run(fs);b=run(list(reversed(fs)))
        self.assertEqual(canonical_bytes(a),canonical_bytes(b))
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'patch';report=write_patch(p,a)
            self.assertTrue((p/'manifest.json').is_file())
            manifest=json.loads((p/'manifest.json').read_bytes())
            self.assertEqual(sha((p/'features.json').read_bytes()),manifest['feature_catalog']['sha256'])
            for chunk in manifest['chunks']:self.assertEqual(sha((p/chunk['file']).read_bytes()),chunk['sha256'])
            with self.assertRaises(GeometryCompileError):write_patch(p,b)

    def test_conflicting_identity_is_not_arbitrarily_selected(self):
        with self.assertRaises(GeometryCompileError):run([feature('way/14',box(1,1,2,2)),feature('way/14',box(1,1,3,3))])

    def test_regional_dependencies_skip_unneeded_owner_and_verify_selected_hash(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)
            data=canonical_bytes({'tile':'0_0','features':[feature('way/15',box(10,10,90,90))]})
            (p/'0_0.json').write_bytes(data)
            boundary=canonical_bytes({'type':'Polygon','coordinates':[[[103,1],[104,1],[104,2],[103,2],[103,1]]]})
            (p/'singapore-boundary.geojson').write_bytes(boundary)
            m={'georeference':FRAME,'tile_metres':1000,'tiles':[
                {'file':'0_0.json','bytes':len(data),'sha256':sha(data),'features':1},
                {'file':'20_20.json','bytes':100,'sha256':'0'*64,'features':1}]}
            raw=canonical_bytes(m);(p/'manifest.json').write_bytes(raw)
            idx={'schema':INDEX_SCHEMA,'snapshot_manifest_sha256':sha(raw),'boundary_sha256':sha(boundary),
                'georeference':FRAME,'tile_metres':1000,'indexed_cells':2,'owner_files':2,'features_indexed':2,
                'cells':{'0_0':['0_0.json'],'20_20':['20_20.json']}}
            seal_fixture_index(p,idx)
            _,records,_,provenance=region_source(p,p/'index.json',(0,0,100,100))
            self.assertEqual(len(records),1);self.assertEqual(provenance['dependency_owner_count'],1)
            self.assertFalse((p/'20_20.json').exists())
            (p/'0_0.json').write_text('{}')
            with self.assertRaises(IndexErrorDetail):region_source(p,p/'index.json',(0,0,100,100))
            idx['cells']['0_0']=['../0_0.json'];seal_fixture_index(p,idx)
            with self.assertRaises(GeometryCompileError):region_source(p,p/'index.json',(0,0,100,100))

    def test_removed_cell_and_owner_cannot_publish_an_empty_region(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)
            data=canonical_bytes({'tile':'0_0','features':[feature('way/150',box(10,10,90,90))]})
            (p/'0_0.json').write_bytes(data)
            boundary=canonical_bytes({'type':'Polygon','coordinates':[[[103,1],[104,1],[104,2],[103,2],[103,1]]]})
            (p/'singapore-boundary.geojson').write_bytes(boundary)
            m={'georeference':FRAME,'tile_metres':1000,'tiles':[{'file':'0_0.json','bytes':len(data),'sha256':sha(data),'features':1}]}
            raw=canonical_bytes(m);(p/'manifest.json').write_bytes(raw)
            idx={'schema':INDEX_SCHEMA,'snapshot_manifest_sha256':sha(raw),'boundary_sha256':sha(boundary),
                 'georeference':FRAME,'tile_metres':1000,'indexed_cells':1,'owner_files':1,'features_indexed':1,
                 'cells':{'0_0':['0_0.json']}}
            seal_fixture_index(p,idx)
            idx['cells']={};(p/'index.json').write_bytes(canonical_bytes(idx))
            with self.assertRaisesRegex(GeometryCompileError,'identity'):
                region_source(p,p/'index.json',(0,0,100,100))
            idx['cells']={'0_0':[]};seal_fixture_index(p,idx)
            with self.assertRaisesRegex(GeometryCompileError,'omits'):
                region_source(p,p/'index.json',(0,0,100,100))
            idx['cells']={};seal_fixture_index(p,idx)
            with self.assertRaisesRegex(GeometryCompileError,'count'):
                region_source(p,p/'index.json',(0,0,100,100))

    def test_omitted_tags_explicitly_unassessed(self):
        c=run([feature('way/16',LineString([(10,10),(90,90)]),'road',{'highway':'construction'})])
        coverage=c['report']['attribute_coverage']
        self.assertIn('ele',coverage['unassessed_tags_without_patch_records'])
        self.assertIn('highway',coverage['observed_semantic_tags'])
        self.assertTrue(coverage['missing_is_not_false_or_absent_in_real_world'])
        self.assertIsNone(c['catalog'][0]['explicit_measurements']['width_m'])

    def test_source_frame_and_chunk_budget_enforced(self):
        m={'georeference':{**FRAME,'metres_per_unit':.1}}
        with self.assertRaises(IndexErrorDetail):compile_patch(m,[],box(0,0,1,1))
        with self.assertRaises(GeometryCompileError):run([],box(0,0,10000,10000),chunk=1)
        with self.assertRaises(GeometryCompileError):run([],chunk=0)

if __name__=='__main__':unittest.main()
