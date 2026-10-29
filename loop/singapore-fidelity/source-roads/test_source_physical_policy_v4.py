import copy
import unittest

import compile_roads_semantic_v2 as K
import source_physical_policy_v4 as P


class SourcePhysicalExistenceAndStairFacts(unittest.TestCase):
    def test_private_service_road_exists_with_car_grade_but_keeps_access_blocked(self):
        tags={'highway':'service','access':'private','oneway':'yes'};policy=K.way_policy(tags);before=copy.deepcopy((tags,policy))
        result=P.physical_role(tags,policy)
        self.assertEqual(result['physical_kind'],'vehicle_road')
        self.assertEqual(result['maximum_game_grade'],.12)
        self.assertEqual(result['original_navigation_direction_bits']['car'],0)
        self.assertEqual((tags,policy),before)

    def test_denied_footway_still_has_physical_surface_without_fake_AI_access(self):
        tags={'highway':'footway','foot':'no'}
        result=P.physical_role(tags,K.way_policy(tags))
        self.assertEqual(result['physical_kind'],'foot_surface')
        self.assertEqual(result['original_navigation_direction_bits']['foot'],0)

    def test_steps_are_never_a_car_ribbon_even_with_inconsistent_motorcar_tag(self):
        tags={'highway':'steps','motorcar':'yes'}
        result=P.physical_role(tags,K.way_policy(tags))
        self.assertEqual(result['physical_kind'],'foot_steps')
        self.assertEqual(result['maximum_game_grade'],.7)

    def test_reliable_original_order_and_source_count_are_preserved(self):
        for sign,tag in [(1,'up'),(-1,'down')]:
            tags={'highway':'steps','incline':tag,'step_count':'4'};before=copy.deepcopy(tags)
            result=P.stair_constraints(tags,[101,102],1.5)
            self.assertEqual(result['status'],'SOURCE_SIGN_WITH_EXPLICIT_GAME_RISE_INTERVAL')
            self.assertEqual(result['source_step_count'],4)
            self.assertEqual(result['minimum_game_rise_m'],.32)
            self.assertEqual(result['maximum_game_rise_m'],.96)
            self.assertEqual(result['lower_original_node'],101 if sign>0 else 102)
            self.assertEqual(tags,before)

    def test_source_count_and_grade_conflict_are_not_silently_reduced(self):
        result=P.stair_constraints({'highway':'steps','incline':'up','step_count':'44'},[1,2],2.)
        self.assertEqual(result['status'],'SOURCE_COUNT_RUN_AND_UNCHANGED_STEP_GRADE_INFEASIBLE')
        self.assertEqual(result['source_step_count'],44)
        self.assertEqual(result['maximum_game_rise_m'],1.4)

    def test_area_lift_and_unbuilt_site_need_their_actual_geometry_classes(self):
        for tags,kind in [({'highway':'pedestrian','area':'yes'},'source_area'),({'highway':'elevator'},'vertical_transport'),({'highway':'construction','construction':'service'},'construction_or_proposed_site')]:
            self.assertEqual(P.physical_role(tags,K.way_policy(tags))['physical_kind'],kind)

    def test_actual_elevator_footprint_is_not_a_flat_pedestrian_area(self):
        tags={'highway':'elevator','area':'yes'}
        result=P.physical_role(tags,K.way_policy(tags))
        self.assertEqual(result['physical_kind'],'vertical_transport')
        self.assertIsNone(result['maximum_game_grade'])
        self.assertIn('PHYSICAL_LIFT',result['status'])


if __name__=='__main__':unittest.main()
