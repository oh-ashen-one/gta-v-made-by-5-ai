"""Regional metadata identity/immutability/privacy contracts, not survey proof."""
from copy import deepcopy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import osmium
from enrich_source_tags import (EnrichmentError,TagCollector,canonical_bytes,
    catalog_targets,enrich,input_binding,scan_pbf,sha,sha_file,source_id,write_sidecar)

PIN='1'*64
BINDING={'pbf_sha256':PIN,'source_snapshot_utc':'2026-10-27T21:23:59Z',
         'regional_source_catalog_sha256':'2'*64,'canonical_snapshot_manifest_sha256':'3'*64,
         'geometry_patch_manifest_sha256':'4'*64}
PROVENANCE={'attribution':'© OpenStreetMap contributors','data_license':'ODbL-1.0',
            'source_url':'https://example.org/source','license_url':'https://www.openstreetmap.org/copyright'}
def catalog(id='way/1',kind='road',tags=None):
    return {'id':id,'kind':kind,'feature_key':kind+'|'+id,'tags':tags or {},'source_feature_sha256':'a'*64}
def observed(tags):return {'source_tags':tags,'osm_metadata':{'version':7,'timestamp_utc':'2026-10-20T00:00:00Z'}}
def run(catalogue,found,**kw):return enrich(catalog_targets(catalogue),found,BINDING,PROVENANCE,**kw)

class EnrichmentTests(unittest.TestCase):
    def test_source_identity_is_typed_and_positive(self):
        self.assertEqual(source_id('way/17'),('way',17))
        self.assertEqual(source_id('relation/17'),('relation',17))
        for invalid in ('node/1','way/-1','way/0','way/1/../secret',17,'way/1x'):
            with self.assertRaises(EnrichmentError):source_id(invalid)

    def test_same_way_semantic_roles_share_one_source_tag_record(self):
        fs=[catalog(kind='water',tags={'name':'Rain Oculus'}),catalog(kind='waterway',tags={'name':'Rain Oculus'})]
        doc=run(fs,{'way/1':observed({'name':'Rain Oculus','ele':'4','waterway':'waterfall'})})
        self.assertEqual(len(doc['records']),1)
        self.assertEqual(doc['records']['way/1']['feature_keys'],['waterway|way/1','water|way/1'])
        self.assertEqual(doc['audit']['exact_canonical_tag_matches'],1)
        self.assertTrue(doc['audit']['ready_for_exact_bound_tag_overlay'])

    def test_full_strings_multilingual_and_semantics_are_not_interpreted(self):
        tags={'name':'海湾','name:zh':'海湾','name:ms':'Teluk','addr:unit':'B2-09',
              'width:carriageway':'12.5 m','width:lanes':'3|3.5','ele:datum':'unknown',
              'highway':'construction','construction':'secondary','proposed':'bridge',
              'motorcar:conditional':'no @ (Mo-Fr 07:00-10:00)','roof:levels':'1.5','height':'~200'}
        doc=run([catalog(tags={'name':'海湾'})],{'way/1':observed(tags)})
        self.assertEqual(doc['records']['way/1']['source_tags'],tags)
        self.assertNotIn('height_m',doc['records']['way/1'])
        self.assertFalse(doc['merge_contract']['inferred_measurements'])
        self.assertFalse(doc['merge_contract']['missing_tag_is_false'])

    def test_conflicts_and_missing_old_tags_are_reported_not_overwritten(self):
        original=[catalog(tags={'name':'Old','bridge':'yes'})];saved=deepcopy(original)
        doc=run(original,{'way/1':observed({'name':'Changed','ele':'5'})})
        self.assertEqual(original,saved)
        self.assertFalse(doc['audit']['ready_for_exact_bound_tag_overlay'])
        self.assertEqual(doc['records']['way/1']['status'],'conflict_with_canonical_v1')
        self.assertEqual({c['tag'] for c in doc['audit']['conflicts']},{'name','bridge'})
        conflict=next(c for c in doc['audit']['conflicts'] if c['tag']=='bridge')
        self.assertFalse(conflict['pbf_tag_present']);self.assertIsNone(conflict['pbf_value'])

    def test_unresolved_source_id_is_not_empty_tags_or_false(self):
        doc=run([catalog(),catalog('relation/1','building')],{'way/1':observed({})})
        self.assertEqual(doc['audit']['missing_source_ids'],['relation/1'])
        self.assertIsNone(doc['records']['relation/1']['source_tags'])
        self.assertFalse(doc['audit']['ready_for_exact_bound_tag_overlay'])

    def test_duplicate_source_object_never_last_writer_wins(self):
        targets=catalog_targets([catalog()]);c=TagCollector(targets)
        c.observe('way',1,{'name':'First'},{'version':1})
        c.observe('way',1,{'name':'Second'},{'version':2})
        doc=enrich(targets,c.found,BINDING,PROVENANCE,duplicate_source_ids=c.duplicate_source_ids)
        self.assertEqual(doc['records']['way/1']['source_tags']['name'],'First')
        self.assertEqual(doc['records']['way/1']['status'],'unresolved_duplicate_source_id')
        self.assertFalse(doc['audit']['ready_for_exact_bound_tag_overlay'])

    def test_way_and_relation_same_numeric_id_do_not_collide(self):
        targets=catalog_targets([catalog(),catalog('relation/1','building')]);c=TagCollector(targets)
        c.observe('way',1,{'name':'Road'},{});c.observe('relation',1,{'name':'Building'},{})
        self.assertEqual(set(c.found),{'way/1','relation/1'})
        for bad in [('node',1,{},{}),('way',True,{},{}),('way',1,{'width':3},{})]:
            with self.assertRaises(EnrichmentError):c.observe(*bad)

    def test_catalog_rejects_wrong_semantic_identity_and_numeric_tags(self):
        for row in [{**catalog(),'feature_key':'building|way/1'},catalog(tags={'width':3}),{**catalog(),'source_feature_sha256':'invalid'}]:
            with self.assertRaises(EnrichmentError):catalog_targets([row])
        with self.assertRaises(EnrichmentError):catalog_targets([catalog(),catalog()])

    def test_snapshot_header_timestamp_conflict_is_unresolved(self):
        doc=run([catalog()],{'way/1':observed({})},header_metadata={'osmosis_replication_timestamp':'EARLIER'})
        self.assertTrue(doc['audit']['header_snapshot_time_conflict'])
        self.assertFalse(doc['audit']['ready_for_exact_bound_tag_overlay'])

    def test_exact_input_catalog_snapshot_and_pbf_binding(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);raw=canonical_bytes([catalog()]);(p/'catalog.json').write_bytes(raw)
            snapshot={'pbf_sha256':PIN,'source_snapshot_utc':BINDING['source_snapshot_utc'],**PROVENANCE}
            sr=canonical_bytes(snapshot);(p/'snapshot.json').write_bytes(sr)
            manifest={'schema':'singapore_source_geometry_patch_v1','feature_catalog':{'sha256':sha(raw)},
                      'source':{'snapshot_manifest_sha256':sha(sr),'source':snapshot}}
            (p/'patch.json').write_bytes(canonical_bytes(manifest))
            targets,binding,provenance=input_binding(p/'catalog.json',p/'patch.json',p/'snapshot.json',PIN)
            self.assertEqual(set(targets),{'way/1'});self.assertEqual(binding['regional_source_catalog_sha256'],sha(raw))
            self.assertEqual(provenance['data_license'],'ODbL-1.0')
            with self.assertRaises(EnrichmentError):input_binding(p/'catalog.json',p/'patch.json',p/'snapshot.json','b'*64)
            (p/'catalog.json').write_text('[]')
            with self.assertRaises(EnrichmentError):input_binding(p/'catalog.json',p/'patch.json',p/'snapshot.json',PIN)

    def test_native_metadata_only_scan_keeps_tags_and_target_types(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'synthetic.osm.pbf';w=osmium.SimpleWriter(str(p))
            w.add_way(osmium.osm.mutable.Way(id=1,version=2,timestamp='2026-10-20T00:00:00Z',tags={'name':'Road','width':'3.5'},nodes=[]))
            w.add_way(osmium.osm.mutable.Way(id=99,tags={'name':'Not requested'},nodes=[]))
            w.add_relation(osmium.osm.mutable.Relation(id=1,version=4,tags={'name':'Building'},members=[]))
            w.close()
            targets=catalog_targets([catalog(),catalog('relation/1','building')])
            collector,header=scan_pbf(p,targets,sha_file(p))
            self.assertEqual(set(collector.found),{'way/1','relation/1'})
            self.assertEqual(collector.found['way/1']['source_tags']['width'],'3.5')
            self.assertEqual(collector.found['way/1']['osm_metadata']['version'],2)
            with self.assertRaises(EnrichmentError):scan_pbf(p,targets,'0'*64)

    def test_no_private_paths_or_environment_credentials_in_output(self):
        secret='SYNTHETIC-TEST-SENTINEL-NOT-A-CREDENTIAL'
        with patch.dict(os.environ,{'GEODATA_TEST_SECRET':secret}):
            doc=run([catalog()],{'way/1':observed({'name':'Public source name'})})
            text=canonical_bytes(doc).decode()
            self.assertNotIn(secret,text);self.assertNotIn('/Users/',text);self.assertNotIn('/private/tmp/',text)
        result=subprocess.run([os.sys.executable,str(Path(__file__).with_name('enrich_source_tags.py')),
            '--pbf','/private/tmp/do-not-echo-this-source.osm.pbf','--expected-pbf-sha256',PIN,
            '--catalog','/private/tmp/do-not-echo-catalog.json','--patch-manifest','/private/tmp/missing-patch.json',
            '--snapshot-manifest','/private/tmp/missing-snapshot.json','--output','/private/tmp/not-created-sidecar.json'],
            capture_output=True,text=True)
        self.assertEqual(result.returncode,2)
        self.assertNotIn('/private/tmp/',result.stdout+result.stderr)
        self.assertNotIn('Traceback',result.stderr)

    def test_deterministic_sidecar_and_no_overwrite(self):
        a=run([catalog()],{'way/1':observed({'width':'3','name':'Main'})})
        b=run([catalog()],{'way/1':observed({'name':'Main','width':'3'})})
        self.assertEqual(canonical_bytes(a),canonical_bytes(b))
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'sidecar.json';report=write_sidecar(p,a)
            self.assertEqual(sha(p.read_bytes()),report['sidecar_sha256'])
            self.assertNotIn(str(p),canonical_bytes(report).decode())
            with self.assertRaises(EnrichmentError):write_sidecar(p,b)

if __name__=='__main__':unittest.main()
