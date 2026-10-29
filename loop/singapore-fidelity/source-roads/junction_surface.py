"""Bounded shared-junction surface preflight and clipped-plane proof tools.

No DB/source/profile/navigation mutation. Actual infeasible source pins are
reported before any geometry is emitted. A protected multi-level branch is
never converted to one nearest-height surface.
"""
import math
import numpy as np
from shapely import constrained_delaunay_triangles
from shapely.geometry import LineString, Polygon, Point
from shapely.ops import unary_union

import expand_national as batch
import audit_national as audit
F=batch.frozen


def original_geometry(ways,anchor):
    polygons=[];pins={};tables={}
    for identifier,way in ways.items():
        points=way['canonical_source_points'];ids=way['vertex_ids'];width=way['policy']['width']['metres']
        hubs=[0.]*len(points)
        for hub in way['hubs']:hubs[hub['index']]=hub['plateau_arc_radius']
        mesh=F.ribbon(points,width,anchor,hubs=hubs)
        vertices=np.asarray(mesh['vertices_local_xyz'],dtype=np.float64)+np.asarray(anchor,dtype=np.float64)
        indices=np.asarray(mesh['indices'],dtype=np.int64).reshape(-1,3)
        pieces=[Polygon([(p[0],p[2]) for p in vertices[index]]) for index in indices]
        polygons.extend(pieces);tables[identifier]={'mesh':mesh,'anchor_source_xyz':list(anchor),'footprint':unary_union(pieces)}
        for v,node,point in zip(ids,way['raw_source']['node_ids'],points):
            if v in pins and pins[v]['source_xyz']!=point:raise ValueError('Inconsistent repeated canonical source vertex')
            pins[v]={'source_vertex_id':v,'original_node_id':node,'source_xyz':list(point),'source_way':identifier}
    return unary_union(polygons),list(pins.values()),tables


def preflight(footprint,pins,*,protected_source_branches=(),maximum_grade=.12):
    if protected_source_branches:
        return {'status':'PROTECTED_MULTILEVEL_SOURCE_BRANCHES_REQUIRE_SEPARATE_SHEETS',
                'protected_source_branch_records':list(protected_source_branches),'mesh_emitted':False}
    if len(pins)>4096:raise ValueError('Bounded local source-pin budget exceeded')
    if not F.number(maximum_grade) or not 0<maximum_grade<=.12:raise ValueError('Existing hard grade cannot be relaxed')
    conflicts=[];covered_pairs=0;seen={}
    for pin in pins:
        p=pin['source_xyz']
        if len(p)!=3 or not all(F.number(v) for v in p):raise ValueError('Finite canonical source pin required')
        key=(p[0],p[2])
        if key in seen and abs(seen[key]-p[1])>1e-7:
            return {'status':'INCONSISTENT_MULTIPLE_Y_PINS_AT_SAME_XZ','source_xyz':p,'other_y':seen[key],'mesh_emitted':False}
        seen[key]=p[1]
    for number,first in enumerate(pins):
        p=first['source_xyz']
        for second in pins[number+1:]:
            q=second['source_xyz'];length=math.hypot(q[0]-p[0],q[2]-p[2])
            if length<1e-9:continue
            line=LineString([(p[0],p[2]),(q[0],q[2])])
            missing=line.difference(footprint).length
            if missing>1e-7:continue  # No Euclidean shortcut across non-road land/holes.
            covered_pairs+=1;required=abs(q[1]-p[1])/length
            if required>maximum_grade+1e-9:
                conflicts.append({'first':first,'second':second,'covered_horizontal_distance_m':length,
                                  'height_difference_m':abs(q[1]-p[1]),'minimum_shared_sheet_grade':required,
                                  'uncovered_segment_length_m':missing,'hard_grade':maximum_grade})
    return {'status':'INFEASIBLE_FIXED_SOURCE_PINS_FOOTPRINT_AND_GRADE' if conflicts else 'PIN_PAIR_NECESSARY_CONDITIONS_PASS_NOT_A_SURFACE_SOLUTION',
            'pin_count':len(pins),'covered_pin_pairs':covered_pairs,'infeasible_pin_pairs':conflicts,
            'maximum_required_straight_covered_grade':max((r['minimum_shared_sheet_grade'] for r in conflicts),default=0.),
            'scope':'Necessary continuous-sheet bound on fully covered road segments; passing is not sufficient feasibility',
            'source_profile_navigation_or_XZ_changed':False,'mesh_emitted':False}


def boundary_controls(original_meshes,domain,source_pins,spacing=.5):
    """Preserve actual old boundary surfaces; reject conflicting interior cuts.

    Includes every old triangle/boundary event and interval samples. Agreement
    between duplicate old Float32 surfaces is checked before producing one
    boundary pin; distinct heights are never made two fixed values at one XZ.
    """
    if not F.number(spacing) or not .1<=spacing<=2.:raise ValueError('Bounded boundary sampling required')
    tables={key:audit.triangle_table(value) for key,value in original_meshes.items()}
    samples=set()
    def collect(shape):
        if shape.is_empty:return
        if shape.geom_type=='Point':
            samples.add((shape.x,shape.y));return
        if shape.geom_type=='LineString':
            steps=max(1,math.ceil(shape.length/spacing))
            for i in range(steps+1):
                p=shape.interpolate(shape.length*i/steps);samples.add((p.x,p.y))
            return
        for part in getattr(shape,'geoms',()):collect(part)
    for table in tables.values():
        for triangle in table[0]:
            collect(Polygon([(p[0],p[2]) for p in triangle]).intersection(domain.boundary))
    pins=[dict(pin) for pin in source_pins if domain.covers(Point(pin['source_xyz'][0],pin['source_xyz'][2]))]
    canonical={(round(pin['source_xyz'][0],9),round(pin['source_xyz'][2],9)):pin for pin in pins}
    conflicts=[];maximum=0.;boundary_count=0
    for x,z in sorted(samples):
        rows=[(key,audit.heights(table,x,z)) for key,table in tables.items()]
        values=[h for _,hs in rows for h in hs]
        if not values:continue
        delta=max(values)-min(values);maximum=max(maximum,delta)
        if delta>.00025:
            conflicts.append({'xz':[x,z],'actual_surface_heights':values,'height_range_m':delta});continue
        key=(round(x,9),round(z,9))
        if key in canonical:
            if any(abs(h-canonical[key]['source_xyz'][1])>.00025 for h in values):
                conflicts.append({'xz':[x,z],'canonical_y':canonical[key]['source_xyz'][1],'actual_surface_heights':values})
            continue
        pins.append({'boundary_control':boundary_count,'source_xyz':[x,values[0],z],
                     'actual_source_ways':[key for key,hs in rows if hs],
                     'all_old_surfaces_agree_within_codec_m':.00025});boundary_count+=1
    return {'status':'INCONSISTENT_PATCH_BOUNDARY' if conflicts else 'BOUNDARY_CONTROLS_AGREE',
            'pins':pins,'boundary_pin_count':boundary_count,'boundary_event_sample_count':len(samples),
            'maximum_old_boundary_disagreement_m':maximum,'conflicts':conflicts,'mesh_emitted':False}


def _polygons(shape):
    if shape.is_empty:return []
    if shape.geom_type=='Polygon':return [shape]
    return [p for part in getattr(shape,'geoms',()) for p in _polygons(part)]


def clipped_shared_planes(triangles,footprint,anchor):
    """Positive proof control: clip one already-feasible common field per way.

    This does not invent a field for infeasible actual source constraints.
    Canonical double coordinates are converted to Float32 only after anchor
    subtraction. Holes and original footprint boundaries are retained.
    """
    if len(anchor)!=3 or not all(F.number(v) for v in anchor):raise ValueError('Finite canonical field anchor required')
    if len(triangles)>10000:raise ValueError('Bounded local field budget exceeded')
    positions=[];normals=[];indices=[];field_polygons=[]
    for triangle in triangles:
        points=np.asarray(triangle,dtype=np.float64)
        if points.shape!=(3,3) or not np.isfinite(points).all():raise ValueError('Finite canonical field triangle required')
        a,b,c=points;den=(b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0])
        if abs(den)<1e-12:raise ValueError('Degenerate field triangle')
        gx=((b[1]-a[1])*(c[2]-a[2])-(c[1]-a[1])*(b[2]-a[2]))/den
        gz=((b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1]))/den
        if math.hypot(gx,gz)>.12+1e-9:raise ValueError('Common field violates unchanged hard grade')
        shape=Polygon([(p[0],p[2]) for p in points]);field_polygons.append(shape)
        clipped=shape.intersection(footprint)
        for piece in _polygons(clipped):
            for face in constrained_delaunay_triangles(piece).geoms:
                coords=list(face.exterior.coords)[:3];vertices=[]
                for x,z in coords:
                    y=a[1]+gx*(x-a[0])+gz*(z-a[2])
                    vertices.append(np.asarray([x-anchor[0],y-anchor[1],z-anchor[2]],dtype=np.float32).astype(np.float64))
                cross=np.cross(vertices[1]-vertices[0],vertices[2]-vertices[0])
                if cross[1]>0:vertices[1],vertices[2]=vertices[2],vertices[1];cross=-cross
                if cross[1]>=0 or np.linalg.norm(cross)<1e-10:raise ValueError('Invalid emitted shared-field winding')
                normal=-cross/np.linalg.norm(cross)
                if math.hypot(normal[0],normal[2])/normal[1]>.121:raise ValueError('Actual Float32 field slope exceeds existing emitted guard')
                for vertex in vertices:indices.append(len(positions));positions.append(vertex.tolist());normals.append(normal.tolist())
    target=unary_union(field_polygons).intersection(footprint)
    actual=[]
    for start in range(0,len(indices),3):
        vertices=[np.asarray(positions[i])+np.asarray(anchor) for i in indices[start:start+3]]
        actual.append(Polygon([(p[0],p[2]) for p in vertices]))
    actual=unary_union(actual) if actual else Polygon()
    if not actual.buffer(.0002).covers(target) or not target.buffer(.0002).covers(actual):
        raise ValueError('Emitted shared field changed original footprint/holes beyond codec tolerance')
    return {'vertices_local_xyz':positions,'normals':normals,'indices':indices,
            'original_target_area_m2':target.area,'actual_area_m2':actual.area,
            'footprint_symmetric_difference_m2':target.symmetric_difference(actual).area,
            'source_footprint_preserved_within_codec_m':.0002,
            'source_profile_navigation_or_canonical_XZ_mutated':False}
