#!/usr/bin/env python3
"""Small explicitly SYNTHETIC native-physics fixture, never Singapore evidence."""
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'game/tools/geography'))
from compile_roads import canonical,sha,ribbon,write_new,SCHEMA,GRAPH_SCHEMA,IDENTITY

def main():
    output=ROOT/'game/data/geography/source-roads/qa-fixture-v4'
    if output.exists(): raise SystemExit('Fresh fixture directory required')
    snapshot=ROOT/'game/data/geography/osm-2026-10-27/manifest.json'
    source_raw=snapshot.read_bytes();source=json.loads(source_raw)
    surface='["surface",0,""]';bridge='["bridge",1,""]'
    rows=[(1,1,surface,[-120,0,0]),(2,2,surface,[-60,0,0]),(3,3,surface,[0,6,0]),
          (4,3,bridge,[0,6,0]),(5,4,bridge,[25,6,0]),(6,5,bridge,[50,6,0]),
          (7,5,surface,[50,6,0]),(8,6,surface,[110,0,0]),(9,7,surface,[170,0,0]),
          (10,8,surface,[25,0,-50]),(11,9,surface,[25,0,0]),(12,10,surface,[25,0,50])]
    vertices=[{'vertex_id':v,'original_node_id':node,'grade_key':grade,'key':f'node/{node}|grade/{grade}','source_xyz':xyz,'egm96_preferred_m':0,'world_y_is_game_profile':True} for v,node,grade,xyz in rows]
    edges=[]
    for index,(a,b,way) in enumerate([(1,2,'approach-west'),(2,3,'approach-west'),(3,4,None),(4,5,'bridge'),(5,6,'bridge'),(6,7,None),(7,8,'approach-east'),(8,9,'approach-east'),(10,11,'lower-crossing'),(11,12,'lower-crossing')]):
        pa=rows[a-1][3];pb=rows[b-1][3]
        edges.append({'id':f'fixture/edge/{index}','a':a,'b':b,'length_m':((pa[0]-pb[0])**2+(pa[2]-pb[2])**2)**.5,'source_way':None if way is None else 'fixture/'+way,'grade_transition':way is None,'directions':{'car':3 if way is None or way=='lower-crossing' else 1,'bicycle':3,'foot':3}})
    graph={'schema':GRAPH_SCHEMA,'owner':'fixture','vertices':vertices,'edges':edges,'ways':[],'xy_connectivity_added':False,'synthetic_fixture_not_actual_OSM':True}
    graph_desc=write_new(output/'graph/fixture.json',canonical(graph));graph_desc.update(file='graph/fixture.json',owner='fixture')
    features=[]
    for label,points,width in [('approach-west',[[-120,0,0],[-60,0,0],[0,6,0]],3.2),('bridge',[[0,6,0],[25,6,0],[50,6,0]],12.8),('approach-east',[[50,6,0],[110,0,0],[170,0,0]],3.2),('lower-crossing',[[25,0,-50],[25,0,0],[25,0,50]],6.4),('ring',[[200,0,200],[240,0,200],[240,0,240],[200,0,240],[200,0,200]],4.0)]:
        radii=[1.6,0,6.4] if label=='approach-west' else [6.4,0,1.6] if label=='approach-east' else None
        features.append({'id':'fixture/'+label,'name':'SYNTHETIC QA '+label,'anchor_source_xyz':[0,0,0],'source_points_xyz':points,'policy':{'fixture_only':True},'mesh':ribbon(points,width,[0,0,0],hubs=radii)})
    physical={'schema':SCHEMA,'tile':'fixture','features':features,'physical_scope':'SYNTHETIC_NATIVE_QA_NOT_ACTUAL_SINGAPORE'}
    desc=write_new(output/'physical/fixture.json',canonical(physical));desc.update(file='physical/fixture.json',tile='fixture')
    manifest={'schema':SCHEMA,'snapshot_manifest_sha256':sha(source_raw),'georeference':source['georeference'],'graph_chunks':[graph_desc],'physical_tiles':[desc],'physical_scope':{'fixture':True,'actual_country_roads':False},'attribution':{'fixture':'Original isolated test geometry; not sourced street evidence'}}
    manifest_desc=write_new(output/'manifest.json',canonical(manifest))
    identity={'schema':IDENTITY,'manifest':manifest_desc,'snapshot_manifest_sha256':sha(source_raw),'synthetic_fixture':True}
    identity_raw=canonical(identity);write_new(output/'identity.json',identity_raw)
    write_new(output/'fixture-receipt.json',canonical({'identity_sha256':sha(identity_raw),'source_frame_only_snapshot_sha256':sha(source_raw),'actual_street_or_country_acceptance':False}))
    print(json.dumps({'fixture':str(output),'identity_sha256':sha(identity_raw)}))

if __name__=='__main__':main()
