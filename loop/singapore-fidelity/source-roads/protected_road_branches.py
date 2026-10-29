"""Exact source-way flat-branch evidence for protected multi-level portals.

Never selects the nearest height. A removed audit height must match a
different original portal's source-proven flat geometry and grade continuation,
while the current portal has its own positive matching physical surface.
"""
import json
import math

from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

import expand_national as batch
F = batch.frozen
HEIGHT_CODEC_TOLERANCE = .00025
XZ_CODEC_TOLERANCE = .0002
MIN_SEPARATE_LEVEL_GAP = 2.3  # Explicit inferred game-profile clearance policy.


def transition_groups(db):
    parents, grades = {}, {}
    def find(v):
        while parents.get(v,v)!=v:
            parents[v]=parents.get(parents[v],parents[v]);v=parents[v]
        return v
    for a,b,ga,gb in db.execute('select e.a,e.b,a.grade,b.grade from edges e join vertices a on a.v=e.a join vertices b on b.v=e.b where e.transition=1'):
        parents[find(a)]=find(b)
        grades.setdefault(a,set()).add(gb);grades.setdefault(b,set()).add(ga)
    return find,grades


def way_data(db,identifier):
    row=db.execute('select raw,policy,vertices from ways where id=?',(identifier,)).fetchone()
    if row is None:raise ValueError('Protected branch references missing original way')
    raw,policy,ids=json.loads(row[0]),json.loads(row[1]),json.loads(row[2])
    points=[list(db.execute('select x,y,z from vertices where v=?',(v,)).fetchone()) for v in ids]
    radii=[(db.execute('select radius from render_hubs where v=?',(v,)).fetchone() or [0.])[0] for v in ids]
    return raw,policy,ids,points,radii


def apron(point,width):
    return Polygon([(point[0]+width*.5*math.cos(i*math.tau/16),point[2]+width*.5*math.sin(i*math.tau/16)) for i in range(16)])


def discover(db,identifiers):
    _,grades=transition_groups(db);records=[]
    for identifier in sorted(identifiers):
        raw,policy,ids,points,radii=way_data(db,identifier)
        hubs=[i for i,r in enumerate(radii) if r>0]
        for position,i in enumerate(hubs):
            for j in hubs[position+1:]:
                signatures=[sorted(grades.get(ids[k],())) for k in (i,j)]
                if signatures[0]==signatures[1]:continue
                area=apron(points[i],policy['width']['metres']).intersection(apron(points[j],policy['width']['metres'])).area
                if area<=1e-8:continue
                records.append({'source_way':identifier,'source_indices':[i,j],'vertex_ids':[ids[i],ids[j]],
                                'original_node_ids':[raw['node_ids'][i],raw['node_ids'][j]],
                                'continuation_grades_by_source_index':{str(i):signatures[0],str(j):signatures[1]},
                                'source_grade_key':policy['grade']['key'],'overlap_area_m2':area})
    return records


def zero_height_groups(db):
    parents={}
    def find(v):
        while parents.get(v,v)!=v:
            parents[v]=parents.get(parents[v],parents[v]);v=parents[v]
        return v
    for a,b in db.execute('select a,b from height_constraints where allowance=0 union all select a,b from edges where allowance=0'):
        parents[find(a)]=find(b)
    return find


def _flat_shape(ids,points,radii,width,portal,find_zero):
    stations=[0.]
    for a,b in zip(points,points[1:]):stations.append(stations[-1]+math.hypot(b[0]-a[0],b[2]-a[2]))
    hubs=[i for i,r in enumerate(radii) if r>0]
    pieces=[apron(points[portal],width)]
    for span in F._section_layout(points,width,radii)['spans']:
        i=span['index'];sx=points[i+1][0]-points[i][0];sz=points[i+1][2]-points[i][2];length2=sx*sx+sz*sz
        if length2<1e-16:continue
        for a,oa,ta,b,ob,tb in span['cells']:
            governed={i if t==0 else i+1 for t in (ta,tb)}
            if any(find_zero(ids[k])!=find_zero(ids[portal]) for k in governed):continue
            if any(abs(points[k][1]-points[portal][1])>1e-7 for k in governed):
                raise ValueError('Supposed zero-height source branch is not equal')
            interval=[]
            for x,z in (a,b):
                t=max(0.,min(1.,((x-points[i][0])*sx+(z-points[i][2])*sz)/length2))
                interval.append(stations[i]+math.sqrt(length2)*t)
            local=True
            for station in interval:
                distances=[(abs(station-stations[h]),h) for h in hubs];minimum=min(d for d,_ in distances)
                if {h for d,h in distances if abs(d-minimum)<1e-7}!={portal}:local=False
            if not local:continue
            al,ar=(a[0]+oa[0],a[1]+oa[1]),(a[0]-oa[0],a[1]-oa[1])
            bl,br=(b[0]+ob[0],b[1]+ob[1]),(b[0]-ob[0],b[1]-ob[1])
            pieces.extend([Polygon([al,ar,bl]),Polygon([ar,br,bl])])
    return unary_union(pieces)


def build_rules(db,records):
    _,grades=transition_groups(db);find_zero=zero_height_groups(db);rules={}
    for record in records:
        identifier=record['source_way'];raw,policy,ids,points,radii=way_data(db,identifier)
        i,j=record['source_indices']
        if not 0<=i<len(ids) or not 0<=j<len(ids) or i==j:raise ValueError('Invalid protected source-portal indices')
        if [ids[i],ids[j]]!=record['vertex_ids']:raise ValueError('Protected portal source identity changed')
        if [raw['node_ids'][i],raw['node_ids'][j]]!=record['original_node_ids']:raise ValueError('Protected original node IDs changed')
        signatures=[sorted(grades.get(ids[k],())) for k in (i,j)]
        if signatures[0]==signatures[1]:raise ValueError('No distinct source continuation-grade evidence')
        expected={str(i):signatures[0],str(j):signatures[1]}
        if record['continuation_grades_by_source_index']!=expected:raise ValueError('Protected continuation evidence changed')
        gap=abs(points[i][1]-points[j][1])
        if gap<MIN_SEPARATE_LEVEL_GAP:continue  # Protection is not permission to waive a small unexplained step.
        shapes={k:_flat_shape(ids,points,radii,policy['width']['metres'],k,find_zero) for k in (i,j)}
        for near,far in ((i,j),(j,i)):
            rules.setdefault((identifier,near),[]).append({'source_way':identifier,'near_index':near,'far_index':far,
                    'near_vertex_id':ids[near],'far_vertex_id':ids[far],'near_y':points[near][1],'far_y':points[far][1],
                    'near_shape':shapes[near],'far_shape':shapes[far],'level_gap_m':gap,
                    'continuation_grades':expected,'source_grade_key':policy['grade']['key']})
    return rules


def partition(heights,identifier,node_index,x,z,rules):
    remaining=list(heights);proof=[];point=Point(x,z)
    for rule in rules.get((identifier,node_index),()):
        if rule['near_shape'].distance(point)>XZ_CODEC_TOLERANCE:continue
        if not any(abs(h-rule['near_y'])<=HEIGHT_CODEC_TOLERANCE for h in remaining):continue
        if rule['far_shape'].distance(point)>XZ_CODEC_TOLERANCE:continue
        explained=[h for h in remaining if abs(h-rule['far_y'])<=HEIGHT_CODEC_TOLERANCE]
        if not explained:continue
        remaining=[h for h in remaining if abs(h-rule['far_y'])>HEIGHT_CODEC_TOLERANCE]
        proof.append({'source_way':identifier,'near_index':node_index,'far_index':rule['far_index'],
                      'near_vertex_id':rule['near_vertex_id'],'far_vertex_id':rule['far_vertex_id'],
                      'near_y':rule['near_y'],'far_y':rule['far_y'],'removed_actual_heights':explained,
                      'continuation_grades':rule['continuation_grades'],'level_gap_m':rule['level_gap_m'],
                      'xz':[x,z],'evidence':'OTHER_ORIGINAL_PORTAL_FLAT_FOOTPRINT_PLUS_DISTINCT_CONTINUATION_GRADES_AND_POSITIVE_LOCAL_SURFACE'})
    if heights and not remaining:raise ValueError('Protected-branch filter removed every physical support surface')
    return remaining,proof
