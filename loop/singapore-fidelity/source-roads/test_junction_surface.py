import copy
import json
import math
from pathlib import Path
import unittest

from shapely.geometry import Polygon, box

import audit_national as audit
import junction_surface as surface

HERE=Path(__file__).resolve().parent
ACTUAL=json.loads((HERE/'country-r2-records/alexandra-surface-fixture.json').read_text())
ORIGINAL=json.loads((HERE/'country-r2-records/targeted-profile-fixture.json').read_text())
ELIGIBILITY=json.loads((HERE/'country-r2-records/measured-repair-eligibility.json').read_text())


class SharedJunctionSurface(unittest.TestCase):
    def test_exact_alexandra_pin_grade_contradiction_is_rejected(self):
        original=copy.deepcopy(ACTUAL)
        footprint,pins,_=surface.original_geometry(ACTUAL['ways'],ACTUAL['anchor_source_xyz'])
        result=surface.preflight(footprint,pins)
        self.assertEqual(result['status'],'INFEASIBLE_FIXED_SOURCE_PINS_FOOTPRINT_AND_GRADE')
        self.assertEqual(len(result['infeasible_pin_pairs']),2)
        self.assertAlmostEqual(result['maximum_required_straight_covered_grade'],.16032500063468888,places=10)
        self.assertTrue(all(row['uncovered_segment_length_m']==0 for row in result['infeasible_pin_pairs']))
        self.assertEqual(ACTUAL,original)
        self.assertFalse(result['mesh_emitted'])

    def test_known_ramp_is_preserved_as_separate_source_sheets(self):
        keys=('way/1453057757','way/1453057758','way/1453057759')
        footprint,pins,_=surface.original_geometry({key:ORIGINAL['ways'][key] for key in keys},[-3959.537,0.,-598.5125])
        result=surface.preflight(footprint,pins,protected_source_branches=ELIGIBILITY['protected_source_portal_records'])
        self.assertEqual(result['status'],'PROTECTED_MULTILEVEL_SOURCE_BRANCHES_REQUIRE_SEPARATE_SHEETS')
        self.assertFalse(result['mesh_emitted'])
        ramp=ORIGINAL['ways']['way/1453057758']['canonical_source_points']
        self.assertAlmostEqual(ramp[0][1]-ramp[-1][1],4.968220851106032,places=9)

    def test_boundary_must_enclose_discontinuity_and_fixed_clean_boundary_still_rejects(self):
        footprint,pins,meshes=surface.original_geometry(ACTUAL['ways'],ACTUAL['anchor_source_xyz'])
        x,_,z=ACTUAL['anchor_source_xyz']
        for radius in (6.,10.,14.):
            controls=surface.boundary_controls(meshes,box(x-radius,z-radius,x+radius,z+radius),pins)
            self.assertEqual(controls['status'],'INCONSISTENT_PATCH_BOUNDARY')
            self.assertGreater(controls['maximum_old_boundary_disagreement_m'],.005)
        domain=box(x-16,z-16,x+16,z+16)
        controls=surface.boundary_controls(meshes,domain,pins)
        self.assertEqual(controls['status'],'BOUNDARY_CONTROLS_AGREE')
        self.assertEqual(controls['conflicts'],[])
        result=surface.preflight(footprint.intersection(domain),controls['pins'])
        self.assertEqual(result['status'],'INFEASIBLE_FIXED_SOURCE_PINS_FOOTPRINT_AND_GRADE')
        self.assertGreater(result['maximum_required_straight_covered_grade'],.20)
        self.assertFalse(result['mesh_emitted'])

    def test_nonroad_gap_is_not_an_invented_metric_shortcut(self):
        footprint=Polygon([(0,0),(1,0),(1,1),(0,1)]).union(Polygon([(3,0),(4,0),(4,1),(3,1)]))
        result=surface.preflight(footprint,[{'source_xyz':[.5,0.,.5]},{'source_xyz':[3.5,5.,.5]}])
        self.assertEqual(result['covered_pin_pairs'],0)
        self.assertEqual(result['status'],'PIN_PAIR_NECESSARY_CONDITIONS_PASS_NOT_A_SURFACE_SOLUTION')

    def test_same_xz_different_levels_are_not_nearest_height_merged(self):
        result=surface.preflight(Polygon([(0,0),(2,0),(2,2),(0,2)]),[{'source_xyz':[1.,0.,1.]},{'source_xyz':[1.,4.,1.]}])
        self.assertEqual(result['status'],'INCONSISTENT_MULTIPLE_Y_PINS_AT_SAME_XZ')
        self.assertFalse(result['mesh_emitted'])

    def test_feasible_banked_field_clips_each_footprint_preserves_holes_and_overlap(self):
        origin=80000.;anchor=[origin,0.,origin]
        def p(x,z):return [origin+x,20.+.01*x+.02*z,origin+z]
        field=[[p(0,0),p(10,0),p(0,10)],[p(10,0),p(10,10),p(0,10)]]
        a=Polygon([(origin,origin),(origin+8,origin),(origin+8,origin+8),(origin,origin+8)],holes=[[(origin+2,origin+2),(origin+4,origin+2),(origin+4,origin+4),(origin+2,origin+4)]])
        b=Polygon([(origin+3,origin+2),(origin+9,origin+2),(origin+9,origin+9),(origin+3,origin+9)])
        meshes=[surface.clipped_shared_planes(field,shape,anchor) for shape in (a,b)]
        tables=[audit.triangle_table({'mesh':mesh,'anchor_source_xyz':anchor}) for mesh in meshes]
        self.assertFalse(audit.heights(tables[0],origin+3,origin+3))
        for x,z in ((5,6),(4.5,2.5),(5.5,7),(3.5,5.5)):
            values=[audit.heights(table,origin+x,origin+z) for table in tables]
            self.assertTrue(all(values))
            self.assertLessEqual(max(abs(left-right) for left in values[0] for right in values[1]),.00025)
            self.assertLessEqual(max(abs(y-(20.+.01*x+.02*z)) for row in values for y in row),.00025)
        for mesh,table in zip(meshes,tables):
            self.assertLessEqual(mesh['footprint_symmetric_difference_m2'],1e-7)
            _,gx,gz,_=table
            self.assertLessEqual(float((gx*gx+gz*gz).max())**.5,.121)
            self.assertFalse(mesh['source_profile_navigation_or_canonical_XZ_mutated'])

    def test_hard_grade_and_nonfinite_values_cannot_be_waived(self):
        footprint=Polygon([(0,0),(10,0),(10,10),(0,10)])
        with self.assertRaisesRegex(ValueError,'hard grade'):
            surface.clipped_shared_planes([[[0,0,0],[10,5,0],[0,0,10]]],footprint,[0,0,0])
        with self.assertRaisesRegex(ValueError,'Finite canonical'):
            surface.clipped_shared_planes([[[0,0,0],[10,math.nan,0],[0,0,10]]],footprint,[0,0,0])
        with self.assertRaisesRegex(ValueError,'cannot be relaxed'):
            surface.preflight(footprint,[{'source_xyz':[0,0,0]},{'source_xyz':[1,1,0]}],maximum_grade=.2)


if __name__=='__main__':unittest.main()
