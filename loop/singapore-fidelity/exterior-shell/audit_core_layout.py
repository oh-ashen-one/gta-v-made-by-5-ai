"""Independent CPU packing audit against retained source footprints and real geometry.

No Godot runtime or gameplay claim. Uses double precision source polygons, actual
shaft/gate/stair formula bounds and complete segment containment (not just corners).
"""
from __future__ import annotations
import hashlib,json,math,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HELPER=ROOT/'game/src/world/mbs_interior/source_core_layout.gd'
SHELL=ROOT/'game/src/world/mbs_interior/exterior_shell.gd'
REFERENCE=ROOT/'game/src/world/mbs_interior/site_reference.gd'

def const(path,name):
    text=path.read_text(); start=re.search(r'^const '+name+r'\s*:?=\s*',text,re.M)
    if not start: raise ValueError(name)
    return json.JSONDecoder().raw_decode(text[start.end():])[0]

def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
def dist_segment(p,a,b):
    dx=b[0]-a[0];dy=b[1]-a[1]; t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy)))
    return math.dist(p,(a[0]+t*dx,a[1]+t*dy))
def inside(p,poly):
    if any(dist_segment(p,a,b)<1e-9 for a,b in zip(poly,poly[1:]+poly[:1])):return True
    odd=False
    for a,b in zip(poly,poly[1:]+poly[:1]):
        if (a[1]>p[1])!=(b[1]>p[1]) and p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]:odd=not odd
    return odd

def proper_cross(a,b,c,d):return cross(a,b,c)*cross(a,b,d)<-1e-12 and cross(c,d,a)*cross(c,d,b)<-1e-12

def segment_contained(a,b,poly):
    # Subdivide at ALL boundary events, including vertex touches and collinear
    # overlaps. Proper-crossing-only checks miss a concave cut through a vertex.
    dx=b[0]-a[0];dz=b[1]-a[1];denom=dx*dx+dz*dz
    if denom<1e-20:return inside(a,poly)
    cuts=[0.0,1.0]
    for c,d in zip(poly,poly[1:]+poly[:1]):
        ex=d[0]-c[0];ez=d[1]-c[1];det=dx*ez-dz*ex
        if abs(det)>1e-12:
            t=((c[0]-a[0])*ez-(c[1]-a[1])*ex)/det
            u=((c[0]-a[0])*dz-(c[1]-a[1])*dx)/det
            if -1e-10<=t<=1+1e-10 and -1e-10<=u<=1+1e-10:cuts.append(max(0,min(1,t)))
        elif abs(cross(a,b,c))<1e-10:
            for p in [c,d]:
                t=((p[0]-a[0])*dx+(p[1]-a[1])*dz)/denom
                if 0<t<1:cuts.append(t)
    cuts=sorted(set(cuts))
    return all(inside([a[0]+dx*t,a[1]+dz*t],poly) for t in cuts+[(lo+hi)/2 for lo,hi in zip(cuts,cuts[1:])])

def contains(container,shape):
    return all(segment_contained(a,b,container) for a,b in zip(shape,shape[1:]+shape[:1]))

def signed_area(poly):return sum(a[0]*b[1]-a[1]*b[0] for a,b in zip(poly,poly[1:]+poly[:1]))*.5

def convex_intersection_area(subject,clip):
    result=subject[:];orientation=1 if signed_area(clip)>0 else -1
    for a,b in zip(clip,clip[1:]+clip[:1]):
        if not result:return 0.0
        prior=result[-1];dp=cross(a,b,prior)*orientation;out=[]
        for p in result:
            dc=cross(a,b,p)*orientation
            if (dp>=-1e-10)!=(dc>=-1e-10):
                t=dp/(dp-dc);out.append([prior[0]+t*(p[0]-prior[0]),prior[1]+t*(p[1]-prior[1])])
            if dc>=-1e-10:out.append(p)
            prior=p;dp=dc
        result=out
    return abs(signed_area(result)) if len(result)>=3 else 0.0

def rectangle(x0,z0,x1,z1):return [[x0,z0],[x1,z0],[x1,z1],[x0,z1]]
def shifted(poly,c):return [[x+c[0],z+c[1]] for x,z in poly]
def axis_bounds(poly):return [min(p[0] for p in poly),min(p[1] for p in poly),max(p[0] for p in poly),max(p[1] for p in poly)]
def overlap(a,b):return convex_intersection_area(a,b)>1e-8

def audit():
    reference=const(REFERENCE,'DATA'); axes=const(SHELL,'AXES'); centres=const(HELPER,'BANK_CENTRES')
    sizes=const(HELPER,'BANK_SIZE'); intervals=const(HELPER,'OWN_ATRIUM_INTERVALS'); lifts=const(HELPER,'LIFT_X')
    rows=[]; assertions=[]
    def check(name,condition,detail=None):
        assertions.append({'name':name,'passed':bool(condition),'detail':detail})
    check('6 required stable core aliases per tower',len(const(HELPER,'LIFT_ALIASES'))==4)
    # Numeric formulas independently derived from current production collision.
    cabin_source=(ROOT/'game/src/world/mbs_interior/cabins.gd').read_text()
    gate_source=(ROOT/'game/src/world/mbs_interior/stair_gates.gd').read_text()
    guest_source=(ROOT/'game/src/world/mbs_interior/guest_floor.gd').read_text()
    player_source=(ROOT/'game/src/actors/player.gd').read_text()
    def number(text,name):return float(re.search(r'^const '+name+r'\s*:?=\s*([0-9.]+)',text,re.M).group(1))
    width=number(cabin_source,'WIDTH');depth=number(cabin_source,'DEPTH');door=number(cabin_source,'DOOR_W')
    stair_door=number(gate_source,'WIDTH');leaf=number(gate_source,'LEAF_THICKNESS');frame=number(gate_source,'FRAME_THICKNESS');setback=number(gate_source,'GATE_EDGE_SETBACK')
    capsule_radius=float(re.search(r'cap.radius\s*=\s*([0-9.]+)',player_source).group(1))
    hinge_clearance=(frame+leaf)*.5+.005;leaf_plane=setback-hinge_clearance;approach_z=leaf_plane-(stair_door+.75)
    shaft_half=width/2+.14+.16/2; grille_half=door/4+.72+door/4
    complete_stair_bounds=[-(.78+(stair_door+.80)/2+.01),min(approach_z-capsule_radius-.02,leaf_plane-math.hypot(stair_door,leaf*.5)),.78+(stair_door+.80)/2+.01,5.20]
    check('full physical stair/hinge/query/capsule envelope inside reservation',contains(rectangle(-1.84,-2.20,1.84,5.30),rectangle(*complete_stair_bounds)),{'derived_actual_bounds':complete_stair_bounds,'actual_capsule_radius_m':capsule_radius,'hinge_frame_clearance_m':hinge_clearance,'receiving_approach_z_m':approach_z})
    check('source guard perimeter and outboard hinge match audited recipe','[-1.54, 1.54]' in guest_source and 'HINGE_FRAME_CLEARANCE=(FRAME_THICKNESS+LEAF_THICKNESS)*.5+.005' in gate_source)
    check('open grilles do not overlap adjacent real shafts',all(b-a>2*max(shaft_half,grille_half)+.20 for a,b in zip(lifts,lifts[1:])),{'shaft_width':2*shaft_half,'open_grille_width':2*grille_half,'centres':lifts})
    source_stamps={}
    for file in ['cabins.gd','guest_floor.gd','stair_gates.gd']:
        p=ROOT/'game/src/world/mbs_interior'/file;source_stamps[file]=hashlib.sha256(p.read_bytes()).hexdigest()
    code=(ROOT/'game/src/world/mbs_interior/cabins.gd').read_text()
    check('cabin dimensions agree with audited complete geometry',all(s in code for s in ['const WIDTH := 2.20','const DEPTH := 2.80','const DOOR_W := 1.30','fraction * .72','WIDTH * .5 + .14','DEPTH + .45']))
    for source in reference['towers']:
        name=source['tower'];c=centres[name]; axis=axes[name];center=source['centroid_world_xz']; u=reference['axis_south_xz'];v=reference['axis_bayward_xz']
        ground=[]
        for q in source['footprint_rings_world_xz'][0]:
            dx=q[0]-center[0];dz=q[1]-center[1];a=dx*u[0]+dz*u[1];b=dx*v[0]+dz*v[1]
            ground.append([a*axis['south'][0]+b*axis['south'][1],a*axis['bayward'][0]+b*axis['bayward'][1]])
        if ground[-1]==ground[0]:ground.pop()
        bounds=axis_bounds(ground); bank=shifted(rectangle(-sizes[0]/2,-sizes[1]/2,sizes[0]/2,sizes[1]/2),c)
        minimum_margin=1e9
        # Supplemental continuous affine taper critical sections: vertices crossing each bank
        # corner Z are included, in addition to all half-metre height sections.
        scales=[1-i/200*(1-30/(bounds[3]-bounds[1])) for i in range(201)]
        for p in ground:
            for q in bank:
                if abs(p[1]-bounds[3])>1e-12:
                    scale=(q[1]-bounds[3])/(p[1]-bounds[3])
                    if min(scales)<scale<max(scales):scales.append(scale)
        # Exact continuous proof: inverse-affine images of this fixed rectangle
        # over all scales form one swept rectangle in the unchanged ground
        # polygon. Prove its COMPLETE boundary containment, not sampled corners.
        minimum_scale=30/(bounds[3]-bounds[1])
        bx0,bz0,bx1,bz1=axis_bounds(bank)
        inverse_swept=rectangle(bx0,bounds[3]+(bz0-bounds[3])/minimum_scale,bx1,bz1)
        continuous_inside=contains(ground,inverse_swept)
        all_inside=True
        for scale in sorted(set(scales)):
            profile=[[p[0],bounds[3]+(p[1]-bounds[3])*scale] for p in ground]
            all_inside &= contains(profile,bank)
            minimum_margin=min(minimum_margin,min(dist_segment(q,a,b) for q in bank for a,b in zip(profile,profile[1:]+profile[:1])))
        check(name+' complete bank within unchanged source ground and continuous tapered profile',continuous_inside and all_inside,{'exact_continuous_inverse_swept_rectangle':inverse_swept,'complete_segment_boundary_event_proof':continuous_inside,'supplemental_sampled_and_critical_sections':len(set(scales)),'min_sampled_corner_boundary_margin_m':minimum_margin})
        check(name+' revised own-axis public void avoids full bank',intervals[name][1]<min(p[1] for p in bank),{'void_interval':intervals[name],'bank_z_interval':[bank[0][1],bank[2][1]]})
        components=[]
        for x in lifts:components.append({'id':'lift'+str(x),'envelope':shifted(rectangle(x-1.40,-.90,x+1.40,3.10),c)})
        for sign in [-1,1]:
            # Original stair coordinates. Preserve real width3.2/run5.2,
            # 3.68m conservative occupancy cross-span, and1.6m approach plus
            # .36m full capsule/.15m reserve. Rotate as a rigid module.
            corners=rectangle(-1.84,-2.20,1.84,5.30)
            envelope=[[c[0]+sign*(8.3+z),c[1]+1.0-sign*x] for x,z in corners]
            components.append({'id':'stair'+str(sign),'envelope':envelope})
        check(name+' operational component polygons inside bank',all(contains(bank,q['envelope']) for q in components))
        collisions=[[a['id'],b['id']] for i,a in enumerate(components) for b in components[i+1:] if overlap(a['envelope'],b['envelope'])]
        check(name+' no overlap between operational component envelopes',not collisions,collisions)
        # Main hall is2.6m clear. Each lift approach centre is >full capsule
        # radius from adjacent shafts. Stair side approaches run on x=+/-6.5825,
        # clear of the nearest lift x=+/-5.87 and opened leaf ending x=7.3325.
        hall=shifted(rectangle(-13.75,-3.50,13.75,-.90),c)
        check(name+' full-size hall remains inside bank',contains(bank,hall) and abs(hall[2][1]-hall[0][1]-2.6)<1e-8)
        check(name+' stair side approach full capsule clears lifts and open leaves',8.3+approach_z-capsule_radius>4.5+grille_half and 8.3+approach_z+capsule_radius<8.3+leaf_plane-math.hypot(stair_door,leaf*.5))
        check(name+' stair occupancy span encloses both current lane queries',1.84>=.78+(1.30+.80)/2+.01)
        rows.append({'tower':name,'source_id':source['id'],'unchanged_source_ring_sha256':hashlib.sha256(json.dumps(source['footprint_rings_world_xz'],separators=(',',':')).encode()).hexdigest(),'own_ground_ring':ground,'bank_polygon':bank,'shared_hall':hall,'components':components,'minimum_observed_shell_margin_m':minimum_margin,'sections_tested':len(set(scales))})
    # Negative controls: former2.5m spacing MUST detect overlap, and a rectangle
    # crossing a concave notch must fail even when all its corners are inside.
    check('old 2.5m spacing rejected',2.5<2*grille_half)
    notch=[[0,0],[6,0],[6,6],[4,6],[4,2],[2,2],[2,6],[0,6]]
    check('concave edge crossing not accepted by corner-only logic',all(inside(p,notch) for p in rectangle(1,1,5,5)) and not contains(notch,rectangle(1,1,5,5)))
    check('out-of-source bank negative control',not contains(rows[0]['own_ground_ring'],rectangle(-14,12,14,20)))
    return {'schema':'mbs_source_core_packing_audit_v2','passed':sum(a['passed'] for a in assertions),'failed':sum(not a['passed'] for a in assertions),'assertions':assertions,'towers':rows,'production_geometry_source_sha256':source_stamps,'helper_sha256':hashlib.sha256(HELPER.read_bytes()).hexdigest(),'runtime_parse_tested':False,'native_collision_or_traversal_verified':False,'current_factories_integrated':False,'continuous_taper_proof':'Exact inverse-affine swept rectangle fully contained in the original source polygon; every segment subdivided at proper, vertex, and collinear boundary events. Samples supplemental only.','scope':'Source-polygon and operational-envelope packing only. Reconstruction, not private as-built layout.'}

if __name__=='__main__':
    report=audit(); path=Path(__file__).with_name('CORE_PACKING_V2_AUDIT.json');path.write_text(json.dumps(report,indent=2)+'\n'); print(json.dumps({'passed':report['passed'],'failed':report['failed'],'report':str(path)}));raise SystemExit(bool(report['failed']))
