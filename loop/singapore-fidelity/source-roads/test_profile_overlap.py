import copy
import json
import math
from pathlib import Path
import sqlite3
import unittest

import audit_national as audit
import profile_overlap as overlap

HERE = Path(__file__).resolve().parent
FIXTURE = json.loads((HERE / 'country-r2-records/targeted-profile-fixture.json').read_text())
FAILURE = json.loads((HERE / 'country-r2-records/seam-audit.json').read_text())


def proposals(way, radii=None):
    count = len(way['vertex_ids'])
    hubs, grades = [0.] * count, [[] for _ in range(count)]
    for hub in way['hubs']:
        hubs[hub['index']] = radii.get(hub['vertex_id'], hub['plateau_arc_radius']) if radii is not None else hub['plateau_arc_radius']
        grades[hub['index']] = hub['continuation_grades']
    return overlap.propose(way['canonical_source_points'], way['policy']['width']['metres'], hubs,
                           way['vertex_ids'], grades, source_ele_tag=way['policy']['grade']['source_ele_tag'])


def geometry_proposals():
    radii = {hub['vertex_id']: hub['plateau_arc_radius'] for way in FIXTURE['ways'].values() for hub in way['hubs']}
    parents = {v: v for v in radii}

    def find(v):
        while parents[v] != v:
            parents[v] = parents[parents[v]]
            v = parents[v]
        return v

    for edge in FIXTURE['edges']:
        if edge[10] and edge[1] in parents and edge[2] in parents:
            parents[find(edge[1])] = find(edge[2])
    equalities, history = set(), []
    for iteration in range(32):
        reports = {key: proposals(way, radii) for key, way in FIXTURE['ways'].items()}
        updated = dict(radii)
        for key, report in reports.items():
            equalities.update(tuple(pair) for pair in report['equalities'])
            for index, radius in report['radius_overrides'].items():
                vertex = FIXTURE['ways'][key]['vertex_ids'][int(index)]
                updated[vertex] = max(updated[vertex], radius)
        maximums = {}
        for vertex, radius in updated.items():
            maximums[find(vertex)] = max(maximums.get(find(vertex), 0.), radius)
        updated = {vertex: maximums[find(vertex)] for vertex in updated}
        history.append({'iteration': iteration, 'changed_hubs': sum(updated[v] > radii[v] + 1e-7 for v in radii)})
        if not any(updated[v] > radii[v] + 1e-7 for v in radii):
            return reports, sorted(equalities), radii, history
        radii = updated
    raise ValueError('Bounded targeted geometry-radius fixed point did not converge')


def database(equalities=(), radii=None):
    db = sqlite3.connect(':memory:')
    db.executescript('create table vertices(v integer primary key,node integer,grade text,x real,z real,base real,lower_y real,upper_y real,y real);'
                     'create table edges(id text primary key,a integer,b integer,length real,allowance real,way text,seg integer,car integer,bicycle integer,foot integer,transition integer);'
                     'create table height_constraints(a integer,b integer,allowance real,primary key(a,b));'
                     'create table diagnostics(kind text,detail text);')
    rows = copy.deepcopy(FIXTURE['vertices'])
    for row in rows:
        row[5] = row[8]  # Explicit fixture preferred starting inferred Y, not raw DEM.
    db.executemany('insert into vertices values(?,?,?,?,?,?,?,?,?)', rows)
    db.executemany('insert into edges values(?,?,?,?,?,?,?,?,?,?,?)', FIXTURE['edges'])
    db.executemany('insert into height_constraints values(?,?,?)', FIXTURE['height_constraints'])
    db.executemany('insert or ignore into height_constraints values(?,?,0)', equalities)
    if radii is not None:
        for key, way in FIXTURE['ways'].items():
            points, ids = way['canonical_source_points'], way['vertex_ids']
            layout = overlap.kernel._section_layout(points, way['policy']['width']['metres'], [radii.get(v, 0.) for v in ids])
            for a, b in layout['equalities']:
                if ids[a] != ids[b]:
                    db.execute('insert or ignore into height_constraints values(?,?,0)', tuple(sorted((ids[a], ids[b]))))
            for span in layout['spans']:
                db.execute('update edges set allowance=min(allowance,?) where id=?', (.12 * span['allowance_distance'], key + '@' + str(span['index'])))
    db.commit()
    return db


def mesh_table(way, db=None, radii=None):
    points = copy.deepcopy(way['canonical_source_points'])
    if db is not None:
        for point, vertex in zip(points, way['vertex_ids']):
            point[1] = db.execute('select y from vertices where v=?', (vertex,)).fetchone()[0]
    hubs = [0.] * len(points)
    for hub in way['hubs']:
        hubs[hub['index']] = radii.get(hub['vertex_id'], hub['plateau_arc_radius']) if radii is not None else hub['plateau_arc_radius']
    anchor = [points[0][0], 0., points[0][2]]
    mesh = overlap.kernel.ribbon(points, way['policy']['width']['metres'], anchor, hubs=hubs)
    return audit.triangle_table({'mesh': mesh, 'anchor_source_xyz': anchor})


class TargetedProfileOverlap(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = copy.deepcopy(FIXTURE)
        cls.reports, cls.equalities, cls.radii, cls.radius_history = geometry_proposals()
        cls.db = database(cls.equalities, cls.radii)
        cls.original_edges = FIXTURE['edges']
        cls.solve = overlap.kernel.solve_profiles(cls.db, conflict_policy='reject')
        cls.before = {key: mesh_table(way) for key, way in FIXTURE['ways'].items()}
        cls.after = {key: mesh_table(way, cls.db, cls.radii) for key, way in FIXTURE['ways'].items()}

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_measured_old_failures_are_reproduced_not_discarded(self):
        maximum = {}
        for row in FAILURE['outlier_examples']:
            x, z = row['xz']
            left, right = audit.heights(self.before[row['from']], x, z), audit.heights(self.before[row['other']], x, z)
            delta = max(abs(a - b) for a in left for b in right)
            maximum[row['group']] = max(maximum.get(row['group'], 0.), delta)
        self.assertGreater(maximum[144411], .0609)
        self.assertGreater(maximum[396340], 4.96)
        self.assertGreater(maximum[338649], .0059)
        self.assertGreater(maximum[791776], .032)

    def test_mandai_hindoo_alexandra_actual_meshes_agree_after_proposed_profile(self):
        for row in FAILURE['outlier_examples']:
            if row['group'] in (396340, 396354):
                continue  # Explicitly tested as protected separate levels below.
            x, z = row['xz']
            left, right = audit.heights(self.after[row['from']], x, z), audit.heights(self.after[row['other']], x, z)
            self.assertTrue(left and right, row)
            self.assertLessEqual(max(abs(a - b) for a in left for b in right), .005, row)

    def test_mandai_long_tunnel_retains_underground_interior(self):
        way = FIXTURE['ways']['way/1366486110']
        heights = [self.db.execute('select y from vertices where v=?', (v,)).fetchone()[0] for v in way['vertex_ids']]
        self.assertGreater(way['source_arc_length_m'], 450.)
        self.assertAlmostEqual(heights[0], heights[-1], places=8)
        self.assertLess(min(heights[1:-1]), heights[0] - 3.)
        self.assertLessEqual(abs(heights[0] - way['canonical_source_points'][0][1]), .061)
        self.assertLessEqual(abs(heights[-1] - way['canonical_source_points'][-1][1]), .061)

    def test_parking_ramp_different_grade_portals_stay_separate(self):
        key = 'way/1453057758'
        report, way = self.reports[key], FIXTURE['ways'][key]
        self.assertTrue(report['protected'])
        self.assertTrue(any(row['kind'] == 'DISTINCT_CONTINUATION_GRADES' for row in report['protected']))
        high, low = [self.db.execute('select y from vertices where v=?', (v,)).fetchone()[0] for v in (way['vertex_ids'][0], way['vertex_ids'][-1])]
        self.assertGreater(high - low, 4.)
        for group, adjoining in ((396340, 'way/1453057757'), (396354, 'way/1453057759')):
            row = next(row for row in FAILURE['outlier_examples'] if row['group'] == group)
            x, z = row['xz']
            ramp_values, arrival_values = audit.heights(self.after[key], x, z), audit.heights(self.after[adjoining], x, z)
            self.assertTrue(ramp_values and arrival_values)
            self.assertLessEqual(min(abs(a - b) for a in ramp_values for b in arrival_values), .005)
            self.assertGreater(max(ramp_values) - min(ramp_values), 4.)

    def test_graph_source_identity_and_order_unchanged(self):
        self.assertEqual(FIXTURE, self.original)
        strip_allowance = lambda rows: [list(row[:4]) + list(row[5:]) for row in rows]
        self.assertEqual(strip_allowance(self.db.execute('select * from edges order by id').fetchall()), strip_allowance(self.original_edges))
        for old, new in zip(self.original_edges, self.db.execute('select * from edges order by id')):
            self.assertLessEqual(new[4], old[4] + 1e-12)
        for key, report in self.reports.items():
            ids = set(FIXTURE['ways'][key]['vertex_ids'])
            self.assertTrue(all(a in ids and b in ids for a, b in report['equalities']))
            self.assertFalse(report['source_xz_tags_ids_navigation_mutated'])

    def test_new_profile_keeps_exact_slope_and_height_constraints(self):
        self.assertLessEqual(self.solve['maximum_allowance_error_m'], 1e-7)
        self.assertLessEqual(self.solve['maximum_height_only_constraint_error_m'], 1e-7)
        self.assertEqual(self.solve['conflicting_game_constraints'], 0)
        for table in self.after.values():
            _, gx, gz, _ = table
            self.assertLessEqual(float((gx * gx + gz * gz).max()) ** .5, .121)

    def test_overlapping_multihub_order_invariance_and_disjoint_hubs(self):
        points = [[0., 0., 0.], [1., .1, 0.], [2., .2, 0.], [20., 1., 0.]]
        report = overlap.propose(points, 4., [2.] * 4, [1, 2, 3, 4], [[], [], [], []])
        reverse = overlap.propose(points[::-1], 4., [2.] * 4, [4, 3, 2, 1], [[], [], [], []])
        self.assertEqual(report['equalities'], reverse['equalities'])
        self.assertIn([1, 2], report['equalities'])
        self.assertIn([2, 3], report['equalities'])
        self.assertFalse(any(4 in pair for pair in report['equalities']))

    def test_unconnected_and_different_grade_crossings_are_not_joined(self):
        first = overlap.propose([[-10., 0., 0.], [10., 0., 0.]], 3.2, [1.6, 1.6], [1, 2], [[], []])
        second = overlap.propose([[0., 6., -10.], [0., 6., 10.]], 3.2, [1.6, 1.6], [3, 4], [[], []])
        self.assertEqual(first['equalities'], [])
        self.assertEqual(second['equalities'], [])
        protected = overlap.propose([[0., 0., 0.], [0., 1., 8.], [1., 6., 0.]], 3.2,
                                    [1.6, 0., 1.6], [1, 2, 3], [['["surface",0,""]'], [], ['["bridge",1,""]']])
        self.assertTrue(protected['protected'])
        self.assertNotIn([1, 3], protected['equalities'])

    def test_contradictory_height_bounds_reject_before_height_write(self):
        db = database()
        a, b = FIXTURE['ways']['way/1366486110']['vertex_ids'][0], FIXTURE['ways']['way/1366486110']['vertex_ids'][-1]
        db.execute('update vertices set lower_y=50 where v=?', (a,))
        db.execute('update vertices set upper_y=40 where v=?', (b,))
        db.execute('insert or replace into height_constraints values(?,?,0)', tuple(sorted((a, b))))
        original = db.execute('select v,y from vertices order by v').fetchall()
        with self.assertRaisesRegex(overlap.kernel.RoadError, 'grade constraints conflict'):
            overlap.kernel.solve_profiles(db, conflict_policy='reject')
        self.assertEqual(db.execute('select v,y from vertices order by v').fetchall(), original)
        db.close()

    def test_source_height_evidence_and_nonfinite_input_are_not_overridden(self):
        report = overlap.propose([[0., 0., 0.], [1., 1., 0.]], 4., [2., 2.], [1, 2], [[], []], source_ele_tag='12')
        self.assertEqual(report['status'], 'REVIEW_SOURCE_ELEVATION_EVIDENCE')
        self.assertEqual(report['equalities'], [])
        with self.assertRaises(ValueError):
            overlap.propose([[math.nan, 0., 0.], [1., 1., 0.]], 4., [2., 2.], [1, 2], [[], []])


if __name__ == '__main__':
    unittest.main()
