import json
import unittest

import semantic_baseline as baseline
import test_reprofile_country as fixture


def original_subset():
    db=fixture.database();db.execute('create table source_nodes(id integer primary key,x real,z real)')
    for row in fixture.fixture.FIXTURE['vertices']:
        db.execute('update vertices set base=? where v=?',(row[5],row[0]))
        db.execute('insert or ignore into source_nodes values(?,?,?)',(row[1],row[3],row[4]))
    db.commit();return db


class FreshSemanticBaseline(unittest.TestCase):
    def setUp(self):
        self.original=original_subset();self.new=baseline.K.database(':memory:')
        self.counts=baseline.ingest_original_facts(self.original,self.new)

    def tearDown(self):self.original.close();self.new.close()

    def test_actual_source_tags_ids_xy_directions_and_dem_are_preserved(self):
        baseline.K.add_endpoint_transitions(self.new);baseline.K.install_geometry_allowances(self.new)
        result=baseline.audit_original_source(self.original,self.new)
        self.assertEqual(result['counts']['source_ways'],10)
        self.assertTrue(result['generated_grade_vertex_ids_are_versioned'])
        row=self.new.execute("select policy,vertices from ways where id='way/1453057759'").fetchone()
        grade=json.loads(row[0])['grade'];ids=json.loads(row[1])
        self.assertEqual(grade['structure'],'covered_passage')
        self.assertIsNone(self.new.execute('select upper_y from vertices where v=?',(ids[0],)).fetchone()[0])
        # The baseline starts from raw preferred DEM, never the old underground Y.
        self.assertGreater(self.new.execute('select base from vertices where v=?',(ids[0],)).fetchone()[0],19.)

    def test_actual_parking_order_is_detected_and_enforced_automatically(self):
        baseline.K.add_endpoint_transitions(self.new);baseline.K.install_geometry_allowances(self.new)
        orders=baseline.install_ramp_orders(self.new)
        record=next(r for r in orders['records'] if r['source_way']=='way/1453057758')
        self.assertFalse(record['native_or_as_built_clearance_verified'])
        result=baseline.K.solve_profiles(self.new)
        lower,upper,gap=self.new.execute("select lower_v,upper_v,clearance from vertical_orders where source_way='way/1453057758'").fetchone()
        yl=self.new.execute('select y from vertices where v=?',(lower,)).fetchone()[0]
        yu=self.new.execute('select y from vertices where v=?',(upper,)).fetchone()[0]
        self.assertGreaterEqual(yu-yl,gap-1e-7)
        self.assertEqual(result['conflicting_game_constraints'],0)

    def test_audit_rejects_mode_or_original_node_change(self):
        key=self.new.execute('select id from ways order by id limit 1').fetchone()[0]
        policy=json.loads(self.new.execute('select policy from ways where id=?',(key,)).fetchone()[0])
        policy['modes']['car']['bits']=0
        self.new.execute('update ways set policy=? where id=?',(json.dumps(policy),key))
        with self.assertRaisesRegex(ValueError,'width/direction/access'):
            baseline.audit_original_source(self.original,self.new)

    def test_audit_rejects_reusing_old_inferred_y_as_dem(self):
        self.new.execute('update vertices set base=base+.1 where v=(select min(v) from vertices)')
        with self.assertRaisesRegex(ValueError,'preferred DEM'):
            baseline.audit_original_source(self.original,self.new)


if __name__=='__main__':unittest.main()
