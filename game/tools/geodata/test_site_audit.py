"""Labeled synthetic analytic fixtures; never physical MBS validation."""
import hashlib,json,tempfile,unittest
from pathlib import Path
from shapely.affinity import rotate
from shapely.geometry import box,mapping
from georeference import manifest as geoframe,to_wgs84
from site_audit import AuditError,SnapshotNotReady,audit,candidate_roles,geometry_metrics,legacy_plan,read_snapshot,compare_overpass,component_input

def fixture(identifier,geom,tags,kind="building",height=None):
    return {"id":identifier,"kind":kind,"geometry":mapping(geom),"tags":tags,"height_m":height,"height_status":"unknown" if height is None else "source_tag"}
def source():
    return {"source_snapshot_utc":"SYNTHETIC_TEST_FIXTURE","data_license":"ODbL-1.0","georeference":geoframe()}
def features():
    from shapely.geometry import LineString
    return [fixture("way/1",box(-100,-20,100,20),{"name":"Marina Bay Sands Hotel","building":"hotel"}),
            fixture("way/2",box(-150,80,150,140),{"name":"The Shoppes at Marina Bay Sands","building":"retail"}),
            fixture("way/3",LineString([[-200,50],[200,50]]),{"name":"Bayfront Avenue","highway":"primary"},"road")]
class SiteAuditTests(unittest.TestCase):
    def test_source_geometry_separation_and_named_road(self):
        r=audit(source(),features());self.assertEqual(r['hotel_selection']['source_id'],'way/1')
        s=r['hotel_retail_separation'];self.assertEqual(s['minimum_surface_gap_m'],60)
        self.assertEqual(s['named_drivable_road_intersects_gap_connector'],['way/3'])
        self.assertEqual(s['evidence_status'],'source_geometry_supports_separate_footprints_and_named_road_between')
        self.assertFalse(r['full_interior_acceptance']);self.assertFalse(r['one_to_one_city_acceptance'])
    def test_bare_mbs_name_is_not_guessed_to_be_hotel(self):
        f=fixture('way/4',box(0,0,100,100),{'name':'Marina Bay Sands','building':'yes'})
        self.assertEqual(candidate_roles(f),['unclassified_mbs_name'])
        self.assertEqual(audit(source(),[f])['hotel_selection']['status'],'missing')
    def test_ambiguous_sources_are_retained_not_arbitrarily_selected(self):
        fs=features();fs.append(fixture('way/5',box(0,-60,40,-30),{'name':'Marina Bay Sands Hotel','tourism':'hotel'}))
        r=audit(source(),fs);self.assertEqual(r['hotel_selection']['status'],'ambiguous');self.assertIsNone(r['hotel_retail_separation'])
        selected=audit(source(),fs,hotel_id='way/1');self.assertEqual(selected['hotel_selection']['source_id'],'way/1')
        self.assertFalse(selected['candidate_buildings'][0]['architectural_identity_verified'])
    def test_geometric_nearness_does_not_prove_road_between(self):
        from shapely.geometry import LineString
        fs=features();fs[-1]['geometry']=mapping(LineString([[-200,200],[200,200]]))
        r=audit(source(),fs);self.assertEqual(r['hotel_retail_separation']['evidence_status'],'inconclusive')
    def test_rotated_footprint_dimensions_and_bearing(self):
        r=geometry_metrics(rotate(box(-100,-20,100,20),45))['oriented_envelope']
        self.assertAlmostEqual(r['long_m'],200,places=3);self.assertAlmostEqual(r['short_m'],40,places=3)
        self.assertAlmostEqual(r['major_axis_grid_bearing_deg_mod180'],45,places=4)
        self.assertTrue(r['not_tower_or_door_positions'])
    def test_three_explicit_towers_group_without_inventing_an_atrium(self):
        fs=features()[1:]
        for number,x in [(3,-120),(2,0),(1,120)]:
            fs.append(fixture('way/'+str(10+number),box(x-20,-20,x+20,20),{'name':f'Marina Bay Sands Tower {number}','building':'hotel'}))
        r=audit(source(),fs)
        self.assertEqual(r['hotel_selection']['status'],'three_explicitly_named_tower_footprints_grouped_not_full_hotel')
        self.assertIsNone(r['hotel_selection']['source_id'])
        self.assertEqual(len(r['hotel_selection']['source_ids']),3)
        self.assertEqual(r['selected_hotel_geometry']['type'],'MultiPolygon')
        self.assertTrue(r['tower_order_north_to_south']['order_matches'])
        self.assertFalse(r['full_interior_acceptance'])
    def test_same_name_tower_duplicates_are_not_grouped(self):
        fs=features()[1:]
        for identifier,number,x in [(13,3,-120),(12,2,0),(11,1,120),(14,3,-100)]:
            fs.append(fixture('way/'+str(identifier),box(x-10,-10,x+10,10),{'name':f'Marina Bay Sands Tower {number}','building':'hotel'}))
        self.assertEqual(audit(source(),fs)['hotel_selection']['status'],'ambiguous')
    def test_unknown_height_and_missing_landmark_stay_unknown(self):
        r=audit(source(),features());self.assertIsNone(r['candidate_buildings'][0]['source_height_m'])
        self.assertEqual(r['landmarks']['merlion_landmark']['status'],'missing_from_extracted_building_features')
    def test_compressed_or_wrong_frame_is_rejected(self):
        s=source();s['georeference']['distance_compression']=True
        with self.assertRaises(AuditError):audit(s,features())
    def test_snapshot_pending_and_checksum_failure(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            with self.assertRaises(SnapshotNotReady):read_snapshot(p)
            data=(json.dumps({'features':features()})+'\n').encode();(p/'0_0.json').write_bytes(data)
            m={**source(),'tiles':[{'file':'0_0.json','features':3,'sha256':hashlib.sha256(data).hexdigest()}]};(p/'manifest.json').write_text(json.dumps(m))
            _,fs=read_snapshot(p);self.assertEqual(len(fs),3)
            (p/'0_0.json').write_text('{}')
            with self.assertRaises(AuditError):read_snapshot(p)
    def test_fullerton_semantic_key_maps_to_actual_legacy_anchor(self):
        fs=features();fs.append(fixture('way/7',box(-200,10,-160,50),{'name':'The Fullerton Hotel'}))
        old={'anchors_world_xyz_m':{'marina_bay_sands':[-118,0,-705],'fullerton_hotel':[-485,0,-257]}}
        r=audit(source(),fs,legacy=old)
        self.assertEqual(r['legacy_comparison']['pairwise_distance_comparisons'][0]['anchors'],['fullerton_hotel','marina_bay_sands'])
    def test_later_overpass_geometry_is_separately_dated_and_checked(self):
        fs=features();r=audit(source(),fs)
        coords=fs[0]['geometry']['coordinates'][0]
        geometry=[dict(zip(['lon','lat'],to_wgs84(x,0,z))) for x,z in coords]
        d={'osm3s':{'timestamp_osm_base':'LATER_SYNTHETIC_FIXTURE'},'elements':[{'type':'way','id':1,'geometry':geometry}]}
        c=compare_overpass(r,fs,d,'synthetic')
        self.assertEqual(c['source_snapshot_utc'],'LATER_SYNTHETIC_FIXTURE')
        self.assertEqual(c['feature_comparisons'][0]['comparison'],'boundary_consistent_within_1cm')
        self.assertEqual(c['feature_comparisons'][1]['comparison'],'unavailable')
        self.assertTrue(c['not_a_survey_or_full_interior_verification'])
    def test_later_geometry_change_is_not_hidden(self):
        fs=features();r=audit(source(),fs)
        geometry=[dict(zip(['lon','lat'],to_wgs84(x+1,0,z))) for x,z in fs[0]['geometry']['coordinates'][0]]
        c=compare_overpass(r,fs,{'elements':[{'type':'way','id':1,'geometry':geometry}]},'synthetic')
        self.assertEqual(c['feature_comparisons'][0]['comparison'],'geometry_differs')
        self.assertAlmostEqual(c['feature_comparisons'][0]['boundary_hausdorff_m'],1,places=5)
    def test_metric_component_export_keeps_source_ids_coordinates_and_limits(self):
        fs=features();r=audit(source(),fs);c=component_input(r,fs)
        self.assertEqual({f['id'] for f in c['features']},{'way/1','way/2','way/3'})
        self.assertEqual(c['features'][0]['geometry'],fs[0]['geometry'])
        self.assertFalse(c['complete_hotel_interior']);self.assertEqual(c['coordinate_frame']['metres_per_unit'],1)
        self.assertEqual(c['source']['data_license'],'ODbL-1.0')
    def test_unresolved_identity_cannot_export_a_finished_looking_site(self):
        fs=[features()[1]]
        with self.assertRaises(AuditError):component_input(audit(source(),fs),fs)
    def test_pairwise_comparison_does_not_invent_absolute_registration(self):
        from shapely.geometry import Point
        fs=features();fs.append(fixture('way/6',box(-300,40,-260,80),{'name':'ArtScience Museum'}))
        old={'anchors_world_xyz_m':{'marina_bay_sands':[-118,0,-705],'artscience_museum':[-290,0,-598]},'frame_registration_to_survey':'NOT_ESTABLISHED'}
        r=audit(source(),fs,legacy=old);c=r['legacy_comparison']['pairwise_distance_comparisons'][0]
        self.assertTrue(c['not_identical_reference_points']);self.assertNotIn('absolute_position_error',c)
if __name__=='__main__':unittest.main()
