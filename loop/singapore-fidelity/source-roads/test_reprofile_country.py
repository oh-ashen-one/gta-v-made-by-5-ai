import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

import reprofile_country as recipe
import test_profile_overlap as fixture


def database():
    db = fixture.database()
    db.executescript('create table ways(id text primary key,owner text,name text,raw text,policy text,vertices text);'
                     'create table owners(owner text primary key,descriptor text);'
                     'create table occurrences(node integer,v integer,way text,endpoint integer);'
                     'create table render_hubs(v integer primary key,radius real);')
    for key, way in fixture.FIXTURE['ways'].items():
        db.execute('insert into ways values(?,?,?,?,?,?)', (key, 'fixture', way['raw_source']['name'], json.dumps(way['raw_source']), json.dumps(way['policy']), json.dumps(way['vertex_ids'])))
        for i, vertex in enumerate(way['vertex_ids']):
            node = db.execute('select node from vertices where v=?', (vertex,)).fetchone()[0]
            db.execute('insert into occurrences values(?,?,?,?)', (node, vertex, key, int(i in (0, len(way['vertex_ids'])-1))))
        for hub in way['hubs']:
            db.execute('insert or replace into render_hubs values(?,?)', (hub['vertex_id'], hub['plateau_arc_radius']))
    db.execute('insert into owners values(?,?)', ('fixture', 'raw source descriptor'))
    db.commit()
    return db


class GlobalRecipeSafety(unittest.TestCase):
    def setUp(self):
        self.before, self.after = database(), database()
        self.after.execute('create table protected_levels(way text,a integer,b integer,details text)')

    def tearDown(self):
        self.before.close(); self.after.close()

    def test_exact_source_baseline_is_accepted(self):
        result = recipe.verify_invariants(self.before, self.after)
        self.assertEqual(result['new_or_worsened_bounds'], 0)
        self.assertEqual(result['changed_inferred_vertex_heights'], 0)

    def test_source_xy_and_direction_change_are_rejected(self):
        vertex = self.after.execute('select min(v) from vertices').fetchone()[0]
        self.after.execute('update vertices set x=x+.001 where v=?', (vertex,))
        with self.assertRaisesRegex(ValueError, 'invariant changed'):
            recipe.verify_invariants(self.before, self.after)
        original_x = self.before.execute('select x from vertices where v=?', (vertex,)).fetchone()[0]
        self.after.execute('update vertices set x=? where v=?', (original_x, vertex))
        self.after.execute('update edges set car=0 where id=(select min(id) from edges)')
        with self.assertRaisesRegex(ValueError, 'navigation_edges'):
            recipe.verify_invariants(self.before, self.after)

    def test_grade_allowance_cannot_relax(self):
        self.after.execute('update edges set allowance=allowance+.1 where id=(select min(id) from edges)')
        with self.assertRaisesRegex(ValueError, 'allowance relaxed'):
            recipe.verify_invariants(self.before, self.after)

    def test_each_height_bound_is_checked_independently(self):
        vertex = self.after.execute('select min(v) from vertices').fetchone()[0]
        for db in (self.before, self.after):
            db.execute('update vertices set lower_y=0,upper_y=-10,y=-1 where v=?', (vertex,))
        self.after.execute('update vertices set y=-2 where v=?', (vertex,))
        # Upper violation improves, but lower violation worsens: max-only
        # checking would hide the regression under the larger old violation.
        with self.assertRaisesRegex(ValueError, 'height-bound contradictions'):
            recipe.verify_invariants(self.before, self.after)

    def test_new_inherited_conflict_is_not_silently_accepted(self):
        self.before.execute("insert into diagnostics values('incompatible_bridge_tunnel_clearance_constraints','1')")
        self.after.execute("insert into diagnostics values('incompatible_bridge_tunnel_clearance_constraints','2')")
        with self.assertRaisesRegex(ValueError, 'height-bound contradictions'):
            recipe.verify_invariants(self.before, self.after)

    def test_copied_geometry_recipe_converges_and_preserves_protected_ramp(self):
        self.after.close(); self.after = database()
        eligibility=json.loads((Path(__file__).resolve().parent/'country-r2-records/measured-repair-eligibility.json').read_text())
        with tempfile.TemporaryDirectory() as temporary:
            result = recipe.propose_geometry(self.after, Path(temporary),eligibility)
        self.assertEqual(result['changed_hub_radii'], 3)
        self.assertEqual(result['rounds'][-1]['changed_hubs'], 0)
        self.assertEqual(result['repair_source_ways'],eligibility['selected_incident_source_ways'])
        self.assertNotIn('way/1453057758',result['repair_source_ways'])
        self.assertTrue(all(v in eligibility['target_original_vertices'] for v, in self.after.execute('select v from radius_changes')))
        solved = recipe.F.solve_profiles(self.after, conflict_policy='reject')
        self.assertEqual(solved['conflicting_game_constraints'], 0)
        result = recipe.verify_invariants(self.before, self.after)
        ramp = next(p for p in result['protected_levels'] if p['source_way'] == 'way/1453057758')
        self.assertGreater(ramp['inferred_height_gap_m'], 4.9)
        self.assertTrue(result['original_IDS_XZ_tags_order_directions_access_unchanged'])


if __name__ == '__main__':
    unittest.main()
