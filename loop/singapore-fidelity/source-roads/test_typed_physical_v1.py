import copy
import json
from pathlib import Path
import unittest

import numpy as np
import compile_roads_semantic_v2 as K
import typed_physical_v1 as T
import audit_national as audit

HERE=Path(__file__).resolve().parent


def make(points,tags,identifier='way/1'):
    raw={'id':identifier,'name':'Fixture','tags':tags,'source_feature_sha256':'f'*64,'source_geometry_sha256':'e'*64}
    return T.build_feature(identifier,raw,K.way_policy(tags),list(range(1,len(points)+1)),points,{},[-30,-30,30,30],'fixture')


class TypedSourcePhysicalSurfaces(unittest.TestCase):
    def test_footbridge_slope_does_not_widen_car_contract(self):
        points=[[-10.,6.,0.],[10.,9.,0.]]
        feature,error=make(points,{'highway':'footway','bridge':'yes','layer':'1'})
        self.assertIsNone(error)
        self.assertEqual(feature['physical_contract']['surface_class'],'foot_ribbon')
        self.assertEqual(feature['policy']['modes']['car']['bits'],0)
        self.assertGreater(feature['mesh']['maximum_emitted_surface_slope'],.122)
        with self.assertRaisesRegex(ValueError,'car_ribbon'):
            make(points,{'highway':'residential'})
        self.assertEqual(T.NATIVE_LIMIT['car_ribbon'],.122)

    def test_different_level_crossing_keeps_distinct_original_surfaces(self):
        car,_=make([[-10.,0.,0.],[10.,0.,0.]],{'highway':'residential'},'way/1')
        bridge,_=make([[0.,6.,-10.],[0.,6.,10.]],{'highway':'footway','bridge':'yes','layer':'1'},'way/2')
        self.assertEqual(set(round(y,6) for y in audit.heights(audit.triangle_table(car),0,0)),{0.})
        self.assertEqual(set(round(y,6) for y in audit.heights(audit.triangle_table(bridge),0,0)),{6.})
        self.assertNotEqual(car['id'],bridge['id'])
        self.assertEqual(car['source_points_xyz'],[[-10.,0.,0.],[10.,0.,0.]])

    def test_visible_step_count_direction_and_separate_walk_collision(self):
        for first,last,incline in [(0.,1.7,'up'),(1.7,0.,'down')]:
            feature,error=make([[0.,first,0.],[5.,last,0.]],{'highway':'steps','step_count':'10','incline':incline})
            self.assertIsNone(error)
            self.assertEqual(feature['physical_contract']['surface_class'],'foot_steps')
            self.assertEqual(feature['step_evidence']['steps'],10)
            self.assertEqual(feature['visual_mesh']['counts']['riser_triangles'],20)
            self.assertEqual(feature['visual_mesh']['counts']['tread_triangles'],20)
            self.assertEqual(feature['mesh']['usage'],'CONTINUOUS_STAIR_WALK_COLLISION_ONLY')
            self.assertFalse(feature['mesh']['native_collision_uses_identical_topology'])
            normals=np.asarray(feature['visual_mesh']['normals'])
            risers=normals[np.abs(normals[:,1])<.01]
            self.assertTrue(np.all(risers[:,0]<0) if incline=='up' else np.all(risers[:,0]>0))

    def test_source_count_or_incline_conflict_is_not_rewritten_to_pass(self):
        tags={'highway':'steps','step_count':'10','incline':'down'};before=copy.deepcopy(tags)
        feature,error=make([[0.,0.,0.],[5.,1.7,0.]],tags)
        self.assertIsNone(feature);self.assertIn('CONTRADICTS',error['status']);self.assertEqual(tags,before)
        feature,error=make([[0.,0.,0.],[20.,11.499,0.]],{'highway':'steps','step_count':'44','incline':'up'})
        self.assertIsNone(feature);self.assertIn('RISER_OR_TREAD',error['status'])
        self.assertEqual(error['source_count_preserved'],44)

    def test_area_boundary_is_not_filled_or_misrepresented_as_line_walkway(self):
        feature,error=make([[0.,0.,0.],[5.,0.,0.],[5.,0.,5.],[0.,0.,0.]],{'highway':'pedestrian','area':'yes'})
        self.assertIsNone(feature);self.assertIn('POLYGON_AND_HOLE',error['status'])

    def test_actual_jubilee_helix_and_cavenagh_source_decks(self):
        data=json.loads((HERE/'typed-physical-fixtures/actual-central-footbridges.json').read_text())
        checked=0
        for row in data['features']:
            before=copy.deepcopy(row)
            feature,error=T.build_feature(row['id'],row['raw'],row['policy'],row['source_vertex_ids'],row['source_points_xyz'],dict(row['render_hubs']),[-2000,-2500,2000,2000],'actual-fixture')
            self.assertIsNone(error,row['id']);self.assertEqual(row,before)
            self.assertEqual(feature['physical_contract']['surface_class'],'foot_ribbon')
            self.assertEqual(feature['name'],row['raw']['name'])
            self.assertEqual(feature['source_points_xyz'],row['source_points_xyz'])
            self.assertLessEqual(feature['mesh']['maximum_emitted_surface_slope'],.251)
            tri,gx,gz,_=audit.triangle_table(feature)
            self.assertTrue(np.all(np.isfinite(tri)))
            self.assertLessEqual(float(np.hypot(gx,gz).max()),.251)
            checked+=1
        self.assertEqual(checked,6)


if __name__=='__main__':unittest.main()
