"""Directed source coastline contracts; not completed terrain acceptance."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
import osmium
from shapely.geometry import Polygon,box,mapping,shape
import georeference
from build_spatial_index import projected_country
from enrich_source_tags import canonical_bytes,sha_file
from extract_coastline import (CoastlineError,assemble_rings,assemble_land,build_document,
    scan_coastline,write_output)

COUNTRY=box(103.83,1.26,103.89,1.32)

def ring_points(a=103.85,b=1.28,size=.02,clockwise=False):
    p=[[a,b],[a+size,b],[a+size,b+size],[a,b+size],[a,b]]
    return list(reversed(p)) if clockwise else p

def data_ring(points,start=1,way='way/1'):
    ids=list(range(start,start+len(points)-1));refs=ids+[ids[0]]
    return {way:{'ordered_node_ids':refs,'source_tags':{'natural':'coastline'}}},{n:{'source_wgs84_lon_lat':p,'source_tags':{}} for n,p in zip(ids,points[:-1])}

def compile(ways,nodes,country=COUNTRY,**kw):
    return build_document(ways,nodes,country,projected_country(mapping(country)),{'pbf_sha256':'a'*64},**kw)

class CoastlineTests(unittest.TestCase):
    def test_directed_island_uses_land_left_in_projected_handedness(self):
        ways,nodes=data_ring(ring_points());doc=compile(ways,nodes)
        self.assertEqual(doc['counts']['closed_directed_valid_rings'],1)
        self.assertEqual(doc['closed_rings'][0]['land_left_role'],'land_interior')
        self.assertLess(doc['closed_rings'][0]['signed_area_xz_m2'],0)
        self.assertEqual(doc['counts']['country_clipped_source_land_features'],1)
        self.assertFalse(doc['acceptance']['terrain_or_rendered_city_completed'])

    def test_original_way_direction_node_identity_joins_without_reverse_or_snap(self):
        p=ring_points();nodes={i+1:{'source_wgs84_lon_lat':xy,'source_tags':{}} for i,xy in enumerate(p[:-1])}
        ways={'way/1':{'ordered_node_ids':[1,2,3],'source_tags':{'natural':'coastline'}},
              'way/2':{'ordered_node_ids':[3,4,1],'source_tags':{'natural':'coastline'}}}
        doc=compile(ways,nodes)
        self.assertEqual(doc['closed_rings'][0]['ordered_node_ids'],[1,2,3,4,1])
        self.assertFalse(doc['contract']['reversed_source_ways'])
        self.assertEqual(doc['closed_rings'][0]['source_way_ids_in_order'],['way/1','way/2'])

    def test_source_supported_hole_and_nested_island(self):
        outer,ns=data_ring(ring_points(size=.03));hole,hn=data_ring(ring_points(103.855,1.285,.02,True),10,'way/2')
        island,ins=data_ring(ring_points(103.86,1.29,.005),20,'way/3')
        ways={**outer,**hole,**island};nodes={**ns,**hn,**ins};doc=compile(ways,nodes)
        self.assertEqual(doc['counts']['water_interior_rings'],1)
        self.assertEqual(doc['counts']['country_clipped_source_land_features'],2)
        self.assertEqual(sum(len(shape(f['geometry']).interiors) for f in doc['land']['features']),1)
        self.assertEqual(doc['assembly_issues'],[])

    def test_orphan_clockwise_water_ring_does_not_fill_administrative_sea(self):
        ways,nodes=data_ring(ring_points(clockwise=True));doc=compile(ways,nodes)
        self.assertEqual(doc['land']['features'],[])
        self.assertTrue(any(i['issue']=='orphan_water_interior_ring_no_land_exterior_invented' for i in doc['assembly_issues']))
        self.assertFalse(doc['contract']['country_or_rectangle_filled_as_land'])

    def test_open_and_branching_chains_are_unresolved(self):
        ways,nodes=data_ring(ring_points());ways['way/1']['ordered_node_ids'].pop()
        opened=compile(ways,nodes)
        self.assertEqual(opened['land']['features'],[])
        self.assertIn('open_or_direction_mismatched_coastline_chain',opened['unresolved_components'][0]['issues'])
        ways,nodes=data_ring(ring_points());nodes[8]={'source_wgs84_lon_lat':[103.86,1.27],'source_tags':{}}
        ways['way/2']={'ordered_node_ids':[1,8],'source_tags':{'natural':'coastline'}}
        branched=compile(ways,nodes)
        self.assertEqual(branched['land']['features'],[])
        self.assertIn('ambiguous_branch_or_retraced_coastline',branched['unresolved_components'][0]['issues'])

    def test_same_xy_different_original_ids_never_close_chain(self):
        nodes={1:{'source_wgs84_lon_lat':[103.85,1.28]},2:{'source_wgs84_lon_lat':[103.86,1.28]},
               3:{'source_wgs84_lon_lat':[103.86,1.28]},4:{'source_wgs84_lon_lat':[103.85,1.28]}}
        ways={f'way/{i}':{'ordered_node_ids':refs,'source_tags':{'natural':'coastline'}} for i,refs in [(1,[1,2]),(2,[3,4])]}
        doc=compile(ways,nodes)
        self.assertEqual(doc['counts']['unresolved_source_components'],2)
        self.assertEqual(doc['land']['features'],[])

    def test_missing_invalid_duplicate_nodes_fail_closed(self):
        ways,nodes=data_ring(ring_points());del nodes[2]
        missing=compile(ways,nodes);self.assertEqual(missing['land']['features'],[])
        self.assertEqual(missing['unresolved_components'][0]['known_chain_country_scope'],'UNKNOWN')
        ways,nodes=data_ring(ring_points());nodes[2]['source_wgs84_lon_lat']=None
        invalid=compile(ways,nodes);self.assertEqual(invalid['land']['features'],[])
        ways,nodes=data_ring(ring_points());duplicate=compile(ways,nodes,duplicate_node_ids=[2])
        self.assertEqual(duplicate['land']['features'],[])

    def test_self_crossed_ring_is_not_buffer_repaired(self):
        points=[[103.85,1.28],[103.87,1.30],[103.87,1.28],[103.85,1.30],[103.85,1.28]]
        ways,nodes=data_ring(points);doc=compile(ways,nodes)
        self.assertEqual(doc['land']['features'],[])
        self.assertIn('invalid_closed_source_polygon_no_repair',doc['unresolved_components'][0]['issues'])

    def test_overlapping_and_same_orientation_nesting_excluded(self):
        a,an=data_ring(ring_points());b,bn=data_ring(ring_points(103.86,1.29,.02),10,'way/2')
        overlap=compile({**a,**b},{**an,**bn})
        self.assertEqual(overlap['land']['features'],[])
        a,an=data_ring(ring_points(size=.03));b,bn=data_ring(ring_points(103.855,1.285,.01),10,'way/2')
        nested=compile({**a,**b},{**an,**bn})
        self.assertEqual(nested['land']['features'],[])
        self.assertTrue(any(i['issue']=='nested_same_land_left_orientation_ambiguous' for i in nested['assembly_issues']))

    def test_projection_preserves_source_values_and_metre_units(self):
        ways,nodes=data_ring(ring_points());saved=deepcopy((ways,nodes));doc=compile(ways,nodes)
        ring=doc['closed_rings'][0]
        for lonlat,xz in zip(ring['source_wgs84_lon_lat'],ring['projected_world_xz']):
            x,_,z=georeference.from_wgs84(*lonlat)
            self.assertEqual(xz,[x,z])
        self.assertEqual(doc['contract']['metres_per_unit'],1.0)
        self.assertEqual((ways,nodes),saved)
        self.assertIsNone(doc['land']['features'][0]['properties']['terrain_elevation_m'])

    def test_country_clips_only_already_supported_land_not_sea(self):
        ways,nodes=data_ring(ring_points(size=.005));doc=compile(ways,nodes)
        land=shape(doc['land']['features'][0]['geometry']);country=projected_country(mapping(COUNTRY))
        self.assertLess(land.area,country.area*.02)
        self.assertTrue(country.covers(land))
        self.assertTrue(doc['contract']['clip_only_after_source_assembly'])
        self.assertFalse(doc['acceptance']['whole_country_land_coverage_certified'])

    def test_safe_deterministic_write_and_no_overwrite(self):
        ways,nodes=data_ring(ring_points());doc=compile(ways,nodes)
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);receipt=write_output(p,doc,ways,nodes)
            self.assertEqual(receipt['status'],'complete')
            self.assertNotIn('/private/tmp/',canonical_bytes(receipt).decode())
            with self.assertRaises(CoastlineError):write_output(p,doc,ways,nodes)

    def test_native_pbf_tag_filter_preserves_only_coastline_not_water(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'coast.osm.pbf';writer=osmium.SimpleWriter(str(p));points=ring_points(size=.005)
            for n,loc in enumerate(points[:-1],1):writer.add_node(osmium.osm.mutable.Node(id=n,location=loc,tags={'ele':'1.2'} if n==1 else {}))
            writer.add_way(osmium.osm.mutable.Way(id=10,nodes=[1,2,3,4,1],tags={'natural':'coastline','name':'Source island','tidal':'yes'}))
            writer.add_way(osmium.osm.mutable.Way(id=11,nodes=[1,2,3,4,1],tags={'natural':'water','water':'lake'}));writer.close()
            ways,nodes,header=scan_coastline(p,sha_file(p))
            self.assertEqual(set(ways.ways),{'way/10'})
            self.assertEqual(ways.ways['way/10']['ordered_node_ids'],[1,2,3,4,1])
            self.assertEqual(ways.ways['way/10']['source_tags']['tidal'],'yes')
            self.assertEqual(nodes.nodes[1]['source_tags']['ele'],'1.2')
            doc=compile(ways.ways,nodes.nodes)
            self.assertEqual(doc['counts']['country_clipped_source_land_features'],1)
            self.assertTrue(doc['contract']['inland_water_is_not_coastline'])
            self.assertFalse(doc['contract']['terrain_elevation_inferred'])
            with self.assertRaises(CoastlineError):scan_coastline(p,'0'*64)

class CoastlineBindingTests(unittest.TestCase):
    def test_native_cli_exact_country_binding_failure_and_existing_output_safety(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);source=p/'source.osm.pbf';writer=osmium.SimpleWriter(str(source));writer.close()
            manifest={'pbf_sha256':sha_file(source),'source_snapshot_utc':None,'georeference':georeference.manifest()}
            (p/'manifest.json').write_bytes(canonical_bytes(manifest))
            (p/'country.json').write_bytes(canonical_bytes(mapping(COUNTRY)))
            command=[sys.executable,str(Path(__file__).with_name('extract_coastline.py')),
                '--pbf',str(source),'--expected-pbf-sha256',manifest['pbf_sha256'],
                '--snapshot-manifest',str(p/'manifest.json'),'--country',str(p/'country.json'),
                '--expected-country-sha256','0'*64,'--output-dir',str(p/'new-output')]
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            receipt=json.loads((p/'new-output/supervisor.json').read_bytes())
            self.assertEqual(receipt['status'],'incomplete')
            self.assertIn('country',receipt['failure']['reason'])
            self.assertNotIn(str(p),canonical_bytes(receipt).decode())
            before=(p/'new-output/supervisor.json').read_bytes()
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual((p/'new-output/supervisor.json').read_bytes(),before)

if __name__=='__main__':unittest.main()
