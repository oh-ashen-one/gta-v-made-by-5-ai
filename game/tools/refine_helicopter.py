"""Repartition the existing helicopter into body and correctly pivoted rotors.

CPU-only Blender 4.5.11:
  blender --background --factory-startup --threads 4 --python game/tools/refine_helicopter.py

No assets are generated/downloaded. Source geometry, UVs, normals and materials
are preserved. New helicopter_refined.glb is private and does not clear rights.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import sys
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT=Path(__file__).resolve().parents[2]
ASSETS=ROOT/'game/assets/providers'
SOURCE=ROOT.parent/'relay-manager/assets/W1-HERO-004.glb'
EDITABLE=ROOT/'art/source/helicopter'
EVIDENCE=ROOT/'docs/wave-02/helicopter'
SCALE=8.112126350402832 # Match predecessor's measured 6.5m rotor-width normalization.


def components(mesh):
    vertices=mesh.data.vertices;parent=list(range(len(vertices)))
    def find(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    def union(a,b):parent[find(a)]=find(b)
    weld={}
    for v in vertices:
        key=tuple(round(x,5) for x in v.co)
        if key in weld:union(v.index,weld[key])
        else:weld[key]=v.index
    for edge in mesh.data.edges:union(*edge.vertices)
    groups={}
    for v in vertices:groups.setdefault(find(v.index),[]).append(v.index)
    labels={i:key for key,indices in groups.items() for i in indices}
    # Diagnostic/classification coordinates are the original Godot axes:
    # +X nose, +Y up, +Z right/left. Convert Blender's +Z up explicitly.
    coords=np.array([(v.co.x,v.co.z,-v.co.y) for v in vertices])
    stats={}
    for key,indices in groups.items():
        p=coords[indices];stats[key]={'vertices':len(indices),'lo':p.min(axis=0).tolist(),
            'hi':p.max(axis=0).tolist(),'center':p.mean(axis=0).tolist()}
    return labels,stats,coords


def classify(stats):
    roles={};main_hub=None;tail_motor=None
    for key,record in stats.items():
        lo=np.array(record['lo']);hi=np.array(record['hi']);span=hi-lo
        role='body'
        # Complete upper assembly: five blades, hub and their hub-level links.
        # Lower swashplate support rods and tail fin remain on the static body.
        if lo[1]>3.12 and lo[0]>-2.2 and hi[0]>-2.5:
            role='main_rotor'
            if hi[1]>3.70 and span[0]<.8 and span[2]<.8:main_hub=record
        # Three source tail-fan blades occupy an isolated thin outboard plane.
        # The motor shaft and tail stabilizers extend inward and stay static.
        if hi[0]<-2.5 and hi[2]<-.5 and lo[1]>1.75 and hi[1]<3.05:
            role='tail_rotor'
        if hi[0]<-2.5 and span[0]<.4 and span[1]<.4 and span[2]>.5:
            tail_motor=record
        roles[key]=role
    if main_hub is None or tail_motor is None:raise RuntimeError('Measured rotor hub signature not found')
    main_lo=np.array(main_hub['lo']);main_hi=np.array(main_hub['hi'])
    tail_lo=np.array(tail_motor['lo']);tail_hi=np.array(tail_motor['hi'])
    main=np.array([(main_lo[0]+main_hi[0])*.5,3.43,(main_lo[2]+main_hi[2])*.5])
    tail=np.array([(tail_lo[0]+tail_hi[0])*.5,(tail_lo[1]+tail_hi[1])*.5,-.646])
    # Source Godot -> normalized Blender: X'=oldZ, Y'=oldX, Z'=oldY.
    to_blender=lambda p:Vector((p[2],p[0],p[1]))
    return roles,{'body':Vector((0,0,0)),'main_rotor':to_blender(main),'tail_rotor':to_blender(tail)}


def partition(mesh,labels,roles,pivots):
    source=mesh.data
    normal_values=[n.vector.copy() for n in source.corner_normals]
    uv_values=[uv.uv.copy() for uv in source.uv_layers.active.data]
    result={}
    for name in ['body','main_rotor','tail_rotor']:
        selected=[p for p in source.polygons if roles[labels[p.vertices[0]]]==name]
        indices=sorted({i for p in selected for i in p.vertices});remap={old:new for new,old in enumerate(indices)}
        pivot=pivots[name]
        new=bpy.data.meshes.new('Helicopter_'+name)
        new.from_pydata([source.vertices[i].co-pivot for i in indices],[],[[remap[i] for i in p.vertices] for p in selected])
        for material in source.materials:new.materials.append(material)
        uv_layer=new.uv_layers.new(name='UVMap')
        normals=[]
        for target,original in zip(new.polygons,selected):
            target.material_index=original.material_index;target.use_smooth=True
            for dst,src in zip(target.loop_indices,original.loop_indices):
                uv_layer.data[dst].uv=uv_values[src];normals.append(normal_values[src])
        new.normals_split_custom_set(normals);new.update()
        obj=bpy.data.objects.new(name,new);bpy.context.collection.objects.link(obj);obj.location=pivot
        obj['source']='W1-HERO-004.glb'
        obj['role']=name
        obj['axis_godot']='Y' if name=='main_rotor' else ('X' if name=='tail_rotor' else 'static')
        result[name]=(obj,indices)
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,default=SOURCE)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if not args.source.exists():raise FileNotFoundError(args.source)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    if len(meshes)>1:bpy.ops.object.join()
    mesh=bpy.context.object
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    for vertex in mesh.data.vertices:vertex.co*=SCALE
    ground=min(v.co.z for v in mesh.data.vertices)
    for vertex in mesh.data.vertices:vertex.co.z-=ground
    mesh.data.update()
    labels,stats,source_coords=components(mesh)
    roles,pivots=classify(stats)
    mesh.rotation_mode='XYZ'
    mesh.rotation_euler.z=math.pi/2
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
    oriented=np.array([list(v.co) for v in mesh.data.vertices])
    expected=source_coords[:,[2,0,1]]
    orientation_error=float(np.abs(oriented-expected).max())
    if orientation_error>1e-5:raise RuntimeError('Nose-to-forward orientation transform failed')
    parts=partition(mesh,labels,roles,pivots)
    original_faces=len(mesh.data.polygons)
    if sum(len(obj.data.polygons) for obj,_ in parts.values())!=original_faces:
        raise RuntimeError('Partition lost or duplicated source faces')
    report={'source':str(args.source),'source_sha256':hashlib.sha256(args.source.read_bytes()).hexdigest(),
        'output':'helicopter_refined.glb','blender':bpy.app.version_string,'source_triangles':original_faces,
        'source_components':len(stats),'orientation_max_error_m':orientation_error,'forward':'Godot -Z','ground_y':0.0,'parts':{},
        'rights':'Private derivative of existing Customuse output; no new generation and no blanket rights clearance.',
        'limits':['Generated blade geometry remains asymmetric; it is not an aerodynamics model.',
            'Lower swashplate rods, shaft/motor and all ambiguous body-linked pieces remain static.',
            'In-engine rotor/collision/landing acceptance must be recorded separately.']}
    all_pos=[];all_tri=[];all_uv=[];all_roles=[];offset=0
    for index,(name,(obj,indices)) in enumerate(parts.items()):
        points=np.array([list(obj.matrix_world @ v.co) for v in obj.data.vertices])
        # matrix_world may not yet be evaluated for a freshly linked object.
        points=np.array([list(v.co+obj.location) for v in obj.data.vertices])
        reconstructed=np.array([list(mesh.data.vertices[i].co) for i in indices])
        error=float(np.abs(points-reconstructed).max())
        if error>1e-5:raise RuntimeError('Rest geometry moved during partition')
        obj.data.calc_loop_triangles();triangles=np.array([list(t.vertices) for t in obj.data.loop_triangles])
        uv=np.array([[list(obj.data.uv_layers.active.data[k].uv) for k in t.loops] for t in obj.data.loop_triangles])
        # Runtime axis invariant: spin around local Y (Godot) / local Z
        # (Blender) for main; local X for tail, body geometry never changes.
        axis='Z' if name=='main_rotor' else 'X'
        spin_errors=[]
        for angle in [0,45,90,180,270]:
            R=Matrix.Rotation(math.radians(angle),3,axis)
            transformed=np.array([list(R @ v.co+obj.location) for v in obj.data.vertices])
            component=2 if name=='main_rotor' else 0
            spin_errors.append(float(np.abs(transformed[:,component]-points[:,component]).max()))
        if name!='body' and max(spin_errors)>1e-5:raise RuntimeError('Rotor axis invariant failed')
        report['parts'][name]={'vertices':len(indices),'triangles':len(triangles),
            'component_count':sum(1 for value in roles.values() if value==name),
            'pivot_godot':[float(obj.location.x),float(obj.location.z),float(-obj.location.y)],
            'axis_godot':'Y' if name=='main_rotor' else ('X' if name=='tail_rotor' else 'static'),
            'bounds_blender':[points.min(axis=0).tolist(),points.max(axis=0).tolist()],
            'rest_reconstruction_max_error_m':error,'spin_axis_max_error_m':max(spin_errors) if name!='body' else 0}
        all_pos.append(points);all_tri.append(triangles+offset);all_uv.append(uv)
        all_roles.extend([index]*len(triangles));offset+=len(indices)
    bpy.data.objects.remove(mesh,do_unlink=True)
    ASSETS.mkdir(parents=True,exist_ok=True);EDITABLE.mkdir(parents=True,exist_ok=True);EVIDENCE.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(EDITABLE/'helicopter_refined.blend'))
    target=ASSETS/'helicopter_refined.glb'
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',export_yup=True,
        export_apply=False,export_animations=False,export_materials='EXPORT',export_extras=True)
    report['output_sha256']=hashlib.sha256(target.read_bytes()).hexdigest()
    (ASSETS/'helicopter_refined_report.json').write_text(json.dumps(report,indent=2)+'\n')
    (EVIDENCE/'refinement-report.json').write_text(json.dumps(report,indent=2)+'\n')
    np.savez_compressed('/tmp/astra_heli_refined.npz',vertices=np.concatenate(all_pos),triangles=np.concatenate(all_tri),
        uv=np.concatenate(all_uv),roles=np.array(all_roles),pivots=np.array([list(pivots[n]) for n in parts]))
    print('HELICOPTER_REFINEMENT',json.dumps(report))

if __name__=='__main__':main()
