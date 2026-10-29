#!/usr/bin/env python3
"""Bounded public Skadi acquisition +25m source-metre DEM derivative.

EGM96 source elevation is not surveyed/current ground, terrain collision,
MBS L1, ellipsoid altitude, a sea level or a 3D hydrology model.
"""
import argparse
from datetime import datetime,timezone
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import sys
import urllib.request
import urllib.error
import numpy as np
from pyproj import Transformer
from shapely.geometry import box
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'geodata'))
import georeference
from build_spatial_index import projected_country,validate_frame

TILES={'N01E103':'https://s3.amazonaws.com/elevation-tiles-prod/skadi/N01/N01E103.hgt.gz',
       'N01E104':'https://s3.amazonaws.com/elevation-tiles-prod/skadi/N01/N01E104.hgt.gz'}
SAMPLES=3601
HGT_BYTES=SAMPLES*SAMPLES*2
MAX_GZIP_BYTES=32*1024*1024
VOID=-32768
SPACING=25
CHUNK_METRES=1000
CELLS=40
STORED=43
CHUNK_BYTES=STORED*STORED*4
MAX_CHUNKS=5000
MANIFEST_SCHEMA='singapore_skadi_terrain_manifest_v1'
IDENTITY_SCHEMA='singapore_skadi_terrain_identity_v1'
FRAME=georeference.manifest()
INVERSE=Transformer.from_crs('EPSG:3414','EPSG:4326',always_xy=True)

class TerrainError(ValueError):pass

def canonical(value):return (json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)+'\n').encode()
def sha(raw):return hashlib.sha256(raw).hexdigest()
def sha_file(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()
def now():return datetime.now(timezone.utc).isoformat()
def publish(part,target):
    os.link(part,target) # Atomic exclusive publication; never replace another file.
    part.unlink()

def cleanup_owned_part(path,identity):
    # Exclusive open may fail because another writer owns this path. Never
    # remove that writer's part, including a dangling link or later generation.
    if identity is None:return
    try:
        current=path.lstat()
        if (current.st_dev,current.st_ino)==identity:path.unlink()
    except FileNotFoundError:pass

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):raise TerrainError('Unexpected public-source redirect; not followed')

def decode_hgt(path,samples=SAMPLES):
    if path.is_symlink() or path.stat().st_size!=samples*samples*2:raise TerrainError('HGT dimensions/byte length mismatch')
    return np.memmap(path,dtype='>i2',mode='r',shape=(samples,samples))

def bounded_gunzip(source,target,expected=HGT_BYTES):
    part=target.with_suffix(target.suffix+'.part')
    written=0;h=hashlib.sha256();owned=None
    try:
        with gzip.open(source,'rb') as src,part.open('xb') as out:
            created=os.fstat(out.fileno());owned=(created.st_dev,created.st_ino)
            while True:
                block=src.read(65536)
                if not block:break
                written+=len(block)
                if written>expected:raise TerrainError('Gzip output exceeds exact HGT byte bound')
                out.write(block);h.update(block)
            out.flush();os.fsync(out.fileno())
        if written!=expected:raise TerrainError('Gzip output does not match exact HGT byte count')
        publish(part,target)
    except Exception:
        cleanup_owned_part(part,owned)
        raise
    return h.hexdigest()

def download_sources(directory):
    directory.mkdir(parents=True,exist_ok=True)
    receipts=[];opener=urllib.request.build_opener(NoRedirect())
    for tile,url in TILES.items():
        gz=directory/(tile+'.hgt.gz');hgt=directory/(tile+'.hgt');receipt=directory/(tile+'.download.json')
        if any(p.is_symlink() for p in (receipt,gz,hgt)):raise TerrainError('Symlink source/receipt refused')
        if receipt.exists():
            r=json.loads(receipt.read_bytes())
            if r.get('url')!=url or r.get('http_status')!=200 or sha_file(gz)!=r.get('compressed_sha256') or sha_file(hgt)!=r.get('hgt_sha256') or hgt.stat().st_size!=HGT_BYTES:
                raise TerrainError('Existing public source receipt/bytes mismatch; no overwrite/re-download')
            receipts.append(r);continue
        if gz.exists() or hgt.exists():raise TerrainError('Unreceipted source file exists; refusing overwrite')
        part=gz.with_suffix(gz.suffix+'.part');size=0;digest=hashlib.sha256();started=now()
        owned=None;receipt_part=receipt.with_suffix('.json.part');receipt_owned=None
        try:
            request=urllib.request.Request(url,method='GET',headers={'User-Agent':'OrchardReach-source-terrain/1.0','Accept-Encoding':'identity'})
            with opener.open(request,timeout=90) as response,part.open('xb') as out:
                created=os.fstat(out.fileno());owned=(created.st_dev,created.st_ino)
                if response.status!=200:raise TerrainError('Public source did not return HTTP200')
                length=response.headers.get('Content-Length')
                if length is not None and int(length)>MAX_GZIP_BYTES:raise TerrainError('Compressed source exceeds32MiB bound')
                metadata={k:response.headers.get(k) for k in ('ETag','Last-Modified','Content-Length','Content-Type','Content-Encoding','X-Imagery-Sources','x-amz-version-id') if response.headers.get(k) is not None}
                while True:
                    block=response.read(65536)
                    if not block:break
                    size+=len(block)
                    if size>MAX_GZIP_BYTES:raise TerrainError('Compressed source exceeds32MiB bound')
                    out.write(block);digest.update(block)
                out.flush();os.fsync(out.fileno())
            if length is not None and size!=int(length):raise TerrainError('HTTP source byte count mismatch')
            publish(part,gz)
            owned=None
            hgt_hash=bounded_gunzip(gz,hgt)
            r={'tile':tile,'url':url,'http_status':200,'requested_utc':started,'completed_utc':now(),
                'http_metadata':metadata,'compressed_bytes':size,'compressed_sha256':digest.hexdigest(),
                'hgt_bytes':HGT_BYTES,'hgt_sha256':hgt_hash,'samples':[SAMPLES,SAMPLES],
                'format':'gzip SRTMGL1 big-endian signed int16; row0 north2deg/column0 west tile longitude',
                'vertical_reference':'EGM96 geoid metres','void_value':VOID,'authentication':'Public anonymous ordinary HTTPS GET; no account/API key',
                'source_age':'Download time is not measurement time; older composite, per-pixel acquisition date unverified'}
            with receipt_part.open('xb') as f:
                created=os.fstat(f.fileno());receipt_owned=(created.st_dev,created.st_ino)
                f.write(canonical(r))
            publish(receipt_part,receipt)
            receipt_owned=None
            receipts.append(r)
        except Exception as e:
            cleanup_owned_part(part,owned)
            cleanup_owned_part(receipt_part,receipt_owned)
            failed=directory/(tile+'.failure.json')
            try:
                with failed.open('xb') as failure_file:failure_file.write(canonical({'tile':tile,'url':url,'status':'failed','failure_type':type(e).__name__,
                    'http_status':e.code if isinstance(e,urllib.error.HTTPError) else None,'scope':'No alternate endpoint/authentication/security bypass attempted'}))
            except FileExistsError:pass
            raise
    return receipts

class HgtPair:
    def __init__(self,west,east):
        if west.shape!=east.shape or len(west.shape)!=2 or west.shape[0]!=west.shape[1] or west.shape[0]<2:raise TerrainError('Need matching square source grids')
        self.west=west;self.east=east;self.n=west.shape[0];self.intervals=self.n-1
        self.seam_conflicts=int(np.count_nonzero(np.asarray(west[:,-1])!=np.asarray(east[:,0])))
    def posts(self,row,column):
        out=np.empty(row.shape,dtype=np.int16);n=self.intervals
        left=column<n;right=column>n;seam=column==n
        out[left]=self.west[row[left],column[left]]
        out[right]=self.east[row[right],column[right]-n]
        if np.any(seam):
            a=self.west[row[seam],n];b=self.east[row[seam],0]
            out[seam]=np.where(a==b,a,VOID)
        return out
    def sample(self,lon,lat):
        lon,lat=np.broadcast_arrays(np.asarray(lon,dtype=np.float64),np.asarray(lat,dtype=np.float64))
        valid=np.isfinite(lon)&np.isfinite(lat)&(lon>=103)&(lon<=105)&(lat>=1)&(lat<=2)
        gx=np.where(valid,(lon-103)*self.intervals,0.);gy=np.where(valid,(2-lat)*self.intervals,0.)
        col=np.minimum(np.floor(gx).astype(np.int64),2*self.intervals-1);row=np.minimum(np.floor(gy).astype(np.int64),self.intervals-1)
        u=gx-col;v=gy-row;result=np.zeros(lon.shape,dtype=np.float64)
        for dr,dc,weight in ((0,0,(1-u)*(1-v)),(0,1,u*(1-v)),(1,0,(1-u)*v),(1,1,u*v)):
            values=self.posts(row+dr,col+dc)
            valid &= (weight==0)|(values!=VOID)
            result+=np.where(weight==0,0.,values.astype(np.float64)*weight)
        return np.where(valid,result,np.nan)
    def global_grid(self,gx,gz):
        x=np.asarray(gx,dtype=np.float64)*SPACING;z=np.asarray(gz,dtype=np.float64)*SPACING
        lon,lat=INVERSE.transform(30000.-z,30000.-x)
        values=self.sample(lon,lat).astype('<f4');values[np.isnan(values)]=np.float32(np.nan)
        return values

def chunk_indices(tx,tz):
    xs=np.arange(tx*CELLS-1,tx*CELLS+CELLS+2,dtype=np.int64)
    zs=np.arange(tz*CELLS-1,tz*CELLS+CELLS+2,dtype=np.int64)
    return np.meshgrid(xs,zs,indexing='xy')

def verify_shared_edge(a,b,axis):
    if axis=='x':return a[:,-3:].tobytes()==b[:,:3].tobytes()
    if axis=='z':return a[-3:,:].tobytes()==b[:3,:].tobytes()
    raise TerrainError('Unknown seam axis')

def compile_chunks(pair,country,output):
    if output.exists():raise TerrainError('Refusing to overwrite terrain dataset')
    bounds=country.bounds
    if len(bounds)!=4 or any(not math.isfinite(v) or abs(v)>10000000.0 for v in bounds):
        raise TerrainError('Country bounds are nonfinite or outside the canonical source domain')
    if bounds[0]>=bounds[2] or bounds[1]>=bounds[3]:raise TerrainError('Country extent must have positive area')
    x0,z0,x1,z1=(math.floor(v/CHUNK_METRES) for v in bounds)
    # Check candidate work BEFORE enumerating/intersecting/allocating. A thin
    # or misprojected polygon cannot force enormous bounding-grid loops.
    if (x1-x0+1)*(z1-z0+1)>MAX_CHUNKS*2:
        raise TerrainError('Country bounding grid exceeds10000 candidate work budget')
    cells=[]
    for tx in range(x0,x1+1):
        for tz in range(z0,z1+1):
            if country.intersects(box(tx*1000,tz*1000,(tx+1)*1000,(tz+1)*1000)):
                cells.append((tx,tz))
                if len(cells)>MAX_CHUNKS:raise TerrainError('National terrain exceeds5000 chunk work budget')
    output.mkdir(parents=True);inventory=[];completed={};seams=0
    for tx,tz in cells:
        gx,gz=chunk_indices(tx,tz);values=pair.global_grid(gx,gz);raw=values.tobytes()
        if len(raw)!=CHUNK_BYTES:raise TerrainError('Unexpected binary chunk dimensions')
        for neighbor,axis in (((tx-1,tz),'x'),((tx,tz-1),'z')):
            if neighbor in completed:
                other=np.fromfile(output/completed[neighbor],dtype='<f4').reshape(STORED,STORED)
                if not verify_shared_edge(other,values,axis):raise TerrainError('Shared global sample seam bytes differ')
                seams+=1
        name=f'{tx}_{tz}.f32'
        with (output/name).open('xb') as f:f.write(raw)
        finite=values[np.isfinite(values)]
        inventory.append({'file':name,'chunk_xz':[tx,tz],'bytes':len(raw),'sha256':sha(raw),
            'core_global_index_min_xz':[tx*CELLS,tz*CELLS],'stored_global_index_min_xz':[tx*CELLS-1,tz*CELLS-1],
            'valid_posts':int(finite.size),'void_posts':int(values.size-finite.size),
            'minimum_egm96_m':float(finite.min()) if finite.size else None,'maximum_egm96_m':float(finite.max()) if finite.size else None})
        completed[(tx,tz)]=name
    return inventory,seams

def compile_dataset(source_dir,manifest_path,country_path,output,expected_snapshot,expected_country):
    mr=manifest_path.read_bytes();br=country_path.read_bytes();m=json.loads(mr);boundary=json.loads(br)
    if sha(mr)!=expected_snapshot or sha(br)!=expected_country:raise TerrainError('Canonical country/snapshot differs from explicit expected hashes')
    validate_frame(m.get('georeference'))
    if m['georeference']!=FRAME:raise TerrainError('Current projection differs from canonical frame')
    receipts=[]
    for tile,url in TILES.items():
        r=json.loads((source_dir/(tile+'.download.json')).read_bytes())
        if r.get('url')!=url or r.get('http_status')!=200 or sha_file(source_dir/(tile+'.hgt'))!=r.get('hgt_sha256'):
            raise TerrainError('Private raw source differs from verified acquisition receipt')
        receipts.append(r)
    pair=HgtPair(decode_hgt(source_dir/'N01E103.hgt'),decode_hgt(source_dir/'N01E104.hgt'))
    inventory,seams=compile_chunks(pair,projected_country(boundary),output)
    data={'schema':MANIFEST_SCHEMA,'version':1,'provider_id':'mapzen-public-skadi/sampled-egm96/v1',
        'bindings':{'snapshot_manifest_sha256':sha(mr),'country_wgs84_sha256':sha(br),'pbf_sha256':m['pbf_sha256'],
            'georeference':FRAME,'projection_implementation_sha256':sha(Path(georeference.__file__).read_bytes())},
        'sources':receipts,'grid':{'spacing_metres':SPACING,'chunk_metres':CHUNK_METRES,'cells_per_chunk':CELLS,
            'core_samples':41,'halo_samples':1,'stored_samples':STORED,'encoding':'float32_little_endian_row_z_ascending_column_x_ascending',
            'void_encoding':'canonical float32 NaN','global_node_identity':'[integerIndexX,integerIndexZ]*25metres; same indices across chunks',
            'native_posting_arcseconds':1,'derived_spacing_is_new_measurement_resolution':False},
        'vertical_reference':'EGM96 geoid metres','sampling':'bilinear from source HGT posting lattice; then bilinear from25m derivative',
        'normal_method':'central differences over25m derivative at query +/-25m; no invented up normal on unknown stencil',
        'coverage':'Exact administrative-country intersecting1km chunks plus one-post halo; chunk coverage does not mean territory, land, dry surface or physical support',
        'chunks':inventory,'integrity':{'shared_halo_edge_comparisons':seams,'shared_halo_bytes_identical':True,
            'source_tile_shared_column_conflict_posts':pair.seam_conflicts,'source_seam_conflicts_become_void':True},
        'attribution':{'credit':'Mapzen; SRTM/GMTED2010: U.S. Geological Survey; ETOPO1: U.S. National Oceanic and Atmospheric Administration.',
            'source_terms':'Underlying USGS/global NOAA datasets are public-domain/open source products subject to their documented attribution/disclaimer terms; no blanket code/MIT claim.',
            'urls':['https://registry.opendata.aws/terrain-tiles/','https://raw.githubusercontent.com/tilezen/joerd/master/docs/attribution.md','https://raw.githubusercontent.com/tilezen/joerd/master/docs/data-sources.md','https://raw.githubusercontent.com/tilezen/joerd/master/docs/formats.md'],
            'modifications':'Reprojected/resampled to25mSVY21-derived grid; float32 quantized; no void fill, smoothing or ground/building removal.'},
        'limits':{'max_cached_chunks':64,'default_cached_chunks':8,'max_chunk_bytes':CHUNK_BYTES,'max_chunks':MAX_CHUNKS},
        'limitations':['Older composite DEM, not current Singapore survey or current reclaimed ground; SRTM/radar/building/canopy/coastal merge artefacts possible.',
            'Native posting1arcsecond (~31m here) is not effective per-pixel resolution; GMTED/ETOPO contributions may be coarser.25m interpolation creates no new detail.',
            'EGM96 geoid elevation is not ellipsoid altitude and is not automatically aligned to the game frame/source architectural floor datum.',
            'Numeric zero may be a real source DEM value; missing/void/version errors stay unknown and are never replaced by zero ground.',
            'Not current MBSL1, physical support, dryland classification, tide/sea-surface/bottom or3D hydrology; not navigation-grade or full city acceptance.']}
    raw=canonical(data)
    with (output/'manifest.json').open('xb') as f:f.write(raw)
    identity={'schema':IDENTITY_SCHEMA,'version':1,'manifest':{'file':'manifest.json','bytes':len(raw),'sha256':sha(raw)},
        'snapshot_manifest_sha256':sha(mr),'vertical_reference':'EGM96 geoid metres','chunk_count':len(inventory)}
    iraw=canonical(identity)
    with (output/'identity.json').open('xb') as f:f.write(iraw)
    return {'identity_sha256':sha(iraw),'manifest_sha256':sha(raw),'manifest_bytes':len(raw),'chunks':len(inventory),
        'binary_bytes':len(inventory)*CHUNK_BYTES,'seam_comparisons':seams,'source_seam_conflicts':pair.seam_conflicts,
        'valid_posts_including_halo_duplicates':sum(c['valid_posts'] for c in inventory),'void_posts_including_halo_duplicates':sum(c['void_posts'] for c in inventory)}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source-dir',type=Path,required=True);p.add_argument('--download-only',action='store_true')
    p.add_argument('--manifest',type=Path);p.add_argument('--country',type=Path);p.add_argument('--expected-snapshot-sha256');p.add_argument('--expected-country-sha256');p.add_argument('--output-dir',type=Path)
    a=p.parse_args()
    try:
        if a.download_only:
            r=download_sources(a.source_dir);print(json.dumps({'status':'complete','sources':r},sort_keys=True));return 0
        if None in (a.manifest,a.country,a.expected_snapshot_sha256,a.expected_country_sha256,a.output_dir):raise TerrainError('Explicit source/snapshot/country/output arguments required')
        print(json.dumps(compile_dataset(a.source_dir,a.manifest,a.country,a.output_dir,a.expected_snapshot_sha256,a.expected_country_sha256),sort_keys=True));return 0
    except Exception as e:
        print(json.dumps({'status':'failed','reason':str(e) if isinstance(e,TerrainError) else 'Terrain source I/O/decode/projection failure; no private input paths emitted'}));return 2
if __name__=='__main__':raise SystemExit(main())
