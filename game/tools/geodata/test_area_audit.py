"""Conservative area-failure classification; not source completeness proof."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
import osmium
from shapely.geometry import MultiPolygon,Polygon,box
from audit_area_failures import (AreaAuditError,AreaFailureAudit,MAX_REPORT_BYTES,
    classify_bounds,inspect_raw_rings,report_for,selected_area,source_inputs,write_json_new,audit_raw_source_failures)
from enrich_source_tags import canonical_bytes,sha,sha_file

class FakeNode:
    def __init__(self,id,lon,lat,valid=True):
        self.ref=id;self.lon=lon;self.lat=lat;self.location=SimpleNamespace(valid=lambda:valid)
class FakeArea:
    def __init__(self,rings):self.rings=rings
    def outer_rings(self):return iter(self.rings)
    def inner_rings(self,outer):return iter(())

class ClassificationTests(unittest.TestCase):
    def test_valid_node_bbox_disjoint_from_exact_country_proves_outside(self):
        country=MultiPolygon([box(0,0,1,1),box(5,5,6,6)])
        r=classify_bounds([10,10,11,11],valid_nodes=8,country=country)
        self.assertEqual(r['classification'],'outside_country')
    def test_touching_or_potential_intersection_not_repaired_or_declared_present(self):
        for bounds in [(1,0,2,1),(.1,.1,.9,.9),(-1,.2,2,.8)]:
            self.assertEqual(classify_bounds(bounds,valid_nodes=4,country=box(0,0,1,1))['classification'],'potentially_missing')
    def test_holes_and_disjoint_islands_use_actual_country_not_its_bbox(self):
        p=Polygon([(0,0),(10,0),(10,10),(0,10)],holes=[[(2,2),(8,2),(8,8),(2,8)]])
        self.assertEqual(classify_bounds((3,3,7,7),valid_nodes=4,country=p)['classification'],'outside_country')
        islands=MultiPolygon([box(0,0,1,1),box(5,5,6,6)])
        self.assertEqual(classify_bounds((2,2,3,3),valid_nodes=4,country=islands)['classification'],'outside_country')
    def test_invalid_missing_or_inaccessible_coordinates_are_unknown_even_if_known_bbox_outside(self):
        for kwargs in [{'invalid_nodes':1,'valid_nodes':8},{'inaccessible_rings':1,'valid_nodes':8},{'valid_nodes':0}]:
            self.assertEqual(classify_bounds((10,10,11,11),country=box(0,0,1,1),**kwargs)['classification'],'UNKNOWN')
        self.assertEqual(classify_bounds(None,valid_nodes=4,country=box(0,0,1,1))['classification'],'UNKNOWN')
        self.assertEqual(classify_bounds((float('nan'),0,1,1),valid_nodes=4,country=box(0,0,1,1))['classification'],'UNKNOWN')
    def test_degenerate_envelopes_conservatively_keep_points_and_lines(self):
        self.assertEqual(classify_bounds((.5,.5,.5,.5),valid_nodes=1,country=box(0,0,1,1))['classification'],'potentially_missing')
        self.assertEqual(classify_bounds((5,5,5,5),valid_nodes=1,country=box(0,0,1,1))['classification'],'outside_country')
    def test_predicate_exactly_retains_original_key_presence_behavior(self):
        self.assertEqual(selected_area({'building':'no'}),(False,True,False))
        self.assertEqual(selected_area({'water':'no'}),(False,False,True))
        self.assertEqual(selected_area({'ISO3166-1':'SG'}),(True,False,False))
        self.assertEqual(selected_area({'admin_level':'2','name:en':'Singapore'}),(True,False,False))
        self.assertEqual(selected_area({'waterway':'river'}),(False,False,False))
    def test_raw_ring_samples_bounded_but_all_nodes_contribute_bounds_and_validity(self):
        nodes=[FakeNode(i,10+i/1000,20+i/1000) for i in range(200)]
        raw=inspect_raw_rings(FakeArea([nodes]))
        self.assertEqual(raw['node_references'],200);self.assertEqual(raw['valid_nodes'],200)
        self.assertEqual(raw['valid_node_bounds_wgs84'],[10,20,10.199,20.199])
        self.assertEqual(len(raw['ring_records'][0]['head_samples']),8)
        self.assertEqual(len(raw['ring_records'][0]['tail_samples']),8)
        nodes.append(FakeNode(300,0,0,False));raw=inspect_raw_rings(FakeArea([nodes]))
        self.assertEqual(raw['invalid_nodes'],1)
    def test_inaccessible_raw_rings_are_not_proven_outside(self):
        class BadArea:
            def outer_rings(self):raise RuntimeError('unreadable')
        raw=inspect_raw_rings(BadArea());self.assertFalse(raw['all_ring_coordinates_inspected'])
        self.assertEqual(raw['inaccessible_rings'],1)
    def test_report_does_not_claim_native_assembler_source_completeness(self):
        audit=AreaFailureAudit(box(0,0,1,1))
        report=report_for(audit,{'recorded_area_geometry_exceptions':0})
        self.assertFalse(report['scope']['native_assembler_suppressed_objects_audited'])
        self.assertFalse(report['scope']['source_completeness_certified'])
        self.assertEqual(report['recorded_failure_scope_conclusion'],'unresolved_or_potential_country_omissions')
    def test_report_bound_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'report.json';write_json_new(p,{'status':'complete'})
            with self.assertRaises(FileExistsError):write_json_new(p,{})
            with self.assertRaises(AreaAuditError):write_json_new(Path(t)/'too-large.json',{'large':'x'*MAX_REPORT_BYTES})

class NativeAreaTests(unittest.TestCase):
    def _pbf(self,p):
        w=osmium.SimpleWriter(str(p));points={
            1:(0,0),2:(1,0),3:(1,1),4:(0,1),
            11:(10,10),12:(11,10),13:(11,11),14:(10,11),
            21:(.2,.2),22:(.4,.2),23:(.4,.4),24:(.2,.4)}
        for id,loc in points.items():w.add_node(osmium.osm.mutable.Node(id=id,location=loc))
        w.add_way(osmium.osm.mutable.Way(id=100,nodes=[1,2,3,4,1],tags={'ISO3166-1':'SG','admin_level':'2','name':'Singapore'}))
        w.add_way(osmium.osm.mutable.Way(id=101,nodes=[11,12,13,14,11],tags={'building':'yes','name':'Outside fixture'}))
        w.add_way(osmium.osm.mutable.Way(id=102,nodes=[21,22,23,24,21],tags={'natural':'water'}))
        w.add_way(osmium.osm.mutable.Way(id=103,nodes=[1,2,3],tags={'building':'yes','name':'Unclosed, not emitted as area'}))
        w.close()
    def test_native_disk_backed_area_events_classification_and_suppressed_unclosed_limit(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'areas.osm.pbf';self._pbf(p)
            class ControlledFactory:
                def __init__(self):self.real=osmium.geom.GeoJSONFactory()
                def create_multipolygon(self,a):
                    if a.orig_id() in (101,102):raise RuntimeError('Private sentinel /private/tmp/do-not-echo-input-path')
                    return self.real.create_multipolygon(a)
            audit=AreaFailureAudit(box(0,0,1,1),factory=ControlledFactory())
            audit.apply_file(str(p),locations=True,idx='sparse_file_array,'+str(Path(t)/'index.bin'))
            self.assertEqual(audit.counts['eligible_factory_attempts'],3)
            self.assertEqual(audit.counts['area_geometry'],2)
            failures={f['source_id']:f for f in audit.failures}
            self.assertEqual(failures['way/101']['classification'],'outside_country')
            self.assertEqual(failures['way/102']['classification'],'potentially_missing')
            self.assertTrue(audit.country_factory_checks[0]['matches_exact_pinned_country'])
            self.assertNotIn('way/103',failures)
            report=report_for(audit,{'recorded_area_geometry_exceptions':2})
            self.assertNotIn('/private/tmp/',canonical_bytes(report).decode())
            self.assertFalse(report['scope']['source_completeness_certified'])
            self.assertFalse(report['scope']['native_assembler_suppressed_objects_audited'])
    def test_raw_source_fallback_recovers_empty_event_bounds_without_geometry_repair(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'areas.osm.pbf';self._pbf(p)
            original={'schema':'singapore_emitted_area_failure_audit_v1','status':'complete',
                'binding':{'recorded_area_geometry_exceptions':2},'reproduces_recorded_exception_count':True,
                'country_factory_matches_exact_pinned_country':True,'limitations':[],
                'failures':[{'source_id':'way/101','relevant_source_tags':{'building':'yes'},'classification':'UNKNOWN','reason':'empty area'},
                    {'source_id':'way/102','relevant_source_tags':{'natural':'water'},'classification':'UNKNOWN','reason':'empty area'}]}
            before=canonical_bytes(original)
            result=audit_raw_source_failures(original,box(0,0,1,1),p,predecessor_sha256='a'*64)
            self.assertEqual(canonical_bytes(original),before)
            self.assertEqual(result['failures'][0]['classification'],'outside_country')
            self.assertEqual(result['failures'][1]['classification'],'potentially_missing')
            self.assertEqual(result['failures'][0]['assembled_event_classification'],'UNKNOWN')
            self.assertEqual(result['failures'][0]['raw_source_evidence']['valid_source_nodes'],4)
            self.assertFalse(result['raw_source_fallback']['geometry_repaired'])
            self.assertFalse(result['raw_source_fallback']['node_location_cache_created'])
            self.assertNotIn('/private/tmp/',canonical_bytes(result).decode())

    def test_raw_relation_missing_empty_or_nested_members_stay_unknown(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'members.osm.pbf';w=osmium.SimpleWriter(str(p))
            for id,loc in [(1,(10,10)),(2,(11,10)),(3,(11,11))]:w.add_node(osmium.osm.mutable.Node(id=id,location=loc))
            w.add_way(osmium.osm.mutable.Way(id=301,nodes=[1,2,3,1]))
            w.add_way(osmium.osm.mutable.Way(id=302,nodes=[]))
            w.add_relation(osmium.osm.mutable.Relation(id=201,members=[('w',301,'outer'),('w',399,'inner')],tags={'building':'yes'}))
            w.add_relation(osmium.osm.mutable.Relation(id=202,members=[('w',301,'outer'),('r',299,'inner')],tags={'building':'yes'}))
            w.add_relation(osmium.osm.mutable.Relation(id=203,members=[('w',301,'outer'),('w',302,'inner')],tags={'building':'yes'}));w.close()
            original={'schema':'singapore_emitted_area_failure_audit_v1','status':'complete',
                'binding':{'recorded_area_geometry_exceptions':3},'reproduces_recorded_exception_count':True,
                'country_factory_matches_exact_pinned_country':True,'limitations':[],
                'failures':[{'source_id':'relation/'+str(i),'relevant_source_tags':{'building':'yes'},'classification':'UNKNOWN','reason':'empty area'} for i in (201,202,203)]}
            result=audit_raw_source_failures(original,box(0,0,1,1),p,predecessor_sha256='a'*64)
            self.assertTrue(all(f['classification']=='UNKNOWN' for f in result['failures']))
            self.assertTrue(all(f['raw_source_evidence']['unresolved_source_conditions'] for f in result['failures']))

    def test_pinned_pbf_country_and_snapshot_identity_fail_closed(self):
        with tempfile.TemporaryDirectory() as t:
            d=Path(t);p=d/'areas.osm.pbf';self._pbf(p)
            boundary=canonical_bytes({'type':'Polygon','coordinates':[[[0,0],[1,0],[1,1],[0,1],[0,0]]]})
            (d/'country.json').write_bytes(boundary)
            m={'pbf_sha256':sha_file(p),'source_snapshot_utc':None,'parse_errors':{'area_geometry':0}}
            (d/'manifest.json').write_bytes(canonical_bytes(m))
            args=SimpleNamespace(pbf=p,expected_pbf_sha256=m['pbf_sha256'],snapshot_manifest=d/'manifest.json',country=d/'country.json',expected_country_sha256=sha(boundary))
            country,binding=source_inputs(args)
            self.assertTrue(country.equals(box(0,0,1,1)));self.assertEqual(binding['exact_country_sha256'],sha(boundary))
            args.expected_country_sha256='0'*64
            with self.assertRaises(AreaAuditError):source_inputs(args)
            args.expected_country_sha256=sha(boundary);args.expected_pbf_sha256='0'*64
            with self.assertRaises(AreaAuditError):source_inputs(args)

if __name__=='__main__':unittest.main()
