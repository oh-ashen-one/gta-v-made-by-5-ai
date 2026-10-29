import copy
import math
import json
from pathlib import Path
import unittest

import road_semantics_v2 as policy


class CorrectSourceVerticalSemantics(unittest.TestCase):
    def test_building_passage_missing_layer_is_covered_zero_without_depth_cap(self):
        tags={'highway':'service','tunnel':'building_passage'};before=copy.deepcopy(tags)
        grade=policy.grade_policy(tags);bounds=policy.metric_assumption(grade,20.)
        self.assertEqual(grade['structure'],'covered_passage');self.assertEqual(grade['layer'],0)
        self.assertFalse(grade['source_layer_explicit']);self.assertTrue(grade['covered_building_passage'])
        self.assertIsNone(bounds['lower_y']);self.assertIsNone(bounds['upper_y']);self.assertEqual(tags,before)

    def test_explicit_negative_passage_layer_and_level_are_order_not_depth(self):
        grade=policy.grade_policy({'highway':'service','tunnel':'building_passage','layer':'-2','level':'-1'})
        self.assertEqual((grade['layer'],grade['raw_layer'],grade['level']),(-2,'-2','-1'))
        self.assertTrue(grade['source_layer_explicit'])
        self.assertIsNone(policy.metric_assumption(grade,20.)['upper_y'])
        self.assertFalse(grade['metric_layer_height_is_source_fact'])

    def test_explicit_underground_location_remains_distinct_from_covered(self):
        grade=policy.grade_policy({'tunnel':'building_passage','location':'underground','layer':'-1'})
        self.assertEqual(grade['structure'],'tunnel')
        self.assertTrue(grade['explicit_underground_location'])
        self.assertEqual(policy.metric_assumption(grade,20.)['upper_y'],15.)

    def test_ordinary_tunnel_keeps_own_role_but_no_ordinal_multiplication(self):
        for layer in ('-1','-3','-5'):
            grade=policy.grade_policy({'tunnel':'yes','layer':layer})
            self.assertEqual(grade['structure'],'tunnel');self.assertEqual(grade['raw_layer'],layer)
            bounds=policy.metric_assumption(grade,30.)
            self.assertEqual(bounds['upper_y'],25.);self.assertFalse(bounds['layer_ordinal_multiplied_into_metres'])

    def test_bridge_ordinal_preserved_without_fictional_storey_height(self):
        for layer in ('1','4','-1'):
            grade=policy.grade_policy({'bridge':'yes','layer':layer})
            self.assertEqual(grade['layer'],int(layer))
            self.assertEqual(policy.metric_assumption(grade,30.)['lower_y'],36.)
        self.assertEqual(policy.grade_policy({'bridge':'yes'})['layer'],1)

    def test_negative_surface_layer_does_not_mean_underground(self):
        grade=policy.grade_policy({'highway':'service','layer':'-1'})
        self.assertEqual(grade['structure'],'surface')
        self.assertIsNone(policy.metric_assumption(grade,30.)['upper_y'])

    def test_bridge_through_building_is_not_false_tunnel_conflict(self):
        grade=policy.grade_policy({'bridge':'yes','tunnel':'building_passage','layer':'2'})
        self.assertEqual(grade['structure'],'bridge');self.assertTrue(grade['covered_building_passage'])
        self.assertEqual(policy.metric_assumption(grade,30.)['lower_y'],36.)
        self.assertEqual(policy.grade_policy({'bridge':'yes','tunnel':'yes'})['structure'],'conflicting_structure')

    def test_covered_compatibility_is_exact_layer_level_not_xy_or_tag_erasure(self):
        surface=policy.grade_policy({'highway':'service'})
        passage=policy.grade_policy({'highway':'service','tunnel':'building_passage'})
        negative=policy.grade_policy({'highway':'service','tunnel':'building_passage','layer':'-1'})
        self.assertEqual(surface['key'],passage['key'])
        self.assertNotEqual(surface['key'],negative['key'])
        self.assertNotEqual(passage['structure'],surface['structure'])
        self.assertEqual(passage['raw_tunnel'],'building_passage')

    def test_unknown_tunnel_values_and_bad_layer_are_not_fabricated_depth(self):
        for tunnel in ('covered','corridor','avalanche_protector','custom_value'):
            grade=policy.grade_policy({'tunnel':tunnel})
            self.assertEqual(grade['structure'],'unresolved_tunnel_value')
            self.assertEqual(grade['raw_tunnel'],tunnel)
            self.assertIsNone(policy.metric_assumption(grade,20.)['upper_y'])
        invalid=policy.grade_policy({'tunnel':'building_passage','layer':'1;2'})
        self.assertIsNone(invalid['layer']);self.assertEqual(invalid['raw_layer'],'1;2')
        self.assertIn('unresolved_raw_layer',invalid['key'])

    def test_explicit_elevation_text_and_datum_are_preserved_not_guessed(self):
        grade=policy.grade_policy({'bridge':'yes','ele':'99.5','ele:datum':'unverified_local'})
        self.assertEqual(grade['source_ele_tag'],'99.5');self.assertEqual(grade['source_ele_datum'],'unverified_local')
        self.assertEqual(policy.metric_assumption(grade,20.)['lower_y'],26.)

    def test_source_proven_parking_ramp_remains_a_relative_multilevel_site(self):
        fixture=json.loads((Path(__file__).resolve().parent/'country-r2-records/targeted-profile-fixture.json').read_text())
        ramp=fixture['ways']['way/1453057758'];upper=fixture['ways']['way/1453057757'];lower=fixture['ways']['way/1453057759']
        upper_grade=policy.grade_policy(upper['raw_source']['tags']);lower_grade=policy.grade_policy(lower['raw_source']['tags'])
        endpoints=[ramp['raw_source']['node_ids'][0],ramp['raw_source']['node_ids'][-1]]
        self.assertIn(endpoints[0],upper['raw_source']['node_ids']);self.assertIn(endpoints[1],lower['raw_source']['node_ids'])
        self.assertEqual((upper_grade['layer'],lower_grade['layer']),(1,0))
        result=policy.ramp_order_assumption(1,0,source_way_connected=True,ports_overlap=True,
                                           original_endpoint_nodes=endpoints,available_source_path_m=ramp['source_arc_length_m'])
        self.assertEqual(result['constraint'],{'upper_endpoint':0,'lower_endpoint':1,'minimum_game_separation_m':5.})
        self.assertFalse(result['ordinal_difference_used_as_metric_storeys'])
        other=policy.ramp_order_assumption(5,-2,source_way_connected=True,ports_overlap=True,
                                          original_endpoint_nodes=[1,2],available_source_path_m=60.)
        self.assertEqual(other['constraint']['minimum_game_separation_m'],5.)

    def test_unconnected_or_too_short_ramp_has_no_fake_clearance(self):
        unconnected=policy.ramp_order_assumption(1,0,source_way_connected=False,ports_overlap=True,original_endpoint_nodes=[1,2],available_source_path_m=60.)
        self.assertIsNone(unconnected['constraint'])
        short=policy.ramp_order_assumption(1,0,source_way_connected=True,ports_overlap=True,original_endpoint_nodes=[1,2],available_source_path_m=10.)
        self.assertEqual(short['status'],'INFEASIBLE_LOCAL_GAME_CLEARANCE_REQUIRES_REVIEW');self.assertIsNone(short['constraint'])

    def test_typed_guards_precede_inference(self):
        with self.assertRaises(ValueError):policy.grade_policy({'layer':True})
        with self.assertRaises(ValueError):policy.metric_assumption(policy.grade_policy({}),math.nan)
        with self.assertRaises(ValueError):policy.ramp_order_assumption(1,0,source_way_connected='yes',ports_overlap=True,original_endpoint_nodes=[1,2],available_source_path_m=60.)


if __name__=='__main__':unittest.main()
