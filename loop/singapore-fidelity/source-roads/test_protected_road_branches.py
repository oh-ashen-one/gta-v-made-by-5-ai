import copy
import unittest

import audit_national as audit
import protected_road_branches as branches
import test_profile_overlap as data
from test_reprofile_country import database


class ProtectedBranchEvidence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db=database();cls.records=branches.discover(cls.db,data.FIXTURE['ways'])
        cls.rules=branches.build_rules(cls.db,cls.records)
        cls.tables={key:data.mesh_table(way) for key,way in data.FIXTURE['ways'].items()}
        find,_=branches.transition_groups(cls.db);cls.find=staticmethod(find)

    @classmethod
    def tearDownClass(cls):cls.db.close()

    def test_all_measured_ramp_cases_explained_but_all_real_defects_remain(self):
        explained,unexplained=0,0
        for row in data.FAILURE['outlier_examples']:
            kept=[];proof=[];x,z=row['xz']
            for key in (row['from'],row['other']):
                indices=[i for i,v in enumerate(data.FIXTURE['ways'][key]['vertex_ids']) if self.find(v)==self.find(row['group'])]
                self.assertEqual(len(indices),1)
                values=audit.heights(self.tables[key],x,z)
                remaining,evidence=branches.partition(values,key,indices[0],x,z,self.rules)
                kept.append(remaining);proof.extend(evidence)
            delta=max(abs(a-b) for a in kept[0] for b in kept[1])
            if delta<=.005:
                self.assertTrue(proof)
                explained+=1
            else:
                self.assertFalse(proof)
                unexplained+=1
        self.assertEqual(explained,16)
        self.assertEqual(unexplained,26)

    def test_no_nearest_height_waiver_without_exact_other_source_branch(self):
        rule=next(iter(self.rules.values()))[0]
        near=rule['near_y'];far=rule['far_y'];key=rule['source_way'];index=rule['near_index']
        points=data.FIXTURE['ways'][key]['canonical_source_points'];p=points[index]
        unknown,evidence=branches.partition([near,far+.01],key,index,p[0],p[2],self.rules)
        self.assertEqual(unknown,[near,far+.01]);self.assertEqual(evidence,[])
        # Even exact far height is not waived without a positive current local surface.
        unknown,evidence=branches.partition([far],key,index,p[0],p[2],self.rules)
        self.assertEqual(unknown,[far]);self.assertEqual(evidence,[])
        unknown,evidence=branches.partition([near,far],key,index,p[0]+100,p[2]+100,self.rules)
        self.assertEqual(unknown,[near,far]);self.assertEqual(evidence,[])

    def test_tampered_portal_ids_or_grade_evidence_rejected(self):
        record=copy.deepcopy(self.records[0]);record['vertex_ids'][0]+=1
        with self.assertRaisesRegex(ValueError,'source identity'):
            branches.build_rules(self.db,[record])
        record=copy.deepcopy(self.records[0]);record['continuation_grades_by_source_index']={}
        with self.assertRaisesRegex(ValueError,'continuation evidence'):
            branches.build_rules(self.db,[record])

    def test_mandai_other_portal_is_not_protected_by_coincident_height_choice(self):
        key='way/1366486110'
        self.assertFalse(any(r['source_way']==key for r in self.records))
        row=next(row for row in data.FAILURE['outlier_examples'] if row['from']==key)
        x,z=row['xz'];values=audit.heights(self.tables[key],x,z)
        self.assertGreater(max(values)-min(values),.06)
        kept,proof=branches.partition(values,key,0,x,z,self.rules)
        self.assertEqual(kept,values);self.assertEqual(proof,[])


if __name__=='__main__':unittest.main()
