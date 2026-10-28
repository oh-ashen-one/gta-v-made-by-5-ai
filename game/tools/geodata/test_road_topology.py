"""Source-node identity topology, deliberately not vehicle route acceptance."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
import osmium
import georeference
from extract_road_topology import (TopologyError,WayNodeCollector,build_topology,
    scan_way_references,select_targets,write_topology,SourceNodeCollector,
    scan_source_nodes,verify_original_node_coordinates)
from enrich_source_tags import (EnrichmentError,canonical_bytes,input_binding,sha,sha_file)

BIND={'pbf_sha256':'1'*64,'source_snapshot_utc':'2026-10-27T21:23:59Z',
      'regional_source_catalog_sha256':'2'*64,'canonical_snapshot_manifest_sha256':'3'*64,
      'geometry_patch_manifest_sha256':'4'*64}
ATTR={'attribution':'© OpenStreetMap contributors','data_license':'ODbL-1.0',
      'source_url':'https://example.org/source','license_url':'https://www.openstreetmap.org/copyright'}
def feature(id,coords,tags=None,kind='road'):
    return {'id':id,'kind':kind,'feature_key':kind+'|'+id,'tags':tags or {},'source_feature_sha256':'a'*64,
            'source_geometry_world_xz':{'type':'LineString','coordinates':coords}}
def source(refs,tags=None):return {'ordered_node_ids':refs,'source_tags':tags or {},'osm_metadata':{'version':3}}
def run(fs,found,kinds=('road',),**kw):return build_topology(select_targets(fs,kinds),found,BIND,ATTR,**kw)

class TopologyTests(unittest.TestCase):
    def test_at_grade_shared_original_node_has_all_index_associations(self):
        fs=[feature('way/1',[[0,0],[1,0],[2,0]]),feature('way/2',[[1,-1],[1,0],[1,1]])]
        doc=run(fs,{'way/1':source([10,11,12]),'way/2':source([20,11,21])})
        self.assertTrue(doc['audit']['ready_for_source_identity_topology'])
        self.assertEqual(doc['audit']['shared_between_source_ways_nodes'],1)
        node=doc['nodes']['11'];self.assertEqual(len(node['associations']),2)
        self.assertEqual(node['source_neighbor_node_ids'],[10,12,20,21])
        self.assertEqual({a['node_index'] for a in node['associations']},{1})

    def test_grade_separated_xy_crossing_with_distinct_ids_not_connected(self):
        fs=[feature('way/1',[[0,0],[2,0]],{'bridge':'yes','layer':'1'}),
            feature('way/2',[[1,-1],[1,1]],{'tunnel':'yes','layer':'-1'})]
        found={'way/1':source([10,11],fs[0]['tags']),'way/2':source([20,21],fs[1]['tags'])}
        doc=run(fs,found)
        self.assertEqual(doc['audit']['shared_between_source_ways_nodes'],0)
        self.assertEqual(set(doc['nodes']),{'10','11','20','21'})
        self.assertEqual(doc['nodes']['10']['source_neighbor_node_ids'],[11])
        self.assertFalse(doc['contract']['connect_by_xy_intersection'])

    def test_equal_xy_endpoints_with_different_ids_stay_separate(self):
        fs=[feature('way/1',[[0,0],[1,0]]),feature('way/2',[[1,0],[2,0]])]
        doc=run(fs,{'way/1':source([1,2]),'way/2':source([3,4])})
        self.assertEqual(doc['audit']['shared_between_source_ways_nodes'],0)
        self.assertEqual(doc['nodes']['2']['source_neighbor_node_ids'],[1])
        self.assertEqual(doc['nodes']['3']['source_neighbor_node_ids'],[4])

    def test_negative_oneway_and_roundabout_tags_preserved_without_inference(self):
        tags={'oneway':'-1','junction':'roundabout','bicycle':'yes','name:zh':'滨海大道','highway':'proposed','proposed':'primary'}
        doc=run([feature('way/1',[[0,0],[1,0]],tags)],{'way/1':source([1,2],tags)})
        way=doc['ways']['way/1'];self.assertEqual(way['source_tags'],tags)
        self.assertEqual(way['semantic_tags']['oneway'],'-1')
        self.assertEqual(way['multilingual_names']['name:zh'],'滨海大道')
        self.assertEqual(doc['source_segments']['way/1@0']['from_node_id'],1)
        self.assertEqual(doc['contract']['routable_vehicle_classification'],'unassessed')
        self.assertNotIn('allowed_travel_arcs',doc)

    def test_same_way_multiple_logical_roles_do_not_duplicate_segments(self):
        coords=[[0,0],[1,0],[2,0]]
        fs=[feature('way/1',coords,kind='road'),feature('way/1',coords,kind='waterway')]
        doc=run(fs,{'way/1':source([1,2,3])},kinds=('road','waterway'))
        self.assertEqual(len(doc['ways']),1);self.assertEqual(len(doc['source_segments']),2)
        self.assertEqual(len(doc['nodes']['2']['associations']),2)
        self.assertEqual(doc['source_segments']['way/1@0']['feature_keys'],['road|way/1','waterway|way/1'])

    def test_closed_retraced_order_and_repeated_indices_survive(self):
        fs=[feature('way/1',[[0,0],[1,0],[0,0],[0,1],[0,0]])]
        refs=[1,2,1,3,1];doc=run(fs,{'way/1':source(refs)})
        self.assertEqual(doc['ways']['way/1']['ordered_node_ids'],refs)
        self.assertTrue(doc['ways']['way/1']['closed_by_node_identity'])
        self.assertEqual([a['node_index'] for a in doc['nodes']['1']['associations']],[0,2,4])
        self.assertEqual([a['node_index'] for a in doc['nodes']['1']['endpoint_associations']],[0,4])
        self.assertEqual(len(doc['source_segments']),4)

    def test_node_count_mismatch_is_unresolved_without_truncation(self):
        fs=[feature('way/1',[[0,0],[1,0],[2,0]])]
        doc=run(fs,{'way/1':source([1,2])})
        self.assertFalse(doc['audit']['ready_for_source_identity_topology'])
        self.assertEqual(doc['ways']['way/1']['ordered_node_ids'],[1,2])
        self.assertEqual(doc['nodes'],{});self.assertEqual(doc['source_segments'],{})
        self.assertEqual(doc['audit']['issues'][0]['type'],'node_coordinate_count_mismatch')

    def test_shared_node_coordinate_mismatch_is_unresolved(self):
        fs=[feature('way/1',[[0,0],[1,0]]),feature('way/2',[[1.1,0],[2,0]])]
        doc=run(fs,{'way/1':source([1,2]),'way/2':source([2,3])})
        self.assertFalse(doc['audit']['ready_for_source_identity_topology'])
        self.assertEqual(doc['nodes']['2']['coordinate_status'],'unresolved_shared_node_coordinate_conflict')
        self.assertEqual(doc['ways']['way/1']['status'],'unresolved_shared_node_coordinate_conflict')
        self.assertEqual(doc['ways']['way/2']['status'],'unresolved_shared_node_coordinate_conflict')

    def test_rounding_allowance_not_averaged_or_rescaled(self):
        fs=[feature('way/1',[[0,0],[1,0]]),feature('way/2',[[1.00009,0],[2,0]])]
        doc=run(fs,{'way/1':source([1,2]),'way/2':source([2,3])})
        self.assertTrue(doc['audit']['ready_for_source_identity_topology'])
        self.assertEqual(doc['nodes']['2']['canonical_reference_position_world_xz'],[1,0])
        self.assertEqual(doc['nodes']['2']['associations'][1]['canonical_position_world_xz'],[1.00009,0])
        self.assertFalse(doc['audit']['source_node_locations_independently_projected'])

    def test_rounding_allowance_checks_pairwise_extent_not_just_first_reference(self):
        fs=[feature('way/1',[[0,0],[1,0]]),feature('way/2',[[1.00009,0],[2,0]]),
            feature('way/3',[[.99991,0],[3,0]])]
        doc=run(fs,{'way/1':source([1,2]),'way/2':source([2,3]),'way/3':source([2,4])})
        self.assertFalse(doc['audit']['ready_for_source_identity_topology'])
        self.assertGreater(doc['nodes']['2']['max_axis_coordinate_delta_m'],.0001)

    def test_missing_way_and_duplicate_source_way_fail_closed(self):
        fs=[feature('way/1',[[0,0],[1,0]])];targets=select_targets(fs)
        missing=build_topology(targets,{},BIND,ATTR)
        self.assertFalse(missing['audit']['ready_for_source_identity_topology'])
        self.assertEqual(missing['audit']['missing_source_ways'],['way/1'])
        self.assertIsNone(missing['ways']['way/1']['ordered_node_ids'])
        c=WayNodeCollector(targets);c.observe(1,[1,2],{},{});c.observe(1,[3,4],{},{})
        duplicate=build_topology(targets,c.found,BIND,ATTR,duplicate_source_ids=c.duplicate_source_ids)
        self.assertFalse(duplicate['audit']['ready_for_source_identity_topology'])
        self.assertEqual(duplicate['ways']['way/1']['ordered_node_ids'],[1,2])

    def test_source_tag_conflict_does_not_accept_graph(self):
        fs=[feature('way/1',[[0,0],[1,0]],{'oneway':'-1'})]
        doc=run(fs,{'way/1':source([1,2],{'oneway':'yes'})})
        self.assertFalse(doc['audit']['ready_for_source_identity_topology'])
        self.assertEqual(doc['nodes'],{})
        self.assertEqual(doc['audit']['issues'][0]['type'],'canonical_tag_conflict')

    def test_header_binding_conflict_fails_closed(self):
        doc=run([feature('way/1',[[0,0],[1,0]])],{'way/1':source([1,2])},header_metadata={'osmosis_replication_timestamp':'different'})
        self.assertFalse(doc['audit']['ready_for_source_identity_topology'])
        self.assertTrue(doc['audit']['header_snapshot_time_conflict'])

    def test_typed_source_and_geometry_contracts(self):
        for f in [feature('relation/1',[[0,0],[1,0]]),
                  {**feature('way/1',[[0,0],[1,0]]),'source_geometry_world_xz':{'type':'MultiLineString','coordinates':[[[0,0],[1,0]]]}},
                  feature('way/1',[[0,0],[float('nan'),0]])]:
            with self.assertRaises(TopologyError):select_targets([f])
        c=WayNodeCollector(select_targets([feature('way/1',[[0,0],[1,0]])]))
        for id,refs in [(True,[1,2]),(1,[1,-2]),(1,[1,True])]:
            with self.assertRaises(TopologyError):c.observe(id,refs,{},{})

    def test_native_pbf_node_references_require_no_source_nodes_or_location_cache(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'ways.osm.pbf';writer=osmium.SimpleWriter(str(p))
            writer.add_way(osmium.osm.mutable.Way(id=1,version=3,tags={'name':'Test'},nodes=[12,15,12]))
            writer.add_way(osmium.osm.mutable.Way(id=99,tags={'name':'Not requested'},nodes=[100,101]))
            writer.close()
            fs=[feature('way/1',[[0,0],[1,0],[0,0]],{'name':'Test'})];targets=select_targets(fs)
            c,header=scan_way_references(p,targets,sha_file(p))
            self.assertEqual(set(c.found),{'way/1'})
            self.assertEqual(c.found['way/1']['ordered_node_ids'],[12,15,12])
            doc=build_topology(targets,c.found,BIND,ATTR,header_metadata=header)
            self.assertTrue(doc['audit']['ready_for_source_identity_topology'])
            with self.assertRaises(TopologyError):scan_way_references(p,targets,'0'*64)

    def test_exact_catalog_binding_failure_and_deterministic_no_overwrite(self):
        fs=[feature('way/1',[[0,0],[1,0]])]
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);raw=canonical_bytes(fs);(p/'catalog.json').write_bytes(raw)
            snapshot={'pbf_sha256':BIND['pbf_sha256'],'source_snapshot_utc':BIND['source_snapshot_utc'],**ATTR}
            sr=canonical_bytes(snapshot);(p/'snapshot.json').write_bytes(sr)
            patch={'schema':'singapore_source_geometry_patch_v1','feature_catalog':{'sha256':sha(raw)},
                   'source':{'snapshot_manifest_sha256':sha(sr),'source':snapshot}}
            (p/'patch.json').write_bytes(canonical_bytes(patch))
            _,binding,_=input_binding(p/'catalog.json',p/'patch.json',p/'snapshot.json',BIND['pbf_sha256'])
            self.assertEqual(binding['regional_source_catalog_sha256'],sha(raw))
            (p/'catalog.json').write_text('[]')
            with self.assertRaises(EnrichmentError):input_binding(p/'catalog.json',p/'patch.json',p/'snapshot.json',BIND['pbf_sha256'])
            doc=run(fs,{'way/1':source([1,2])});saved=deepcopy(fs)
            receipt=write_topology(p/'topology.json',doc)
            self.assertEqual(sha((p/'topology.json').read_bytes()),receipt['sha256'])
            self.assertNotIn(str(p),canonical_bytes(doc).decode())
            self.assertNotIn(str(p),canonical_bytes(receipt).decode())
            self.assertEqual(fs,saved)
            with self.assertRaises(TopologyError):write_topology(p/'topology.json',doc)

def rounded_position(lon,lat):
    x,_,z=georeference.from_wgs84(lon,lat)
    return [round(x,4),round(z,4)]

class OriginalNodeProjectionTests(unittest.TestCase):
    def _native_case(self,directory,*,reverse=False,missing=False):
        p=Path(directory)/'source.osm.pbf';writer=osmium.SimpleWriter(str(p))
        locations={11:(103.861,1.2841),12:(103.862,1.2851)}
        writer.add_node(osmium.osm.mutable.Node(id=11,location=locations[11],version=2,
            tags={'highway':'traffic_signals','crossing':'uncontrolled','kerb':'lowered','ele':'1.5'}))
        if not missing:writer.add_node(osmium.osm.mutable.Node(id=12,location=locations[12],tags={}))
        writer.add_node(osmium.osm.mutable.Node(id=999,location=(103.9,1.3),tags={'name':'not requested'}))
        writer.add_way(osmium.osm.mutable.Way(id=17,nodes=[11,12],tags={'name':'Source road'}));writer.close()
        coordinates=[rounded_position(*locations[i]) for i in (11,12)]
        if reverse:coordinates.reverse()
        fs=[feature('way/17',coordinates,{'name':'Source road'})];targets=select_targets(fs)
        ways,way_header=scan_way_references(p,targets,sha_file(p))
        original=build_topology(targets,ways.found,BIND,ATTR,header_metadata=way_header)
        nodes,node_header=scan_source_nodes(p,{11,12},sha_file(p))
        return original,nodes,node_header

    def test_native_source_projection_order_consistency_and_node_tag_facts(self):
        with tempfile.TemporaryDirectory() as t:
            original,nodes,header=self._native_case(t)
            self.assertEqual(set(nodes.found),{11,12})
            saved=canonical_bytes(original)
            verified=verify_original_node_coordinates(original,nodes.found,predecessor_sha256=sha(saved),node_header_metadata=header)
            self.assertEqual(canonical_bytes(original),saved)
            self.assertTrue(verified['audit']['ready_for_source_identity_topology'])
            self.assertTrue(verified['audit']['source_node_locations_independently_projected'])
            self.assertEqual(verified['node_coordinate_validation']['ordered_associations_checked'],2)
            self.assertLessEqual(verified['node_coordinate_validation']['maximum_axis_error_m'],.0001)
            node=verified['nodes']['11']['source_node']
            self.assertEqual(node['source_wgs84_lon_lat'],[103.861,1.2841])
            self.assertEqual(node['source_tags']['ele'],'1.5')
            self.assertEqual(node['source_tags']['kerb'],'lowered')
            self.assertFalse(verified['node_coordinate_validation']['elevation_inferred_from_tags'])

    def test_native_reversed_isolated_way_fails_despite_matching_count(self):
        with tempfile.TemporaryDirectory() as t:
            original,nodes,header=self._native_case(t,reverse=True)
            self.assertTrue(original['audit']['ready_for_source_identity_topology'])
            verified=verify_original_node_coordinates(original,nodes.found,predecessor_sha256='a'*64,node_header_metadata=header)
            self.assertFalse(verified['audit']['ready_for_source_identity_topology'])
            self.assertFalse(verified['audit']['source_node_coordinate_order_validation_passed'])
            self.assertEqual(len(verified['node_coordinate_validation']['coordinate_mismatches']),2)
            self.assertEqual(verified['ways']['way/17']['status'],'unresolved_source_node_projection_or_order')

    def test_native_missing_original_node_fails_readiness(self):
        with tempfile.TemporaryDirectory() as t:
            original,nodes,header=self._native_case(t,missing=True)
            verified=verify_original_node_coordinates(original,nodes.found,predecessor_sha256='a'*64,node_header_metadata=header)
            self.assertFalse(verified['audit']['ready_for_source_identity_topology'])
            self.assertEqual(verified['node_coordinate_validation']['missing_source_node_ids'],[12])

    def test_invalid_and_duplicate_source_node_observations_fail(self):
        coordinates=[rounded_position(103.861,1.2841),rounded_position(103.862,1.2851)]
        original=run([feature('way/1',coordinates)],{'way/1':source([11,12])})
        nodes=SourceNodeCollector({11,12});nodes.observe(11,103.861,1.2841,{},{});nodes.observe(12,None,None,{},{})
        invalid=verify_original_node_coordinates(original,nodes.found,predecessor_sha256='a'*64)
        self.assertFalse(invalid['audit']['ready_for_source_identity_topology'])
        self.assertEqual(invalid['node_coordinate_validation']['invalid_source_node_ids'],[12])
        nodes=SourceNodeCollector({11,12});nodes.observe(11,103.861,1.2841,{},{});nodes.observe(11,103.861,1.2841,{},{})
        nodes.observe(12,103.862,1.2851,{},{})
        duplicate=verify_original_node_coordinates(original,nodes.found,predecessor_sha256='a'*64,duplicate_source_ids=nodes.duplicate_source_ids)
        self.assertFalse(duplicate['audit']['ready_for_source_identity_topology'])
        self.assertEqual(duplicate['node_coordinate_validation']['duplicate_source_node_ids'],[11])

    def test_shifted_isolated_coordinates_and_node_header_conflicts_fail(self):
        p=rounded_position(103.861,1.2841);q=rounded_position(103.862,1.2851)
        original=run([feature('way/1',[[p[0]+10,p[1]],q])],{'way/1':source([11,12])})
        nodes=SourceNodeCollector({11,12});nodes.observe(11,103.861,1.2841,{},{});nodes.observe(12,103.862,1.2851,{},{})
        verified=verify_original_node_coordinates(original,nodes.found,predecessor_sha256='a'*64)
        self.assertFalse(verified['audit']['ready_for_source_identity_topology'])
        self.assertEqual(len(verified['node_coordinate_validation']['coordinate_mismatches']),1)
        original=run([feature('way/1',[p,q])],{'way/1':source([11,12])})
        verified=verify_original_node_coordinates(original,nodes.found,predecessor_sha256='a'*64,
            node_header_metadata={'osmosis_replication_timestamp':'different'})
        self.assertFalse(verified['audit']['ready_for_source_identity_topology'])
        self.assertTrue(verified['node_coordinate_validation']['snapshot_time_conflict'])

if __name__=='__main__':unittest.main()
