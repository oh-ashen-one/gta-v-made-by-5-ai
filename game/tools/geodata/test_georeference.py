import math,unittest
from georeference import from_svy21,to_svy21,from_wgs84,to_wgs84
class ProjectionTests(unittest.TestCase):
    def test_one_metre_is_one_unit(self):
        a=from_svy21(30000,30000);b=from_svy21(30100,30000)
        self.assertAlmostEqual(math.dist(a,b),100.0,places=9)
        self.assertEqual(from_svy21(30000,30100),[-100,0,0])
    def test_roundtrip_all_island_controls(self):
        for lon,lat in [(103.61,1.16),(104.04,1.40),(103.86,1.28),(103.76,1.47)]:
            r=to_wgs84(*from_wgs84(lon,lat));self.assertAlmostEqual(r[0],lon,places=8);self.assertAlmostEqual(r[1],lat,places=8)
    def test_onemap_public_response_control(self):
        # Actual unauthenticated response included an auth error and partial
        # result. This is only a projection control, not proof of API access.
        p=from_wgs84(103.859450636919,1.283994101392069)
        e,n=to_svy21(*p);self.assertAlmostEqual(e,30908.28190684784,places=2);self.assertAlmostEqual(n,29603.07868608087,places=2)
    def test_invalid_wgs84(self):
        with self.assertRaises(ValueError):from_wgs84(400,1)
if __name__=='__main__':unittest.main()
