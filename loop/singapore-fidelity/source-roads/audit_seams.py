#!/usr/bin/env python3
"""Actual emitted junction-surface sampling, never a native driving claim."""
from collections import defaultdict
import argparse,json,math,sqlite3,time
from pathlib import Path
import numpy as np

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--artifact',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    started=time.monotonic();m=json.loads((args.artifact/'manifest.json').read_bytes());ways={};pieces=defaultdict(list)
    for descriptor in m['physical_tiles']:
        tile=json.loads((args.artifact/descriptor['file']).read_bytes())
        for feature in tile['features']:
            identifier=feature['id'];ways[identifier]={'points':feature['source_points_xyz'],'vertices':feature['source_vertex_ids'],'width':feature['policy']['width']['metres']}
            mesh=feature['mesh'];v=np.array(mesh['vertices_local_xyz'],dtype=float)+np.array(feature['anchor_source_xyz']);tri=v[np.array(mesh['indices']).reshape(-1,3)]
            pieces[identifier].append(tri)
    tables={}
    for identifier,arrays in pieces.items():
        tri=np.concatenate(arrays);a=tri[:,0,:];b=tri[:,1,:];c=tri[:,2,:]
        den=(b[:,0]-a[:,0])*(c[:,2]-a[:,2])-(b[:,2]-a[:,2])*(c[:,0]-a[:,0]);assert np.all(den>0)
        gx=((b[:,1]-a[:,1])*(c[:,2]-a[:,2])-(c[:,1]-a[:,1])*(b[:,2]-a[:,2]))/den
        gz=((b[:,0]-a[:,0])*(c[:,1]-a[:,1])-(c[:,0]-a[:,0])*(b[:,1]-a[:,1]))/den
        tables[identifier]=(tri,gx,gz,a[:,1]-gx*a[:,0]-gz*a[:,2],tri[:,:,0].min(axis=1),tri[:,:,0].max(axis=1),tri[:,:,2].min(axis=1),tri[:,:,2].max(axis=1))
    def heights(identifier,x,z):
        tri,gx,gz,intercept,xmin,xmax,zmin,zmax=tables[identifier]
        mask=(x>=xmin-1e-6)&(x<=xmax+1e-6)&(z>=zmin-1e-6)&(z<=zmax+1e-6)
        ids=np.flatnonzero(mask)
        if not len(ids):return []
        selected=tri[ids]
        for i,j in [(0,1),(1,2),(2,0)]:
            cross=(selected[:,j,0]-selected[:,i,0])*(z-selected[:,i,2])-(selected[:,j,2]-selected[:,i,2])*(x-selected[:,i,0])
            mask=cross>=-1e-6;ids=ids[mask];selected=selected[mask]
            if not len(ids):return []
        return (gx[ids]*x+gz[ids]*z+intercept[ids]).tolist()
    db=sqlite3.connect('file:'+str(args.artifact/'work.sqlite')+'?mode=ro',uri=True);parent={}
    def find(v):
        while parent.get(v,v)!=v:parent[v]=parent.get(parent[v],parent[v]);v=parent[v]
        return v
    for a,b in db.execute('select a,b from edges where transition=1'):
        a=find(a);b=find(b)
        if a!=b:parent[b]=a
    groups=defaultdict(list)
    for identifier,item in ways.items():
        for i,v in enumerate(item['vertices']):groups[find(v)].append((identifier,i))
    sampled=0;overlaps=0;largest=0.;cases=[];centres=0
    for group,associations in groups.items():
        incident={identifier for identifier,_ in associations}
        if len(incident)<2:continue
        centres+=1
        max_half=max(ways[identifier]['width']*.5 for identifier in incident)
        center=ways[associations[0][0]]['points'][associations[0][1]]
        for identifier,index in associations:
            points=ways[identifier]['points']
            for step in [-1,1]:
                j=index;distance=0.
                while 0<=j+step<len(points) and distance<max_half:
                    a=points[j];b=points[j+step];length=math.hypot(b[0]-a[0],b[2]-a[2])
                    if length<1e-9:j+=step;continue
                    samples=max(1,math.ceil(min(length,max_half-distance)/.5))
                    for i in range(samples+1):
                        along=min(length,max_half-distance)*i/samples;x=a[0]+(b[0]-a[0])*along/length;z=a[2]+(b[2]-a[2])*along/length
                        own=heights(identifier,x,z)
                        if not own:continue
                        sampled+=1
                        for other in incident:
                            if other==identifier:continue
                            target=heights(other,x,z)
                            if not target:continue
                            overlaps+=1;delta=max(abs(a-b) for a in own for b in target);largest=max(largest,delta)
                            if delta>.005 and len(cases)<100:cases.append({'junction_group':group,'from':identifier,'other':other,'xz':[x,z],'height_delta_m':delta,'own_y':own,'other_y':target})
                    distance+=length;j+=step
    result={'status':'PASS_EMITTED_NEAR_JUNCTION_SEAMS' if not cases else 'REVIEW_REQUIRED_SEAM_OUTLIERS','junction_groups':centres,'samples':sampled,'overlap_comparisons':overlaps,'maximum_height_mismatch_m':largest,'outliers_over5mm':cases,'elapsed_seconds':time.monotonic()-started,'scope':'Source-connected emitted-way centreline overlap within largest incident halfwidth; not full-curve/all-area/native/vehicle/terrain/source-world acceptance'}
    if args.output.exists():raise SystemExit('Existing seam receipt refused')
    args.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='outliers_over5mm'}));db.close()

if __name__=='__main__':main()
