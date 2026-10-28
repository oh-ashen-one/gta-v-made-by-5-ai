#!/usr/bin/env python3
"""Immutable projected territory/coast domain data, not dryland or water levels."""
import argparse
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'geodata'))
import georeference
from build_spatial_index import validate_frame
from shapely.geometry import shape,Polygon

DATA_SCHEMA='singapore_source_domain_dataset_v1'
IDENTITY_SCHEMA='singapore_source_domain_identity_v1'
REGISTRY_VERSION='singapore_source_domain_registry_v1'
MAX_BYTES=16*1024*1024
MAX_VERTICES=250000
MAX_POLYGONS=4096
MAX_RINGS=8192

class DomainCompileError(ValueError):pass

def raw_bytes(value):
    return (json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)+'\n').encode('utf-8')
def sha(raw):return hashlib.sha256(raw).hexdigest()
def read(path):
    if path.is_symlink():raise DomainCompileError('Symlink source input refused')
    raw=path.read_bytes()
    if not raw or len(raw)>MAX_BYTES:raise DomainCompileError('Source input exceeds bounded byte contract')
    return json.loads(raw),raw

def descriptors(domain_sha):
    return [{'kind':kind,'provider_id':'singapore-source-domain/'+kind+'/v1/'+domain_sha,
        'source_reference':'source-domain/v1/'+domain_sha,'registry_version':REGISTRY_VERSION}
        for kind in ('territory','land','water')]

def flatten_polygons(geometry,prefix,project=False):
    if geometry.get('type')=='Polygon':polygons=[geometry['coordinates']]
    elif geometry.get('type')=='MultiPolygon':polygons=geometry['coordinates']
    else:raise DomainCompileError('Domain geometry must be Polygon/MultiPolygon')
    out=[]
    for pi,polygon in enumerate(polygons):
        rings=[];points=[]
        if not polygon:raise DomainCompileError('Polygon must contain an outer ring')
        for ring in polygon:
            if len(ring)<4 or ring[0]!=ring[-1]:raise DomainCompileError('Source ring must be explicitly closed')
            coords=[]
            for point in ring:
                if len(point)!=2 or not all(isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v) for v in point):
                    raise DomainCompileError('Require finite two-dimensional source positions')
                if project:
                    x,_,z=georeference.from_wgs84(*point);position=[x,z]
                else:position=[float(point[0]),float(point[1])]
                if not all(math.isfinite(v) and abs(v)<=1e9 for v in position):raise DomainCompileError('Projected coordinate outside supported bound')
                coords.extend(position);points.append(position)
            rings.append(coords)
        check=Polygon(list(zip(rings[0][::2],rings[0][1::2])),[list(zip(r[::2],r[1::2])) for r in rings[1:]])
        if not check.is_valid or check.is_empty or check.area<=0:raise DomainCompileError('Invalid domain polygon; no repair/simplification')
        out.append({'id':prefix+'/'+str(pi),'bounds_xz':[min(p[0] for p in points),min(p[1] for p in points),max(p[0] for p in points),max(p[1] for p in points)],'rings':rings})
    return out

def inventory(polygons):
    return {'polygons':len(polygons),'rings':sum(len(p['rings']) for p in polygons),
        'vertices':sum(len(r)//2 for p in polygons for r in p['rings'])}

def compile_dataset(manifest,country,coast,bindings):
    validate_frame(manifest.get('georeference'))
    if manifest['georeference']!=georeference.manifest():raise DomainCompileError('Current projection differs from source frame')
    if not shape(country).is_valid:raise DomainCompileError('Invalid exact country; no substitute')
    territory=flatten_polygons(country,'territory',True)
    enclosure=[]
    land=coast.get('land',{})
    if land.get('type')!='FeatureCollection' or not isinstance(land.get('features'),list):raise DomainCompileError('Missing verified coast-enclosure collection')
    for index,feature in enumerate(land['features']):
        enclosure.extend(flatten_polygons(feature['geometry'],'coast-enclosure/'+str(index)))
    counts={'territory':inventory(territory),'coast_enclosure':inventory(enclosure)}
    if sum(c['polygons'] for c in counts.values())>MAX_POLYGONS or sum(c['rings'] for c in counts.values())>MAX_RINGS or sum(c['vertices'] for c in counts.values())>MAX_VERTICES:
        raise DomainCompileError('Domain geometry exceeds bounded cache contract')
    return {'schema':DATA_SCHEMA,'version':1,'registry_version':REGISTRY_VERSION,'georeference':deepcopy(manifest['georeference']),
        'bindings':deepcopy(bindings),'data_scope':'Pinned OSM national territory plus verified source coast enclosure; not dryland/hydrology/terrain',
        'source_attribution':{'attribution':'© OpenStreetMap contributors','data_license':'ODbL-1.0','license_url':'https://www.openstreetmap.org/copyright'},
        'territory':territory,'coast_enclosure':enclosure,'counts':counts,
        'semantic_contract':{'territory_boundary':'inclusive','hole_boundary':'inclusive boundary; hole interior excluded',
            'polygon_arithmetic':'double scalar arrays; no absolute engine vectors or Geometry2D',
            'coast_enclosure_is_dryland':False,'territory_is_land':False,'land_state':'unknown','water_state':'unknown',
            'inland_water_resolved':False,'terrain_elevation_resolved':False,'tides_resolved':False,
            'finite_water_columns_available':False,'source_completeness_certified':False}}

def compile_inputs(manifest_path,country_path,coast_path,coast_identity_path):
    manifest,mraw=read(manifest_path);country,braw=read(country_path);coast,craw=read(coast_path);identity,iraw=read(coast_identity_path)
    if identity.get('schema')!='singapore_coastline_artifact_identity_v1' or identity.get('coastline',{}).get('file')!='coastline.json' or identity['coastline'].get('sha256')!=sha(craw) or identity['coastline'].get('bytes')!=len(craw):
        raise DomainCompileError('Coast artifact identity/checksum mismatch')
    b=coast.get('binding',{})
    if coast.get('schema')!='singapore_source_coastline_v1' or b.get('canonical_manifest_sha256')!=sha(mraw) or b.get('country_sha256')!=sha(braw) or b.get('pbf_sha256')!=manifest.get('pbf_sha256') or b.get('source_snapshot_utc')!=manifest.get('source_snapshot_utc'):
        raise DomainCompileError('Coast/country/canonical snapshot binding mismatch')
    if coast.get('projection_frame')!=manifest.get('georeference'):raise DomainCompileError('Coast projection differs from canonical frame')
    if manifest.get('attribution')!='© OpenStreetMap contributors' or manifest.get('data_license')!='ODbL-1.0':raise DomainCompileError('OSM source attribution/license contract missing')
    bindings={'snapshot_manifest_sha256':sha(mraw),'country_wgs84_sha256':sha(braw),'coastline_sha256':sha(craw),
        'coast_identity_sha256':sha(iraw),'pbf_sha256':manifest['pbf_sha256'],'source_snapshot_utc':manifest['source_snapshot_utc'],
        'projection_implementation_sha256':sha(Path(georeference.__file__).read_bytes())}
    return compile_dataset(manifest,country,coast,bindings)

def write_dataset(directory,dataset):
    if directory.exists():raise DomainCompileError('Refusing to overwrite existing domain dataset')
    raw=raw_bytes(dataset)
    if len(raw)>MAX_BYTES:raise DomainCompileError('Domain dataset exceeds bounded16MiB decode contract')
    digest=sha(raw)
    identity={'schema':IDENTITY_SCHEMA,'version':1,'registry_version':REGISTRY_VERSION,
        'dataset':{'file':'domain.json','sha256':digest,'bytes':len(raw)},'bindings':deepcopy(dataset['bindings']),
        'counts':deepcopy(dataset['counts']),'provider_descriptors':descriptors(digest)}
    identity_raw=raw_bytes(identity);directory.mkdir(parents=True)
    (directory/'domain.json').write_bytes(raw);(directory/'identity.json').write_bytes(identity_raw)
    return {'identity_sha256':sha(identity_raw),'domain_sha256':digest,'domain_bytes':len(raw),'identity_bytes':len(identity_raw),
        'counts':dataset['counts'],'snapshot_manifest_sha256':dataset['bindings']['snapshot_manifest_sha256']}

def relation_ring(x,z,ring):
    inside=False
    for i in range(0,len(ring)-2,2):
        ax,az,bx,bz=ring[i:i+4];dx=x-ax;dz=z-az
        cross=dx*(bz-az)-dz*(bx-ax)
        if cross==0.0 and min(ax,bx)<=x<=max(ax,bx) and min(az,bz)<=z<=max(az,bz):return 'boundary'
        if (az>z)!=(bz>z) and dx<(z-az)*(bx-ax)/(bz-az):inside=not inside
    return 'inside' if inside else 'outside'
def relation_collection(x,z,polygons):
    boundary=False
    for p in polygons:
        a,b,c,d=p['bounds_xz']
        if not a<=x<=c or not b<=z<=d:continue
        outer=relation_ring(x,z,p['rings'][0])
        if outer=='outside':continue
        if outer=='boundary':boundary=True;continue
        excluded=False
        for hole in p['rings'][1:]:
            result=relation_ring(x,z,hole)
            if result=='boundary':boundary=True;excluded=True;break
            if result=='inside':excluded=True;break
        if not excluded:return 'inside'
    return 'boundary' if boundary else 'outside'

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest',type=Path,required=True);p.add_argument('--country',type=Path,required=True)
    p.add_argument('--coastline',type=Path,required=True);p.add_argument('--coast-identity',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True)
    a=p.parse_args()
    try:print(json.dumps(write_dataset(a.output_dir,compile_inputs(a.manifest,a.country,a.coastline,a.coast_identity)),sort_keys=True))
    except Exception as e:
        print(json.dumps({'status':'failed','reason':str(e) if isinstance(e,DomainCompileError) else 'Domain source I/O/parser failure; no private input paths emitted'}));return 2
    return 0
if __name__=='__main__':raise SystemExit(main())
