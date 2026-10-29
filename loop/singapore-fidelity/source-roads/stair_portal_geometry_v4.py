"""Targeted actual-source straight stair/landing reconstruction prototype.

Source XZ/nodes are immutable. New relative heights are explicit inputs from
the future v4 metric solver. This is not a global builder or native proof.
"""
import math
import numpy as np
from shapely import constrained_delaunay_triangles
from shapely.geometry import LineString,Polygon
from shapely.ops import unary_union

import compile_roads_semantic_v2 as K
import typed_physical_v1 as typed


def _coords(geometry):
    if geometry.is_empty:return []
    if hasattr(geometry,'geoms'):return [xy for part in geometry.geoms for xy in _coords(part)]
    return list(geometry.coords) if geometry.geom_type in ('Point','LineString','LinearRing') else []


def flight(stair,neighbors,lower_y,upper_y):
    original=stair['points'];node_ids=stair['raw']['node_ids']
    if len(original)!=2 or len(node_ids)!=2:raise ValueError('Targeted straight-flight prototype; polyline/junction extension still required')
    p0,p1=original;dx=p1[0]-p0[0];dz=p1[2]-p0[2];run=math.hypot(dx,dz)
    if run<=0 or not math.isfinite(lower_y) or not math.isfinite(upper_y):raise ValueError('Finite nonzero source flight required')
    u=(dx/run,dz/run);normal=(-u[1],u[0]);width=stair['policy']['width']['metres']
    def at(s,side):return (p0[0]+u[0]*s+normal[0]*width*.5*side,p0[2]+u[1]*s+normal[1]*width*.5*side)
    footprint=Polygon([at(0,1),at(0,-1),at(run,-1),at(run,1)])
    landings=[.12,.12];incidence=[]
    for neighbor in neighbors:
        shared=set(neighbor['raw']['node_ids'])&set(node_ids)
        if not shared:continue
        if not set(neighbor['vertices'])&set(stair['vertices']):
            raise ValueError('Same source node has another grade; explicit original transition binding required before clipping')
        if len(shared)>1:raise ValueError('Parallel/source-overlapping ramp needs a distinct junction solution, not a clip shortcut')
        end=0 if node_ids[0] in shared else 1
        centre=LineString([(p[0],p[2]) for p in neighbor['points']])
        samples=_coords(centre.intersection(footprint.buffer(-1e-6)))
        stations=[(x-p0[0])*u[0]+(z-p0[2])*u[1] for x,z in samples]
        if stations:
            extent=max(stations) if end==0 else run-min(stations)
            landings[end]=max(landings[end],extent+.02)
        incidence.append({'neighbor_way':neighbor['id'],'shared_original_node':node_ids[end],'end':end})
    if sum(landings)>=run:raise ValueError('Source-connected landings consume flight; no source centreline removal')
    active=run-sum(landings);rise=upper_y-lower_y
    if abs(rise)/active>.7:raise ValueError('Proposed source stair height exceeds unchanged walking grade after real landings')
    points=[[p0[0],lower_y,p0[2]],
            [p0[0]+u[0]*landings[0],lower_y,p0[2]+u[1]*landings[0]],
            [p1[0]-u[0]*landings[1],upper_y,p1[2]-u[1]*landings[1]],
            [p1[0],upper_y,p1[2]]]
    corridor=Polygon([at(landings[0],1),at(landings[0],-1),at(run-landings[1],-1),at(run-landings[1],1)])
    for neighbor in neighbors:
        if not set(neighbor['raw']['node_ids'])&set(node_ids):continue
        centre=LineString([(p[0],p[2]) for p in neighbor['points']])
        if centre.intersection(corridor.buffer(-1e-6)).length>1e-6:
            raise ValueError('Stair aperture would remove an original neighboring centreline')
    return {'original_stair_way':stair['id'],'original_source_nodes':list(node_ids),'original_source_xz':[[p[0],p[2]] for p in original],
            'proposed_endpoint_y':[lower_y,upper_y],'source_run_m':run,'landing_lengths_m':landings,'active_ramp_run_m':active,
            'derived_non_source_geometry_points':points,'corridor':corridor,'source_connected_neighbors':incidence,
            'original_graph_xy_or_node_identity_changed':False,'whole_country_or_native_acceptance':False}


def stair_mesh(stair,plan,anchor):
    points=plan['derived_non_source_geometry_points'];width=stair['policy']['width']['metres']
    collision=K.ribbon(points,width,anchor,None,[False]*len(points))
    cells,evidence=typed.step_layout(points,width,[False]*len(points),stair['raw']['tags'])
    if cells is None:raise ValueError('Source count/profile does not fit: '+evidence['status'])
    visual=typed.visible_steps(cells,anchor,None)
    return {'mesh':collision,'visual_mesh':visual,'step_evidence':evidence,'anchor_source_xyz':anchor,
            'derived_geometry_is_not_extra_OSM_nodes':True}


def trim_connected_neighbor(neighbor,mesh,anchor,stair,plan):
    shared=set(neighbor['raw']['node_ids'])&set(stair['raw']['node_ids'])
    if not shared:return mesh,{'status':'UNCHANGED_UNCONNECTED_SOURCE_WAY','original_id':neighbor['id']}
    if not set(neighbor['vertices'])&set(stair['vertices']):
        raise ValueError('Unproven grade connection cannot authorize a stair aperture')
    corridor=plan['corridor'];positions=[];normals=[];indices=[];footprints=[];removed=0.
    old=np.asarray(mesh['vertices_local_xyz'],dtype=float)+np.asarray(anchor,dtype=float)
    for ids in np.asarray(mesh['indices']).reshape(-1,3):
        triangle=old[ids];a,b,c=triangle
        polygon=Polygon([(p[0],p[2]) for p in triangle]);remaining=polygon.difference(corridor)
        removed+=polygon.area-remaining.area
        denominator=(b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0])
        if denominator<=0:raise ValueError('Original neighbor triangle is not clockwise-up')
        for piece in getattr(remaining,'geoms',[remaining]):
            if piece.is_empty or piece.geom_type!='Polygon':continue
            footprints.append(piece)
            for t in constrained_delaunay_triangles(piece).geoms:
                coords=list(t.exterior.coords)[:3];verts=[]
                for x,z in coords:
                    u=((x-a[0])*(c[2]-a[2])-(z-a[2])*(c[0]-a[0]))/denominator
                    v=((b[0]-a[0])*(z-a[2])-(b[2]-a[2])*(x-a[0]))/denominator
                    y=a[1]+u*(b[1]-a[1])+v*(c[1]-a[1])
                    verts.append(np.asarray([x-anchor[0],y-anchor[1],z-anchor[2]],dtype='<f4').astype(float))
                cross=np.cross(verts[1]-verts[0],verts[2]-verts[0])
                if cross[1]>0:verts[1],verts[2]=verts[2],verts[1];cross=-cross
                length=np.linalg.norm(cross)
                if cross[1]==0 or length<1e-10:continue
                normal=-cross/length
                for vertex in verts:indices.append(len(positions));positions.append(vertex.tolist());normals.append(normal.tolist())
    union=unary_union(footprints)
    result=dict(mesh,vertices_local_xyz=positions,normals=normals,indices=indices,
                source_connected_stair_aperture=stair['id'],ribbon_area_xz_m2=union.area)
    return result,{'status':'SOURCE_CONNECTED_STAIR_FLIGHT_APERTURE','neighbor_way':neighbor['id'],'stair_way':stair['id'],
                   'shared_original_nodes':sorted(shared),'removed_overhanging_surface_area_m2':removed,
                   'original_centreline_removed':False,'other_unconnected_crossings_modified':False,
                   'lateral_step_sidewalls_and_handrails_still_required':True}
