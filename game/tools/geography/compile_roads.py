#!/usr/bin/env python3
"""Original-node country road graph and bounded physical ribbon work batches.

No XY snapping, legal/current-traffic certification, actor mutation or scene
authority. Source tags and DEM remain distinct from explicit game policies.
"""
import argparse
import array
from collections import Counter, defaultdict
from copy import deepcopy
import hashlib
import heapq
import json
import math
import os
from pathlib import Path
import re
import resource
import sqlite3
import struct
import subprocess
import sys
import time

import numpy as np
from shapely import constrained_delaunay_triangles
from shapely.geometry import LineString, Polygon, box
from shapely.ops import unary_union

from compile_city import TerrainGrid, FRAME

SCHEMA = 'singapore_source_roads_v1'
GRAPH_SCHEMA = 'singapore_source_road_graph_chunk_v1'
IDENTITY = 'singapore_source_roads_identity_v1'
MAX_CATALOG = 32 * 1024 * 1024
MAX_VERTICES = 3000000
MAX_SEGMENTS = 4500000
MAX_RSS = 2 * 1024**3
XY_TOLERANCE = .000100000001
MODES = ('car', 'bicycle', 'foot')
CAR = {'motorway','motorway_link','trunk','trunk_link','primary','primary_link',
       'secondary','secondary_link','tertiary','tertiary_link','unclassified',
       'residential','living_street','service'}
PRIMARY = {'motorway','motorway_link','trunk','trunk_link','primary','primary_link',
           'secondary','secondary_link','tertiary','tertiary_link'}
FOOT = {'footway','pedestrian','path','steps','bridleway','cycleway','track'}
ALLOW = {'yes','designated','permissive','official'}
DENY = {'no','use_sidepath'}
RESTRICT = {'private','destination','delivery','customers','agricultural','forestry','permit','emergency'}

class RoadError(ValueError): pass

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False,
                      allow_nan=False).encode()

def sha(raw): return hashlib.sha256(raw).hexdigest()

def number(value):
    return isinstance(value, (int,float)) and not isinstance(value,bool) and math.isfinite(value)

def budget():
    peak=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    if sys.platform != 'darwin': peak *= 1024
    if peak > MAX_RSS: raise RoadError('Two-GiB RSS budget exceeded')
    return peak

def write_new(path, raw):
    path=Path(path)
    if path.is_symlink() or path.exists(): raise RoadError(f'Existing output refused: {path}')
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream: stream.write(raw)
    return {'file':path.name,'bytes':len(raw),'sha256':sha(raw)}

def read_bound(root, descriptor):
    name=descriptor.get('file')
    if not isinstance(name,str) or Path(name).is_absolute() or '..' in Path(name).parts:
        raise RoadError('Unsafe source descriptor path')
    path=Path(root)/name
    if path.is_symlink() or descriptor['bytes'] > MAX_CATALOG: raise RoadError('Source symlink/catalog size refused')
    raw=path.read_bytes()
    if len(raw)!=descriptor['bytes'] or sha(raw)!=descriptor['sha256']: raise RoadError('Source descriptor integrity failure')
    return json.loads(raw)

def metric_tag(value):
    if not isinstance(value,str): return None
    match=re.fullmatch(r'\s*(\d+(?:\.\d+)?)\s*(m|metres|meters)?\s*', value)
    if match: return float(match[1])
    match=re.fullmatch(r'''\s*(\d+(?:\.\d+)?)\s*'\s*(\d+(?:\.\d+)?)?\s*"?\s*''', value)
    return float(match[1])*.3048+float(match[2] or 0)*.0254 if match else None

def width_policy(tags):
    for key in ('width:carriageway','width'):
        width=metric_tag(tags.get(key))
        if width is not None and .5<=width<=80:
            return {'metres':width,'status':'source_tag_value_not_survey_certification','tag':key,'raw':tags[key]}
    lanes=tags.get('lanes','')
    if re.fullmatch(r'[1-9]\d?',lanes) and 1<=int(lanes)<=16:
        return {'metres':int(lanes)*3.2,'status':'GAME_source_lane_count_times_3.2m_not_measured_width','lanes':int(lanes),'lane_width_game_m':3.2}
    highway=tags.get('highway','')
    lanes=1 if tags.get('oneway') in ('yes','1','true','-1') or highway=='service' else 2
    width=2.0 if highway in FOOT or highway=='corridor' else lanes*3.2
    return {'metres':width,'status':'GAME_highway_class_width_fallback_NOT_SURVEYED','highway':highway,'lane_width_game_m':3.2,'footpath_game_m':2.0,'unusable_width_tag':tags.get('width')}

def mode_access(tags, mode, direction=None):
    highway=tags.get('highway','')
    if highway in ('construction','proposed') or tags.get('construction') or tags.get('proposed'):
        return {'state':'blocked','reason':'construction_or_proposed_not_ordinary_open_road'}
    keys={'car':('motorcar','motor_vehicle','vehicle','access'),
          'bicycle':('bicycle','vehicle','access'),'foot':('foot','access')}[mode]
    for base_key in keys:
        candidates=(base_key+':'+direction,base_key) if direction else (base_key,)
        key=next((k for k in candidates if k in tags or k+':conditional' in tags),None)
        if key is None: continue
        if key+':conditional' in tags:
            return {'state':'conditional_unresolved','key':key+':conditional','value':tags[key+':conditional']}
        value=tags[key]
        if value in ALLOW:
            if mode=='car' and highway in ('steps','corridor','elevator'):
                return {'state':'blocked','reason':'car_geometry_incompatible_even_with_access_tag','key':key,'value':value}
            return {'state':'allowed','reason':'explicit_mode_access','key':key,'value':value}
        if value in DENY: return {'state':'blocked','key':key,'value':value}
        if value in RESTRICT: return {'state':'restricted','key':key,'value':value}
        return {'state':'unresolved','key':key,'value':value}
    if mode=='car': allowed=highway in CAR
    elif mode=='bicycle': allowed=highway not in ('motorway','motorway_link','steps','elevator','construction','proposed') and (highway in CAR or highway in FOOT)
    else: allowed=highway not in ('motorway','motorway_link','trunk','trunk_link') and (highway in CAR or highway in FOOT or highway=='corridor')
    return {'state':'allowed' if allowed else 'unresolved','reason':'GAME_highway_mode_default_NOT_current_legal_order','highway':highway}

def direction_policy(tags, mode):
    keys={'car':('oneway:motorcar','oneway:motor_vehicle','oneway:vehicle','oneway'),
          'bicycle':('oneway:bicycle','oneway:vehicle','oneway'),'foot':('oneway:foot',)}[mode]
    for key in keys:
        if key+':conditional' in tags: return {'bits':0,'status':'conditional_direction_unresolved','tag':key+':conditional'}
        if key not in tags: continue
        raw=tags[key]
        bits=1 if raw in ('yes','1','true') else 2 if raw=='-1' else 3 if raw in ('no','0','false') else 0
        return {'bits':bits,'status':'explicit_source_direction' if bits else 'direction_unresolved','tag':key,'raw':raw}
    if mode=='foot' and tags.get('highway') in FOOT and tags.get('oneway') not in (None,'no','0','false'):
        return {'bits':0,'status':'general_oneway_on_pedestrian_path_is_ambiguous_use_oneway_foot'}
    if mode!='foot' and (tags.get('junction')=='roundabout' or tags.get('highway')=='motorway'):
        return {'bits':1,'status':'OSM_implied_oneway_not_current_order_verification'}
    return {'bits':3,'status':'OSM_documented_default_two_way_not_blanket_undirected_expansion_or_current_order_verification'}

def grade_policy(tags):
    bridge=tags.get('bridge') not in (None,'no','false','0')
    tunnel=tags.get('tunnel') not in (None,'no','false','0')
    raw=tags.get('layer')
    layer=int(raw) if isinstance(raw,str) and re.fullmatch(r'-?\d+',raw) and abs(int(raw))<=20 else None
    status='source_layer_ordinal_NOT_metric_height' if layer is not None else 'GAME_structure_default_layer_NOT_source_metric_height'
    if layer is None: layer=1 if bridge else -1 if tunnel else 0
    structure='bridge' if bridge and not tunnel else 'tunnel' if tunnel and not bridge else 'conflicting_structure' if bridge and tunnel else 'surface'
    level=tags.get('level','')
    signature=canonical([structure,layer,level]).decode()
    return {'key':signature,'structure':structure,'layer':layer,'level':level,'status':status,
            'raw_layer':raw,'vertical_profile_source':'UNRESOLVED','source_ele_tag':tags.get('ele'),'source_ele_datum':tags.get('ele:datum'),
            'metric_layer_height_is_source_fact':False}

def way_policy(tags):
    result={'width':width_policy(tags),'grade':grade_policy(tags),'modes':{},'traffic_side':'left_GAME_policy',
            'turn_restrictions':'UNRESOLVED_relation_restrictions_not_in_way_catalog',
            'multilingual_names':{k:v for k,v in tags.items() if k=='name' or k.startswith('name:')}}
    for mode in MODES:
        access=mode_access(tags,mode);direction=direction_policy(tags,mode)
        forward=mode_access(tags,mode,'forward');backward=mode_access(tags,mode,'backward')
        bits=(direction['bits']&1 if forward['state']=='allowed' else 0)|(direction['bits']&2 if backward['state']=='allowed' else 0)
        result['modes'][mode]={'access':access,'forward_access':forward,'backward_access':backward,'direction':direction,'bits':bits}
    return result

def database(path):
    db=sqlite3.connect(path)
    db.executescript('''pragma cache_size=-65536;pragma temp_store=FILE;pragma mmap_size=0;
      create table owners(owner text primary key,descriptor text);
      create table source_nodes(id integer primary key,x real,z real);
      create table vertices(v integer primary key,node integer,grade text,x real,z real,base real,lower_y real,upper_y real,y real,unique(node,grade));
      create index vertex_node on vertices(node);
      create table ways(id text primary key,owner text,name text,raw text,policy text,vertices text);
      create index way_owner on ways(owner);
      create table occurrences(node integer,v integer,way text,endpoint integer);
      create index occurrence_node on occurrences(node);
      create table edges(id text primary key,a integer,b integer,length real,allowance real,way text,seg integer,car integer,bicycle integer,foot integer,transition integer);
      create index edges_a on edges(a);create index edges_b on edges(b);
      create index edges_way on edges(way);
      create table diagnostics(kind text,detail text);''')
    return db

def ingest_catalog(db, catalog, terrain):
    if catalog.get('schema')!='singapore_source_city_geometry_v1' or not isinstance(catalog.get('features'),list): raise RoadError('Unexpected city catalog schema')
    anchor=catalog.get('anchor_source_xyz')
    if not isinstance(anchor,list) or len(anchor)!=3 or not all(number(v) for v in anchor): raise RoadError('Invalid canonical owner anchor')
    count=0
    for feature in catalog['features']:
        if feature.get('kind')!='road': continue
        identifier=feature.get('id');road=feature.get('road',{});refs=road.get('original_ordered_node_ids');points=road.get('centerline_local_xz_double');tags=road.get('full_source_tags')
        if feature.get('canonical_anchor_source_xyz')!=anchor or feature.get('catalog_owner')!=catalog.get('owner'): raise RoadError('Road owner/canonical anchor mismatch')
        if not isinstance(identifier,str) or not re.fullmatch(r'way/[1-9]\d*',identifier) or feature.get('feature_key')!='road|'+identifier: raise RoadError('Invalid original way identity')
        if road.get('source_contract_issues') or not isinstance(refs,list) or not isinstance(points,list) or len(refs)!=len(points) or len(refs)<2: raise RoadError('Unresolved original-node/coordinate association')
        if not isinstance(tags,dict) or not all(isinstance(k,str) and isinstance(v,str) for k,v in tags.items()): raise RoadError('Missing full exact source tags')
        policy=way_policy(tags);grade=policy['grade'];vertices=[]
        for index,(node,point) in enumerate(zip(refs,points)):
            if not isinstance(node,int) or isinstance(node,bool) or node<=0 or not isinstance(point,list) or len(point)!=2 or not all(number(v) for v in point): raise RoadError('Invalid ordered node/point')
            x=float(anchor[0])+float(point[0]);z=float(anchor[2])+float(point[1])
            old=db.execute('select x,z from source_nodes where id=?',(node,)).fetchone()
            if old and max(abs(old[0]-x),abs(old[1]-z))>XY_TOLERANCE: raise RoadError(f'Conflicting coordinates for original node {node}')
            if old: x,z=old
            else: db.execute('insert into source_nodes values(?,?,?)',(node,x,z))
            old=db.execute('select v from vertices where node=? and grade=?',(node,grade['key'])).fetchone()
            if old: vertex=old[0]
            else:
                dem=terrain.sample(x,z) if terrain else 0.0
                base=float(dem) if dem is not None else 0.0
                lower=base+6.0*max(1,grade['layer']) if grade['structure']=='bridge' else None
                upper=base-5.0*max(1,abs(grade['layer'])) if grade['structure']=='tunnel' else None
                cursor=db.execute('insert into vertices(node,grade,x,z,base,lower_y,upper_y,y) values(?,?,?,?,?,?,?,?)',(node,grade['key'],x,z,base,lower,upper,base))
                vertex=cursor.lastrowid
                if dem is None: db.execute('insert into diagnostics values(?,?)',('unresolved_DEM_GAME_zero_fallback',str(vertex)))
            vertices.append(vertex)
            db.execute('insert into occurrences values(?,?,?,?)',(node,vertex,identifier,int(index in (0,len(refs)-1))))
        raw={'id':identifier,'name':feature.get('name'),'node_ids':refs,'tags':tags,'source_version':road.get('source_version'),
             'source_feature_sha256':feature['source_feature_sha256'],'source_geometry_sha256':feature['source_geometry_sha256'],
             'source_bounds_xz':feature['source_bounds_xz'],'original_order_preserved':True}
        db.execute('insert into ways values(?,?,?,?,?,?)',(identifier,catalog['owner'],feature.get('name'),canonical(raw).decode(),canonical(policy).decode(),canonical(vertices).decode()))
        for index,(a,b) in enumerate(zip(vertices,vertices[1:])):
            pa=db.execute('select x,z from vertices where v=?',(a,)).fetchone();pb=db.execute('select x,z from vertices where v=?',(b,)).fetchone()
            length=math.hypot(pb[0]-pa[0],pb[1]-pa[1])
            if length<.000001:
                db.execute('insert into diagnostics values(?,?)',('source_zero_length_segment',f'{identifier}@{index}'));continue
            g=.12 if policy['modes']['car']['bits'] else .7 if tags.get('highway')=='steps' else .25
            db.execute('insert into edges values(?,?,?,?,?,?,?,?,?,?,?)',(f'{identifier}@{index}',a,b,length,g*length,identifier,index,*[policy['modes'][m]['bits'] for m in MODES],0))
        count+=1
    db.commit();budget()
    return count

def add_endpoint_transitions(db):
    count=0
    rows=db.execute('select node from occurrences group by node having count(distinct v)>1')
    for (node,) in rows:
        groups=db.execute('select v,max(endpoint) from occurrences where node=? group by v order by v',(node,)).fetchall()
        for index,(a,endpoint_a) in enumerate(groups):
            for b,endpoint_b in groups[index+1:]:
                if not endpoint_a or not endpoint_b:
                    db.execute('insert into diagnostics values(?,?)',('incompatible_interior_grade_shared_node',canonical([node,a,b]).decode()));continue
                # Explicit original way endpoints, not an XY intersection. The
                # metric grade transition is still a GAME reconstruction.
                modes=[]
                for mode in MODES:
                    aa=db.execute(f'select max({mode}>0) from edges where a=? or b=?',(a,a)).fetchone()[0]
                    bb=db.execute(f'select max({mode}>0) from edges where a=? or b=?',(b,b)).fetchone()[0]
                    modes.append(3 if aa and bb else 0)
                db.execute('insert into edges values(?,?,?,?,?,?,?,?,?,?,?)',(f'node/{node}@grade/{a}-{b}',a,b,0.0,0.0,None,-1,*modes,1));count+=1
    db.commit();return count

def _csr(db):
    total=db.execute('select max(v) from vertices').fetchone()[0] or 0
    extra=db.execute("select count(*) from sqlite_master where type='table' and name='height_constraints'").fetchone()[0]
    query='select a,b,allowance from edges'+(' union all select a,b,allowance from height_constraints' if extra else '')
    edges=db.execute('select count(*) from edges').fetchone()[0]+(db.execute('select count(*) from height_constraints').fetchone()[0] if extra else 0)
    if total>MAX_VERTICES or edges>MAX_SEGMENTS: raise RoadError('Full source graph exceeds explicit work budget; no partial artifact')
    degree=np.zeros(total+1,dtype=np.uint32)
    for a,b,_ in db.execute(query): degree[a]+=1;degree[b]+=1
    offsets=np.empty(total+2,dtype=np.uint64);offsets[0]=0;np.cumsum(degree,out=offsets[1:])
    cursor=offsets[:-1].copy();neighbor=np.empty(edges*2,dtype=np.uint32);cost=np.empty(edges*2,dtype=np.float64)
    for a,b,weight in db.execute(query):
        neighbor[cursor[a]]=b;cost[cursor[a]]=weight;cursor[a]+=1
        neighbor[cursor[b]]=a;cost[cursor[b]]=weight;cursor[b]+=1
    return total,offsets,neighbor,cost

def envelope(initial,offsets,neighbors,cost,maximum=True):
    values=initial.copy();heap=[((-float(v) if maximum else float(v)),i) for i,v in enumerate(values) if math.isfinite(float(v)) and i]
    heapq.heapify(heap)
    while heap:
        encoded,node=heapq.heappop(heap);value=-encoded if maximum else encoded
        if (maximum and value<values[node]-1e-10) or (not maximum and value>values[node]+1e-10): continue
        for edge in range(int(offsets[node]),int(offsets[node+1])):
            other=int(neighbors[edge]);candidate=value-float(cost[edge]) if maximum else value+float(cost[edge])
            if (maximum and candidate>values[other]+1e-10) or (not maximum and candidate<values[other]-1e-10):
                values[other]=candidate;heapq.heappush(heap,(-candidate if maximum else candidate,other))
    return values

def solve_profiles(db,conflict_policy='reject'):
    total,offsets,neighbors,cost=_csr(db)
    base=np.full(total+1,-np.inf);lower=np.full(total+1,-np.inf);upper=np.full(total+1,np.inf)
    for v,h,lo,hi in db.execute('select v,base,lower_y,upper_y from vertices'):
        base[v]=h
        if lo is not None: lower[v]=lo
        if hi is not None: upper[v]=hi
    preferred=envelope(base,offsets,neighbors,cost)
    low=envelope(lower,offsets,neighbors,cost)
    high=envelope(upper,offsets,neighbors,cost,False)
    conflicts=np.flatnonzero(low[1:]>high[1:]+.000001)+1
    db.execute("delete from diagnostics where kind='incompatible_bridge_tunnel_clearance_constraints'")
    if len(conflicts):
        for v in conflicts: db.execute('insert into diagnostics values(?,?)',('incompatible_bridge_tunnel_clearance_constraints',str(int(v))))
        db.commit()
        if conflict_policy=='reject':raise RoadError(f'{len(conflicts)} grade constraints conflict; no silent flattening/partial mesh')
        if conflict_policy!='bridge-priority':raise RoadError('Unknown explicit grade conflict policy')
    heights=np.maximum(low,np.minimum(preferred,high))
    db.executemany('update vertices set y=? where v=?',((float(heights[v]),v) for v in range(1,total+1)))
    maximum_error=0.0
    for a,b,allowance in db.execute('select a,b,allowance from edges'):
        maximum_error=max(maximum_error,abs(float(heights[a]-heights[b]))-allowance)
    extra_error=0.0
    if db.execute("select count(*) from sqlite_master where type='table' and name='height_constraints'").fetchone()[0]:
        for a,b,allowance in db.execute('select a,b,allowance from height_constraints'):
            extra_error=max(extra_error,abs(float(heights[a]-heights[b]))-allowance)
    db.commit();budget()
    return {'vertices':total,'maximum_allowance_error_m':maximum_error,
            'maximum_height_only_constraint_error_m':extra_error,
            'status':'GAME_Lipschitz_cut_fill_bridge6m_tunnel5m_NOT_SURVEYED',
            'bridge_clearance_game_m_per_layer':6.0,'tunnel_depth_game_m_per_layer':5.0,
            'car_max_grade_game':.12,'foot_max_grade_game':.25,'steps_max_grade_game':.7,
            'DEM_reference':'EGM96 metres; separate preferred terrain reference, not road survey',
            'conflicting_game_constraints':len(conflicts),'conflict_policy':conflict_policy,
            'tunnel_depth_unresolved_where_bridge_priority_conflicts':bool(len(conflicts)),
            'terrain_cut_fill_required_for_physical_integration':True}

def route(db,start,goal,mode='car',physical_only=False):
    if mode not in MODES: raise RoadError('Unknown mode')
    costs={start:0.0};parents={};heap=[(0.0,start)]
    while heap:
        value,node=heapq.heappop(heap)
        if value!=costs[node]: continue
        if node==goal: break
        for identifier,a,b,length,bits,way,transition in db.execute(f'select id,a,b,length,{mode},way,transition from edges where a=? or b=?',(node,node)):
            other=b if node==a and bits&1 else a if node==b and bits&2 else None
            if other is None: continue
            if physical_only and way is not None:
                policy=json.loads(db.execute('select policy from ways where id=?',(way,)).fetchone()[0])
                if policy['grade']['structure'] not in ('surface','bridge') or policy['grade']['level']:continue
            distance=value+length
            if distance<costs.get(other,math.inf):
                costs[other]=distance;parents[other]=(node,identifier,way,transition);heapq.heappush(heap,(distance,other))
    if goal not in costs: return {'found':False,'start':start,'goal':goal,'mode':mode}
    vertices=[goal];edges=[];node=goal
    while node!=start:
        previous,identifier,way,transition=parents[node];edges.append({'id':identifier,'way':way,'transition':bool(transition)});vertices.append(previous);node=previous
    return {'found':True,'mode':mode,'distance_m':costs[goal],'vertices':vertices[::-1],'edges':edges[::-1],
            'legal_current_traffic_or_turn_restrictions_verified':False,'physical_policy_filter':physical_only}

def _nearest_height(x,z,points):
    best=math.inf;chosen=None
    for a,b in zip(points,points[1:]):
        dx=b[0]-a[0];dz=b[2]-a[2];length=dx*dx+dz*dz
        fraction=max(0.,min(1.,((x-a[0])*dx+(z-a[2])*dz)/length)) if length else 0.
        distance=(x-a[0]-fraction*dx)**2+(z-a[2]-fraction*dz)**2
        if distance<best: best=distance;chosen=a[1]+fraction*(b[1]-a[1])
    return chosen

def _unit(a,b):
    dx=b[0]-a[0];dz=b[1]-a[1];length=math.hypot(dx,dz)
    return (dx/length,dz/length) if length>1e-9 else None

def _cross2(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])

def _miter_vectors(points,half):
    closed=len(points)>2 and points[0]==points[-1];count=len(points)-1 if closed else len(points);result=[]
    for i in range(count):
        before=None;after=None
        for step in range(1,count):
            j=(i-step)%count if closed else i-step
            if j<0:break
            before=_unit(points[j],points[i])
            if before:break
        for step in range(1,count):
            j=(i+step)%count if closed else i+step
            if j>=count:break
            after=_unit(points[i],points[j])
            if after:break
        direction=after or before or (1.,0.)
        if not before or not after:offset=(-direction[1]*half,direction[0]*half)
        else:
            a=(-before[1],before[0]);b=(-after[1],after[0]);denominator=1+a[0]*b[0]+a[1]*b[1]
            if denominator<1e-8:offset=(-direction[1]*half,direction[0]*half)
            else:
                offset=((a[0]+b[0])*half/denominator,(a[1]+b[1])*half/denominator)
                length=math.hypot(*offset)
                if length>2*half:offset=(offset[0]*2*half/length,offset[1]*2*half/length)
        result.append(offset)
    if closed:result.append(result[0])
    return result

def _section_layout(points,width,hubs=None):
    half=width*.5;xy=[(float(p[0]),float(p[-1])) for p in points]
    values=list(hubs) if hubs is not None else [i in (0,len(points)-1) for i in range(len(points))]
    if len(values)!=len(points):raise RoadError('Render hub/source-node count mismatch')
    radii=[half if value is True else 0. if value is False else float(value) for value in values]
    if not all(math.isfinite(r) and 0<=r<=1024 for r in radii):raise RoadError('Invalid explicit junction plateau radius')
    distances=[0.]
    for a,b in zip(xy,xy[1:]):distances.append(distances[-1]+math.dist(a,b))
    intervals=sorted((max(0.,distances[i]-r),min(distances[-1],distances[i]+r),[i]) for i,r in enumerate(radii) if r>0)
    merged=[];equalities=[]
    for lo,hi,centres in intervals:
        if merged and lo<=merged[-1][1]+1e-8:
            before=merged[-1];equalities.extend((before[2][0],index) for index in centres);before[1]=max(before[1],hi);before[2].extend(centres)
        else:merged.append([lo,hi,centres])
    covered=[False]*len(points)
    for lo,hi,centres in merged:
        for i,distance in enumerate(distances):
            if lo-1e-8<=distance<=hi+1e-8:covered[i]=True;equalities.append((centres[0],i))
    miters=_miter_vectors(xy,half);result=[]
    for i,(a,b) in enumerate(zip(xy,xy[1:])):
        direction=_unit(a,b);length=math.dist(a,b)
        if direction is None:result.append({'index':i,'allowance_distance':0.,'cells':[]});continue
        normal=(-direction[1]*half,direction[0]*half)
        original_a=normal if radii[i]>0 else miters[i];original_b=normal if radii[i+1]>0 else miters[i+1]
        ra=rb=0.
        for lo,hi,_ in merged:
            if lo-1e-8<=distances[i]<=hi+1e-8:ra=max(ra,min(length,hi-distances[i]))
            if lo-1e-8<=distances[i+1]<=hi+1e-8:rb=max(rb,min(length,distances[i+1]-lo))
        if length<=ra+rb+1e-7:
            equalities.append((i,i+1));result.append({'index':i,'allowance_distance':0.,'cells':[(a,original_a,0.,b,original_b,1.)]});continue
        start=(a[0]+direction[0]*ra,a[1]+direction[1]*ra);end=(b[0]-direction[0]*rb,b[1]-direction[1]*rb)
        off_a=normal if ra>0 else original_a;off_b=normal if rb>0 else original_b
        la=(start[0]+off_a[0],start[1]+off_a[1]);ar=(start[0]-off_a[0],start[1]-off_a[1])
        bl=(end[0]+off_b[0],end[1]+off_b[1]);br=(end[0]-off_b[0],end[1]-off_b[1])
        area1=_cross2(la,ar,bl);area2=_cross2(ar,br,bl)
        altitude=min(abs(area1)/max(2*math.hypot(*off_a),1e-9),abs(area2)/max(2*math.hypot(*off_b),1e-9),length-ra-rb)
        if area1<=1e-10 or area2<=1e-10:altitude=0.0
        cells=[]
        if ra:cells.append((a,original_a,0.,start,normal,0.))
        cells.append((start,off_a,0.,end,off_b,1.))
        if rb:cells.append((end,normal,1.,b,original_b,1.))
        result.append({'index':i,'allowance_distance':max(0.,altitude)*.999,'cells':cells})
    return {'spans':result,'flat_nodes':covered,'hub_nodes':[r>0 for r in radii],'equalities':equalities}

def structured_sections(points,width,hubs=None):
    """Source-only centerlines with common original-node junction plateaus.
    Extra constraints affect height modeling ONLY, never navigation adjacency.
    """
    return _section_layout(points,width,hubs)['spans']

def _hub_vertices(db):
    return {row[0] for row in db.execute('select v from occurrences group by v having count(distinct way)>1 or max(endpoint)=1')}

def _common_hub_radii(db):
    hubs=_hub_vertices(db);parents={};directions=defaultdict(list);widths=defaultdict(float)
    def find(v):
        while parents.get(v,v)!=v:parents[v]=parents.get(parents[v],parents[v]);v=parents[v]
        return v
    for a,b in db.execute('select a,b from edges where transition=1'):
        a=find(a);b=find(b)
        if a!=b:parents[b]=a
    for policy,vertices in db.execute('select policy,vertices from ways'):
        p=json.loads(policy);ids=json.loads(vertices);half=p['width']['metres']*.5
        points=[db.execute('select x,z from vertices where v=?',(v,)).fetchone() for v in ids]
        for i,v in enumerate(ids):
            if v not in hubs:continue
            group=find(v);widths[group]=max(widths[group],half)
            for step in (-1,1):
                j=i+step
                while 0<=j<len(points):
                    direction=_unit(points[i],points[j])
                    if direction:directions[group].append(direction);break
                    j+=step
    radii={};capped=0
    for group,half in widths.items():
        radius=half;rays=directions[group]
        for i,a in enumerate(rays):
            for b in rays[i+1:]:
                cosine=a[0]*b[0]+a[1]*b[1];sine=abs(a[0]*b[1]-a[1]*b[0])
                if cosine>0 and sine>1e-4:radius=max(radius,half/sine)
        if radius>128.:capped+=1;radius=128.
        radii[group]=max(half,radius)
    return {v:radii[find(v)] for v in hubs},capped

def install_geometry_allowances(db):
    radii,capped=_common_hub_radii(db);updated=0;equalities=0
    db.executescript('create table if not exists render_hubs(v integer primary key,radius real);delete from render_hubs;create table if not exists height_constraints(a integer,b integer,allowance real,primary key(a,b));delete from height_constraints;')
    db.executemany('insert into render_hubs values(?,?)',radii.items())
    for identifier,policy,vertices in db.execute('select id,policy,vertices from ways'):
        p=json.loads(policy);ids=json.loads(vertices)
        points=[db.execute('select x,z from vertices where v=?',(v,)).fetchone() for v in ids]
        grade=.12 if p['modes']['car']['bits'] else .7 if json.loads(db.execute('select raw from ways where id=?',(identifier,)).fetchone()[0])['tags'].get('highway')=='steps' else .25
        layout=_section_layout(points,p['width']['metres'],[radii.get(v,0.) for v in ids])
        for a,b in layout['equalities']:
            if ids[a]!=ids[b]:db.execute('insert or ignore into height_constraints values(?,?,0)',tuple(sorted((ids[a],ids[b]))));equalities+=1
        for span in layout['spans']:
            edge_id=identifier+'@'+str(span['index']);a=ids[span['index']];b=ids[span['index']+1]
            length=math.dist(points[span['index']],points[span['index']+1]);allowance=grade*span['allowance_distance']
            db.execute('insert into edges values(?,?,?,?,?,?,?,?,?,?,?) on conflict(id) do update set allowance=excluded.allowance',
                       (edge_id,a,b,length,allowance,identifier,span['index'],*[p['modes'][m]['bits'] for m in MODES],0))
            updated+=1
    db.commit();return {'source_segments_with_geometry_aware_height_constraints':updated,'junction_hub_vertices':len(radii),
                        'navigation_connections_inferred_from_XY':False,'zero_horizontal_original_segments_retained':True,
                        'junction_plateau_height_only_constraints':db.execute('select count(*) from height_constraints').fetchone()[0],'acute_merge_plateau_length_capped_groups':capped,
                        'junction_hub_radius':'common incident-width/angle flat approach length; drawn apron keeps each own halfwidth; capped128m',
                        'max_surface_grade_margin':.999}

def ribbon(points,width,anchor,clip_bounds=None,hubs=None):
    if len(points)<2 or not number(width) or width<=0: raise RoadError('Invalid physical ribbon inputs')
    hub_flags=list(hubs) if hubs is not None else [i in (0,len(points)-1) for i in range(len(points))]
    layout=_section_layout(points,width,hub_flags)
    triangles=[]
    for span in layout['spans']:
        i=span['index'];ha=float(points[i][1]);hb=float(points[i+1][1])
        for a,oa,ta,b,ob,tb in span['cells']:
            ya=ha+(hb-ha)*ta;yb=ha+(hb-ha)*tb
            al=[a[0]+oa[0],ya,a[1]+oa[1]];ar=[a[0]-oa[0],ya,a[1]-oa[1]]
            bl=[b[0]+ob[0],yb,b[1]+ob[1]];br=[b[0]-ob[0],yb,b[1]-ob[1]]
            triangles.extend([[al,ar,bl],[ar,br,bl]])
    # Flat hubs are render-only source-node junction aprons. They create no
    # graph vertices/arcs and never join unrelated equal-XY source nodes.
    seen_hubs=set()
    for p,enabled in zip(points,layout['hub_nodes']):
        if not enabled or tuple(p) in seen_hubs:continue
        seen_hubs.add(tuple(p));ring=[]
        for i in range(16):
            angle=i*math.tau/16;ring.append([p[0]+math.cos(angle)*width*.5,p[1],p[2]+math.sin(angle)*width*.5])
        triangles.extend([[list(p),ring[i],ring[(i+1)%16]] for i in range(16)])
    positions=[];normals=[];indices=[];footprints=[];quantized_degenerate=0;max_slope=0.
    clipping=box(*clip_bounds) if clip_bounds is not None else None
    for tri in triangles:
        a,b,c=tri;denominator=_cross2((a[0],a[2]),(b[0],b[2]),(c[0],c[2]))
        if abs(denominator)<1e-12:continue
        footprint=Polygon([(p[0],p[2]) for p in tri])
        footprint=footprint.intersection(clipping) if clipping else footprint
        if footprint.is_empty or footprint.geom_type!='Polygon' or footprint.area<1e-12:continue
        footprints.append(footprint);ring=list(footprint.exterior.coords)[:-1]
        for i in range(1,len(ring)-1):
            vertices=[]
            for x,z in (ring[0],ring[i],ring[i+1]):
                u=((x-a[0])*(c[2]-a[2])-(z-a[2])*(c[0]-a[0]))/denominator
                v=((b[0]-a[0])*(z-a[2])-(b[2]-a[2])*(x-a[0]))/denominator
                y=a[1]+u*(b[1]-a[1])+v*(c[1]-a[1])
                vertices.append(np.asarray([x-anchor[0],y-anchor[1],z-anchor[2]],dtype='<f4').astype(float))
            cross=np.cross(vertices[1]-vertices[0],vertices[2]-vertices[0])
            if cross[1]>0:vertices[1],vertices[2]=vertices[2],vertices[1];cross=-cross
            if cross[1]==0 or np.linalg.norm(cross)<1e-10:
                quantized_degenerate+=1;continue
            if cross[1]>0 or not np.isfinite(cross).all():raise RoadError('Invalid structured Float32 winding')
            normal=(-cross/np.linalg.norm(cross)).tolist();max_slope=max(max_slope,math.hypot(normal[0],normal[2])/normal[1])
            for vertex in vertices:indices.append(len(positions));positions.append(vertex.tolist());normals.append(normal)
    union=unary_union(footprints) if footprints else Polygon()
    pieces=[union] if union.geom_type=='Polygon' else [p for p in getattr(union,'geoms',()) if p.geom_type=='Polygon']
    return {'vertices_local_xyz':positions,'normals':normals,'indices':indices,'ribbon_area_xz_m2':union.area,'holes':sum(len(p.interiors) for p in pieces),
            'surface_model':'structured constant-height cross sections plus flat original-node junction hubs',
            'maximum_emitted_surface_slope':max_slope,'quantized_degenerate_triangles_omitted':quantized_degenerate,
            'native_collision_uses_identical_topology':True,'godot_clockwise_top_cross_y_negative':True}

def export_catalogs(db,output):
    descriptors=[]
    for (owner,) in db.execute('select owner from owners order by owner'):
        ways=[];needed=set()
        for identifier,raw,policy,vertices in db.execute('select id,raw,policy,vertices from ways where owner=? order by id',(owner,)):
            item=json.loads(raw);item['policy']=json.loads(policy);item['vertex_ids']=json.loads(vertices);needed.update(item['vertex_ids']);ways.append(item)
        nodes=[]
        for v in sorted(needed):
            node,grade,x,z,y,base=db.execute('select node,grade,x,z,y,base from vertices where v=?',(v,)).fetchone()
            nodes.append({'vertex_id':v,'key':f'node/{node}|grade/{grade}','original_node_id':node,'grade_key':grade,'source_xyz':[x,y,z],'egm96_preferred_m':base,'world_y_is_game_profile':True})
        edges=[]
        for way in ways:
            for identifier,a,b,length,car,bicycle,foot,transition in db.execute('select id,a,b,length,car,bicycle,foot,transition from edges where way=? order by seg',(way['id'],)):
                edges.append({'id':identifier,'a':a,'b':b,'length_m':length,'directions':{'car':car,'bicycle':bicycle,'foot':foot},'source_way':way['id'],'grade_transition':False})
        transition_ids=set();listed_nodes=set(needed)
        for v in sorted(needed):
            for identifier,a,b,length,car,bicycle,foot in db.execute('select id,a,b,length,car,bicycle,foot from edges where transition=1 and (a=? or b=?)',(v,v)):
                if identifier in transition_ids:continue
                transition_ids.add(identifier)
                for other in (a,b):
                    if other in listed_nodes:continue
                    node,grade,x,z,y,base=db.execute('select node,grade,x,z,y,base from vertices where v=?',(other,)).fetchone()
                    nodes.append({'vertex_id':other,'key':f'node/{node}|grade/{grade}','original_node_id':node,'grade_key':grade,'source_xyz':[x,y,z],'egm96_preferred_m':base,'world_y_is_game_profile':True})
                    listed_nodes.add(other)
                edges.append({'id':identifier,'a':a,'b':b,'length_m':0.0,'directions':{'car':car,'bicycle':bicycle,'foot':foot},'source_way':None,'grade_transition':True})
        data={'schema':GRAPH_SCHEMA,'owner':owner,'ways':ways,'vertices':nodes,'edges':edges,'xy_connectivity_added':False}
        raw=canonical(data)
        if len(raw)>MAX_CATALOG: raise RoadError('Graph owner catalog budget exceeded')
        path=output/'graph'/f'{owner}.json';desc=write_new(path,raw);desc.update(file=f'graph/{owner}.json',owner=owner);descriptors.append(desc)
    return descriptors

def export_physical_batch(db,output,bounds,max_ways=10000):
    features=[];selected=[];hub_radii=dict(db.execute('select v,radius from render_hubs'));maximum_surface_slope=0.0
    for identifier,raw,policy,vertices in db.execute('select id,raw,policy,vertices from ways order by id'):
        item=json.loads(raw);p=json.loads(policy);b=item['source_bounds_xz']
        if b[2]<bounds[0] or b[0]>bounds[2] or b[3]<bounds[1] or b[1]>bounds[3] or not p['modes']['car']['bits']: continue
        if p['grade']['level'] or p['grade']['structure']=='conflicting_structure': continue
        selected.append((identifier,item,p,json.loads(vertices)))
        if len(selected)>max_ways: raise RoadError('Physical work batch exceeds explicit way budget; use smaller batches, no truncation')
    for identifier,item,policy,vertices in selected:
        points=[list(db.execute('select x,y,z from vertices where v=?',(v,)).fetchone()) for v in vertices]
        source_bounds=item['source_bounds_xz'];half=policy['width']['metres']*.5
        low_x=math.floor(max(bounds[0],source_bounds[0]-half)/1000);high_x=math.floor(min(bounds[2],source_bounds[2]+half)/1000)
        low_z=math.floor(max(bounds[1],source_bounds[1]-half)/1000);high_z=math.floor(min(bounds[3],source_bounds[3]+half)/1000)
        for tx in range(low_x,high_x+1):
            for tz in range(low_z,high_z+1):
                anchor=[tx*1000.,0.,tz*1000.]
                clip=[max(bounds[0],tx*1000),max(bounds[1],tz*1000),min(bounds[2],(tx+1)*1000),min(bounds[3],(tz+1)*1000)]
                mesh=ribbon(points,policy['width']['metres'],anchor,clip,[hub_radii.get(v,0.) for v in vertices])
                if not mesh['indices']: continue
                maximum_surface_slope=max(maximum_surface_slope,mesh['maximum_emitted_surface_slope'])
                if mesh['maximum_emitted_surface_slope']>.121:raise RoadError(f'Actual Float32 road surface exceeds physical grade policy: {identifier} {mesh["maximum_emitted_surface_slope"]}')
                features.append({'id':identifier,'name':item['name'],'tile':f'{tx}_{tz}','anchor_source_xyz':anchor,'source_vertex_ids':vertices,
                                 'policy':policy,'source_points_xyz':points,'mesh':mesh})
        budget()
    grouped=defaultdict(list)
    for feature in features: grouped[feature['tile']].append(feature)
    descriptors=[]
    for tile,items in sorted(grouped.items()):
        raw=canonical({'schema':SCHEMA,'tile':tile,'features':items,'physical_scope':'explicit_work_batch_NOT_world_boundary'})
        if len(raw)>MAX_CATALOG: raise RoadError('Physical tile JSON exceeds bounded load budget')
        desc=write_new(output/'physical'/f'{tile}.json',raw);desc.update(file=f'physical/{tile}.json',tile=tile);descriptors.append(desc)
    return descriptors,{'ways':len(selected),'fragments':len(features),'bounds_xz':bounds,'maximum_actual_surface_slope':maximum_surface_slope,'scope':'bounded continuous-region work batch; country graph is complete and compiler can build other regions'}

def reuse_owned_ingest(source,output,manifest,expected_db_sha):
    path=source/'work.sqlite'
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for part in iter(lambda:stream.read(1024*1024),b''):digest.update(part)
    if digest.hexdigest()!=expected_db_sha:raise RoadError('Owned terminal ingest cache SHA mismatch')
    if json.loads((source/'supervisor.json').read_bytes()).get('worker_exit') is None:raise RoadError('Reuse requires terminal supervised ownership evidence')
    prior=sqlite3.connect('file:'+str(path)+'?mode=ro',uri=True)
    db=sqlite3.connect(output/'work.sqlite');prior.backup(db);prior.close()
    db.execute('create index if not exists edges_way on edges(way)')
    for descriptor in manifest['catalogs']:
        row=db.execute('select descriptor from owners where owner=?',(descriptor['key'],)).fetchone()
        if row is None or json.loads(row[0])!=descriptor:raise RoadError('Ingest cache owner descriptor mismatch')
    if db.execute('select count(*) from owners').fetchone()[0]!=906 or db.execute('select count(*) from ways').fetchone()[0]!=257845:raise RoadError('Reuse cache is not complete source ingestion')
    db.execute('pragma cache_size=-65536');db.execute('pragma temp_store=FILE');db.execute('pragma mmap_size=0')
    # Source geometry/IDs/order remain immutable in the owned hashed cache.
    # Recompute policies/arcs from exact preserved tags under the NEW compiler.
    db.execute('delete from edges where transition=1')
    for identifier,raw in db.execute('select id,raw from ways'):
        value=json.loads(raw);policy=way_policy(value['tags'])
        db.execute('update ways set policy=? where id=?',(canonical(policy).decode(),identifier))
        grade=.12 if policy['modes']['car']['bits'] else .7 if value['tags'].get('highway')=='steps' else .25
        db.execute('update edges set car=?,bicycle=?,foot=?,allowance=length*? where way=?',(*[policy['modes'][m]['bits'] for m in MODES],grade,identifier))
    db.commit()
    return db,{'source_directory':str(source),'database_sha256':expected_db_sha,'all_source_descriptors_matched':True,
               'source_geometry_reparsed_in_this_reuse':False,'new_policies_recomputed_from_preserved_exact_tags':True}

def compile_dataset(args):
    started=time.monotonic();root=args.city;output=args.output
    if output.exists() or output.is_symlink(): raise RoadError('Fresh output directory required')
    identity_raw=(root/'identity.json').read_bytes();identity=json.loads(identity_raw)
    if sha(identity_raw)!=args.expected_city_identity or identity.get('schema')!='singapore_source_city_identity_v1': raise RoadError('Pinned city identity mismatch')
    manifest=read_bound(root,identity['manifest'])
    if manifest.get('schema')!='singapore_source_city_geometry_v1' or manifest['road_source_audit']!={'found':257845,'targets':257845,'vehicle_graph_or_mesh':False}: raise RoadError('Unexpected incomplete full-country road source audit')
    if manifest.get('georeference')!=FRAME: raise RoadError('Require exact uncompressed source coordinate frame')
    terrain=TerrainGrid(args.terrain,manifest['bindings']['dem_identity'],manifest['bindings']['snapshot_sha'])
    output.mkdir(parents=True);counts=Counter();reuse=None
    if args.reuse_ingest:
        db,reuse=reuse_owned_ingest(args.reuse_ingest,output,manifest,args.expected_ingest_sha)
        counts.update(owners=906,ways=257845)
    else:
        db=database(output/'work.sqlite')
        for desc in manifest['catalogs']:
            catalog=read_bound(root,desc);counts['ways']+=ingest_catalog(db,catalog,terrain)
            db.execute('insert into owners values(?,?)',(catalog['owner'],canonical(desc).decode()));db.commit();counts['owners']+=1
            if counts['owners']%50==0: print(json.dumps({'stage':'ingest','counts':dict(counts),'peak_rss':budget()}),flush=True)
    if counts['owners']!=906 or counts['ways']!=257845: raise RoadError('Full-country source counts differ; no partial-country success')
    counts['endpoint_grade_transitions']=add_endpoint_transitions(db)
    geometry_allowances=install_geometry_allowances(db)
    profile=solve_profiles(db,args.grade_conflict_policy)
    graph=export_catalogs(db,output)
    physical,physical_scope=export_physical_batch(db,output,args.bounds)
    diagnostics=dict(db.execute('select kind,count(*) from diagnostics group by kind'))
    result={'schema':SCHEMA,'version':1,'city_identity_sha256':args.expected_city_identity,'snapshot_manifest_sha256':manifest['bindings']['snapshot_sha'],
            'dem_identity_sha256':manifest['bindings']['dem_identity'],'georeference':manifest['georeference'],
            'compiler_sha256':sha(Path(__file__).read_bytes()),'counts':dict(counts),'profile':profile,'graph_chunks':graph,
            'owned_ingest_reuse':reuse,
            'surface_height_constraints':geometry_allowances,
            'physical_tiles':physical,'physical_scope':physical_scope,'diagnostics':diagnostics,
            'attribution':manifest['attribution'],'traffic_budget':'Caller GLOBAL48ambient/7physics, never per chunk',
            'limits':{'catalog_bytes':MAX_CATALOG,'maximum_vertices':MAX_VERTICES,'maximum_segments':MAX_SEGMENTS},
            'resources':{'worker_wall_seconds':time.monotonic()-started,'peak_rss_bytes':budget()},
            'not_proved':['current legal/conditional/turn restrictions','surveyed widths/vertical profiles','terrain cut/fill or tunnel walls integrated','graph alone physical playability','root scene/actor/traffic/save integration','whole Singapore acceptance']}
    raw=canonical(result);desc=write_new(output/'manifest.json',raw)
    record={'schema':IDENTITY,'version':1,'manifest':desc,'snapshot_manifest_sha256':manifest['bindings']['snapshot_sha'],'city_identity_sha256':args.expected_city_identity}
    identity_out=canonical(record);write_new(output/'identity.json',identity_out);db.close()
    return {'status':'complete_compile_not_runtime_acceptance','identity_sha256':sha(identity_out),'counts':dict(counts),'physical':physical_scope,'profile':profile,'resources':result['resources']}

def supervise(args):
    if args.output.exists() or args.output.is_symlink(): raise RoadError('Fresh supervised output required')
    log=args.output.parent/(args.output.name+'.worker.log')
    if log.exists() or log.is_symlink(): raise RoadError('Fresh owned worker log required')
    log.parent.mkdir(parents=True,exist_ok=True)
    started=time.monotonic();peak=0;reason=None
    with log.open('xb') as stream:
        proc=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),*sys.argv[1:],'--worker'],stdout=stream,stderr=subprocess.STDOUT)
        try:
            while proc.poll() is None:
                sample=subprocess.run(['/bin/ps','-o','rss=','-p',str(proc.pid)],capture_output=True,text=True).stdout.strip()
                if sample: peak=max(peak,int(sample)*1024)
                if peak>MAX_RSS: reason='Owned worker exceeded2GiB RSS';break
                if time.monotonic()-started>7200: reason='Owned worker exceeded bounded7200s wall';break
                time.sleep(1)
        finally:
            if proc.poll() is None:
                proc.terminate()
                try: proc.wait(timeout=30)
                except subprocess.TimeoutExpired: proc.kill();proc.wait()
    receipt={'status':'complete_compile_not_runtime_acceptance' if proc.returncode==0 and reason is None else 'FAILED_incomplete',
             'worker_exit':proc.returncode,'reason':reason,'sampled_peak_rss_bytes':peak,'wall_seconds':time.monotonic()-started,
             'limits':{'rss_bytes':MAX_RSS,'cpu_seconds':3600,'wall_seconds':7200},'worker_log':log.name}
    if args.output.is_dir(): write_new(args.output/'supervisor.json',canonical(receipt))
    return receipt

def main():
    p=argparse.ArgumentParser();p.add_argument('--city',type=Path,required=True);p.add_argument('--expected-city-identity',required=True)
    p.add_argument('--terrain',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--bounds',type=float,nargs=4,default=[-2000,-2500,2000,2000]);p.add_argument('--worker',action='store_true',help=argparse.SUPPRESS)
    p.add_argument('--grade-conflict-policy',choices=['reject','bridge-priority'],default='reject')
    p.add_argument('--reuse-ingest',type=Path);p.add_argument('--expected-ingest-sha');args=p.parse_args()
    if not all(math.isfinite(v) for v in args.bounds) or args.bounds[0]>=args.bounds[2] or args.bounds[1]>=args.bounds[3]: p.error('Invalid physical work bounds')
    resource.setrlimit(resource.RLIMIT_CPU,(3600,3630))
    try:
        result=compile_dataset(args) if args.worker else supervise(args)
        print(json.dumps(result,sort_keys=True),flush=True)
        if result['status'].startswith('FAILED'): raise SystemExit(1)
    except (RoadError,ValueError,sqlite3.Error,OSError) as exc:
        print(json.dumps({'status':'FAILED_no_complete_artifact','error':str(exc)}),flush=True);raise SystemExit(1)

if __name__=='__main__':main()
