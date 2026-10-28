#!/usr/bin/env python3
"""Extract actual OSM country geometry into attributed, metre-scale game tiles.

Requires pyosmium, pyproj, shapely. Source PBF stays outside public Git.
Buildings of unknown height remain unknown; no invented street/building names.
This prepares geometry, not a claim that the playable world is already rebuilt.
"""
import argparse, collections, hashlib, json, math
from datetime import datetime, timezone
from pathlib import Path
import osmium
from shapely.geometry import shape
from georeference import from_wgs84, manifest

PRESERVE = {'name','name:en','name:zh','alt_name','ref','highway','oneway','lanes','maxspeed',
            'bridge','tunnel','layer','surface','building','building:part','building:levels',
            'building:min_level','height','min_height','roof:shape','roof:height','roof:levels',
            'amenity','tourism','leisure','natural','water','waterway','landuse','entrance',
            'addr:street','addr:housenumber','addr:postcode','access','foot','motor_vehicle',
            'level','indoor','width','area'}

def project_coords(value):
    if value and isinstance(value[0],(int,float)):
        x,y,z=from_wgs84(value[0],value[1]);return [round(x,4),round(z,4)]
    return [project_coords(v) for v in value]

def height_value(raw):
    if not raw:return None
    try:
        text=raw.strip().lower();factor=1.0
        if text.endswith('ft'):text=text[:-2].strip();factor=0.3048
        elif text.endswith('m'):text=text[:-1].strip()
        result=float(text)*factor
        return result if math.isfinite(result) and 0<result<1000 else None
    except ValueError:return None

class Country(osmium.SimpleHandler):
    def __init__(self):
        super().__init__();self.geometry=None;self.factory=osmium.geom.GeoJSONFactory()
    def area(self,a):
        tags=dict(a.tags)
        if tags.get('ISO3166-1')=='SG' or (tags.get('admin_level')=='2' and tags.get('name:en',tags.get('name'))=='Singapore'):
            self.geometry=json.loads(self.factory.create_multipolygon(a))

class Extract(osmium.SimpleHandler):
    def __init__(self,country):
        super().__init__();self.factory=osmium.geom.GeoJSONFactory();self.features=[];self.country=country;self.country_shape=shape(country);self.errors=collections.Counter()
    def add(self,kind,identifier,tags,geometry):
        try:
            g=shape(geometry)
            if g.is_empty or not self.country_shape.intersects(g):return
        except Exception:
            self.errors['country_intersection']+=1;return
        self.features.append({'id':identifier,'kind':kind,'tags':{k:v for k,v in tags.items() if k in PRESERVE},'geometry_wgs84':geometry})
    def way(self,w):
        tags=dict(w.tags)
        if not ('highway' in tags or 'waterway' in tags):return
        try:coords=[[n.lon,n.lat] for n in w.nodes if n.location.valid()]
        except Exception:self.errors['way_locations']+=1;return
        if len(coords)<2:return
        self.add('road' if 'highway' in tags else 'waterway','way/'+str(w.id),tags,{'type':'LineString','coordinates':coords})
    def area(self,a):
        tags=dict(a.tags)
        is_country=tags.get('ISO3166-1')=='SG' or (tags.get('admin_level')=='2' and tags.get('name:en',tags.get('name'))=='Singapore')
        building='building' in tags or 'building:part' in tags
        water=tags.get('natural')=='water' or 'water' in tags
        if not (is_country or building or water):return
        try:
            geometry=json.loads(self.factory.create_multipolygon(a))
        except Exception as e:self.errors['area_geometry']+=1;return
        if is_country:self.country=geometry;return
        self.add('building' if building else 'water',('way/' if a.from_way() else 'relation/')+str(a.orig_id()),tags,geometry)

def main():
    p=argparse.ArgumentParser();p.add_argument('pbf',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--tile-metres',type=int,default=1000);a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=True)
    if (a.output/'manifest.json').exists():raise SystemExit('Refusing to overwrite a snapshot; use a new output directory.')
    boundary=Country();boundary.apply_file(str(a.pbf),locations=True,idx='flex_mem')
    if boundary.geometry is None:raise SystemExit('Singapore national boundary missing; refusing an approximate bounding-box substitute.')
    ex=Extract(boundary.geometry);ex.apply_file(str(a.pbf),locations=True,idx='flex_mem')
    country=shape(ex.country)
    if not country.is_valid:country=country.buffer(0)
    tiles=collections.defaultdict(list);kinds=collections.Counter();unknown_heights=0
    for f in ex.features:
        g=shape(f['geometry_wgs84'])
        if g.is_empty or not country.intersects(g):continue
        f['geometry']={'type':g.geom_type,'coordinates':project_coords(f.pop('geometry_wgs84')['coordinates'])}
        if f['kind']=='building':
            f['height_m']=height_value(f['tags'].get('height'));f['height_status']='source_tag' if f['height_m'] is not None else 'unknown'
            unknown_heights+=f['height_m'] is None
        centroid=g.centroid;x,_,z=from_wgs84(centroid.x,centroid.y)
        tile=f'{math.floor(x/a.tile_metres)}_{math.floor(z/a.tile_metres)}'
        tiles[tile].append(f);kinds[f['kind']]+=1
    inventory=[]
    for key,features in sorted(tiles.items()):
        target=a.output/(key+'.json');payload={'tile':key,'features':features}
        data=(json.dumps(payload,separators=(',',':'),ensure_ascii=False)+'\n').encode();target.write_bytes(data)
        inventory.append({'file':target.name,'features':len(features),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
    r=osmium.io.Reader(str(a.pbf));header=r.header();snapshot=header.get('osmosis_replication_timestamp');r.close()
    info={'created_utc':datetime.now(timezone.utc).isoformat(),'source_url':'https://download.geofabrik.de/asia/malaysia-singapore-brunei.html','pbf_sha256':hashlib.sha256(a.pbf.read_bytes()).hexdigest(),'source_snapshot_utc':snapshot,'attribution':'© OpenStreetMap contributors','data_license':'ODbL-1.0','license_url':'https://www.openstreetmap.org/copyright','georeference':manifest(),'counts':dict(kinds),'building_heights_unknown':unknown_heights,'tile_metres':a.tile_metres,'tiles':inventory,'boundary_method':'Intersects actual OSM Singapore admin2 multipolygon; crossing features preserved','completeness':'Source coverage only; missing names/heights/interiors remain unknown; no runtime migration or one-to-one acceptance claimed','parse_errors':dict(ex.errors)}
    (a.output/'manifest.json').write_text(json.dumps(info,indent=2,ensure_ascii=False)+'\n');(a.output/'singapore-boundary.geojson').write_text(json.dumps(ex.country,separators=(',',':'))+'\n')
    print(json.dumps({k:info[k] for k in ['counts','building_heights_unknown','parse_errors','source_snapshot_utc']}),flush=True)
if __name__=='__main__':main()
