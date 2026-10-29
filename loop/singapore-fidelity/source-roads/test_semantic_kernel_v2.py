import json
from pathlib import Path
import unittest

import compile_roads_semantic_v2 as kernel

HERE=Path(__file__).resolve().parent
FIXTURE=json.loads((HERE/'country-r2-records/targeted-profile-fixture.json').read_text())


def catalog_way(identifier,refs,points,tags):
    return {'kind':'road','id':identifier,'feature_key':'road|'+identifier,'name':tags.get('name'),
            'canonical_anchor_source_xyz':[0.,0.,0.],'catalog_owner':'fixture',
            'source_feature_sha256':'f'*64,'source_geometry_sha256':'e'*64,
            'source_bounds_xz':[min(p[0] for p in points),min(p[1] for p in points),max(p[0] for p in points),max(p[1] for p in points)],
            'road':{'original_ordered_node_ids':refs,'centerline_local_xz_double':points,'full_source_tags':tags,
                    'source_contract_issues':[],'source_version':1}}


class FlatTerrain:
    def sample(self,x,z):return 20.


def minimal_db(length=100.,bounds=None):
    db=kernel.database(':memory:')
    for v,x in ((1,0.),(2,length)):
        lo,hi=(bounds or {}).get(v,(None,None))
        db.execute('insert into vertices values(?,?,?,?,?,?,?,?,?)',(v,v,'fixture',x,0.,0.,lo,hi,0.))
    db.execute('insert into edges values(?,?,?,?,?,?,?,?,?,?,?)',('way/1@0',1,2,length,.12*length,'way/1',0,3,3,3,0))
    db.execute('create table vertical_orders(id text primary key,lower_v integer,upper_v integer,clearance real)')
    db.execute('insert into vertical_orders values(?,?,?,?)',('site-order',1,2,5.));db.commit()
    return db


class VersionedSemanticKernel(unittest.TestCase):
    def test_covered_ground_source_node_compatibility_without_xy_snapping(self):
        db=kernel.database(':memory:')
        features=[catalog_way('way/1',[1,2,3],[[-10,0],[0,0],[10,0]],{'highway':'service'}),
                  catalog_way('way/2',[4,2,5],[[0,-10],[0,0],[0,10]],{'highway':'service','tunnel':'building_passage','oneway':'-1'}),
                  catalog_way('way/3',[6,7],[[0,0],[1,1]],{'highway':'service','tunnel':'building_passage'})]
        kernel.ingest_catalog(db,{'schema':'singapore_source_city_geometry_v1','owner':'fixture','anchor_source_xyz':[0.,0.,0.],'features':features},FlatTerrain())
        self.assertEqual(db.execute('select count(*) from vertices where node=2').fetchone()[0],1)
        shared=db.execute('select v from vertices where node=2').fetchone()[0]
        distinct=db.execute('select v from vertices where node=6').fetchone()[0]
        self.assertNotEqual(shared,distinct)
        self.assertIsNone(db.execute('select upper_y from vertices where v=?',(shared,)).fetchone()[0])
        self.assertTrue(all(row[0]==2 for row in db.execute("select car from edges where way='way/2'")))
        self.assertEqual(json.loads(db.execute("select raw from ways where id='way/2'").fetchone()[0])['tags'],features[1]['road']['full_source_tags'])
        db.close()

    def test_ingested_explicit_negative_passage_is_not_fabricated_underground(self):
        for tag,layer,expected in (('building_passage','-2',None),('yes','-3',15.)):
            db=kernel.database(':memory:');feature=catalog_way('way/1',[1,2],[[0,0],[100,0]],{'highway':'service','tunnel':tag,'layer':layer})
            kernel.ingest_catalog(db,{'schema':'singapore_source_city_geometry_v1','owner':'fixture','anchor_source_xyz':[0.,0.,0.],'features':[feature]},FlatTerrain())
            self.assertEqual(db.execute('select upper_y from vertices where v=1').fetchone()[0],expected)
            grade=json.loads(db.execute('select policy from ways').fetchone()[0])['grade']
            self.assertEqual(grade['raw_layer'],layer);db.close()

    def test_relative_clearance_closure_is_solved_not_only_proposed(self):
        db=minimal_db();result=kernel.solve_profiles(db)
        values=[row[0] for row in db.execute('select y from vertices order by v')]
        self.assertGreaterEqual(values[1]-values[0],5.-1e-7)
        self.assertLessEqual(result['maximum_allowance_error_m'],1e-7)
        self.assertLessEqual(result['maximum_relative_clearance_error_m'],1e-7);db.close()

    def test_relative_order_upper_bound_propagates_backwards(self):
        db=minimal_db(bounds={2:(None,3.)});kernel.solve_profiles(db)
        a,b=[row[0] for row in db.execute('select y from vertices order by v')]
        self.assertLessEqual(b,3.);self.assertLessEqual(a,-2.+1e-7);self.assertGreaterEqual(b-a,5.-1e-7);db.close()

    def test_infeasible_relative_cycle_and_bound_conflict_never_write_heights(self):
        for db in (minimal_db(length=1.),minimal_db(bounds={1:(0.,None),2:(None,3.)})):
            before=db.execute('select v,y from vertices order by v').fetchall()
            with self.assertRaises(kernel.RoadError):kernel.solve_profiles(db)
            self.assertEqual(db.execute('select v,y from vertices order by v').fetchall(),before);db.close()

    def test_actual_source_parking_ramp_keeps_two_levels_after_covered_fix(self):
        db=kernel.database(':memory:');keys=('way/1453057757','way/1453057758','way/1453057759')
        vertices={row[0]:row for row in FIXTURE['vertices']};preferred={}
        for key in keys:
            w=FIXTURE['ways'][key]
            for v,p in zip(w['vertex_ids'],w['canonical_source_points']):preferred[(p[0],p[2])]=vertices[v][5]
        class SourceTerrain:
            def sample(self,x,z):return preferred[(x,z)]
        features=[]
        for key in keys:
            way=FIXTURE['ways'][key];raw=way['raw_source']
            features.append(catalog_way(key,raw['node_ids'],[[p[0],p[2]] for p in way['canonical_source_points']],raw['tags']))
        kernel.ingest_catalog(db,{'schema':'singapore_source_city_geometry_v1','owner':'fixture','anchor_source_xyz':[0.,0.,0.],'features':features},SourceTerrain())
        kernel.add_endpoint_transitions(db);kernel.install_geometry_allowances(db)
        ramp=json.loads(db.execute("select vertices from ways where id='way/1453057758'").fetchone()[0])
        db.execute('create table vertical_orders(id text primary key,lower_v integer,upper_v integer,clearance real)')
        db.execute('insert into vertical_orders values(?,?,?,?)',('source-proven-parking-site',ramp[-1],ramp[0],5.))
        result=kernel.solve_profiles(db)
        high=db.execute('select y from vertices where v=?',(ramp[0],)).fetchone()[0]
        low=db.execute('select y from vertices where v=?',(ramp[-1],)).fetchone()[0]
        self.assertGreaterEqual(high-low,5.-1e-7)
        covered=json.loads(db.execute("select policy from ways where id='way/1453057759'").fetchone()[0])['grade']
        self.assertEqual(covered['structure'],'covered_passage');self.assertEqual(covered['layer'],0)
        self.assertLessEqual(result['maximum_relative_clearance_error_m'],1e-7)
        self.assertEqual(result['conflicting_game_constraints'],0);db.close()


if __name__=='__main__':unittest.main()
