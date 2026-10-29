#!/usr/bin/env python3
"""Streaming national source/mesh/seam validation; no engine or adoption.

Reads one physical part for conservation and a bounded3x3 neighborhood for
seams. It does not put the national mesh/triangle corpus into RAM.
"""
import argparse
from collections import Counter
import hashlib,json,math
from pathlib import Path
import resource,sqlite3,subprocess,sys,time,uuid
import numpy as np
from shapely.geometry import LineString,box

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'game/tools/geography'))
import compile_roads as frozen
MAX_RSS=2*1024**3

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for b in iter(lambda:stream.read(1024*1024),b''):h.update(b)
    return h.hexdigest()

def put(path,data):
    path=Path(path)
    if path.exists():raise ValueError('Fresh audit receipt required')
    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(frozen.canonical(data))

def read(root,descriptor):
    path=root/descriptor['file'];raw=path.read_bytes()
    if len(raw)!=descriptor['bytes'] or frozen.sha(raw)!=descriptor['sha256']:raise ValueError('National audit descriptor hash/size mismatch')
    return json.loads(raw)

def inputs(args):
    if digest(args.country/'identity.json')!=args.country_identity or digest(args.source/'identity.json')!=args.source_identity:raise ValueError('Pinned country/source identity mismatch')
    identity=json.loads((args.country/'identity.json').read_bytes());manifest=read(args.country,identity['manifest'])
    if manifest.get('parent_road_identity_sha256')!=args.source_identity:raise ValueError('National source lineage mismatch')
    original=json.loads((args.source/'identity.json').read_bytes());base=read(args.source,original['manifest'])
    if manifest['graph_chunks']!=base['graph_chunks'] or manifest['profile']!=base['profile'] or manifest['surface_height_constraints']!=base['surface_height_constraints']:raise ValueError('Frozen R5 graph/grade policy changed')
    db=sqlite3.connect('file:'+str(args.source/'work.sqlite')+'?mode=ro',uri=True);db.execute('pragma cache_size=-65536');db.execute('pragma mmap_size=0')
    index=sqlite3.connect('file:'+str(args.country/'index.sqlite')+'?mode=ro',uri=True)
    return manifest,base,db,index

def triangle_table(feature):
    mesh=feature['mesh'];vertices=np.asarray(mesh['vertices_local_xyz'],dtype=float)
    indices=np.asarray(mesh['indices'],dtype=np.int64).reshape(-1,3)
    if not np.isfinite(vertices).all() or indices.size==0 or indices.min()<0 or indices.max()>=len(vertices):raise ValueError('Invalid national mesh vertices/indices')
    tri=vertices[indices]+np.asarray(feature['anchor_source_xyz'],dtype=float)
    a=tri[:,0,:];b=tri[:,1,:];c=tri[:,2,:]
    den=(b[:,0]-a[:,0])*(c[:,2]-a[:,2])-(b[:,2]-a[:,2])*(c[:,0]-a[:,0])
    if np.any(den<=0):raise ValueError('National emitted winding not clockwise top')
    gx=((b[:,1]-a[:,1])*(c[:,2]-a[:,2])-(c[:,1]-a[:,1])*(b[:,2]-a[:,2]))/den
    gz=((b[:,0]-a[:,0])*(c[:,1]-a[:,1])-(c[:,0]-a[:,0])*(b[:,1]-a[:,1]))/den
    return tri,gx,gz,a[:,1]-gx*a[:,0]-gz*a[:,2]

def heights(table,x,z):
    tri,gx,gz,intercept=table
    mask=(x>=tri[:,:,0].min(axis=1)-.0002)&(x<=tri[:,:,0].max(axis=1)+.0002)&(z>=tri[:,:,2].min(axis=1)-.0002)&(z<=tri[:,:,2].max(axis=1)+.0002)
    ids=np.flatnonzero(mask)
    if not len(ids):return []
    selected=tri[ids]
    for i,j in [(0,1),(1,2),(2,0)]:
        dx=selected[:,j,0]-selected[:,i,0];dz=selected[:,j,2]-selected[:,i,2]
        cross=dx*(z-selected[:,i,2])-dz*(x-selected[:,i,0]);tolerance=np.hypot(dx,dz)*.0002+1e-10
        keep=cross>=-tolerance;ids=ids[keep];selected=selected[keep]
        if not len(ids):return []
    return (gx[ids]*x+gz[ids]*z+intercept[ids]).tolist()

def audit_source(args,manifest,base,source_db,index):
    counts=Counter();seen=set();maximum=0.;max_part=0;started=time.monotonic();codec=0
    descriptors=manifest['physical_tiles']
    for number,descriptor in enumerate(descriptors):
        data=read(args.country,descriptor)
        if data['tile']!=descriptor['tile'] or data['spatial_tile_key']!=descriptor['spatial_tile_key']:raise ValueError('National tile grouping mismatch')
        total_vertices=0
        for feature in data['features']:
            row=source_db.execute('select raw,policy,vertices from ways where id=?',(feature['id'],)).fetchone()
            if row is None:raise ValueError('Physical original source way missing')
            original,policy,ids=json.loads(row[0]),json.loads(row[1]),json.loads(row[2])
            if feature['name']!=original['name'] or feature['policy']!=policy or feature['source_vertex_ids']!=ids:raise ValueError('National source identity/tag/policy/order altered')
            points=[list(source_db.execute('select x,y,z from vertices where v=?',(v,)).fetchone()) for v in ids]
            if feature['source_points_xyz']!=points:raise ValueError('National canonical source profile changed')
            table=triangle_table(feature);tri,gx,gz,_=table
            slopes=np.hypot(gx,gz);maximum=max(maximum,float(slopes.max()))
            if maximum>.121:raise ValueError('National slope exceeds frozen cutoff')
            normals=np.asarray(feature['mesh']['normals'],dtype=float)[np.asarray(feature['mesh']['indices'],dtype=np.int64).reshape(-1,3)[:,0]]
            crosses=np.cross(tri[:,1,:]-tri[:,0,:],tri[:,2,:]-tri[:,0,:])
            if not np.isfinite(normals).all() or np.any(normals[:,1]<=0) or np.any((crosses*normals).sum(axis=1)>=0):raise ValueError('National normal/collision winding mismatch')
            bounds=descriptor['source_bounds_xz'];clipping=box(*bounds)
            samples=set()
            for a,b in zip(points,points[1:]):
                segment=LineString([(a[0],a[2]),(b[0],b[2])]).intersection(clipping)
                if segment.is_empty:continue
                if segment.geom_type=='LineString':
                    length=segment.length;steps=max(1,math.ceil(length/25))
                    for step in range(steps+1):
                        p=segment.interpolate(length*step/steps);samples.add((p.x,p.y))
                elif segment.geom_type=='Point':samples.add((segment.x,segment.y))
            for x,z in samples:
                if not heights(table,x,z):raise ValueError(f'National emitted physical centreline gap {feature["id"]} {data["spatial_tile_key"]} {x},{z}')
            counts['physical_centerline_samples']+=len(samples);counts['fragments']+=1;counts['triangles']+=len(tri);counts['vertices']+=len(feature['mesh']['vertices_local_xyz']);total_vertices+=len(feature['mesh']['vertices_local_xyz']);seen.add(feature['id'])
            if feature['mesh'].get('codec_anchor_policy'):codec+=1
        if total_vertices!=descriptor['vertices'] or total_vertices>180000 or descriptor['bytes']>33554432:raise ValueError('National runtime part budget/catalog count mismatch')
        max_part=max(max_part,total_vertices);frozen.budget()
        if number%25==0:print(json.dumps({'stage':'national_source_audit','parts':number+1,'total':len(descriptors),'unique_ways':len(seen)}),flush=True)
    eligible=index.execute('select count(*) from ways').fetchone()[0]
    if len(seen)!=eligible or eligible!=147184:raise ValueError('National source footprint conservation incomplete')
    for descriptor in base['graph_chunks']:
        if digest(args.country/descriptor['file'])!=descriptor['sha256']:raise ValueError('Copied frozen graph catalog mismatch')
    result={'status':'PASS_ALL_ELIGIBLE_COUNTRY_SOURCE_MESH_AUDIT','country_identity_sha256':args.country_identity,'source_identity_sha256':args.source_identity,'eligible_source_ways':eligible,'represented_unique_source_ways':len(seen),'counts':dict(counts),'physical_parts':len(descriptors),'maximum_surface_slope':maximum,'maximum_part_vertices':max_part,'adaptive_anchor_fragments':codec,'graph_catalogs_byteidentical':len(base['graph_chunks']),'wall_seconds':time.monotonic()-started,'native_or_scene_acceptance':False}
    put(args.output/'source-mesh-audit.json',result);return result

def build_incidence(args,index,source_db):
    path=args.output/'seam-index.sqlite'
    db=sqlite3.connect(path);db.executescript('pragma cache_size=-32768;pragma temp_store=FILE;pragma mmap_size=0;create table incidence(g integer,way text,i integer,x real,z real,width real);create index incidence_group on incidence(g);create table groups(g integer primary key,tx integer,tz integer);')
    parent={}
    def find(v):
        while parent.get(v,v)!=v:parent[v]=parent.get(parent[v],parent[v]);v=parent[v]
        return v
    for a,b in source_db.execute('select a,b from edges where transition=1'):
        a=find(a);b=find(b)
        if a!=b:parent[b]=a
    for raw, in index.execute('select data from ways'):
        way=json.loads(raw)
        for i,(v,p) in enumerate(zip(way['source_vertex_ids'],way['source_points_xyz'])):
            db.execute('insert into incidence values(?,?,?,?,?,?)',(find(v),way['id'],i,p[0],p[2],way['policy']['width']['metres']))
    db.commit()
    for group,x,z in db.execute('select g,min(x),min(z) from incidence group by g having count(distinct way)>1'):
        db.execute('insert into groups values(?,?,?)',(group,math.floor(x/1000),math.floor(z/1000)))
    db.commit();return db

def audit_seams(args,manifest,index,source_db):
    started=time.monotonic();db=build_incidence(args,index,source_db);by_spatial={}
    for descriptor in manifest['physical_tiles']:by_spatial.setdefault(descriptor['spatial_tile_key'],[]).append(descriptor)
    total_groups=db.execute('select count(*) from groups').fetchone()[0];counts=Counter();maximum=0.;outliers=[]
    cells=db.execute('select distinct tx,tz from groups order by tx,tz').fetchall()
    for tx,tz in cells:
        group_rows=[];needed=set()
        for group, in db.execute('select g from groups where tx=? and tz=?',(tx,tz)):
            associations=db.execute('select way,i,width from incidence where g=?',(group,)).fetchall();group_rows.append((group,associations));needed.update(a[0] for a in associations)
        ways={identifier:json.loads(index.execute('select data from ways where id=?',(identifier,)).fetchone()[0]) for identifier in needed}
        pieces={identifier:[] for identifier in needed}
        for dx in [-1,0,1]:
            for dz in [-1,0,1]:
                for descriptor in by_spatial.get(f'{tx+dx}_{tz+dz}',[]):
                    data=read(args.country,descriptor)
                    for feature in data['features']:
                        if feature['id'] in needed:pieces[feature['id']].append(triangle_table(feature))
        tables={}
        for identifier,items in pieces.items():
            if items:tables[identifier]=tuple(np.concatenate([item[i] for item in items]) for i in range(4))
        for group,associations in group_rows:
            incident={row[0] for row in associations};max_half=max(row[2]*.5 for row in associations);counts['junction_groups']+=1
            for identifier,node_index,_ in associations:
                points=ways[identifier]['source_points_xyz']
                for step in [-1,1]:
                    j=node_index;distance=0.
                    while 0<=j+step<len(points) and distance<max_half:
                        a=points[j];b=points[j+step];length=math.hypot(b[0]-a[0],b[2]-a[2])
                        if length<1e-9:j+=step;continue
                        extent=min(length,max_half-distance);steps=max(1,math.ceil(extent/.5))
                        for sample in range(steps+1):
                            along=extent*sample/steps;x=a[0]+(b[0]-a[0])*along/length;z=a[2]+(b[2]-a[2])*along/length
                            own=heights(tables[identifier],x,z) if identifier in tables else []
                            if not own:counts['missing_source_surface_samples']+=1;continue
                            counts['samples']+=1
                            for other in incident:
                                if other==identifier or other not in tables:continue
                                values=heights(tables[other],x,z)
                                if not values:continue
                                counts['overlap_comparisons']+=1;delta=max(abs(a-b) for a in own for b in values);maximum=max(maximum,delta)
                                if delta>.005:
                                    counts['outlier_comparisons_over5mm']+=1
                                    if len(outliers)<100:outliers.append({'group':group,'from':identifier,'other':other,'xz':[x,z],'height_delta_m':delta})
                        distance+=length;j+=step
        frozen.budget()
        print(json.dumps({'stage':'national_seam_audit','cell':f'{tx}_{tz}','groups_complete':counts['junction_groups'],'groups_total':total_groups,'max_mismatch_m':maximum}),flush=True)
    status='PASS_STREAMED_COUNTRY_NEAR_JUNCTION_SEAMS' if not counts['outlier_comparisons_over5mm'] and not counts['missing_source_surface_samples'] else 'REVIEW_REQUIRED_COUNTRY_SEAM_OUTLIERS'
    result={'status':status,'country_identity_sha256':args.country_identity,'counts':dict(counts),'maximum_height_mismatch_m':maximum,'outlier_examples':outliers,'wall_seconds':time.monotonic()-started,'one3x3_neighborhood_in_memory':True,'scope':'Source-connected emitted centreline overlap within largest incident halfwidth; not all-area/fullcurve/native/car/terrain/current-survey acceptance'}
    put(args.output/'seam-audit.json',result);db.close();return result

def worker(args):
    manifest,base,source_db,index=inputs(args);results={}
    if args.phase in ('source','all'):results['source']=audit_source(args,manifest,base,source_db,index)
    if args.phase in ('seams','all'):results['seams']=audit_seams(args,manifest,index,source_db)
    source_db.close();index.close();return results

def supervise(args):
    if args.output.exists():raise ValueError('Fresh independent country audit output required')
    args.output.mkdir(parents=True);run=uuid.uuid4().hex;log=args.output/'worker.log';started=time.monotonic();peak=0;reason=None
    with log.open('xb') as stream:
        proc=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),*sys.argv[1:],'--worker'],stdout=stream,stderr=subprocess.STDOUT)
        try:
            while proc.poll() is None:
                text=subprocess.run(['/bin/ps','-o','rss=','-p',str(proc.pid)],capture_output=True,text=True).stdout.strip()
                if text:peak=max(peak,int(text)*1024)
                if peak>MAX_RSS:reason='Owned audit exceeded2GiB RSS';break
                if time.monotonic()-started>7200:reason='Owned audit exceeded7200s wall';break
                time.sleep(1)
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:proc.wait(timeout=30)
                except subprocess.TimeoutExpired:proc.kill();proc.wait()
    receipt={'status':'AUDIT_WORKER_EXITED' if proc.returncode==0 and reason is None else 'AUDIT_INCOMPLETE','worker_exit':proc.returncode,'reason':reason,'sampled_peak_rss_bytes':peak,'wall_seconds':time.monotonic()-started,'limits':{'rss_bytes':MAX_RSS,'cpu_seconds':3600,'wall_seconds':7200}}
    put(args.output/'supervisor.json',receipt);return receipt

def main():
    p=argparse.ArgumentParser();p.add_argument('--country',type=Path,required=True);p.add_argument('--country-identity',required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--source-identity',required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--phase',choices=['source','seams','all'],default='all');p.add_argument('--worker',action='store_true');args=p.parse_args()
    resource.setrlimit(resource.RLIMIT_CPU,(3600,3630))
    try:
        result=worker(args) if args.worker else supervise(args);print(json.dumps(result),flush=True)
        if args.worker:
            if any(not row.get('status','').startswith('PASS_') for row in result.values()):raise SystemExit(1)
        elif result.get('worker_exit')!=0:raise SystemExit(1)
    except Exception as error:print(json.dumps({'status':'AUDIT_FAILED_NO_NATIONAL_ADOPTION','error':str(error)}),flush=True);raise SystemExit(1)

if __name__=='__main__':main()
