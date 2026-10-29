import json
import math
from pathlib import Path
import tempfile
import unittest

import numpy as np
from shapely.geometry import Point, Polygon

from compile_roads import (RoadError,canonical,sha,database,ingest_catalog,
    add_endpoint_transitions,solve_profiles,route,ribbon,width_policy,
    direction_policy,mode_access,grade_policy,read_bound,export_catalogs,way_policy,
    install_geometry_allowances,_hub_vertices,_section_layout)

class Flat:
    def sample(self,x,z): return 0.0

def catalog(ways,owner='0_0',anchor=None):
    anchor=anchor or [0.,0.,0.]
    features=[]
    for identifier,refs,points,tags in ways:
        features.append({'id':identifier,'kind':'road','feature_key':'road|'+identifier,
          'catalog_owner':owner,'canonical_anchor_source_xyz':anchor.copy(),'name':tags.get('name'),
          'source_feature_sha256':'a'*64,'source_geometry_sha256':'b'*64,
          'source_bounds_xz':[min(p[0]+anchor[0] for p in points),min(p[1]+anchor[2] for p in points),max(p[0]+anchor[0] for p in points),max(p[1]+anchor[2] for p in points)],
          'road':{'source_contract_issues':[],'original_ordered_node_ids':refs.copy(),'centerline_local_xz_double':points,
                  'full_source_tags':tags.copy(),'source_version':1}})
    return {'schema':'singapore_source_city_geometry_v1','owner':owner,'anchor_source_xyz':anchor,'features':features}

class Roads(unittest.TestCase):
    def setUp(self): self.temp=tempfile.TemporaryDirectory();self.db=database(Path(self.temp.name)/'work.sqlite')
    def tearDown(self): self.db.close();self.temp.cleanup()
    def vertex(self,node,structure=None):
        rows=self.db.execute('select v,grade from vertices where node=?',(node,)).fetchall()
        return next(v for v,g in rows if structure is None or json.loads(g)[0]==structure)
    def test_actual_direction_not_undirected_expansion(self):
        for tag,bits in [('yes',1),('-1',2),('no',3),('reversible',0)]:
            self.assertEqual(direction_policy({'oneway':tag},'car')['bits'],bits)
        self.assertEqual(direction_policy({'junction':'roundabout'},'car')['bits'],1)
        self.assertEqual(direction_policy({'highway':'motorway'},'car')['bits'],1)
        self.assertNotIn('implied_oneway',direction_policy({'highway':'motorway_link'},'car')['status'])
        self.assertEqual(direction_policy({'oneway':'yes'},'foot')['bits'],3)
        self.assertEqual(direction_policy({'oneway':'yes','oneway:bicycle':'no'},'bicycle')['bits'],3)
        self.assertEqual(direction_policy({'oneway:conditional':'yes @ (Mo-Fr)'},'car')['bits'],0)
        self.assertEqual(direction_policy({'highway':'steps','oneway':'yes'},'foot')['bits'],0)
        ingest_catalog(self.db,catalog([('way/1',[1,2],[[0,0],[10,0]],{'highway':'primary','oneway':'yes'})]),Flat())
        a,b=self.vertex(1),self.vertex(2)
        self.assertTrue(route(self.db,a,b)['found']);self.assertFalse(route(self.db,b,a)['found'])
    def test_access_specificity_and_unresolved_conditions(self):
        self.assertEqual(mode_access({'highway':'primary','access':'no','motorcar':'yes'},'car')['state'],'allowed')
        self.assertEqual(mode_access({'highway':'primary','vehicle':'yes','motorcar':'no'},'car')['state'],'blocked')
        self.assertEqual(mode_access({'highway':'service','access':'destination'},'car')['state'],'restricted')
        self.assertEqual(mode_access({'highway':'primary','motor_vehicle:conditional':'no @ (wet)'},'car')['state'],'conditional_unresolved')
        self.assertNotEqual(mode_access({'highway':'footway'},'car')['state'],'allowed')
        self.assertEqual(mode_access({'highway':'steps'},'foot')['state'],'allowed')
        self.assertEqual(mode_access({'highway':'primary','motor_vehicle:forward':'no'},'car','forward')['state'],'blocked')
        self.assertEqual(mode_access({'highway':'primary','motor_vehicle:forward':'no'},'car','backward')['state'],'allowed')
        p=way_policy({'highway':'primary','oneway':'no','motor_vehicle:forward':'no'})
        self.assertEqual(p['modes']['car']['bits'],2)
    def test_width_sources_and_explicit_fallbacks(self):
        self.assertEqual(width_policy({'width':'7 m','lanes':'4'})['metres'],7)
        self.assertEqual(width_policy({'width':'7','width:carriageway':'6'})['metres'],6)
        self.assertAlmostEqual(width_policy({'width':"10' 0\""})['metres'],3.048)
        self.assertAlmostEqual(width_policy({'lanes':'3'})['metres'],9.6,places=12)
        self.assertEqual(width_policy({'highway':'path'})['metres'],2)
        self.assertIn('GAME',width_policy({'highway':'primary','width':'unknown'})['status'])
    def test_equal_xy_never_connects_different_source_nodes(self):
        ingest_catalog(self.db,catalog([
          ('way/1',[1,2],[[0,0],[10,0]],{'highway':'primary','oneway':'no'}),
          ('way/2',[3,4],[[0,0],[0,10]],{'highway':'primary','oneway':'no'})]),Flat())
        self.assertEqual(add_endpoint_transitions(self.db),0)
        self.assertEqual(self.db.execute('select count(*) from vertices').fetchone()[0],4)
        self.assertFalse(route(self.db,self.vertex(2),self.vertex(4))['found'])
    def test_grade_crossing_shared_interior_stays_separate(self):
        ingest_catalog(self.db,catalog([
          ('way/1',[1,5,2],[[-20,0],[0,0],[20,0]],{'highway':'primary','oneway':'no','bridge':'yes','layer':'1'}),
          ('way/2',[3,5,4],[[0,-20],[0,0],[0,20]],{'highway':'primary','oneway':'no'})]),Flat())
        self.assertEqual(add_endpoint_transitions(self.db),0)
        self.assertNotEqual(self.vertex(5,'bridge'),self.vertex(5,'surface'))
        self.assertFalse(route(self.db,self.vertex(1),self.vertex(4))['found'])
        profile=solve_profiles(self.db)
        bridge=self.db.execute('select y from vertices where v=?',(self.vertex(5,'bridge'),)).fetchone()[0]
        ground=self.db.execute('select y from vertices where v=?',(self.vertex(5,'surface'),)).fetchone()[0]
        self.assertGreaterEqual(bridge-ground,6.0);self.assertLess(profile['maximum_allowance_error_m'],1e-7)
    def test_explicit_bridge_endpoint_continuity_and_slope(self):
        ingest_catalog(self.db,catalog([
          ('way/1',[1,2],[[-50,0],[0,0]],{'highway':'primary','oneway':'no','bridge':'yes','layer':'1'}),
          ('way/2',[2,3,4],[[0,0],[50,0],[100,0]],{'highway':'primary','oneway':'no'})]),Flat())
        self.assertEqual(add_endpoint_transitions(self.db),1)
        profile=solve_profiles(self.db)
        y=[r[0] for r in self.db.execute('select y from vertices where node=2')]
        self.assertEqual(y[0],y[1]);self.assertEqual(y[0],6)
        self.assertTrue(route(self.db,self.vertex(1),self.vertex(4))['found'])
        self.assertLess(profile['maximum_allowance_error_m'],1e-7)
    def test_conflicting_game_grade_constraints_do_not_flatten_silently(self):
        ingest_catalog(self.db,catalog([
          ('way/1',[1,2],[[-10,0],[0,0]],{'highway':'primary','bridge':'yes','oneway':'no'}),
          ('way/2',[2,3],[[0,0],[10,0]],{'highway':'primary','tunnel':'yes','oneway':'no'})]),Flat())
        add_endpoint_transitions(self.db)
        with self.assertRaises(RoadError): solve_profiles(self.db)
        profile=solve_profiles(self.db,'bridge-priority')
        self.assertGreater(profile['conflicting_game_constraints'],0)
        self.assertTrue(profile['tunnel_depth_unresolved_where_bridge_priority_conflicts'])
        self.assertLess(profile['maximum_allowance_error_m'],1e-7)
    def test_original_order_full_tags_names_and_anchor_precision(self):
        data=catalog([('way/99',[7,8,9],[[.0001,.0002],[10,3],[20,4]],{'highway':'service','name':'Actual 橋 Road','name:zh':'橋','bridge':'yes'})],owner='17_-81',anchor=[17000.,0.,-81000.])
        ingest_catalog(self.db,data,Flat())
        raw=json.loads(self.db.execute('select raw from ways').fetchone()[0])
        self.assertEqual(raw['node_ids'],[7,8,9]);self.assertEqual(raw['tags']['name:zh'],'橋')
        x,z=self.db.execute('select x,z from source_nodes where id=7').fetchone()
        self.assertAlmostEqual(x,17000.0001,places=10);self.assertAlmostEqual(z,-80999.9998,places=10)
    def test_same_source_node_coordinate_conflict_is_error_not_xy_repair(self):
        ingest_catalog(self.db,catalog([('way/1',[1,2],[[0,0],[10,0]],{'highway':'primary'})]),Flat())
        with self.assertRaises(RoadError): ingest_catalog(self.db,catalog([('way/2',[1,3],[[1,0],[0,10]],{'highway':'primary'})]),Flat())
    def test_physical_ribbon_hole_and_native_clockwise_winding(self):
        mesh=ribbon([[0,0,0],[40,0,0],[40,0,40],[0,0,40],[0,0,0]],4,[0,0,0])
        self.assertEqual(mesh['holes'],1)
        self.assertTrue(mesh['indices'])
        for start in range(0,len(mesh['indices']),3):
            points=[np.array(mesh['vertices_local_xyz'][i]) for i in mesh['indices'][start:start+3]]
            cross=np.cross(points[1]-points[0],points[2]-points[0]);self.assertLess(cross[1],0)
            self.assertFalse(Polygon([(p[0],p[2]) for p in points]).covers(Point(20,20)))
            self.assertGreater(mesh['normals'][start][1],.99)
    def test_metric_3d_slope_normals_and_tile_anchor(self):
        mesh=ribbon([[80000,6,-80000],[80100,0,-80000]],6.4,[80000,0,-80000])
        self.assertLess(max(abs(v[0]) for v in mesh['vertices_local_xyz']),104)
        self.assertGreater(min(n[1] for n in mesh['normals']),.99)
        self.assertTrue(any(abs(n[0])>.01 for n in mesh['normals']))
    def test_hash_bound_source_read_refuses_corruption_and_traversal(self):
        root=Path(self.temp.name);raw=canonical({'fixture':True});(root/'a.json').write_bytes(raw)
        desc={'file':'a.json','bytes':len(raw),'sha256':sha(raw)}
        self.assertTrue(read_bound(root,desc)['fixture'])
        with self.assertRaises(RoadError):read_bound(root,{**desc,'file':'../a.json'})
        (root/'a.json').write_bytes(raw+b' ')
        with self.assertRaises(RoadError):read_bound(root,desc)
    def test_cross_owner_transition_exported_from_both_incident_owners(self):
        ingest_catalog(self.db,catalog([('way/1',[1,2],[[-50,0],[0,0]],{'highway':'primary','bridge':'yes','oneway':'no'})]),Flat())
        ingest_catalog(self.db,catalog([('way/2',[2,3],[[-1000,0],[-900,0]],{'highway':'primary','oneway':'no'})],owner='1_0',anchor=[1000.,0.,0.]),Flat())
        self.db.execute('insert into owners values(?,?)',('0_0','{}'));self.db.execute('insert into owners values(?,?)',('1_0','{}'));self.db.commit()
        self.assertEqual(add_endpoint_transitions(self.db),1);solve_profiles(self.db)
        root=Path(self.temp.name)/'export';descriptors=export_catalogs(self.db,root)
        self.assertEqual(len(descriptors),2)
        identities=[]
        for desc in descriptors:
            data=read_bound(root,desc);transitions=[e for e in data['edges'] if e['grade_transition']]
            self.assertEqual(len(transitions),1);identities.append(transitions[0]['id'])
            ids={v['vertex_id'] for v in data['vertices']}
            self.assertIn(transitions[0]['a'],ids);self.assertIn(transitions[0]['b'],ids)
        self.assertEqual(identities[0],identities[1])
    def test_dense_turn_actual_surface_gradient_regression(self):
        # Translated source shape of way/646795846 from the pinned catalog;
        # attribution OpenStreetMap contributors/ODbL. R2 lifting produced35.9.
        points=[[0.,0.],[-.4533,-.5341],[-.4754,-.9904],[-.2764,-1.6693],[1.4817,-4.5295]]
        preferred=[24.187780549534324,24.27184427107935,24.32666445568319,24.411560211902216,24.814439721135436]
        class Terrain:
            def sample(self,x,z):return preferred[min(range(len(points)),key=lambda i:(points[i][0]-x)**2+(points[i][1]-z)**2)]
        ingest_catalog(self.db,catalog([('way/646795846',[1,2,3,4,5],points,{'highway':'service','lanes':'1'})]),Terrain())
        before=[r[0] for r in self.db.execute('select id from edges order by id')]
        install_geometry_allowances(self.db);solve_profiles(self.db)
        ids=json.loads(self.db.execute('select vertices from ways').fetchone()[0]);source=[list(self.db.execute('select x,y,z from vertices where v=?',(v,)).fetchone()) for v in ids]
        hubs=_hub_vertices(self.db);mesh=ribbon(source,3.2,[0,0,0],hubs=[v in hubs for v in ids])
        self.assertEqual(before,[r[0] for r in self.db.execute('select id from edges order by id')])
        self.assertLessEqual(mesh['maximum_emitted_surface_slope'],.12001)
        self.assertTrue(mesh['indices'])
    def test_original_zero_horizontal_segment_is_retained_not_xy_merged(self):
        ingest_catalog(self.db,catalog([('way/1',[1,2,3],[[0,0],[0,0],[20,0]],{'highway':'primary'})]),Flat())
        install_geometry_allowances(self.db)
        self.assertEqual(self.db.execute('select count(*) from vertices').fetchone()[0],3)
        self.assertEqual(self.db.execute('select a,b,length,allowance from edges where id=?',('way/1@0',)).fetchone(),(1,2,0.,0.))
        solve_profiles(self.db);self.assertTrue(route(self.db,self.vertex(1),self.vertex(3))['found'])
    def test_common_width_junction_plateau_propagates_across_dense_source_nodes(self):
        points=[[0,0],[1,0],[2,0],[3,0],[6,0],[20,0]]
        layout=_section_layout(points,3.2,[6.4,0,0,0,0,1.6])
        self.assertEqual(layout['flat_nodes'][:5],[True]*5)
        self.assertIn((0,4),layout['equalities'])
        # The fifth source segment starts flat until6.4m, NOT immediately at
        # the last covered original node6m. No premature narrow-road ramp.
        self.assertAlmostEqual(layout['spans'][4]['cells'][0][3][0],6.4)
    def test_different_width_incident_roads_share_flat_radius_without_nav_shortcut(self):
        ingest_catalog(self.db,catalog([
          ('way/1',[1,2,3],[[0,0],[50,0],[100,0]],{'highway':'primary','width':'12.8','oneway':'no'}),
          ('way/2',[2,4,5],[[50,0],[50,2],[50,50]],{'highway':'service','width':'3.2','oneway':'no'})]),Flat())
        before=[r[0] for r in self.db.execute('select id from edges order by id')]
        install_geometry_allowances(self.db);solve_profiles(self.db)
        junction=self.vertex(2);radius=self.db.execute('select radius from render_hubs where v=?',(junction,)).fetchone()[0]
        self.assertGreaterEqual(radius,6.4)
        self.assertEqual(before,[r[0] for r in self.db.execute('select id from edges order by id')])
        self.assertEqual(self.db.execute('select count(*) from vertices').fetchone()[0],5)
    def test_unequal_width_bridge_approach_has_no_hub_height_lip(self):
        ingest_catalog(self.db,catalog([
          ('way/1',[1,2],[[0,0],[50,0]],{'highway':'primary','bridge':'yes','width':'12.8','oneway':'no'}),
          ('way/2',[3,4,1],[[-120,0],[-60,0],[0,0]],{'highway':'secondary','width':'3.2','oneway':'no'})]),Flat())
        add_endpoint_transitions(self.db);install_geometry_allowances(self.db);solve_profiles(self.db)
        radii=dict(self.db.execute('select v,radius from render_hubs'));meshes=[]
        for identifier in ['way/1','way/2']:
            policy,vertices=self.db.execute('select policy,vertices from ways where id=?',(identifier,)).fetchone();ids=json.loads(vertices)
            points=[list(self.db.execute('select x,y,z from vertices where v=?',(v,)).fetchone()) for v in ids]
            meshes.append(ribbon(points,json.loads(policy)['width']['metres'],[0,0,0],hubs=[radii.get(v,0) for v in ids]))
        def heights(mesh,x,z):
            result=[]
            for at in range(0,len(mesh['indices']),3):
                a,b,c=[mesh['vertices_local_xyz'][i] for i in mesh['indices'][at:at+3]]
                polygon=Polygon([(p[0],p[2]) for p in (a,b,c)])
                if not polygon.buffer(1e-8).covers(Point(x,z)):continue
                denominator=(b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0])
                u=((x-a[0])*(c[2]-a[2])-(z-a[2])*(c[0]-a[0]))/denominator
                v=((b[0]-a[0])*(z-a[2])-(b[2]-a[2])*(x-a[0]))/denominator
                result.append(a[1]+u*(b[1]-a[1])+v*(c[1]-a[1]))
            return result
        for x in [-6.,-4.,-2.,0.]:
            values=[h for mesh in meshes for h in heights(mesh,x,0)]
            self.assertTrue(values)
            self.assertLess(max(values)-min(values),.001)
            self.assertAlmostEqual(max(values),6.0,places=4)
    def test_covered_interior_node_does_not_draw_overhanging_apron(self):
        mesh=ribbon([[0,6,0],[6.2,6,0],[8,5.81,0],[30,5.81,0]],3.2,[0,0,0],hubs=[6.4,0,0,1.6])
        values=[];x=7.5;z=0.
        for at in range(0,len(mesh['indices']),3):
            a,b,c=[mesh['vertices_local_xyz'][i] for i in mesh['indices'][at:at+3]]
            if not Polygon([(p[0],p[2]) for p in (a,b,c)]).buffer(1e-8).covers(Point(x,z)):continue
            denominator=(b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0])
            u=((x-a[0])*(c[2]-a[2])-(z-a[2])*(c[0]-a[0]))/denominator
            v=((b[0]-a[0])*(z-a[2])-(b[2]-a[2])*(x-a[0]))/denominator
            values.append(a[1]+u*(b[1]-a[1])+v*(c[1]-a[1]))
        self.assertTrue(values)
        self.assertLess(max(values)-min(values),.001)
        self.assertLess(max(values),5.90) # No spurious6m disk from covered6.2m node.

if __name__=='__main__':unittest.main()
