"""Rig existing Customuse figures for Orchard Reach; no generation or downloads.

Tested with Blender 4.5.11 LTS. Run from the repository root:
  /Users/midir/Applications/Blender-4.5.11.app/Contents/MacOS/Blender \
    --background --factory-startup --threads 4 --python game/tools/rig_characters.py

The source *_clean.glb files are read-only inputs. This emits editable .blend
files, *_rigged.glb derivatives and a numeric report under assets/providers.
All animation is authored here, in place; game motion remains authoritative.
There is deliberately no rendering or network access in the default operation.
"""
from __future__ import annotations
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

REPO = Path(__file__).resolve().parents[2]
ASSET_DIR = REPO / 'game/assets/providers'
SOURCE_DIR = REPO / 'art/source/characters'
FPS = 30
SPECS = {
    'player': {'source': 'player_clean.glb', 'height': 1.75, 'budget': None},
    'officer': {'source': 'officer_clean.glb', 'height': 1.78, 'budget': None},
    'civilian': {'source': 'player_clean.glb', 'height': 1.75, 'budget': 18000},
}


def smoothstep(a, b, x):
    t = max(0., min(1., (x-a)/(b-a)))
    return t*t*(3.-2.*t)


def blend(weights, a, b, t):
    weights[a] = weights.get(a, 0.) + 1.-t
    weights[b] = weights.get(b, 0.) + t


def bounds(mesh):
    return [[min(v.co[i] for v in mesh.data.vertices), max(v.co[i] for v in mesh.data.vertices)] for i in range(3)]


def import_figure(spec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ASSET_DIR/spec['source']))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    mesh = bpy.context.object
    mesh.name = 'CharacterMesh'
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Both original figures face approximately +X with a measured 20-degree
    # baked yaw. This aligns their shoulders and ankles to Blender +Y, which
    # exports as Godot/glTF -Z.
    turn = Matrix.Rotation(math.radians(110), 4, 'Z')
    for v in mesh.data.vertices: v.co = turn @ v.co
    box = bounds(mesh)
    factor = spec['height']/(box[2][1]-box[2][0])
    for v in mesh.data.vertices:
        v.co *= factor
    box = bounds(mesh)
    for v in mesh.data.vertices: v.co.z -= box[2][0]
    # Retain generated UVs/PBR maps. Cloth is separately addressable for NPC
    # wardrobe variation while skin, hair and shoes preserve their albedo.
    mesh.data.update()
    base = mesh.data.materials[0]
    base.name = 'CharacterSkinAndDetails'
    cloth = base.copy(); cloth.name = 'CharacterClothing'
    mesh.data.materials.append(cloth)
    for polygon in mesh.data.polygons:
        c = polygon.center
        if 0.91 < c.z < 1.49 and abs(c.x) < (0.24 if c.z < 1.28 else 0.29):
            polygon.material_index = 1
        polygon.use_smooth = True
    return mesh


def replace_sneaker_materials(mesh):
    # Original authored textile, not a recolor of the marked atlas. It replaces
    # only the low shoe surfaces and disconnects their inherited logo normal map.
    # Original UVs and all source inputs remain unchanged. Geometry still needs
    # visual mark inspection; this does not certify output redistribution rights.
    import numpy as np
    size=256;rng=np.random.default_rng(20261021)
    yy,xx=np.mgrid[:size,:size]
    weave=(np.sin(xx*math.pi)*.003+np.cos(yy*math.pi)*.004)
    grain=rng.normal(0,.006,(size,size))+weave
    rgba=np.ones((size,size,4),dtype=np.float32)
    for channel,base in enumerate([.068,.074,.077]):rgba[:,:,channel]=np.clip(base+grain,.03,.11)
    image=bpy.data.images.new('OrchardOriginalCharcoalWeave',width=size,height=size,alpha=True)
    image.pixels.foreach_set(rgba.ravel());image.pack()
    upper=bpy.data.materials.new('OriginalUnbrandedCharcoalTextile');upper.use_nodes=True
    bsdf=upper.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=.88
    texture=upper.node_tree.nodes.new('ShaderNodeTexImage');texture.image=image
    upper.node_tree.links.new(texture.outputs['Color'],bsdf.inputs['Base Color'])
    sole=bpy.data.materials.new('OriginalPlainRubberSole');sole.use_nodes=True
    bsdf=sole.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(.19,.205,.21,1)
    bsdf.inputs['Roughness'].default_value=.92
    upper_index=len(mesh.data.materials);mesh.data.materials.append(upper)
    sole_index=len(mesh.data.materials);mesh.data.materials.append(sole)
    for face in mesh.data.polygons:
        if face.center.z<.145:
            face.material_index=sole_index if face.center.z<.042 else upper_index


def skeleton_points(h):
    s = h/1.75
    P = lambda x,y,z: Vector((x*s,y*s,z*s))
    bones = [
        ('root', P(0,0,0), P(0,0,.16), None),
        ('pelvis', P(0,-.055,.90), P(0,-.055,1.03), 'root'),
        ('spine', P(0,-.055,1.03), P(0,-.065,1.22), 'pelvis'),
        ('chest', P(0,-.065,1.22), P(0,-.065,1.42), 'spine'),
        ('neck', P(0,-.065,1.42), P(0,-.020,1.54), 'chest'),
        ('head', P(0,-.020,1.54), P(0,-.010,1.73), 'neck'),
    ]
    for side, sign in [('l',1),('r',-1)]:
        bones += [
            ('clavicle.'+side, P(.03*sign,-.065,1.40), P(.203*sign,-.065,1.40), 'chest'),
            ('upper_arm.'+side, P(.203*sign,-.065,1.40), P(.259*sign,-.035,1.135), 'clavicle.'+side),
            ('forearm.'+side, P(.259*sign,-.035,1.135), P(.264*sign,.012,.875), 'upper_arm.'+side),
            ('hand.'+side, P(.264*sign,.012,.875), P(.264*sign,.035,.754), 'forearm.'+side),
            ('fingers.'+side, P(.264*sign,.027,.80), P(.264*sign,.035,.73), 'hand.'+side),
            ('thigh.'+side, P(.105*sign,-.055,.90), P(.130*sign,-.035,.50), 'pelvis'),
            ('shin.'+side, P(.130*sign,-.035,.50), P(.146*sign,-.015,.13), 'thigh.'+side),
            ('foot.'+side, P(.146*sign,-.015,.13), P(.146*sign,.08,.065), 'shin.'+side),
            ('toe.'+side, P(.146*sign,.08,.065), P(.146*sign,.16,.065), 'foot.'+side),
        ]
    return bones


def skin_region(mesh):
    # The generated bodies have disconnected clothing/skin shells. Cut the
    # topology below the sleeves, weld only exact duplicate seam coordinates,
    # and identify the two long forearm/hand components. This is safer than a
    # world-X cutoff (fingers reach inward) or UV edge colors (atlas bleed).
    vertices=mesh.data.vertices
    parent=list(range(len(vertices)))
    def find(i):
        while parent[i]!=i:
            parent[i]=parent[parent[i]];i=parent[i]
        return i
    def union(a,b):parent[find(a)]=find(b)
    cutoff=1.24
    weld={}
    for v in vertices:
        if v.co.z>=cutoff:continue
        key=tuple(round(x,5) for x in v.co)
        if key in weld:union(v.index,weld[key])
        else:weld[key]=v.index
    for edge in mesh.data.edges:
        a,b=edge.vertices
        if vertices[a].co.z<cutoff and vertices[b].co.z<cutoff:union(a,b)
    components={}
    for v in vertices:
        if v.co.z<cutoff:components.setdefault(find(v.index),[]).append(v.index)
    result=set()
    for indices in components.values():
        coords=[vertices[i].co for i in indices]
        zlo=min(c.z for c in coords);zhi=max(c.z for c in coords)
        xmean=sum(c.x for c in coords)/len(coords)
        if abs(xmean)>.18 and zlo>.60 and zhi>1.18 and zhi-zlo>.35:
            result.update(indices)
    if len(result)<1000:
        raise RuntimeError('Arm topology segmentation failed; inspect source, do not export.')
    return result


def make_armature(mesh, h, skin_vertices):
    data = bpy.data.armatures.new('OrchardHumanoid')
    arm = bpy.data.objects.new('OrchardRig',data)
    bpy.context.collection.objects.link(arm)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True); bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    points=skeleton_points(h)
    # Fit arm landmarks to the topology-identified skin in each source mesh.
    for side,sign in [('l',1),('r',-1)]:
        def centre(z0,z1,default):
            values=[mesh.data.vertices[i].co for i in skin_vertices
                    if mesh.data.vertices[i].co.x*sign>.13 and z0<mesh.data.vertices[i].co.z<z1]
            if not values:return default
            return Vector(tuple((min(v[k] for v in values)+max(v[k] for v in values))*.5 for k in range(3)))
        elbow=centre(1.105*h/1.75,1.165*h/1.75,Vector((.28*sign,0,1.135)))
        wrist=centre(.86*h/1.75,.90*h/1.75,Vector((.29*sign,0,.88)))
        fingertips=centre(.72*h/1.75,.79*h/1.75,Vector((.29*sign,.03,.755)))
        points=[(n,head,elbow if n=='upper_arm.'+side else tail,parent) for n,head,tail,parent in points]
        points=[(n,elbow,wrist,parent) if n=='forearm.'+side else (n,head,tail,parent) for n,head,tail,parent in points]
        points=[(n,wrist,fingertips,parent) if n=='hand.'+side else (n,head,tail,parent) for n,head,tail,parent in points]
        knuckles=wrist.lerp(fingertips,.65)
        points=[(n,knuckles,fingertips,parent) if n=='fingers.'+side else (n,head,tail,parent) for n,head,tail,parent in points]
    for name,head,tail,parent in points:
        b = data.edit_bones.new(name); b.head=head; b.tail=tail
        if parent: b.parent=data.edit_bones[parent]
        # Sagittal flexion uses local +X for all limb bones. The root and spine
        # point upward; limbs point down. The foot points horizontally forward.
        direction=(tail-head).normalized()
        roll = Vector((0,1,0)) if direction.z<-.5 else Vector((0,-1,0))
        if abs(direction.z)<.5: roll=Vector((0,0,1))
        b.align_roll(roll)
    bpy.ops.object.mode_set(mode='OBJECT')
    mesh.parent=arm
    modifier=mesh.modifiers.new('HumanoidSkin','ARMATURE');modifier.object=arm
    modifier.use_deform_preserve_volume=False
    return arm


def weights_for(co, height, is_arm_skin=False):
    # Explicit anatomy envelopes avoid heat-weight leakage between the arms
    # resting close to the torso and between the two trouser legs.
    x,y,z = co/(height/1.75)
    ax=abs(x);side='l' if x>=0 else 'r'
    arm_w={};body_w={}
    # Measured shoulder/elbow/wrist/crotch landmarks in the normalized source.
    arm_alpha = smoothstep(.09,.23,ax)
    arm_alpha *= smoothstep(1.04,1.20,z)*(1.-smoothstep(1.40,1.50,z))
    if is_arm_skin:arm_alpha=1.0
    if z<.91:
        blend(arm_w,'hand.'+side,'forearm.'+side,smoothstep(.835,.925,z))
        curl=1.-smoothstep(.775,.825,z)
        arm_w={k:v*(1.-curl) for k,v in arm_w.items()};arm_w['fingers.'+side]=curl
    elif z<1.20: blend(arm_w,'forearm.'+side,'upper_arm.'+side,smoothstep(1.08,1.19,z))
    else: blend(arm_w,'upper_arm.'+side,'clavicle.'+side,smoothstep(1.34,1.46,z))
    if z<.16:
        blend(body_w,'foot.'+side,'shin.'+side,smoothstep(.115,.19,z))
        toe=smoothstep(.075,.13,y)*(1.-smoothstep(.10,.16,z))
        body_w={k:v*(1.-toe) for k,v in body_w.items()};body_w['toe.'+side]=toe
    elif z<.58: blend(body_w,'shin.'+side,'thigh.'+side,smoothstep(.43,.57,z))
    elif z<1.04: blend(body_w,'thigh.'+side,'pelvis',smoothstep(.81,.97,z))
    elif z<1.24: blend(body_w,'spine','chest',smoothstep(1.14,1.26,z))
    elif z<1.52: blend(body_w,'chest','neck',smoothstep(1.40,1.50,z))
    else: blend(body_w,'neck','head',smoothstep(1.50,1.58,z))
    # Smooth pelvis/spine transition at the belt line, independent of side.
    if .97<=z<1.14: body_w={};blend(body_w,'pelvis','spine',smoothstep(.97,1.12,z))
    # Loose trousers bridge the inner thighs; keep their central crotch on
    # the pelvis instead of abruptly swapping left/right thigh at X=0.
    if .55<z<.97:
        centre=(1.-smoothstep(.02,.08,ax))*smoothstep(.55,.70,z)
        body_w={k:v*(1.-centre) for k,v in body_w.items()}
        body_w['pelvis']=body_w.get('pelvis',0)+centre
    w={k:v*(1.-arm_alpha) for k,v in body_w.items()}
    for k,v in arm_w.items():w[k]=w.get(k,0)+v*arm_alpha
    w={k:v for k,v in w.items() if v>.0001}
    ordered=sorted(w.items(),key=lambda p:-p[1])[:4];total=sum(v for k,v in ordered)
    return {k:v/total for k,v in ordered}


def skin(mesh,arm,h,skin_vertices):
    groups={b.name:mesh.vertex_groups.new(name=b.name) for b in arm.data.bones}
    influenced={k:0 for k in groups}
    for v in mesh.data.vertices:
        for name,weight in weights_for(v.co,h,v.index in skin_vertices).items():
            groups[name].add([v.index],weight,'REPLACE');influenced[name]+=1
    return influenced


def reset_pose(arm):
    for b in arm.pose.bones:
        b.rotation_mode='QUATERNION';b.rotation_quaternion=Quaternion((1,0,0,0));b.location=(0,0,0);b.scale=(1,1,1)


def rotate(arm,name,x=0,y=0,z=0):
    from mathutils import Euler
    arm.pose.bones[name].rotation_quaternion=Euler(tuple(math.radians(a) for a in (x,y,z)),'XYZ').to_quaternion()


def aim_arms(arm,breath=0):
    # Two-bone analytic IK baked to ordinary FK animation. Aiming brings both
    # hands together around one weapon instead of leaving a handlebar pose.
    rotate(arm,'chest',-3,0,-2)
    bpy.context.view_layer.update()
    chest=arm.pose.bones['chest'].head.copy()
    for side,sign in [('r',-1),('l',1)]:
        upper=arm.pose.bones['upper_arm.'+side]
        lower=arm.pose.bones['forearm.'+side]
        hand=arm.pose.bones['hand.'+side]
        shoulder=upper.head.copy()
        wrist=chest+Vector((-.075 if side=='r' else -.015,.455 if side=='r' else .405,.115+breath*.002))
        first=upper.bone.length;second=lower.bone.length
        delta=wrist-shoulder;distance=min(delta.length,first+second-.003);direction=delta.normalized()
        along=(first*first-second*second+distance*distance)/(2*distance)
        bend=math.sqrt(max(0,first*first-along*along))
        pole=Vector((sign*.55,0,-1));pole=(pole-direction*pole.dot(direction)).normalized()
        elbow=shoulder+direction*along+pole*bend
        wrist=shoulder+direction*distance
        def aim_bone(bone,head,tail):
            rest=(bone.bone.tail_local-bone.bone.head_local).normalized()
            q=rest.rotation_difference((tail-head).normalized()) @ bone.bone.matrix_local.to_quaternion()
            matrix=q.to_matrix().to_4x4();matrix.translation=head;bone.matrix=matrix
            bpy.context.view_layer.update()
        aim_bone(upper,shoulder,elbow)
        aim_bone(lower,elbow,wrist)
        aim_bone(hand,wrist,wrist+Vector((0,.55,-.84))*hand.bone.length)
        rotate(arm,'fingers.'+side,0,0,sign*68)


def pose_frame(arm,kind,t,h):
    reset_pose(arm)
    rotate(arm,'fingers.l',0,0,16)
    rotate(arm,'fingers.r',0,0,-16)
    tau=math.tau*t
    if kind in ('idle','aim','reload'):
        breath=math.sin(tau)
        rotate(arm,'chest',breath*.7,0,breath*.25)
        rotate(arm,'head',0,breath*.65,0)
        rotate(arm,'forearm.l',5+breath*.8)
        rotate(arm,'forearm.r',5-breath*.8)
    if kind in ('walk','run','aim_walk','aim_run'):
        running='run' in kind;amplitude=39 if running else 24
        arm.pose.bones['root'].location.y=(.022 if running else .012)*(1.-math.cos(tau*2))
        rotate(arm,'pelvis',0,math.sin(tau)*2,math.sin(tau)*1.4)
        rotate(arm,'chest',-7 if running else -2,math.sin(tau)*-4,math.sin(tau)*-.8)
        rotate(arm,'head',2 if running else 1,math.sin(tau)*1.4,0)
        for side,phase in [('l',tau),('r',tau+math.pi)]:
            swing=math.cos(phase)*amplitude
            knee=-7-(63 if running else 43)*max(0,-math.sin(phase))**2
            rotate(arm,'thigh.'+side,swing)
            rotate(arm,'shin.'+side,knee)
            rotate(arm,'foot.'+side,-(swing+knee)*.78)
            rotate(arm,'toe.'+side,max(0,math.sin(phase))*-12)
            rotate(arm,'upper_arm.'+side,-math.cos(phase)*(23 if running else 13))
            rotate(arm,'forearm.'+side,44 if running else 12)
    if kind.startswith('aim'):aim_arms(arm,math.sin(tau)*.5)
    if kind=='reload':
        aim_arms(arm)
        rotate(arm,'upper_arm.l',32+math.sin(math.pi*t)*17,0,5)
        rotate(arm,'forearm.l',75+math.sin(math.pi*t)*20,0,-38)
        rotate(arm,'head',10*math.sin(math.pi*t),0,0)
    if kind=='hit':
        pulse=math.sin(math.pi*t)*(1.-t)
        rotate(arm,'chest',-15*pulse,0,11*pulse)
        rotate(arm,'head',8*pulse)
        rotate(arm,'upper_arm.l',-10*pulse,0,-10*pulse)
        rotate(arm,'upper_arm.r',-14*pulse,0,7*pulse)
        rotate(arm,'thigh.l',-10*pulse);rotate(arm,'shin.l',-16*pulse)
    if kind=='jump':
        bend=math.sin(math.pi*t)
        rotate(arm,'thigh.l',26*bend);rotate(arm,'thigh.r',15*bend)
        rotate(arm,'shin.l',-42*bend);rotate(arm,'shin.r',-26*bend)
        rotate(arm,'upper_arm.l',-24*bend);rotate(arm,'upper_arm.r',-20*bend)
        rotate(arm,'forearm.l',22*bend);rotate(arm,'forearm.r',25*bend)
    if kind in ('seated','drive'):
        arm.pose.bones['root'].location.y=-.45*h/1.75
        rotate(arm,'chest',-3+math.sin(tau)*.4)
        rotate(arm,'head',0,math.sin(tau)*.7,0)
        for side,sign in [('l',1),('r',-1)]:
            rotate(arm,'thigh.'+side,88,0,-sign*2)
            rotate(arm,'shin.'+side,-88)
            rotate(arm,'foot.'+side,-2)
            if kind=='drive':
                rotate(arm,'upper_arm.'+side,60,0,sign*10)
                rotate(arm,'forearm.'+side,25,0,sign*4)
                rotate(arm,'hand.'+side,-12)
                rotate(arm,'fingers.'+side,0,0,sign*52)
            else:
                rotate(arm,'upper_arm.'+side,16,0,sign*3)
                rotate(arm,'forearm.'+side,69,0,sign*5)
                rotate(arm,'hand.'+side,-20)
    if kind=='fall':
        d=smoothstep(.05,.92,t)
        rotate(arm,'root',87*d,0,8*d)
        arm.pose.bones['root'].location.y=.08*d
        rotate(arm,'thigh.l',15*d);rotate(arm,'thigh.r',-7*d)
        rotate(arm,'shin.l',-26*d);rotate(arm,'shin.r',-12*d)
        rotate(arm,'upper_arm.l',0,0,-8*d)
        rotate(arm,'upper_arm.r',0,0,10*d)
        rotate(arm,'head',-14*d)


def animate(arm,mesh,h):
    clips={'idle':(2.4,True),'walk':(1.04,True),'run':(.72,True),
           'aim':(2.4,True),'aim_walk':(1.04,True),'aim_run':(.72,True),
           'reload':(1.4,False),'hit':(.36,False),'jump':(.8,True),'fall':(.9,False),
           'seated':(2.4,True),'drive':(2.4,True)}
    scene=bpy.context.scene;scene.render.fps=FPS
    arm.animation_data_create()
    for name,(duration,loop) in clips.items():
        count=max(2,round(duration*FPS));action=bpy.data.actions.new(name)
        action.use_fake_user=True;arm.animation_data.action=action
        for frame in range(count+1):
            scene.frame_set(frame+1);pose_frame(arm,name,frame/count,h)
            if name in ('walk','run','aim_walk','aim_run','fall','hit'):
                bpy.context.view_layer.update()
                evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
                ground=min((evaluated.matrix_world @ Vector(c)).z for c in evaluated.bound_box)
                arm.pose.bones['root'].location.y-=ground
            for b in arm.pose.bones:
                b.keyframe_insert('rotation_quaternion',frame=frame+1,group=b.name)
                b.keyframe_insert('location',frame=frame+1,group=b.name)
        # NLA track names are the stable glTF/Godot animation names.
        track=arm.animation_data.nla_tracks.new();track.name=name
        strip=track.strips.new(name,1,action);strip.action_frame_start=1;strip.action_frame_end=count+1
        if loop: action['loop']=True
        for fc in action.fcurves:
            for point in fc.keyframe_points:point.interpolation='LINEAR'
    arm.animation_data.action=None
    reset_pose(arm);scene.frame_set(1)
    return clips


def write_diagnostics(arm, mesh, name, folder):
    import numpy as np
    folder.mkdir(parents=True, exist_ok=True)
    for track in arm.animation_data.nla_tracks: track.mute = True
    for label, clip, frame in [('idle','idle',1),('walk_contact','walk',1),
            ('walk_swing','walk',24),('run_swing','run',17),('aim','aim',1),
            ('hit','hit',5),('fall','fall',28),('seated','seated',1),('drive','drive',1)]:
        arm.animation_data.action=bpy.data.actions[clip]
        bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
        evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
        data=evaluated.to_mesh();data.calc_loop_triangles()
        positions=np.array([list(v.co) for v in data.vertices], dtype=np.float32)
        triangles=np.array([list(t.vertices) for t in data.loop_triangles],dtype=np.int32)
        uv=np.array([[list(data.uv_layers.active.data[l].uv) for l in t.loops] for t in data.loop_triangles],dtype=np.float32)
        materials=np.array([t.material_index for t in data.loop_triangles],dtype=np.int32)
        np.savez_compressed(folder/(name+'_'+label+'.npz'),positions=positions,triangles=triangles,uv=uv,materials=materials)
        evaluated.to_mesh_clear()


def process(name, diagnostics=None):
    spec=SPECS[name];mesh=import_figure(spec)
    if spec['source']=='player_clean.glb':replace_sneaker_materials(mesh)
    skin_vertices=skin_region(mesh)
    arm=make_armature(mesh,spec['height'],skin_vertices);influenced=skin(mesh,arm,spec['height'],skin_vertices)
    # Reduce the already weighted mesh, so UV-seam fragments retain their
    # arm/hand assignment instead of being reclassified after decimation.
    if spec['budget']:
        bpy.ops.object.select_all(action='DESELECT')
        mesh.select_set(True);bpy.context.view_layer.objects.active=mesh
        mesh.data.calc_loop_triangles();n=len(mesh.data.loop_triangles)
        if n>spec['budget']:
            dec=mesh.modifiers.new('CivilianRuntimeBudget','DECIMATE')
            dec.ratio=spec['budget']/n;dec.use_collapse_triangulate=True
            bpy.ops.object.modifier_apply(modifier=dec.name)
        influenced={group.name:0 for group in mesh.vertex_groups}
        for vertex in mesh.data.vertices:
            for group in vertex.groups:
                if group.weight>.0001:influenced[mesh.vertex_groups[group.group].name]+=1
    clips=animate(arm,mesh,spec['height'])
    mesh.data.calc_loop_triangles()
    report={'asset':name,'source':spec['source'],'output':name+'_rigged.glb',
        'blender':bpy.app.version_string,'vertices':len(mesh.data.vertices),
        'triangles':len(mesh.data.loop_triangles),'bones':len(arm.data.bones),
        'bounds_blender_m':bounds(mesh),'forward':'Blender +Y / Godot -Z',
        'clips':{k:{'duration':v[0],'loop':v[1]} for k,v in clips.items()},
        'weighted_vertices_by_bone':influenced,
        'rights':'Derived private build asset. Player shoe surfaces replaced with original textile/rubber; source and uniform marks remain UNVERIFIED. No blanket clearance.',
        'limitations':['Authored procedural gait, no motion capture or foot-placement IK.',
                        'No facial articulation; fingers use one curl bone per hand, requiring grip refinement.']}
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_DIR/(name+'_rigged.blend')))
    bpy.ops.export_scene.gltf(filepath=str(ASSET_DIR/(name+'_rigged.glb')),
        export_format='GLB',export_yup=True,export_apply=False,
        export_animations=True,export_animation_mode='NLA_TRACKS',
        export_nla_strips=True,export_force_sampling=True,
        export_skins=True,export_def_bones=True,export_materials='EXPORT',
        export_extras=True)
    (ASSET_DIR/(name+'_rig_report.json')).write_text(json.dumps(report,indent=2)+'\n')
    print('CHARACTER_RIG_REPORT',json.dumps(report))
    if diagnostics:write_diagnostics(arm,mesh,name,Path(diagnostics))


def process_weapons():
    import numpy as np
    for name,length in [('pistol',.19),('smg',.62)]:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(ASSET_DIR/(name+'_clean.glb')))
        objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        if len(objects)>1:bpy.ops.object.join()
        mesh=bpy.context.object;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        points=np.array([tuple(v.co) for v in mesh.data.vertices])
        covariance=np.cov(points.T);values,vectors=np.linalg.eigh(covariance)
        forward=Vector(vectors[:,np.argmax(values)])
        if forward.x>0:forward=-forward # rendered source inspection: muzzle is -X.
        up=Vector(vectors[:,np.argsort(values)[-2]])
        if up.z<0:up=-up
        if name=='pistol':forward=Vector((-1,0,0));up=Vector((0,0,1))
        right=forward.cross(up).normalized();up=right.cross(forward).normalized()
        source=Matrix((right,forward,up)).transposed();rotation=source.transposed()
        for vertex in mesh.data.vertices:vertex.co=rotation @ vertex.co
        box=bounds(mesh);scale=length/(box[1][1]-box[1][0])
        for vertex in mesh.data.vertices:vertex.co*=scale
        box=bounds(mesh);height=box[2][1]-box[2][0]
        centre_y=(box[1][0]+box[1][1])*.5
        grip=Vector(((box[0][0]+box[0][1])*.5,
                     centre_y-length*(.32 if name=='pistol' else .22),
                     box[2][0]+height*.30))
        for vertex in mesh.data.vertices:vertex.co-=grip
        mesh.name=name.title()+'GripAligned';mesh['forward']='Godot -Z'
        mesh['source']=name+'_clean.glb';mesh['origin']='estimated grip centre; inspect in game'
        mesh.data.update()
        bpy.ops.export_scene.gltf(filepath=str(ASSET_DIR/(name+'_held.glb')),
            export_format='GLB',export_yup=True,export_apply=True,export_extras=True,
            export_animations=False,export_materials='EXPORT')
        print('HELD_WEAPON',name,'bounds_blender',bounds(mesh))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--characters',nargs='+',choices=list(SPECS),default=list(SPECS))
    parser.add_argument('--weapons-only', action='store_true')
    parser.add_argument('--diagnostics', help='Optional CPU-evaluated deformation NPZs; does not render.')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if not args.weapons_only:
        for name in args.characters:process(name,args.diagnostics)
    process_weapons()

if __name__=='__main__':main()
