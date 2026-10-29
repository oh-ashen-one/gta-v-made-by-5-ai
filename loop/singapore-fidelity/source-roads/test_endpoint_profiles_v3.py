import json
from pathlib import Path
import unittest

import compile_roads_semantic_v2 as K
import endpoint_profiles_v3 as profile
import semantic_baseline as baseline
import test_semantic_baseline as original_fixture


HERE = Path(__file__).resolve().parent


def actual_portals():
    data = json.loads((HERE / 'semantic-v2-records/ten-source-portal-fixture.json').read_text())
    db = K.database(':memory:')
    for table, columns in [('source_nodes', 3), ('vertices', 9), ('ways', 6), ('edges', 11), ('occurrences', 4)]:
        db.executemany('insert into ' + table + ' values(' + ','.join('?' for _ in range(columns)) + ')', data[table])
    K.add_endpoint_transitions(db)
    K.install_geometry_allowances(db)
    return data, db


def synthetic_bridge(length=200., split=False):
    db = K.database(':memory:')
    for v, x in ((1, 0.), (2, length * .25), (3, length * .5), (4, length * .75), (5, length)):
        db.execute('insert into vertices values(?,?,?,?,?,?,?,?,?)', (v, v, '["bridge",1,""]', x, 0., 0., 6., None, 0.))
    for a, b in ((1, 2), (2, 3), (3, 4), (4, 5)):
        owner = 'way/2' if split and a >= 3 else 'way/1'
        db.execute('insert into edges values(?,?,?,?,?,?,?,?,?,?,?)', (f'{owner}@{a}', a, b, length * .25, length * .25 * .12, owner, a, 3, 3, 3, 0))
    for other, bridge, x in ((6, 1, 0.), (7, 5, length)):
        db.execute('insert into vertices values(?,?,?,?,?,?,?,?,?)', (other, bridge, '["surface",0,""]', x, 0., 0., None, None, 0.))
        db.execute('insert into edges values(?,?,?,?,?,?,?,?,?,?,?)', (f'portal/{bridge}', bridge, other, 0., 0., None, -1, 3, 3, 3, 1))
    db.commit()
    return db


class SourceStructurePortalProfiles(unittest.TestCase):
    def test_source_supported_multilevel_parking_ramp_stays_separate(self):
        original = original_fixture.original_subset()
        db = K.database(':memory:')
        baseline.ingest_original_facts(original, db)
        K.add_endpoint_transitions(db); K.install_geometry_allowances(db)
        baseline.install_ramp_orders(db)
        profile.apply(db); result = profile.solve(db)
        lower, upper, gap = db.execute("select lower_v,upper_v,clearance from vertical_orders where source_way='way/1453057758'").fetchone()
        a, b = [db.execute('select y from vertices where v=?', (v,)).fetchone()[0] for v in (lower, upper)]
        self.assertGreaterEqual(b - a, gap - 1e-7)
        self.assertEqual(gap, 5.)
        self.assertEqual(result['ramp_relations'], 1)
        original.close(); db.close()

    def test_infeasible_relative_profile_never_overwrites_current_heights(self):
        db = synthetic_bridge(12.)
        profile.apply(db)
        before = db.execute('select v,y from vertices order by v').fetchall()
        db.execute("update structure_metric_orders set clearance=20 where id='structure/3'")
        with self.assertRaisesRegex(ValueError, 'unresolved within64round'):
            profile.solve(db)
        self.assertEqual(db.execute('select v,y from vertices order by v').fetchall(), before)
        db.close()

    def test_arbitrary_way_split_keeps_continuous_same_structure_run(self):
        left, right = synthetic_bridge(), synthetic_bridge(split=True)
        a, b = profile.plan(left), profile.plan(right)
        self.assertEqual(a['records'], b['records'])
        self.assertEqual(a['portal_vertices'], [1, 5])
        middle = next(r for r in a['records'] if r['vertex'] == 3)
        self.assertEqual(middle['applied_game_offset_m'], 6.)
        self.assertEqual(middle['original_network_distance_from_portal_flat_m'], 100.)
        left.close(); right.close()

    def test_short_structure_reports_unattained_nominal_not_fake_full_clearance(self):
        db = synthetic_bridge(12.)
        result = profile.apply(db)
        middle = next(r for r in result['records'] if r['vertex'] == 3)
        self.assertLess(middle['applied_game_offset_m'], 6.)
        self.assertEqual(middle['status'], 'TRANSITION_RELATIVE_TO_SOLVED_PORTAL_HEIGHT_NOT_TERRAIN_COVER')
        self.assertFalse(result['surveyed_elevations_or_native_clearance_verified'])
        solved = profile.solve(db)
        self.assertLessEqual(solved['maximum_allowance_error_m'], 1e-6)
        db.close()

    def test_exact_ten_source_portals_keep_source_topology_and_continuous_height(self):
        data, db = actual_portals()
        raw_before = db.execute('select id,raw,policy,vertices from ways order by id').fetchall()
        edges_before = db.execute('select * from edges order by id').fetchall()
        coords_before = db.execute('select v,node,grade,x,z,base from vertices order by v').fetchall()
        result = profile.apply(db)
        witnessed = {x['original_node'] for x in result['true_portal_source_transitions']}
        self.assertTrue(set(data['witness_original_nodes']).issubset(witnessed))
        for node in data['witness_original_nodes']:
            bounds = db.execute('select lower_y,upper_y from vertices where node=?', (node,)).fetchall()
            self.assertTrue(all(lo is None and hi is None for lo, hi in bounds))
        solved = profile.solve(db)
        for node in data['witness_original_nodes']:
            heights = [x[0] for x in db.execute('select y from vertices where node=?', (node,))]
            self.assertLessEqual(max(heights) - min(heights), 1e-6)
        self.assertEqual(db.execute('select id,raw,policy,vertices from ways order by id').fetchall(), raw_before)
        self.assertEqual(db.execute('select * from edges order by id').fetchall(), edges_before)
        self.assertEqual(db.execute('select v,node,grade,x,z,base from vertices order by v').fetchall(), coords_before)
        self.assertLessEqual(solved['maximum_allowance_error_m'], 1e-6)
        self.assertEqual(solved['conflicting_game_constraints'], 0)
        db.close()


if __name__ == '__main__':
    unittest.main()
