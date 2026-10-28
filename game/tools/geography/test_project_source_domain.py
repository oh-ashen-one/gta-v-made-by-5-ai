"""Projected domain mathematics/identity, not dryland/runtime acceptance."""
from copy import deepcopy
import json
from pathlib import Path
import random
import tempfile
import unittest
from shapely.geometry import Polygon,MultiPolygon,box,mapping,shape,Point
from shapely.ops import unary_union
from project_source_domain import (DomainCompileError,compile_dataset,compile_inputs,
    descriptors,flatten_polygons,georeference,inventory,raw_bytes,relation_collection,sha,write_dataset)

ROOT=Path(__file__).resolve().parents[3]
BIND={'snapshot_manifest_sha256':'a'*64,'country_wgs84_sha256':'b'*64,'coastline_sha256':'c'*64,
      'coast_identity_sha256':'d'*64,'pbf_sha256':'e'*64,'projection_implementation_sha256':'f'*64,'source_snapshot_utc':'SYNTHETIC_FIXTURE'}
def manifest():return {'georeference':georeference.manifest(),'pbf_sha256':'e'*64,'source_snapshot_utc':'SYNTHETIC_FIXTURE','attribution':'© OpenStreetMap contributors','data_license':'ODbL-1.0'}
def coast(geometry=None):
    return {'land':{'type':'FeatureCollection','features':[] if geometry is None else [{'geometry':mapping(geometry)}]}}
def seal_source(directory):
    m=manifest();country=mapping(box(103.8,1.2,103.9,1.4));mr=raw_bytes(m);br=raw_bytes(country)
    c=coast(box(0,0,100,100));c.update({'schema':'singapore_source_coastline_v1','projection_frame':georeference.manifest(),
       'binding':{'canonical_manifest_sha256':sha(mr),'country_sha256':sha(br),'pbf_sha256':m['pbf_sha256'],'source_snapshot_utc':m['source_snapshot_utc']}})
    cr=raw_bytes(c);identity={'schema':'singapore_coastline_artifact_identity_v1','coastline':{'file':'coastline.json','sha256':sha(cr),'bytes':len(cr)}}
    for name,data in [('manifest.json',mr),('country.json',br),('coastline.json',cr),('coast-identity.json',raw_bytes(identity))]:(directory/name).write_bytes(data)
    return [directory/name for name in ('manifest.json','country.json','coastline.json','coast-identity.json')]

class DomainProjectionTests(unittest.TestCase):
    def test_projection_preserves_exact_metre_coordinates_and_source(self):
        c=mapping(box(103.85,1.28,103.87,1.30));before=deepcopy(c)
        dataset=compile_dataset(manifest(),c,coast(),BIND)
        actual=dataset['territory'][0]['rings'][0]
        for i,point in enumerate(c['coordinates'][0]):
            x,_,z=georeference.from_wgs84(*point);self.assertEqual(actual[2*i:2*i+2],[x,z])
        self.assertEqual(c,before);self.assertEqual(dataset['georeference']['metres_per_unit'],1.0)
        self.assertFalse(dataset['georeference']['distance_compression'])
    def test_holes_multipart_and_inclusive_boundaries(self):
        p=Polygon([(0,0),(10,0),(10,10),(0,10)],holes=[[(3,3),(7,3),(7,7),(3,7)]])
        polygons=flatten_polygons(mapping(MultiPolygon([p,box(20,20,21,21)])),'fixture')
        for point,expected in [((1,1),'inside'),((5,5),'outside'),((0,5),'boundary'),((3,5),'boundary'),((20.5,20.5),'inside'),((15,15),'outside')]:
            self.assertEqual(relation_collection(*point,polygons),expected)
    def test_double_precision_keeps_millimetre_features_near_eighty_km(self):
        p=box(80000,80000,80000.001,80000.001)
        polygons=flatten_polygons(mapping(p),'fixture')
        self.assertEqual(relation_collection(80000.0005,80000.0005,polygons),'inside')
        self.assertEqual(relation_collection(80000.0011,80000.0005,polygons),'outside')
        self.assertEqual(relation_collection(80000,80000.0005,polygons),'boundary')
    def test_reference_parity_matches_independent_shapely_covers(self):
        p=MultiPolygon([Polygon([(80000,80000),(80010,80000),(80010,80010),(80000,80010)],holes=[[(80003,80003),(80007,80003),(80007,80007),(80003,80007)]]),box(80020,80020,80021,80021)])
        polygons=flatten_polygons(mapping(p),'fixture');random.seed(137)
        points=[(80000+random.uniform(-1,22),80000+random.uniform(-1,22)) for _ in range(1000)]
        points += [(80000,80005),(80003,80005),(80020,80020)]
        for x,z in points:self.assertEqual(relation_collection(x,z,polygons)!='outside',p.covers(Point(x,z)))
    def test_territory_coast_and_hydrology_stay_separate(self):
        dataset=compile_dataset(manifest(),mapping(box(103.8,1.2,103.9,1.4)),coast(box(0,0,100,100)),BIND)
        contract=dataset['semantic_contract']
        self.assertFalse(contract['territory_is_land']);self.assertFalse(contract['coast_enclosure_is_dryland'])
        self.assertEqual(contract['land_state'],'unknown');self.assertEqual(contract['water_state'],'unknown')
        self.assertFalse(contract['finite_water_columns_available'])
        self.assertEqual(dataset['coast_enclosure'][0]['rings'][0],flatten_polygons(mapping(box(0,0,100,100)),'ignored')[0]['rings'][0])
    def test_invalid_nonfinite_unclosed_and_compressed_geometry_refused(self):
        for geometry in [{'type':'Polygon','coordinates':[[[0,0],[1,0],[1,1]]]},
                         {'type':'Polygon','coordinates':[[[0,0],[1,1],[1,0],[0,1],[0,0]]]},
                         {'type':'Polygon','coordinates':[[[0,0],[float('nan'),0],[1,1],[0,0]]]}]:
            with self.assertRaises(DomainCompileError):flatten_polygons(geometry,'bad')
        m=manifest();m['georeference']['distance_compression']=True
        with self.assertRaises(ValueError):compile_dataset(m,mapping(box(103.8,1.2,103.9,1.4)),coast(),BIND)
    def test_source_descriptor_and_snapshot_binding_failures(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);paths=seal_source(p);dataset=compile_inputs(*paths)
            self.assertEqual(dataset['bindings']['snapshot_manifest_sha256'],sha(paths[0].read_bytes()))
            old=paths[2].read_bytes();paths[2].write_bytes(b'{}')
            with self.assertRaises(DomainCompileError):compile_inputs(*paths)
            paths[2].write_bytes(old);m=json.loads(paths[0].read_bytes());m['source_snapshot_utc']='OTHER';paths[0].write_bytes(raw_bytes(m))
            with self.assertRaises(DomainCompileError):compile_inputs(*paths)
    def test_separate_identity_hashes_counts_descriptors_and_no_overwrite(self):
        dataset=compile_dataset(manifest(),mapping(box(103.8,1.2,103.9,1.4)),coast(box(0,0,100,100)),BIND)
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'dataset';r=write_dataset(p,dataset);i=json.loads((p/'identity.json').read_bytes())
            self.assertEqual(r['identity_sha256'],sha((p/'identity.json').read_bytes()))
            self.assertEqual(i['dataset']['sha256'],sha((p/'domain.json').read_bytes()))
            self.assertEqual(i['provider_descriptors'],descriptors(r['domain_sha256']))
            self.assertEqual(i['counts'],dataset['counts'])
            self.assertNotIn(str(p),raw_bytes(i).decode())
            with self.assertRaises(DomainCompileError):write_dataset(p,dataset)
    def test_actual_national_sources_and_water_gap(self):
        data=ROOT/'game/data/geography'
        dataset=compile_inputs(data/'osm-2026-10-27/manifest.json',data/'osm-2026-10-27/singapore-boundary.geojson',data/'coastline/osm-2026-10-27/coastline.json',data/'coastline/osm-2026-10-27/identity.json')
        self.assertEqual(dataset['counts']['territory']['vertices'],246)
        self.assertEqual(dataset['counts']['coast_enclosure']['vertices'],9834)
        for lon,lat in [(103.8608,1.2834),(103.8198,1.3521),(103.8285,1.2494),(103.7045,1.27)]:
            x,_,z=georeference.from_wgs84(lon,lat)
            self.assertNotEqual(relation_collection(x,z,dataset['territory']),'outside')
            self.assertNotEqual(relation_collection(x,z,dataset['coast_enclosure']),'outside')
        def poly(p):return Polygon(list(zip(p['rings'][0][::2],p['rings'][0][1::2])),[list(zip(r[::2],r[1::2])) for r in p['rings'][1:]])
        territory=unary_union([poly(p) for p in dataset['territory']]);coasts=unary_union([poly(p) for p in dataset['coast_enclosure']])
        sea=territory.difference(coasts).representative_point()
        self.assertNotEqual(relation_collection(sea.x,sea.y,dataset['territory']),'outside')
        self.assertEqual(relation_collection(sea.x,sea.y,dataset['coast_enclosure']),'outside')
        self.assertEqual(dataset['semantic_contract']['water_state'],'unknown')

if __name__=='__main__':unittest.main()
