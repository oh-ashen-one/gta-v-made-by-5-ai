import json
from copy import deepcopy
from pathlib import Path
import sqlite3
import tempfile
from types import SimpleNamespace
import unittest

import expand_national as country

class CountryExpansion(unittest.TestCase):
    def setUp(self):self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
    def tearDown(self):self.temp.cleanup()
    def test_frozen_kernel_pin_matches(self):
        self.assertEqual(country.digest(country.frozen.__file__),country.EXPECTED_KERNEL)
    def test_immutable_owned_checkpoint_never_overwrites(self):
        path=self.root/'a.json';first=country.put(path,{'owned':True})
        self.assertEqual(first,country.put(path,{'owned':True}))
        with self.assertRaises(ValueError):country.put(path,{'owned':False})
        self.assertEqual(json.loads(path.read_text()),{'owned':True})
    def test_supervisor_refuses_source_alias_before_writing_lock(self):
        with self.assertRaises(ValueError):country.supervise(SimpleNamespace(source=self.root,output=self.root,resume=True))
        self.assertFalse((self.root/'worker.lock').exists())
    def test_partial_index_cannot_be_misreported_complete(self):
        output=self.root/'out';output.mkdir();sqlite3.connect(output/'index.sqlite').close()
        with self.assertRaises(ValueError):country.build_index(SimpleNamespace(output=output,identity='a'*64),None)
    def test_parts_bound_vertices_and_preserve_all_source_fragments(self):
        index=sqlite3.connect(':memory:');index.executescript('create table ways(id text primary key,data text);create table links(tile text,way text);')
        for i in range(8):
            data={'id':'fixture/'+str(i),'name':'SYNTHETIC '+str(i),'source_vertex_ids':[i*2+1,i*2+2],
                  'source_points_xyz':[[i*20.,0.,10.],[i*20.+10.,0.,10.]],'policy':{'width':{'metres':6.4}}}
            index.execute('insert into ways values(?,?)',(data['id'],json.dumps(data)));index.execute('insert into links values(?,?)',('0_0',data['id']))
        output=self.root/'parts';output.mkdir();args=SimpleNamespace(output=output)
        previous=country.MAX_PART_VERTICES
        try:
            country.MAX_PART_VERTICES=12
            result=country.emit_tile(args,index,'0_0',0,0,{})
            self.assertEqual(len(result['parts']),4)
            self.assertEqual(len(result['per_way_fragments']),8)
            all_ids=[]
            for descriptor in result['parts']:
                self.assertLessEqual(descriptor['vertices'],12)
                raw=(output/descriptor['file']).read_bytes()
                self.assertEqual(country.frozen.sha(raw),descriptor['sha256'])
                data=json.loads(raw);self.assertEqual(data['tile'],descriptor['tile']);all_ids.extend(f['id'] for f in data['features'])
            self.assertEqual(sorted(all_ids),['fixture/'+str(i) for i in range(8)])
            # Deterministic partial-run recovery only accepts identical bytes.
            self.assertEqual(result,country.emit_tile(args,index,'0_0',0,0,{}))
        finally:country.MAX_PART_VERTICES=previous
        index.close()
    def test_measured_country_codec_regression_uses_same_kernel_and_profile(self):
        fixture=json.loads((Path(__file__).parent/'NATIONAL_CODEC_ANCHOR_REGRESSION.json').read_text())
        item=fixture['source_way'];before=deepcopy(item)
        radii=dict(zip(item['source_vertex_ids'],fixture['hub_radii']))
        anchor,mesh=country.anchored_mesh(item,*fixture['tile_xz'],radii)
        self.assertGreater(fixture['baseline_maximum_slope'],.121)
        self.assertLessEqual(mesh['maximum_emitted_surface_slope'],.121)
        self.assertNotEqual(anchor,[-18000.,0.,6000.])
        self.assertEqual(item,before)
        self.assertIn('codec_anchor_policy',mesh)

if __name__=='__main__':unittest.main()
