import unittest
import numpy as np
import audit_national as audit

class StreamingAudit(unittest.TestCase):
    def feature(self):
        # Clockwise top: crossYnegative; incline10% along+X.
        return {'anchor_source_xyz':[50000.,10.,-50000.],'mesh':{'vertices_local_xyz':[[0,0,0],[10,1,0],[0,0,10]],'indices':[0,1,2]}}
    def test_feature_local_anchor_restores_canonical_heights(self):
        table=audit.triangle_table(self.feature())
        values=audit.heights(table,50002.,-49998.)
        self.assertEqual(len(values),1)
        self.assertAlmostEqual(values[0],10.2)
        self.assertEqual(audit.heights(table,50009.,-49991.),[])
    def test_actual_reversed_winding_is_not_hidden_by_normals(self):
        f=self.feature();f['mesh']['indices']=[0,2,1]
        with self.assertRaises(ValueError):audit.triangle_table(f)
    def test_nonfinite_mesh_rejected_before_sampling(self):
        f=self.feature();f['mesh']['vertices_local_xyz'][0][0]=float('nan')
        with self.assertRaises(ValueError):audit.triangle_table(f)

if __name__=='__main__':unittest.main()
