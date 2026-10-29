import copy
import json
from pathlib import Path
import unittest

import audit_national as audit
import compile_roads_semantic_v2 as K
import stair_portal_geometry_v4 as geometry

HERE=Path(__file__).resolve().parent


class ActualShortSourceStairGeometry(unittest.TestCase):
    def test_four_step_and_single_step_source_flights_have_clear_connected_apertures(self):
        data=json.loads((HERE/'metric-v4-fixtures/actual-short-source-stairs.json').read_text())
        for case in data['cases']:
            stair=case['stair'];neighbors=copy.deepcopy(case['neighbors']);before=copy.deepcopy(stair)
            low=stair['points'][0][1];count=int(stair['raw']['tags']['step_count']);high=low+.17*count
            # An explicitly proposed local relative height for this geometry
            # fixture, not an adopted country metric or surveyed stair height.
            for neighbor in neighbors:
                endpoint=stair['raw']['node_ids'][-1]
                if endpoint in neighbor['raw']['node_ids']:
                    delta=high-neighbor['points'][neighbor['raw']['node_ids'].index(endpoint)][1]
                    for point in neighbor['points']:point[1]+=delta
            plan=geometry.flight(stair,neighbors,low,high)
            anchor=[stair['points'][0][0],low,stair['points'][0][2]]
            built=geometry.stair_mesh(stair,plan,anchor)
            self.assertEqual(built['step_evidence']['steps'],count)
            self.assertLessEqual(built['mesh']['maximum_emitted_surface_slope'],.701)
            self.assertEqual(stair,before)
            clear=[]
            for neighbor in neighbors:
                mesh=K.ribbon(neighbor['points'],neighbor['policy']['width']['metres'],anchor,None,[dict(neighbor['radii']).get(v,0.) for v in neighbor['vertices']])
                clipped,report=geometry.trim_connected_neighbor(neighbor,mesh,anchor,stair,plan)
                self.assertFalse(report['original_centreline_removed'])
                self.assertGreater(report['removed_overhanging_surface_area_m2'],0)
                clear.append(audit.triangle_table({'mesh':clipped,'anchor_source_xyz':anchor}))
            walking=audit.triangle_table(built)
            p0,p1=plan['derived_non_source_geometry_points'][1:3]
            for fraction in (.2,.5,.8):
                x=p0[0]+(p1[0]-p0[0])*fraction;z=p0[2]+(p1[2]-p0[2])*fraction
                surfaces=audit.heights(walking,x,z)
                self.assertTrue(surfaces)
                self.assertTrue(all(abs(y-(low+(high-low)*fraction))<.00025 for y in surfaces))
                self.assertTrue(all(not audit.heights(table,x,z) for table in clear),'Connected flat apron still overhangs the stair flight')

    def test_unconnected_equal_xy_way_is_not_cut(self):
        case=json.loads((HERE/'metric-v4-fixtures/actual-short-source-stairs.json').read_text())['cases'][0]
        stair=case['stair'];neighbor=copy.deepcopy(case['neighbors'][0]);neighbor['raw']['node_ids']=[n+100000000000 for n in neighbor['raw']['node_ids']]
        plan=geometry.flight(stair,case['neighbors'],0.,.68)
        dummy={'untouched':'unconnected geometry'}
        result,report=geometry.trim_connected_neighbor(neighbor,dummy,[0,0,0],stair,plan)
        self.assertIs(result,dummy);self.assertEqual(report['status'],'UNCHANGED_UNCONNECTED_SOURCE_WAY')

    def test_same_node_without_explicit_grade_connection_cannot_be_cut(self):
        case=json.loads((HERE/'metric-v4-fixtures/actual-short-source-stairs.json').read_text())['cases'][0]
        neighbors=copy.deepcopy(case['neighbors']);neighbors[0]['vertices']=[v+1000000 for v in neighbors[0]['vertices']]
        with self.assertRaisesRegex(ValueError,'explicit original transition binding'):
            geometry.flight(case['stair'],neighbors,0.,.68)


if __name__=='__main__':unittest.main()
