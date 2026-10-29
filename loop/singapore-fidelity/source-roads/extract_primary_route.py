#!/usr/bin/env python3
"""Pinned original-node scenic bridge route; not current-law/driving proof."""
import argparse,hashlib,json,sqlite3,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'game/tools/geography'))
from compile_roads import route,canonical

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--artifact',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    db=sqlite3.connect('file:'+str(args.artifact/'work.sqlite')+'?mode=ro',uri=True)
    anchors=[(237012179,'["surface",0,""]'),(2466494379,'["bridge",1,""]'),(5133988580,'["surface",0,""]')]
    ids=[]
    for original,grade in anchors:
        row=db.execute('select v from vertices where node=? and grade=?',(original,grade)).fetchone()
        if row is None:raise SystemExit('Required original source waypoint absent')
        ids.append(row[0])
    legs=[route(db,a,b,'car',physical_only=True) for a,b in zip(ids,ids[1:])]
    if not all(leg['found'] for leg in legs):raise SystemExit('No ordinary directed original-node primary route')
    vertices=legs[0]['vertices']+legs[1]['vertices'][1:];edges=legs[0]['edges']+legs[1]['edges']
    if not any(edge['way']=='way/763010995' for edge in edges):raise SystemExit('Actual Esplanade bridge not traversed')
    points=[dict(zip(['vertex_id','original_node_id','grade_key','x','y','z'],[v,*db.execute('select node,grade,x,y,z from vertices where v=?',(v,)).fetchone()])) for v in vertices]
    manifest=json.loads((args.artifact/'manifest.json').read_bytes());have=set()
    for descriptor in manifest['physical_tiles']:
        tile=json.loads((args.artifact/descriptor['file']).read_bytes());have.update(f['id'] for f in tile['features'])
    required={edge['way'] for edge in edges if edge['way']};missing=sorted(required-have)
    if missing:raise SystemExit('Route lacks physical candidate way coverage')
    output={'status':'DIRECTED_SOURCE_GRAPH_ROUTE_AND_PHYSICAL_CANDIDATE_COVERAGE_NOT_DRIVEN',
            'artifact_identity_sha256':hashlib.sha256((args.artifact/'identity.json').read_bytes()).hexdigest(),
            'original_waypoint_nodes':anchors,'distance_m':sum(leg['distance_m'] for leg in legs),
            'vertices':points,'edges':edges,'required_original_ways':len(required),'physical_candidate_ways_present':len(required),
            'centerline_bounds_xz':[min(p['x'] for p in points),min(p['z'] for p in points),max(p['x'] for p in points),max(p['z'] for p in points)],
            'actual_bridge_way':'way/763010995','native_driven_or_current_legal_turns_verified':False}
    if args.output.exists():raise SystemExit('Existing route receipt refused')
    args.output.write_bytes(canonical(output));db.close();print(json.dumps({k:v for k,v in output.items() if k not in ['vertices','edges']}))

if __name__=='__main__':main()
