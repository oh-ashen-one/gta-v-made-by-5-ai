#!/usr/bin/env python3
"""Country-bounded dependency index for centroid-owned Singapore source tiles.

Canonical feature geometry is not copied, clipped or rescaled. Index cells point
at owner files whose geometry can intersect that part of Singapore. Querying a
nearby cell can therefore retrieve a long road whose centroid is far away.
"""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import time

from shapely.geometry import box, shape
from shapely.prepared import prep
from georeference import from_wgs84

SCHEMA = 'singapore_country_dependency_index_v1'
TILE_FILE = re.compile(r'^-?\d+_-?\d+\.json$')

class IndexErrorDetail(ValueError):
    pass

def sha(data):
    return hashlib.sha256(data).hexdigest()

def safe_tile_name(value):
    return isinstance(value,str) and len(value)<64 and TILE_FILE.fullmatch(value) is not None

def validate_frame(frame):
    if not isinstance(frame,dict) or frame.get('metres_per_unit')!=1.0 or frame.get('distance_compression') is not False:
        raise IndexErrorDetail('Require uncompressed metre-scale geography frame')
    if frame.get('source_crs')!='EPSG:4326' or frame.get('survey_crs')!='EPSG:3414' or frame.get('origin_easting')!=30000.0 or frame.get('origin_northing')!=30000.0 or frame.get('world_axes')!={'x':'south','y':'up','z':'west'}:
        raise IndexErrorDetail('Unsupported surveying/world axes')

def project_coordinates(value):
    if value and isinstance(value[0],(int,float)):
        if len(value)<2: raise IndexErrorDetail('Invalid boundary point')
        x,_,z=from_wgs84(value[0],value[1]);return [x,z]
    return [project_coordinates(v) for v in value]

def projected_country(document):
    if document.get('type')=='Feature':document=document['geometry']
    if document.get('type') not in {'Polygon','MultiPolygon'}:
        raise IndexErrorDetail('Country boundary must be Polygon or MultiPolygon')
    result=shape({'type':document['type'],'coordinates':project_coordinates(document['coordinates'])})
    if result.is_empty or not result.is_valid:
        raise IndexErrorDetail('Country boundary is empty/invalid; no bbox substitution')
    return result

def cell_range(bounds,size):
    if len(bounds)!=4 or not all(math.isfinite(v) for v in bounds):
        raise IndexErrorDetail('Nonfinite geometry bounds')
    return (math.floor(bounds[0]/size),math.floor(bounds[1]/size),math.floor(bounds[2]/size),math.floor(bounds[3]/size))

def build_index(manifest, owners, country, *, manifest_sha256, boundary_sha256):
    """Build from projected source features and a projected exact country shape.

    owners yields (safe owner filename, features). Invalid source geometry is
    indexed conservatively by its bbox and recorded, never silently repaired.
    """
    validate_frame(manifest.get('georeference'))
    size=manifest.get('tile_metres')
    if not isinstance(size,int) or isinstance(size,bool) or size<=0:
        raise IndexErrorDetail('Invalid tile_metres')
    if country.is_empty or not country.is_valid:
        raise IndexErrorDetail('Country boundary invalid')
    inventory={t['file']:t for t in manifest.get('tiles',[])}
    if len(inventory)!=len(manifest.get('tiles',[])) or not all(safe_tile_name(n) for n in inventory):
        raise IndexErrorDetail('Unsafe or duplicate owner filename')
    prepared=prep(country)
    c0,c1,c2,c3=cell_range(country.bounds,size)
    cells_geometry={}
    # Exact country/tile intersection, including holes and separate islands.
    for ix in range(c0,c2+1):
        for iz in range(c1,c3+1):
            tile=box(ix*size,iz*size,(ix+1)*size,(iz+1)*size)
            if prepared.intersects(tile):
                part=country.intersection(tile)
                if not part.is_empty:cells_geometry[(ix,iz)]=part
    dependencies=defaultdict(set);processed=0;invalid=[];seen_owners=set()
    for filename,features in owners:
        if not safe_tile_name(filename) or filename not in inventory or filename in seen_owners:
            raise IndexErrorDetail('Unexpected/duplicate owner filename')
        seen_owners.add(filename)
        for f in features:
            if not isinstance(f,dict) or not isinstance(f.get('id'),str) or not isinstance(f.get('kind'),str):
                raise IndexErrorDetail('Feature lacks semantic source identity')
            try:g=shape(f['geometry'])
            except Exception as e:raise IndexErrorDetail('Unreadable geometry '+f['id']) from e
            if g.is_empty:raise IndexErrorDetail('Empty source geometry '+f['id'])
            bad=not g.is_valid
            if bad:invalid.append({'owner':filename,'id':f['id'],'kind':f['kind'],'indexing':'conservative_bbox; source not repaired'})
            search=box(*g.bounds) if bad else g
            a,b,c,d=cell_range(g.bounds,size)
            for ix in range(max(a,c0),min(c,c2)+1):
                for iz in range(max(b,c1),min(d,c3)+1):
                    part=cells_geometry.get((ix,iz))
                    if part is not None and search.intersects(part):dependencies[(ix,iz)].add(filename)
            processed+=1
    if seen_owners!=set(inventory):raise IndexErrorDetail('Not all canonical owner files were indexed')
    cells={f'{x}_{z}':sorted(names) for (x,z),names in sorted(dependencies.items())}
    return {'schema':SCHEMA,'created_utc':datetime.now(timezone.utc).isoformat(),
        'snapshot_manifest_sha256':manifest_sha256,'boundary_sha256':boundary_sha256,
        'georeference':manifest['georeference'],'tile_metres':size,
        'source':{k:manifest.get(k) for k in ['source_url','pbf_sha256','source_snapshot_utc','attribution','data_license','license_url']},
        'country_world_bounds_xz':list(country.bounds),'country_cells':len(cells_geometry),
        'indexed_cells':len(cells),'owner_files':len(inventory),'features_indexed':processed,
        'canonical_geometry_unchanged':True,'invalid_source_geometries':invalid,
        'selection':'References only where feature geometry intersects exact projected country/tile intersection; invalid geometry uses recorded conservative bbox',
        'query_scope':'Raw crossing geometry is retained in owner files; consumer must clip render geometry to country if required. Cell membership is not a point-in-country certificate.',
        'cells':cells}

def read_owners(snapshot,manifest):
    for t in manifest['tiles']:
        name=t.get('file')
        if not safe_tile_name(name):raise IndexErrorDetail('Unsafe canonical tile filename')
        p=snapshot/name
        if p.is_symlink():raise IndexErrorDetail('Canonical tile symlink refused')
        data=p.read_bytes()
        if len(data)!=t.get('bytes') or sha(data)!=t.get('sha256'):
            raise IndexErrorDetail('Canonical tile checksum/length mismatch: '+name)
        payload=json.loads(data)
        if payload.get('tile')!=name[:-5] or not isinstance(payload.get('features'),list) or len(payload['features'])!=t.get('features'):
            raise IndexErrorDetail('Canonical tile schema/count mismatch: '+name)
        yield name,payload['features']

def main():
    p=argparse.ArgumentParser();p.add_argument('snapshot',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    if a.output.exists():raise SystemExit('Refusing to overwrite an existing index')
    start=time.monotonic();raw=(a.snapshot/'manifest.json').read_bytes();m=json.loads(raw)
    boundary=(a.snapshot/'singapore-boundary.geojson').read_bytes()
    result=build_index(m,read_owners(a.snapshot,m),projected_country(json.loads(boundary)),manifest_sha256=sha(raw),boundary_sha256=sha(boundary))
    result['build_seconds']=round(time.monotonic()-start,3)
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,separators=(',',':'),ensure_ascii=False)+'\n')
    print(json.dumps({'output':str(a.output),'bytes':a.output.stat().st_size,'sha256':sha(a.output.read_bytes()),**{k:result[k] for k in ['owner_files','features_indexed','country_cells','indexed_cells','build_seconds']},'invalid_source_geometries':len(result['invalid_source_geometries'])}),flush=True)
if __name__=='__main__':main()
