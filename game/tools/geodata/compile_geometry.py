#!/usr/bin/env python3
"""Compile regional source-metre shapes; not a completed/accurate rendered city.

No elevation, road width, storey height, material or interior is invented. Source
features live once in a catalog; chunk fragments reference their kind+OSM ID.
"""
import argparse
from collections import Counter, defaultdict
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import re
import time

import shapely
from shapely import constrained_delaunay_triangles
from shapely.geometry import LineString, Point, Polygon, box, mapping, shape
from shapely.ops import unary_union
from build_spatial_index import (SCHEMA as INDEX_SCHEMA, IndexErrorDetail,
    projected_country, read_owners, safe_tile_name, sha, validate_frame)

SCHEMA = 'singapore_source_geometry_patch_v1'
MAX_QUERY_CELLS = 64
MAX_OWNER_BYTES = 32 * 1024 * 1024
MAX_METADATA_BYTES = 16 * 1024 * 1024
MAX_CHUNKS = 256
SEMANTIC_TAGS = ('highway','construction','proposed','bridge','tunnel','layer',
    'access','vehicle','motor_vehicle','motorcar','foot','bicycle','oneway',
    'junction','service','surface','lanes','maxspeed','width','width:carriageway',
    'ele','incline','level','height','min_height','building','building:part',
    'building:levels','building:min_level')
HASH_RE = re.compile(r'^[0-9a-f]{64}$')
METRES_RE = re.compile(r'^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*(?:m)?\s*$')

class GeometryCompileError(ValueError):
    pass

def canonical_bytes(value):
    return (json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,
                       allow_nan=False)+'\n').encode('utf-8')

def identity(feature):
    if not isinstance(feature,dict) or not isinstance(feature.get('id'),str) or not isinstance(feature.get('kind'),str):
        raise GeometryCompileError('Source feature lacks kind/id')
    return feature['kind']+'|'+feature['id']

def metre_tag(raw, *, positive=False):
    """Parse only explicit simple metre values, never infer from levels/lanes."""
    if raw is None:return None
    match=METRES_RE.fullmatch(str(raw))
    if not match:return None
    value=float(match.group(1))
    return value if math.isfinite(value) and (not positive or value>0) else None

def explicit_measurements(feature):
    tags=feature.get('tags',{})
    height=feature.get('height_m')
    if not isinstance(height,(int,float)) or isinstance(height,bool) or not math.isfinite(height) or height<=0:
        height=None
    return {
        'height_m':height,
        'height_status':feature.get('height_status','unknown'),
        'height_source_tag':tags.get('height'),
        'width_m':metre_tag(tags.get('width'),positive=True),
        'width_source_tag':tags.get('width'),
        'carriageway_width_m':metre_tag(tags.get('width:carriageway'),positive=True),
        'carriageway_width_source_tag':tags.get('width:carriageway'),
        'elevation_tag_m':metre_tag(tags.get('ele')),
        'elevation_source_tag':tags.get('ele'),
        'elevation_datum':'not established by this compiler',
        'terrain_base_elevation_m':None,
        'width_status':'source_tag' if metre_tag(tags.get('width'),positive=True) is not None else 'unknown',
        'vertical_fit_status':'unresolved; source height/ele alone is not a surveyed building base or terrain model',
        'levels_are_not_converted_to_height':True,
        'missing_tag_meaning':'unassessed; absence in canonical snapshot is not proof of real-world absence',
    }

def bounded_json(path,limit=MAX_METADATA_BYTES):
    if path.is_symlink():raise GeometryCompileError('Symlink source file refused: '+str(path))
    data=path.read_bytes()
    if not data or len(data)>limit:raise GeometryCompileError('Source size outside bound: '+str(path))
    return json.loads(data),data

def _bounds(bounds):
    if len(bounds)!=4 or not all(math.isfinite(v) for v in bounds) or bounds[2]<=bounds[0] or bounds[3]<=bounds[1]:
        raise GeometryCompileError('Require finite positive [minX,minZ,maxX,maxZ] metre bounds')
    # Reject extreme external coordinates before integer cell arithmetic.
    if max(abs(v) for v in bounds)>100000000:
        raise GeometryCompileError('Bounds exceed supported projected coordinate domain')
    return tuple(float(v) for v in bounds)

def region_source(snapshot,index_path,bounds):
    """Read only regional dependency owners, verifying every selected source."""
    bounds=_bounds(bounds)
    manifest,manifest_bytes=bounded_json(snapshot/'manifest.json')
    validate_frame(manifest.get('georeference'))
    idx,index_bytes=bounded_json(index_path)
    boundary,boundary_bytes=bounded_json(snapshot/'singapore-boundary.geojson')
    if idx.get('schema')!=INDEX_SCHEMA or idx.get('snapshot_manifest_sha256')!=sha(manifest_bytes) or idx.get('boundary_sha256')!=sha(boundary_bytes):
        raise GeometryCompileError('Index/snapshot/country identity mismatch')
    if idx.get('georeference')!=manifest.get('georeference') or idx.get('tile_metres')!=manifest.get('tile_metres'):
        raise GeometryCompileError('Index coordinate frame differs from snapshot')
    size=manifest.get('tile_metres')
    if not isinstance(size,int) or isinstance(size,bool) or size<=0:raise GeometryCompileError('Invalid source tile size')
    cells=idx.get('cells')
    if not isinstance(cells,dict):raise GeometryCompileError('Missing dependency cells')
    identity_doc,_=bounded_json(snapshot/'spatial-index.identity.json')
    if not isinstance(identity_doc,dict) or identity_doc.get('schema')!='singapore_country_dependency_identity_v1' \
       or identity_doc.get('index_sha256')!=sha(index_bytes) or identity_doc.get('index_bytes')!=len(index_bytes) \
       or identity_doc.get('snapshot_manifest_sha256')!=sha(manifest_bytes) \
       or identity_doc.get('boundary_sha256')!=sha(boundary_bytes):
        raise GeometryCompileError('Dependency index full identity/checksum mismatch')
    x0,z0,x1,z1=(math.floor(v/size) for v in bounds)
    if (x1-x0+1)*(z1-z0+1)>MAX_QUERY_CELLS:raise GeometryCompileError('Region exceeds bounded dependency budget')
    inventory={}
    for tile in manifest.get('tiles',[]):
        name=tile.get('file')
        if not safe_tile_name(name) or name in inventory or not HASH_RE.fullmatch(str(tile.get('sha256',''))):
            raise GeometryCompileError('Unsafe/duplicate source inventory')
        if not isinstance(tile.get('bytes'),int) or not 0<tile['bytes']<=MAX_OWNER_BYTES:
            raise GeometryCompileError('Owner byte size outside bound')
        if not isinstance(tile.get('features'),int) or isinstance(tile['features'],bool) or tile['features']<0:
            raise GeometryCompileError('Invalid owner feature count')
        inventory[name]=tile
    expected={'indexed_cells':len(cells),'owner_files':len(inventory),
              'features_indexed':sum(t['features'] for t in inventory.values())}
    if any(idx.get(k)!=v or identity_doc.get(k)!=v for k,v in expected.items()):
        raise GeometryCompileError('Dependency index inventory/count mismatch')
    referenced=set()
    for key,names in cells.items():
        if not safe_tile_name(key+'.json') or not isinstance(names,list):
            raise GeometryCompileError('Unsafe dependency cell')
        for name in names:
            if not safe_tile_name(name) or name not in inventory:
                raise GeometryCompileError('Unsafe/missing dependency owner')
            referenced.add(name)
    if any(t['features']>0 and name not in referenced for name,t in inventory.items()):
        raise GeometryCompileError('Dependency index omits a nonempty canonical owner')
    owners=set()
    for x in range(x0,x1+1):
        for z in range(z0,z1+1):
            names=cells.get(f'{x}_{z}',[])
            if not isinstance(names,list):raise GeometryCompileError('Invalid dependency list')
            for name in names:
                if not safe_tile_name(name) or name not in inventory:raise GeometryCompileError('Unsafe/missing dependency owner')
                owners.add(name)
    country=projected_country(boundary)
    region=box(*bounds).intersection(country)
    if region.is_empty or region.area<=0:raise GeometryCompileError('Requested region has no country surface')
    records={};owner_manifest=[inventory[name] for name in sorted(owners)]
    for owner,features in read_owners(snapshot,{'tiles':owner_manifest}):
        for feature in features:
            key=identity(feature)
            try:g=shape(feature['geometry'])
            except Exception as e:raise GeometryCompileError('Unreadable source geometry '+key) from e
            if not g.is_empty and g.intersects(region):
                if key in records:
                    if records[key]['feature']!=feature:raise GeometryCompileError('Conflicting duplicate '+key)
                    records[key]['owners'].append(owner)
                else:records[key]={'feature':feature,'owners':[owner]}
    provenance={
        'snapshot_manifest_sha256':sha(manifest_bytes),'dependency_index_sha256':sha(index_bytes),
        'country_boundary_sha256':sha(boundary_bytes),
        'canonical_owners':owner_manifest,'dependency_owner_count':len(owners),
        'attribute_coverage_declared_by_manifest':manifest.get('preserved_tags'),
        'missing_tag_interpretation':'unassessed; omitted source attributes cannot be recovered or inferred by this compiler',
        'source':{k:manifest.get(k) for k in ('source_url','pbf_sha256','source_snapshot_utc','attribution','data_license','license_url')},
    }
    return manifest,[records[k] for k in sorted(records)],region,provenance

def _parts(geometry,kind):
    if geometry.is_empty:return []
    if geometry.geom_type==kind:return [geometry]
    if hasattr(geometry,'geoms'):
        return [p for g in geometry.geoms for p in _parts(g,kind)]
    return []

def _area2(points):
    return sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(points,points[1:]+points[:1]))

def _ring(points,offset,clockwise):
    points=[(float(p[0])-offset[0],float(p[1])-offset[1]) for p in points]
    if points[0]==points[-1]:points.pop()
    if (_area2(points)<0)!=clockwise:points.reverse()
    first=min(range(len(points)),key=lambda i:points[i])
    points=points[first:]+points[:first]
    return [list(p) for p in points+[points[0]]]

def surface_geometry(polygon,offset):
    """Exact constrained triangulation; +Y is up on the reference plane."""
    if polygon.is_empty or not polygon.is_valid or polygon.area<=0:raise GeometryCompileError('Cannot triangulate invalid/empty polygon')
    triangles=list(constrained_delaunay_triangles(polygon).geoms)
    tolerance=max(1e-8,polygon.area*1e-10)
    covered=unary_union(triangles)
    if not triangles or covered.symmetric_difference(polygon).area>tolerance or sum(t.area for t in triangles)-polygon.area>tolerance:
        raise GeometryCompileError('Constrained triangulation failed footprint/hole area identity')
    # Triangles are sorted independently of GEOS collection order. No quantizing
    # or mesh simplification changes the canonical input's metre geometry.
    positions=sorted({(float(p[0])-offset[0],float(p[1])-offset[1]) for t in triangles for p in list(t.exterior.coords)[:-1]})
    lookup={p:i for i,p in enumerate(positions)};indices=[]
    for triangle in triangles:
        if triangle.difference(polygon).area>tolerance:raise GeometryCompileError('Triangle crosses source hole/boundary')
        points=[(float(p[0])-offset[0],float(p[1])-offset[1]) for p in list(triangle.exterior.coords)[:-1]]
        if _area2(points)>0:points.reverse() # CW in XZ -> positive cross-product Y.
        tri=[lookup[p] for p in points]
        start=tri.index(min(tri));tri=tri[start:]+tri[:start]
        indices.append(tri)
    indices.sort()
    vertices=[[x,0.0,z] for x,z in positions]
    exterior=_ring(polygon.exterior.coords,offset,True)
    holes=sorted((_ring(r.coords,offset,False) for r in polygon.interiors),key=lambda r:canonical_bytes(r))
    topology_sha=sha(canonical_bytes({'vertices_local_xyz':vertices,'triangles':indices}))
    return {'rings_local_xz':[exterior,*holes],'vertices_local_xyz':vertices,'triangles':indices,
        'normal_local_xyz':[0.0,1.0,0.0],'reference_plane_y':0.0,
        'reference_plane_is_world_elevation':False,'area_m2':polygon.area,
        'topology_sha256':topology_sha,
        'collision_topology':{'vertices_ref':'vertices_local_xyz','triangles_ref':'triangles',
            'topology_sha256':topology_sha,'activation':'deferred until surveyed vertical placement and gameplay validation'},
    }

def _cell_span(bounds,size):
    a,b,c,d=bounds
    return math.floor(a/size),math.floor(b/size),math.ceil(c/size)-1,math.ceil(d/size)-1

def _owned_boundary_parts(line,ix,iz,size,cells):
    """Positive-side ownership applies only where that actual clip exists.

    A hole/coast can remove that cell, or only part of its shared edge. Keep
    the remaining boundary here rather than dropping a real source segment.
    """
    a,b,c,d=line.bounds
    owned=line
    if a==c and math.floor(a/size)*size==a:
        positive=math.floor(a/size)
        neighbor=cells.get((positive,iz))
        if ix<positive and neighbor is not None:owned=owned.difference(neighbor)
    if b==d and math.floor(b/size)*size==b:
        positive=math.floor(b/size)
        neighbor=cells.get((ix,positive))
        if iz<positive and neighbor is not None:owned=owned.difference(neighbor)
    return _parts(owned,'LineString')

def _path_fragments(part,clip,ix,iz,size,cells):
    # Clip source segments individually. Clipping a whole L-shaped path can
    # retain a seam segment on both sides, and geometric union can erase a
    # deliberate retraced source segment. Segment distances preserve order.
    points=list(part.coords);distance=0.;pieces=[]
    for segment_index,(a,b) in enumerate(zip(points,points[1:])):
        segment=LineString([a,b]);length=segment.length
        if length<=0:continue
        clipped=_parts(segment.intersection(clip),'LineString')
        for piece in (p for line in clipped for p in _owned_boundary_parts(line,ix,iz,size,cells)):
            if piece.length<=0:continue
            pts=list(piece.coords)
            first=segment.project(Point(pts[0]));last=segment.project(Point(pts[-1]))
            if first>last:pts.reverse();first,last=last,first
            pieces.append({'points':pts,'start':distance+first,'end':distance+last,
                'source_segment_start':segment_index,'source_segment_end':segment_index})
        distance+=length
    pieces.sort(key=lambda p:(p['start'],p['end'],p['points']))
    merged=[]
    for piece in pieces:
        if merged and abs(merged[-1]['end']-piece['start'])<1e-9 and merged[-1]['points'][-1]==piece['points'][0]:
            merged[-1]['points'].extend(piece['points'][1:]);merged[-1]['end']=piece['end']
            merged[-1]['source_segment_end']=piece['source_segment_end']
        else:merged.append(piece)
    return merged

def compile_patch(manifest,records,region,*,chunk_metres=250,provenance=None):
    validate_frame(manifest.get('georeference'))
    if not isinstance(chunk_metres,int) or isinstance(chunk_metres,bool) or not 1<=chunk_metres<=2000:
        raise GeometryCompileError('Chunk size must be an integer 1..2000 metres')
    bounds=_bounds(region.bounds);span=_cell_span(bounds,chunk_metres)
    x0,z0,x1,z1=span
    if (x1-x0+1)*(z1-z0+1)>MAX_CHUNKS:raise GeometryCompileError('Patch exceeds256 chunk budget')
    cells={}
    for ix in range(x0,x1+1):
        for iz in range(z0,z1+1):
            clip=region.intersection(box(ix*chunk_metres,iz*chunk_metres,(ix+1)*chunk_metres,(iz+1)*chunk_metres))
            if not clip.is_empty and clip.area>0:cells[(ix,iz)]=clip
    catalog=[];chunks=defaultdict(list);issues=[];seen={};counts=Counter();clipped_area=0.;compiled_area=0.;clipped_length=0.;compiled_length=0.
    for record in sorted(records,key=lambda r:identity(r['feature'])):
        f=record['feature'];key=identity(f)
        if key in seen:
            if seen[key]!=f:raise GeometryCompileError('Conflicting duplicate '+key)
            continue
        seen[key]=f;g=shape(f['geometry'])
        if g.is_empty or not g.intersects(region):continue
        if g.geom_type not in {'Polygon','MultiPolygon','LineString','MultiLineString'}:
            issues.append({'feature_key':key,'status':'unresolved unsupported source geometry','geometry_type':g.geom_type});continue
        if not g.is_valid:
            issues.append({'feature_key':key,'status':'unresolved invalid source geometry; no repair/extrusion invented'});continue
        original_parts=_parts(g,'Polygon' if g.geom_type in {'Polygon','MultiPolygon'} else 'LineString')
        metadata={'feature_key':key,'id':f['id'],'kind':f['kind'],'name':f.get('tags',{}).get('name'),
            'tags':deepcopy(f.get('tags',{})),'source_geometry_world_xz':deepcopy(f['geometry']),
            'source_feature_sha256':sha(canonical_bytes(f)),'canonical_owner_files':sorted(set(record.get('owners',[]))),
            'explicit_measurements':explicit_measurements(f),'semantic_tags':{k:f.get('tags',{}).get(k) for k in SEMANTIC_TAGS if k in f.get('tags',{})},
            'renderer_assumptions':[],'vertical_geometry_status':'not compiled; terrain/base/bridge/tunnel profiles unresolved',
        }
        catalog.append(metadata);counts[f['kind']]+=1
        if f['kind']=='building':counts['building_height_known' if metadata['explicit_measurements']['height_m'] is not None else 'building_height_unknown']+=1
        if f['kind']=='road':
            counts['road_width_known' if metadata['explicit_measurements']['width_m'] is not None else 'road_width_unknown']+=1
            counts['road_elevation_tag_known' if metadata['explicit_measurements']['elevation_tag_m'] is not None else 'road_elevation_unknown']+=1
        for source_part,part in enumerate(original_parts):
            target_kind=part.geom_type
            if target_kind=='Polygon':
                clipped_area+=sum(p.area for p in _parts(part.intersection(region),'Polygon'))
            else:
                points=list(part.coords)
                clipped_length+=sum(LineString([a,b]).intersection(region).length for a,b in zip(points,points[1:]))
            for (ix,iz),clip in cells.items():
                if not part.intersects(clip):continue
                offset=(ix*chunk_metres,iz*chunk_metres)
                if target_kind=='Polygon':
                    pieces=_parts(part.intersection(clip),'Polygon')
                    pieces.sort(key=lambda p:(p.bounds,p.wkb_hex))
                    for fragment_index,piece in enumerate(pieces):
                        if piece.area<=0:continue
                        entry={'feature_key':key,'source_feature_sha256':metadata['source_feature_sha256'],
                            'source_part':source_part,'fragment':fragment_index,'surface':surface_geometry(piece,offset)}
                        compiled_area+=piece.area;chunks[(ix,iz)].append(entry)
                else:
                    pieces=_path_fragments(part,clip,ix,iz,chunk_metres,cells)
                    for fragment_index,piece in enumerate(pieces):
                        length=sum(math.dist(a,b) for a,b in zip(piece['points'],piece['points'][1:]))
                        entry={'feature_key':key,'source_feature_sha256':metadata['source_feature_sha256'],
                            'source_part':source_part,'fragment':fragment_index,
                            'path':{'points_local_xz':[[float(x)-offset[0],float(z)-offset[1]] for x,z in piece['points']],
                                'length_m':length,'source_distance_start_m':piece['start'],'source_distance_end_m':piece['end'],
                                'source_segment_start':piece['source_segment_start'],'source_segment_end':piece['source_segment_end'],
                                'source_centerline_is_simple':part.is_simple,'road_surface_not_inferred':True,
                                'vertical_profile_status':'unknown; layer/bridge/tunnel tags are semantic, not metric elevations'}}
                        compiled_length+=length;chunks[(ix,iz)].append(entry)
    tolerance=max(1e-7,clipped_area*1e-9)
    if abs(clipped_area-compiled_area)>tolerance:raise GeometryCompileError('Chunk surface area loss/duplication')
    if abs(clipped_length-compiled_length)>max(1e-7,clipped_length*1e-9):raise GeometryCompileError('Chunk path length loss/duplication')
    documents={}
    for (ix,iz),entries in sorted(chunks.items()):
        entries.sort(key=lambda e:(e['feature_key'],e['source_part'],e['fragment']))
        documents[f'{ix}_{iz}.json']={'schema':SCHEMA,'chunk':[ix,iz],
            'world_offset_xyz':[ix*chunk_metres,0.0,iz*chunk_metres],
            'metres_per_unit':1.0,'scale_applied':1.0,'fragments':entries}
    report={'schema':SCHEMA,'georeference':deepcopy(manifest['georeference']),
        'region_bounds_world_xz':list(bounds),'chunk_metres':chunk_metres,
        'counts':{'features':len(catalog),**dict(sorted(counts.items())),'chunks':len(documents)},
        'source':provenance or {},'toolchain':{'shapely':shapely.__version__,'geos':shapely.geos_version_string},
        'integrity':{'source_geometry_unchanged_in_catalog':True,'no_distance_compression':True,
            'compiled_surface_area_m2':compiled_area,'selected_source_surface_area_m2':clipped_area,
            'compiled_path_length_m':compiled_length,'selected_source_path_length_m':clipped_length,
            'shared_collision_topology':True,'default_height_or_width_invented':False},
        'issues':issues,
        'attribute_coverage':{'observed_semantic_tags':sorted({k for f in catalog for k in f['semantic_tags']}),
            'unassessed_tags_without_patch_records':sorted(set(SEMANTIC_TAGS)-{k for f in catalog for k in f['semantic_tags']}),
            'missing_is_not_false_or_absent_in_real_world':True},
        'limitations':['Not a completed or visually accepted one-to-one city.',
            'Reference-plane triangulations are not surveyed terrain, road elevation or playable collisions.',
            'Unknown building heights remain unknown; no arbitrary building extrusion is compiled.',
            'Bridge/tunnel/layer/access tags are retained; metric vertical alignments and legal driveability remain unresolved.',
            'Footprints/centreline data do not establish facade detail, roofs, materials, rooms or source-backed interior fit-out.',
            'Canonical extraction may omit source tags; missing tags are unassessed, not a negative real-world assertion.',
            'No texture, lighting, animation, performance or runtime/gameplay verification is implied.'],
    }
    return {'catalog':catalog,'chunks':documents,'report':report}

def write_patch(output,compiled):
    if output.exists():raise GeometryCompileError('Refusing to overwrite output/evidence: '+str(output))
    output.mkdir(parents=True)
    catalog_path=output/'features.json';catalog_bytes=canonical_bytes(compiled['catalog']);catalog_path.write_bytes(catalog_bytes)
    inventory=[]
    for filename,payload in sorted(compiled['chunks'].items()):
        if not safe_tile_name(filename):raise GeometryCompileError('Unsafe generated chunk name')
        data=canonical_bytes(payload);(output/filename).write_bytes(data)
        inventory.append({'file':filename,'bytes':len(data),'sha256':sha(data),'fragments':len(payload['fragments'])})
    report=deepcopy(compiled['report']);report['feature_catalog']={'file':'features.json','bytes':len(catalog_bytes),'sha256':sha(catalog_bytes)};report['chunks']=inventory
    report_bytes=canonical_bytes(report);(output/'manifest.json').write_bytes(report_bytes)
    return {'output':str(output),'manifest_sha256':sha(report_bytes),'total_bytes':sum(p.stat().st_size for p in output.iterdir()),'counts':report['counts'],'integrity':report['integrity'],'issues':len(report['issues'])}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot',type=Path);parser.add_argument('--index',type=Path,required=True)
    parser.add_argument('--bbox',type=float,nargs=4,metavar=('MIN_X','MIN_Z','MAX_X','MAX_Z'),required=True)
    parser.add_argument('--chunk-metres',type=int,default=250);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();started=time.monotonic()
    manifest,records,region,provenance=region_source(args.snapshot,args.index,args.bbox)
    result=write_patch(args.output,compile_patch(manifest,records,region,chunk_metres=args.chunk_metres,provenance=provenance))
    result['compile_seconds']=round(time.monotonic()-started,3);print(json.dumps(result,sort_keys=True),flush=True)

if __name__=='__main__':main()
