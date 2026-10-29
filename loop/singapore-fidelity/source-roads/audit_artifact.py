#!/usr/bin/env python3
"""Independent source-catalog/graph identity and emitted winding audit.
Does not certify policy interpretation, current law, gameplay or native physics.
"""
import argparse,hashlib,json,math,struct,sys,time
from pathlib import Path

def digest(raw):return hashlib.sha256(raw).hexdigest()
def read(root,descriptor):
    raw=(root/descriptor['file']).read_bytes()
    assert len(raw)==descriptor['bytes'] and digest(raw)==descriptor['sha256']
    return json.loads(raw)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--artifact',type=Path,default=Path('/private/tmp/singapore-fidelity/source-roads/candidate-r2'));parser.add_argument('--output',type=Path,default=Path(__file__).parent/'COUNTRY_AUDIT_R2.json')
    parser.add_argument('--source',type=Path,default=Path('/private/tmp/singapore-fidelity/city-geometry/candidate-r2'),help='Complete pinned source-city artifact, including original catalogs; metadata-only archives are insufficient')
    args=parser.parse_args()
    source=args.source
    target=args.artifact
    source_identity=json.loads((source/'identity.json').read_bytes());sm=read(source,source_identity['manifest'])
    identity_raw=(target/'identity.json').read_bytes();identity=json.loads(identity_raw);manifest=read(target,identity['manifest'])
    if digest((source/'identity.json').read_bytes())!=manifest['city_identity_sha256']:
        raise ValueError('Audit source city does not match the artifact lineage')
    graphs={d['owner']:d for d in manifest['graph_chunks']};count=0;segments=0;max_axis_error=0.;max_node=0
    started=time.monotonic()
    for descriptor in sm['catalogs']:
        catalog=read(source,descriptor);graph=read(target,graphs[catalog['owner']])
        ways={w['id']:w for w in graph['ways']};nodes={int(v['vertex_id']):v for v in graph['vertices']};edges={e['id']:e for e in graph['edges']}
        source_ways=[f for f in catalog['features'] if f['kind']=='road']
        assert set(ways)=={f['id'] for f in source_ways}
        for feature in source_ways:
            way=ways[feature['id']];road=feature['road'];anchor=catalog['anchor_source_xyz']
            assert way['node_ids']==road['original_ordered_node_ids']
            assert way['tags']==road['full_source_tags'] and way['name']==feature['name']
            assert way['source_feature_sha256']==feature['source_feature_sha256'] and way['source_geometry_sha256']==feature['source_geometry_sha256']
            assert len(way['vertex_ids'])==len(way['node_ids'])
            for node_id,vid,point in zip(way['node_ids'],way['vertex_ids'],road['centerline_local_xz_double']):
                row=nodes[vid];assert row['original_node_id']==node_id
                max_node=max(max_node,node_id)
                error=max(abs(row['source_xyz'][0]-anchor[0]-point[0]),abs(row['source_xyz'][2]-anchor[2]-point[1]));max_axis_error=max(max_axis_error,error)
                assert error<=.000100000001
                assert row['key'].startswith('node/'+str(node_id)+'|grade/')
            for index,(a,b) in enumerate(zip(way['vertex_ids'],way['vertex_ids'][1:])):
                pa=nodes[a]['source_xyz'];pb=nodes[b]['source_xyz'];length=math.hypot(pb[0]-pa[0],pb[2]-pa[2])
                if length<.000001:continue
                edge=edges[way['id']+'@'+str(index)]
                assert edge['a']==a and edge['b']==b and abs(edge['length_m']-length)<1e-8
                assert edge['source_way']==way['id'] and not edge['grade_transition']
                segments+=1
            count+=1
        for edge in graph['edges']:
            if not edge['grade_transition']:continue
            a=nodes[edge['a']];b=nodes[edge['b']]
            assert a['original_node_id']==b['original_node_id'] and a['grade_key']!=b['grade_key']
            assert abs(a['source_xyz'][1]-b['source_xyz'][1])<1e-6
    triangles=0;holes=0
    for descriptor in manifest['physical_tiles']:
        tile=read(target,descriptor)
        for feature in tile['features']:
            mesh=feature['mesh'];vertices=mesh['vertices_local_xyz'];normals=mesh['normals'];indices=mesh['indices'];holes+=mesh['holes']
            assert len(vertices)==len(normals) and len(indices)%3==0
            for offset in range(0,len(indices),3):
                a,b,c=(vertices[i] for i in indices[offset:offset+3]);ab=[b[j]-a[j] for j in range(3)];ac=[c[j]-a[j] for j in range(3)]
                cross=[ab[1]*ac[2]-ab[2]*ac[1],ab[2]*ac[0]-ab[0]*ac[2],ab[0]*ac[1]-ab[1]*ac[0]]
                assert cross[1]<0 and sum(v*v for v in cross)>0
                n=normals[indices[offset]];assert n[1]>0 and sum(cross[i]*n[i] for i in range(3))<0
                triangles+=1
    assert count==257845 and len(graphs)==906
    result={'status':'PASS_SOURCE_IDENTITY_AND_EMITTED_WINDING_ONLY','artifact_identity_sha256':digest(identity_raw),'owners':len(graphs),'original_ways':count,'original_segments_audited':segments,'maximum_source_axis_delta_m':max_axis_error,'maximum_original_node_id':max_node,'node_ids_fit_current_JSON_double_exact_integer_range':max_node<2**53,'physical_tiles':len(manifest['physical_tiles']),'triangles_checked':triangles,'holes_retained':holes,'elapsed_seconds':time.monotonic()-started,'not_proved':['semantic policy correctness independent review','current legal directions/access/turn restrictions','native collision/driver/gameplay','source terrain/bridge/tunnel survey heights','root integration/full Singapore completion']}
    output=args.output
    if output.exists():raise SystemExit('Existing audit receipt refused')
    output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

if __name__=='__main__':main()
