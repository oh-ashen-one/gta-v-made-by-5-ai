import json
import math
from pathlib import Path
import unittest

import compile_roads_semantic_v2 as K
import metric_geometry_v4 as G

HERE=Path(__file__).resolve().parent


def source_fixture(items):
    db=K.database(':memory:')
    for item in items:
        raw,policy,ids,points=item['raw'],item['policy'],item['vertices'],item['points']
        for node,v,point in zip(raw['node_ids'],ids,points):
            db.execute('insert or ignore into source_nodes values(?,?,?)',(node,point[0],point[2]))
            db.execute('insert or ignore into vertices values(?,?,?,?,?,?,?,?,?)',(v,node,policy['grade']['key'],point[0],point[2],point[1],None,None,point[1]))
        db.execute('insert into ways values(?,?,?,?,?,?)',(item['id'],'fixture',raw.get('name'),K.canonical(raw).decode(),K.canonical(policy).decode(),K.canonical(ids).decode()))
        for i,(node,v) in enumerate(zip(raw['node_ids'],ids)):db.execute('insert into occurrences values(?,?,?,?)',(node,v,item['id'],int(i in (0,len(ids)-1))))
        for i,(a,b) in enumerate(zip(ids,ids[1:])):
            length=math.hypot(points[i+1][0]-points[i][0],points[i+1][2]-points[i][2])
            grade=.12 if policy['modes']['car']['bits'] else .7 if raw['tags'].get('highway')=='steps' else .25
            db.execute('insert into edges values(?,?,?,?,?,?,?,?,?,?,?)',(item['id']+'@'+str(i),a,b,length,length*grade,item['id'],i,*[policy['modes'][m]['bits'] for m in K.MODES],0))
    K.add_endpoint_transitions(db);K.install_geometry_allowances(db)
    return db


def synthetic(key,tags,ids,points):
    return {'id':key,'raw':{'id':key,'name':None,'tags':tags,'node_ids':ids},'policy':K.way_policy(tags),'vertices':ids,'points':points}


class VersionedMetricGeometry(unittest.TestCase):
    def test_actual_short_stair_flights_gain_real_nonzero_allowance(self):
        data=json.loads((HERE/'metric-v4-fixtures/actual-short-source-stairs.json').read_text())
        for case in data['cases']:
            db=source_fixture([case['stair'],*case['neighbors']]);key=case['stair']['id']
            self.assertEqual(db.execute('select allowance from edges where way=?',(key,)).fetchone()[0],0.)
            facts=db.execute('select id,raw,policy,vertices from ways order by id').fetchall()
            result=G.rebuild(db)
            self.assertFalse(result['unresolved_reliable_flat_stairways'])
            minimum=int(case['stair']['raw']['tags']['step_count'])*.08
            self.assertGreater(db.execute('select allowance from edges where way=?',(key,)).fetchone()[0],minimum)
            self.assertEqual(db.execute('select id,raw,policy,vertices from ways order by id').fetchall(),facts)
            self.assertFalse(result['vehicle_junction_equality_recipes_changed']);db.close()

    def test_private_vehicle_road_grade_tightens_without_adding_access(self):
        item=synthetic('way/1',{'highway':'service','access':'private'},[1,2],[[0.,0.,0.],[100.,0.,0.]])
        db=source_fixture([item]);before=db.execute('select allowance,car,foot from edges').fetchone();G.rebuild(db)
        after=db.execute('select allowance,car,foot from edges').fetchone()
        self.assertLess(after[0],before[0]);self.assertEqual(after[1:],before[1:]);self.assertEqual(after[1],0)
        self.assertLessEqual(after[0],.12*100.);db.close()

    def test_elevator_outline_is_retained_but_has_no_new_horizontal_geometry_equalities(self):
        item=synthetic('way/1',{'highway':'elevator','area':'yes'},[1,2,3,4,1],[[0.,0.,0.],[1.,0.,0.],[1.,0.,1.],[0.,0.,1.],[0.,0.,0.]])
        db=source_fixture([item]);before=db.execute('select id,a,b,length,car,bicycle,foot from edges order by id').fetchall();G.rebuild(db)
        self.assertEqual(db.execute('select count(*) from v4_geometry_constraints where way=?',('way/1',)).fetchone()[0],0)
        self.assertEqual(db.execute('select id,a,b,length,car,bicycle,foot from edges order by id').fetchall(),before)
        self.assertEqual(db.execute('select physical_kind from v4_way_geometry').fetchone()[0],'vertical_transport');db.close()


if __name__=='__main__':unittest.main()
