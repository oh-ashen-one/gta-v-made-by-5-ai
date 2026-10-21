#!/usr/bin/env python3
"""Original tropical skyline modules, authored as real facade geometry in Blender.
Run Blender 4.5+ --background --factory-startup --threads 4 --python this_file.
Background scenery, not a claim of accessible tower interiors.
"""
import bpy, math, random, json
from pathlib import Path
from collections import defaultdict
ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/'game/assets/authored'; SRC=ROOT/'art/source'; OUT.mkdir(parents=True,exist_ok=True);SRC.mkdir(exist_ok=True)
random.seed(20261021)
def material(name,c,rough=.6,metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;return m
class Builder:
 def __init__(self):self.data=defaultdict(lambda:[[],[]])
 def box(self,mat,pos,size):
  v,f=self.data[mat.name];k=len(v);x,y,z=pos;a,b,c=[s*.5 for s in size]
  v.extend([(x+sx*a,y+sy*b,z+sz*c) for sx,sy,sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]])
  f.extend([tuple(k+i for i in q) for q in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]])
 def finish(self):
  for name,(v,f) in self.data.items():
   me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.materials.append(bpy.data.materials[name]);me.update();ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
manifest=[]
for variant,(w,d,h) in enumerate([(26,24,98),(22,34,78),(32,22,58),(24,24,116)]):
 bpy.ops.wm.read_factory_settings(use_empty=True);b=Builder()
 shell=material('warm_mineral_stone',(.52,.53,.49),.86)
 edge=material('champagne_aluminium',(.31,.35,.36),.38,.6)
 dark=material('shadow_recess',(.032,.048,.061),.55)
 glasses=[material('glass_'+str(i),(.07+i*.018,.14+i*.022,.19+i*.022),.19,.5) for i in range(5)]
 light=material('interior_shade',(.47,.40,.27),.6)
 green=material('roof_garden',(.08,.19,.075),.95)
 b.box(shell,(0,0,2.2),(w+8,d+8,4.4))
 for sx in [-1,1]:
  for j in range(5):b.box(dark,(sx*(w+8)/2, -d*.42+j*d*.21,2),(0.1,d*.16,2.8))
 # Main envelope, inset behind facade; all facades have dimensional mullions.
 b.box(dark,(0,0,h*.5+4.4),(w-.2,d-.2,h))
 floors=int(h/3.5)
 for floor in range(floors):
  z=4.4+floor*3.5
  b.box(edge,(0,0,z),(w+.5,d+.5,.24))
  for axis in range(2):
   width=w if axis==0 else d; other=d if axis==0 else w
   windows=int(width/2.5)
   for side in [-1,1]:
    for j in range(windows):
     u=-width*.5+(j+.5)*width/windows
     face=side*(other*.5+.09)
     pos=(u,face,z+1.75) if axis==0 else (face,u,z+1.75)
     size=(width/windows-.16,.13,3.14) if axis==0 else (.13,width/windows-.16,3.14)
     mat=light if random.random()<.07 else glasses[random.randrange(5)]
     b.box(mat,pos,size)
     mull=(u-width/windows*.5,face,z+1.75) if axis==0 else (face,u-width/windows*.5,z+1.75)
     b.box(edge,mull,(.09,.28,3.5) if axis==0 else (.28,.09,3.5))
  if floor in [5,12,20] and floor<floors-2:
   b.box(shell,(0,0,z+.15),(w+2.5,d+2.5,.6))
   for side in [-1,1]:
    b.box(green,(side*(w*.5+.7),0,z+.7),(1.1,d,.75))
    b.box(green,(0,side*(d*.5+.7),z+.7),(w,1.1,.75))
 # Original stepped crown and rooftop service enclosure.
 for j in range(3):
  ww=w*(.70-j*.15);dd=d*(.70-j*.15)
  b.box(shell,(0,0,h+4.8+j*2.7),(ww,dd,2.4))
  b.box(edge,(0,0,h+6.1+j*2.7),(ww+.4,dd+.4,.18))
 b.box(edge,(w*.15,d*.1,h+15),(.35,.35,11))
 b.finish();name='skyline_'+str(variant)
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
 bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True,export_apply=True)
 tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH')
 manifest.append({'file':name+'.glb','author':'GPT-6 Astra wave2 original geometry','triangles':tris,'footprint':[w+8,d+8],'height':h+20,'rights':'MIT original authored mesh'})
(OUT/'architecture_manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps(manifest))
