"""Versioned physical-class grade and source-supported stair/ramp geometry.

Original edges/ways/XY/access stay present. Only inferred allowances and
geometry records change; Root's native loader is outside this module.
"""
from collections import defaultdict,deque
import json
import math

import numpy as np
import compile_roads_semantic_v2 as K
import source_physical_policy_v4 as P


def _landing_radius(points,index):
    spans=[]
    if index:spans.append(math.dist(points[index-1],points[index]))
    if index+1<len(points):spans.append(math.dist(points[index],points[index+1]))
    positive=[length for length in spans if length>1e-8]
    return min(.12,min(positive)*.1) if positive else 0.


def rebuild(db):
    total=db.execute('select max(v) from vertices').fetchone()[0]
    xy=np.empty((total+1,2),dtype=float)
    for v,x,z in db.execute('select v,x,z from vertices'):xy[v]=[x,z]
    hubs=dict(db.execute('select v,radius from render_hubs'))
    db.executescript('''
      create table v4_way_geometry(way text primary key,physical_kind text,grade real,record text);
      create table v4_geometry_constraints(way text,a integer,b integer,ia integer,ib integer,kind text,primary key(way,a,b));
      create table v4_ramp_monotone(way text,from_v integer,to_v integer,source_stair text,primary key(way,from_v,to_v,source_stair));
    ''')
    overrides={};stairs=[];counts=defaultdict(int)
    for key,raw,policy,vertices in db.execute('select id,raw,policy,vertices from ways order by id'):
        raw,policy,ids=json.loads(raw),json.loads(policy),json.loads(vertices)
        role=P.physical_role(raw['tags'],policy);kind=role['physical_kind'];points=[xy[v].tolist() for v in ids]
        record={'policy':P.POLICY,'physical_role':role,'hub_overrides':{},'geometry_recipe':'ordinary_source_junctions','source_reasons':[]}
        if kind=='foot_steps':
            record['hub_overrides']={str(i):_landing_radius(points,i) for i,v in enumerate(ids) if hubs.get(v,0)>0}
            record['geometry_recipe']='stair_landings_no_round_apron_with_connected_neighbor_apertures'
            run=sum(math.dist(a,b) for a,b in zip(points,points[1:]))
            rule=P.stair_constraints(raw['tags'],raw['node_ids'],run)
            stairs.append({'way':key,'ids':ids,'rule':rule})
        elif kind=='vertical_transport':record['geometry_recipe']='dedicated_vertical_transport_not_horizontal_ground'
        db.execute('insert into v4_way_geometry values(?,?,?,?)',(key,kind,role['maximum_game_grade'],K.canonical(record).decode()))
        counts[kind]+=1
    db.commit()

    def build_way(key):
        raw,policy,vertices=db.execute('select raw,policy,vertices from ways where id=?',(key,)).fetchone()
        raw,policy,ids=json.loads(raw),json.loads(policy),json.loads(vertices)
        kind,grade,text=db.execute('select physical_kind,grade,record from v4_way_geometry where way=?',(key,)).fetchone();record=json.loads(text)
        db.execute('delete from v4_geometry_constraints where way=?',(key,))
        if kind=='vertical_transport':
            # Source perimeter/transition records remain in `edges`; the new
            # metric working graph must explicitly exclude this non-floor role.
            return
        grade=grade if grade is not None else (.12 if policy['modes']['car']['bits'] else .7 if raw['tags'].get('highway')=='steps' else .25)
        radii=[record['hub_overrides'].get(str(i),hubs.get(v,0.)) for i,v in enumerate(ids)]
        layout=K._section_layout([xy[v].tolist() for v in ids],policy['width']['metres'],radii)
        for a,b in layout['equalities']:
            if ids[a]!=ids[b]:db.execute('insert or ignore into v4_geometry_constraints values(?,?,?,?,?,?)',(key,ids[a],ids[b],a,b,'flat_geometry'))
        for span in layout['spans']:
            i=span['index'];allowance=grade*span['allowance_distance'];edge=key+'@'+str(i)
            before=db.execute('select length,car from edges where id=?',(edge,)).fetchone()
            if before is None:raise ValueError('V4 cannot invent a missing original source segment')
            if kind=='vehicle_road' and allowance>.12*before[0]+1e-6:raise ValueError('Vehicle grade widened')
            db.execute('update edges set allowance=? where id=?',(allowance,edge))
            if allowance==0 and ids[i]!=ids[i+1]:db.execute('insert or ignore into v4_geometry_constraints values(?,?,?,?,?,?)',(key,ids[i],ids[i+1],i,i+1,'zero_geometry_allowance'))

    for index,(key,) in enumerate(db.execute('select id from ways order by id').fetchall()):
        build_way(key)
        if index and index%50000==0:db.commit();K.budget()
    db.commit()
    history=[]
    for iteration in range(4):
        parent={};adj=defaultdict(list)
        def find(v):
            while parent.get(v,v)!=v:parent[v]=parent.get(parent[v],parent[v]);v=parent[v]
            return v
        def connect(a,b,evidence):
            if a==b:return
            aa,bb=find(a),find(b)
            if aa!=bb:parent[max(aa,bb)]=min(aa,bb)
            adj[a].append((b,evidence));adj[b].append((a,evidence))
        for a,b,way in db.execute("select e.a,e.b,e.way from edges e left join v4_way_geometry g on g.way=e.way where (e.transition=1 or e.length=0) and (g.physical_kind is null or g.physical_kind!='vertical_transport')"):
            connect(a,b,{'kind':'original_zero_connection','way':way})
        for way,a,b,ia,ib,kind in db.execute('select * from v4_geometry_constraints'):
            connect(a,b,{'kind':kind,'way':way,'indices':[ia,ib]})
        changed=set();unresolved=[];repaired=0
        for stair in stairs:
            rule=stair['rule'];ids=stair['ids']
            if rule['status']!='SOURCE_SIGN_WITH_EXPLICIT_GAME_RISE_INTERVAL' or find(ids[0])!=find(ids[-1]):continue
            previous={ids[0]:None};queue=deque([ids[0]])
            while queue and ids[-1] not in previous:
                v=queue.popleft()
                for other,e in adj[v]:
                    if other not in previous:previous[other]=(v,e);queue.append(other)
            if ids[-1] not in previous:raise ValueError('Zero-component path construction failed')
            path=[];node=ids[-1]
            while node!=ids[0]:
                before,e=previous[node];path.append((before,node,e));node=before
            path.reverse();eligible=[]
            for a,b,e in path:
                if e['kind']=='original_zero_connection':continue
                role=db.execute('select physical_kind,record from v4_way_geometry where way=?',(e['way'],)).fetchone()
                if role[0]!='foot_surface':continue  # Vehicle junctions remain intact.
                record=json.loads(role[1]);way_ids=json.loads(db.execute('select vertices from ways where id=?',(e['way'],)).fetchone()[0]);points=[xy[v].tolist() for v in way_ids]
                lo,hi=sorted(e['indices'])
                any_change=False
                for i in range(lo,hi+1):
                    target=_landing_radius(points,i)
                    current=record['hub_overrides'].get(str(i),hubs.get(way_ids[i],0.))
                    if target<current-1e-9:record['hub_overrides'][str(i)]=target;any_change=True
                if not any_change:continue
                record['geometry_recipe']='source_connected_architectural_ramp_no_round_apron'
                record['source_reasons'].append({'source_stair':stair['way'],'source_span_indices':[lo,hi],'reason':'Real signed source stair proves these pedestrian alternatives cannot be one flat floor'})
                db.execute('update v4_way_geometry set record=? where way=?',(K.canonical(record).decode(),e['way']))
                start=way_ids.index(a);end=way_ids.index(b);step=1 if end>start else -1
                for i in range(start,end,step):
                    av,bv=way_ids[i],way_ids[i+step]
                    if rule['reliable_original_order_sign']<0:av,bv=bv,av
                    db.execute('insert or ignore into v4_ramp_monotone values(?,?,?,?)',(e['way'],av,bv,stair['way']))
                changed.add(e['way']);eligible.append(e['way'])
            if eligible:repaired+=1
            else:unresolved.append({'source_stair':stair['way'],'rule':rule,'zero_path':[{'a':a,'b':b,**e} for a,b,e in path]})
        history.append({'iteration':iteration,'changed_pedestrian_ways':sorted(changed),'signed_stair_paths_released':repaired,'unresolved':unresolved})
        db.commit()
        if not changed:break
        for key in sorted(changed):build_way(key)
        db.commit()
    db.execute('delete from height_constraints')
    db.execute('insert or ignore into height_constraints(a,b,allowance) select min(a,b),max(a,b),0 from v4_geometry_constraints')
    db.commit()
    final_unresolved=history[-1]['unresolved']
    result={'policy':P.POLICY,'physical_role_counts':dict(counts),'geometry_relaxation_history':history,
            'unresolved_reliable_flat_stairways':final_unresolved,'vehicle_junction_equality_recipes_changed':False,
            'original_graph_nodes_XZ_modes_or_names_changed':False,'vertical_source_records_retained_metric_model_must_exclude_horizontal_grade':True,
            'requires_matching_physical_aperture_and_landing_generator':True}
    return result
