"""Convert the licensed Josh model and native Mixamo clips; never re-skin.
Run with Blender 5.2 --background --factory-startup --python-exit-code 1
--python this_file -- --source-dir ... --output ... . Raw FBX/GLB stays private.
"""
import argparse,sys,json,hashlib
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
parser=argparse.ArgumentParser();parser.add_argument('--source-dir',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
a=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);src=a.source_dir.resolve();out=a.output.resolve();out.parent.mkdir(parents=True,exist_ok=True)
for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
bpy.context.scene.render.fps=30
bpy.ops.import_scene.fbx(filepath=str(src/'run.fbx'),automatic_bone_orientation=False)
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE');rig.name='NativeHumanRig'
meshes=[o for o in bpy.data.objects if o.type=='MESH']
clips={'run':rig.animation_data.action};slots={'run':rig.animation_data.action_slot}
rig.animation_data.action=None
mapping={'idle':'idle.fbx','walk':'walking.fbx','sprint':'running.fbx','jump':'jump.fbx','seated':'Sitting Idle.fbx','drive':'Sitting Idle.fbx','reload':'shooter/reloading.fbx','hit':'shooter/hit reaction.fbx'}
# Optional native armed and seated clips acquired through the same character.
extra=src/'pistol'
if extra.exists():
 for key,filename in [('aim','pistol idle.fbx'),('aim_walk','pistol walk.fbx'),('aim_run','pistol run.fbx'),('aim_back','pistol walk backward.fbx')]:
  if (extra/filename).exists():mapping[key]='pistol/'+filename
for key,filename in mapping.items():
 before=set(bpy.data.objects)
 bpy.ops.import_scene.fbx(filepath=str(src/filename),automatic_bone_orientation=False)
 added=set(bpy.data.objects)-before;other=next(o for o in added if o.type=='ARMATURE')
 assert set(b.name for b in other.data.bones)==set(b.name for b in rig.data.bones),filename
 # Same original character and bone topology, verified below.
 # Skinless FBX exports can store a different reference pose. Verify exact
 # native segment lengths, then use Blender's visual bake of world-space
 # COPY_TRANSFORMS; do not copy curves between incompatible rest frames.
 differences=[]
 for bone in rig.data.bones:
  if bone.parent:
   ob=other.data.bones[bone.name]
   differences.append(abs((bone.head_local-bone.parent.head_local).length-(ob.head_local-ob.parent.head_local).length))
 assert max(differences)<.01,(filename,"native proportions differ")
 frame_start,frame_end=map(int,other.animation_data.action.frame_range)
 for pb in rig.pose.bones:
  pb.rotation_mode='QUATERNION'
  c=pb.constraints.new('COPY_TRANSFORMS');c.target=other;c.subtarget=pb.name;c.target_space='WORLD';c.owner_space='WORLD'
 for o in bpy.context.selected_objects:o.select_set(False)
 rig.select_set(True);bpy.context.view_layer.objects.active=rig
 bpy.ops.nla.bake(frame_start=frame_start,frame_end=frame_end,step=1,only_selected=False,visual_keying=True,clear_constraints=True,clear_parents=False,use_current_action=False,bake_types={'POSE'})
 clips[key]=rig.animation_data.action;slots[key]=rig.animation_data.action_slot
 clips[key].use_fake_user=True
 rig.animation_data.action=None
 for o in added:bpy.data.objects.remove(o,do_unlink=True)
# Alias names only for gameplay sockets. Keep bind transforms, vertex weights,
# mesh topology, motion rotations and authored textures exactly as supplied.
alias={'Hips':'pelvis','Spine':'spine','Spine1':'chest','Spine2':'upper_chest','Neck':'neck','Head':'head','LeftShoulder':'clavicle.l','RightShoulder':'clavicle.r','LeftArm':'upper_arm.l','RightArm':'upper_arm.r','LeftForeArm':'forearm.l','RightForeArm':'forearm.r','LeftHand':'hand.l','RightHand':'hand.r','LeftUpLeg':'thigh.l','RightUpLeg':'thigh.r','LeftLeg':'shin.l','RightLeg':'shin.r','LeftFoot':'foot.l','RightFoot':'foot.r','LeftToeBase':'toe.l','RightToeBase':'toe.r'}
names={b.name:alias.get(b.name.split(':')[-1],b.name.replace(':','_')) for b in rig.data.bones}
for old,new in names.items():
 rig.data.bones[old].name=new
 for mesh in meshes:
  group=mesh.vertex_groups.get(old)
  if group:group.name=new
report={'character':'Mixamo Josh','bones':len(rig.data.bones),'mesh_vertices':sum(len(o.data.vertices) for o in meshes),'clips':{},'source_hashes':{p.relative_to(src).as_posix():hashlib.file_digest(p.open('rb'),'sha256').hexdigest() for p in src.rglob('*.fbx')}}
for key,action in clips.items():
 action.name=key;action.use_fake_user=True
 for layer in action.layers:
  for strip in layer.strips:
   for bag in strip.channelbags:
    for curve in bag.fcurves:
     for old,new in names.items():curve.data_path=curve.data_path.replace('"'+old+'"','"'+new+'"')
     # Extract horizontal root travel only; preserve vertical bob and all rotations.
     if curve.data_path=='pose.bones["pelvis"].location' and curve.array_index in (0,2):
      for point in curve.keyframe_points:point.co.y=0;point.handle_left.y=0;point.handle_right.y=0
 rig.animation_data.action=action;rig.animation_data.action_slot=slots[key]
 bounds=[]
 for f in range(int(action.frame_range[0]),int(action.frame_range[1])+1):
  bpy.context.scene.frame_set(f);bpy.context.view_layer.update()
  dg=bpy.context.evaluated_depsgraph_get();lower=[];upper=[]
  for mesh in meshes:
   ev=mesh.evaluated_get(dg);m=ev.to_mesh()
   points=np.empty(len(m.vertices)*3,dtype=np.float32);m.vertices.foreach_get('co',points)
   matrix=np.asarray(ev.matrix_world,dtype=np.float32)
   world=points.reshape(-1,3)@matrix[:3,:3].T+matrix[:3,3]
   lower.append(world.min(axis=0));upper.append(world.max(axis=0));ev.to_mesh_clear()
  lo=np.asarray(lower).min(axis=0).astype(float).tolist();hi=np.asarray(upper).max(axis=0).astype(float).tolist()
  assert all(abs(c)<4 for c in lo+hi),(key,f,'exploded bounds')
  bounds.append({'frame':f,'min':lo,'max':hi})
 report['clips'][key]={'frames':list(action.frame_range),'seconds':(action.frame_range[1]-action.frame_range[0])/30,'bounds':bounds}
 rig.animation_data.action=None
 track=rig.animation_data.nla_tracks.new();track.name=key
 strip=track.strips.new(key,int(action.frame_range[0]),action);strip.action_slot=slots[key];track.mute=True
# FBX's legacy specular conversion is not PBR metal. Preserve the supplied
# albedo/normal images while removing false metallic fabric and glossy hair.
for material in bpy.data.materials:
 if material.node_tree:
  for node in material.node_tree.nodes:
   if node.type=='BSDF_PRINCIPLED':
    for key,value in [('Metallic',0.0),('Roughness',0.7 if 'hair' in material.name.lower() else 0.82)]:
     socket=node.inputs.get(key)
     if socket:
      for link in list(socket.links):material.node_tree.links.remove(link)
      socket.default_value=value
# Export the preserved native coordinate system.
for o in bpy.context.selected_objects:o.select_set(False)
rig.select_set(True)
for o in meshes:o.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.context.scene.frame_set(1)
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_yup=True,export_extras=False,export_image_format='AUTO',export_skins=True,export_animations=True)
bpy.ops.wm.save_as_mainfile(filepath=str(src/'player_native.blend'))
out.with_suffix('.report.json').write_text(json.dumps(report,indent=2)+'\n')
print('NATIVE_CONVERSION',json.dumps({'output_bytes':out.stat().st_size,'clips':list(clips),'bones':len(rig.data.bones)}))
