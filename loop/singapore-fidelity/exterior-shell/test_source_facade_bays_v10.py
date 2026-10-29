"""Bounded independent geometry guards for the actual source reveal adapter."""
import copy,json,unittest
from pathlib import Path
import source_facade_bays_v10 as bays
import audit_core_layout as g
HERE=Path(__file__).resolve().parent

class SourceFacadeBayTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.doc=json.loads((HERE/'SOURCE_FLOOR_PERIMETER_CANDIDATE_V7.json').read_text());cls.floor=next(f for f in cls.doc['floors'].values() if f['floor_id']=='T1-L23');cls.room=copy.deepcopy(cls.floor['rooms'][0])
 def test_real_tapered_source_bay(self):
  result=bays.plan_room(self.floor,self.room);self.assertTrue(result['minimum_unit_view_frontage_candidate']);self.assertGreaterEqual(result['total_source_window_frontage_m'],2.4)
  for bay in result['bays']:
   self.assertTrue(bay['requires_real_floor_sloped_outer_glass_and_reveal_side_walls']);self.assertTrue(bay['must_not_register_whole_bay_as_uniform3_08m_dry_box']);self.assertFalse(bay['native_glazing_or_sightline_verified'])
 def test_expanded_room_refuses_duplicate_floor(self):
  room=copy.deepcopy(self.room);room['footprint_own_xz'][0][0]-=1
  result=bays.plan_room(self.floor,room);self.assertFalse(result['minimum_unit_view_frontage_candidate']);self.assertIn('outer-union',result['rejected_intervals'][0]['reason'])
 def test_adjacent_room_occludes_real_window(self):
  floor=copy.deepcopy(self.floor);baseline=bays.plan_room(floor,self.room);self.assertTrue(baseline['bays'])
  for i,bay in enumerate(baseline['bays']):floor['rooms'].append({'id':'foreign-room-'+str(i),'footprint_own_xz':bay['floor_ring_own_xz']})
  blocked=bays.plan_room(floor,self.room);self.assertFalse(blocked['minimum_unit_view_frontage_candidate'])
 def test_core_or_public_corridor_cannot_be_crossed(self):
  floor=copy.deepcopy(self.floor);baseline=bays.plan_room(floor,self.room)
  floor['corridors'] += [{'id':'protected-actual-public-route-'+str(i),'polygon':bay['floor_ring_own_xz']} for i,bay in enumerate(baseline['bays'])]
  self.assertFalse(bays.plan_room(floor,self.room)['minimum_unit_view_frontage_candidate'])
 def test_source_edge_parameters_are_actual(self):
  result=bays.plan_room(self.floor,self.room);ring=bays.base.profile(self.floor['tower'],self.floor['elevation_m']+1.5)
  for bay in result['bays']:
   desc=bay['source_window'];index=desc['source_edge_index'];a=ring[index];b=ring[(index+1)%len(ring)]
   for point in desc['source_segment_at_eye_height']:self.assertLess(g.dist_segment(point,a,b),1e-6)
   self.assertGreater(desc['edge_u1'],desc['edge_u0']);self.assertGreaterEqual(desc['edge_u0'],0);self.assertLessEqual(desc['edge_u1'],1)
 def test_whole_incomplete_fixture_not_mislabeled_complete_inventory(self):
  count=sum(len(f['rooms']) for f in self.doc['floors'].values());self.assertLess(count,1850);self.assertTrue(self.doc['remaining_units'])

if __name__=='__main__':unittest.main()
