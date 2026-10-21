#!/usr/bin/env python3
"""Original 70 x 54 metre open-sided hawker pavilion, CPU-only Blender authoring.

Blender --background --factory-startup --threads 4 --python game/tools/build_pavilion.py
Coordinates: Blender X is ridge length, Y roof span, Z height. GLB exports Y-up.
No floor, walls, colliders or lights; hanging fixtures use restrained emission.
"""
from __future__ import annotations
import json
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_foliage import MeshBuilder, material, OUT, SOURCE_OUT


def beam(mesh, start, end, width, depth=None, index=0):
    start,end=Vector(start),Vector(end)
    axis=(end-start).normalized()
    helper=Vector((0,0,1)) if abs(axis.z)<.95 else Vector((0,1,0))
    side=axis.cross(helper).normalized()*width*.5
    up=axis.cross(side).normalized()*(depth or width)*.5
    points=[start-side-up,start+side-up,start+side+up,start-side+up,
            end-side-up,end+side-up,end+side+up,end-side+up]
    for face in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]:
        mesh.face([points[i] for i in face],index,[(0,0),(1,0),(1,(end-start).length),(0,(end-start).length)])


def roof_texture():
    size=512
    image=bpy.data.images.new("Authored_Weathered_Terracotta",size,size)
    rng=random.Random(8112)
    colors=[[rng.uniform(.78,1.16) for x in range(8)] for y in range(8)]
    pixels=[]
    for y in range(size):
        for x in range(size):
            tx,ty=x//64,y//64
            row=y%64
            dust=.04*math.sin(x*.131+y*.021)+rng.uniform(-.018,.018)
            lip=.80 if row<3 else 1.0
            warmth=colors[ty][tx]*lip
            pixels.extend((min(1,.48*warmth+dust),max(0,.205*warmth+dust*.65),max(0,.11*warmth+dust*.3),1))
    image.pixels.foreach_set(pixels)
    image.filepath_raw=str(OUT/"hawker_pavilion_terracotta.png")
    image.file_format="PNG"
    image.save()
    image.pack()
    return image


def emission_material():
    mat=material("Hawker_WarmLampGlass",(.8,.55,.23),.38)
    node=mat.node_tree.nodes.get("Principled BSDF")
    node.inputs["Emission Color"].default_value=(1,.56,.20,1)
    node.inputs["Emission Strength"].default_value=1.7
    return mat


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    SOURCE_OUT.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    structure, roof, trim, details=MeshBuilder(),MeshBuilder(),MeshBuilder(),MeshBuilder()
    steel=material("Hawker_OxideRedPaintedSteel",(.22,.055,.025),.69)
    timber=material("Hawker_AgedTimber",(.14,.062,.026),.85)
    darkmetal=material("Hawker_DarkFixtureMetal",(.042,.049,.044),.53)
    gutter=material("Hawker_WeatheredGutter",(.15,.17,.14),.63)
    concrete=material("Hawker_ColumnFooting",(.32,.30,.25),.92)
    tile=material("Hawker_WeatheredTerracotta",(.48,.205,.11),.88,True,roof_texture())
    # Roof corrugation is real geometry. Horizontal tile rows are textured.
    width,length,eave,ridge=54.0,70.0,5.5,9.0
    def roof_height(y):
        return ridge-(ridge-eave)*abs(y)/(width*.5)
    for side in [-1,1]:
        for ix in range(350):
            x0=-length*.5+ix*.2
            x1=x0+.2
            wave0=.052*math.cos((x0+35)*math.pi/.2)
            wave1=.052*math.cos((x1+35)*math.pi/.2)
            for iy in range(12):
                y0=side*(iy*width*.5/12)
                y1=side*((iy+1)*width*.5/12)
                vertices=[(x0,y0,roof_height(y0)+wave0),(x1,y0,roof_height(y0)+wave1),
                          (x1,y1,roof_height(y1)+wave1),(x0,y1,roof_height(y1)+wave0)]
                coords=[((x0+35)/3.2,abs(y0)/4),((x1+35)/3.2,abs(y0)/4),((x1+35)/3.2,abs(y1)/4),((x0+35)/3.2,abs(y1)/4)]
                if side<0:
                    vertices.reverse(); coords.reverse()
                roof.face(vertices,0,coords)
    # Column footprints avoid the occupied stall row at Godot z=-20 and package (-5,-8).
    for x in [-30,-20,-10,0,10,20,30]:
        for y in [-25.8,25.8]:
            beam(structure,(x,y,.15),(x,y,5.42),.23,.23,0)
            beam(trim,(x,y,0),(x,y,.18),.55,.55,2)
            for dx in [-1.5,1.5]:
                beam(structure,(x,y,4.2),(x+dx,y,5.45),.13,.13,0)
        # Low tie is still 5.25 m above walking space; no human-height crossbar.
        beam(structure,(x,-26.3,5.25),(x,26.3,5.25),.19,.32,0)
        for side in [-1,1]:
            beam(structure,(x,0,8.83),(x,side*26.7,5.32),.2,.30,1)
            for j in range(6):
                y0=side*j*4.4
                y1=side*(j+1)*4.4
                if j%2:
                    start=(x,y0,5.35); end=(x,y1,roof_height(y1)-.23)
                else:
                    start=(x,y0,roof_height(y0)-.23); end=(x,y1,5.35)
                beam(structure,start,end,.105,.13,0)
            for y in [side*8.8,side*17.6]:
                beam(structure,(x,y,5.35),(x,y,roof_height(y)-.20),.095,.095,0)
    for x in [-30,-10,10,30]:
        beam(structure,(x,0,.18),(x,0,8.85),.30,.30,0)
        beam(trim,(x,0,0),(x,0,.18),.60,.60,2)
        for side in [-1,1]:
            beam(structure,(x,0,6.6),(x,side*3.2,8.35),.15,.15,0)
    # Longitudinal roof purlins make the ceiling read as assembled construction.
    for y in [-25.5,-21,-16.5,-12,-7.5,-3,0,3,7.5,12,16.5,21,25.5]:
        beam(structure,(-35,y,roof_height(y)-.19),(35,y,roof_height(y)-.19),.15,.18,1)
    for y in [-26.9,26.9]:
        beam(trim,(-35,y,5.45),(35,y,5.45),.28,.32,0)
        beam(trim,(-35,y,5.32),(35,y,5.32),.18,.13,1)
    for x in [-35,35]:
        beam(trim,(x,-27,5.48),(x,0,9.04),.25,.21,0)
        beam(trim,(x,0,9.04),(x,27,5.48),.25,.21,0)
        for y in [-25.8,25.8]:
            beam(structure,(x,y,0),(x,y,5.45),.23,.23,0)
    # Continuous rounded ridge cap and visible drain downpipes.
    trim.tube([(-35.2,0,9.03),(35.2,0,9.03)],[.17,.17],8,0)
    for x in [-30,0,30]:
        for y in [-26.6,26.6]:
            trim.tube([(x,y,.1),(x,y,4.9),(x,y+(.3 if y>0 else -.3),5.35)],[.07,.07,.07],8,1)
    # Industrial pendants, with actual shades and luminous undersides.
    for x in [-30,-20,-10,0,10,20,30]:
        for y in [-17,17]:
            z=4.9
            details.tube([(x,y,z+.38),(x,y,roof_height(y)-.2)],[.018,.018],5,0)
            details.tube([(x,y,z),(x,y,z+.28)],[.38,.13],12,0)
            details.tube([(x,y,z-.035),(x,y,z+.012)],[.30,.30],12,1)
    objects=[structure.object("Hawker_ColumnsAndExposedTrusses",[steel,timber]),roof.object("Hawker_TerracottaPitchedRoof",[tile],True),trim.object("Hawker_RoofFasciaGuttersAndFootings",[timber,gutter,concrete],True),details.object("Hawker_HangingLampFixtures",[darkmetal,emission_material()],True)]
    for x in [-25,-15,-5,5,15,25]:
        for y in [-9,9]:
            fan=MeshBuilder()
            fan.tube([(x,y,4.55),(x,y,roof_height(y)-.24)],[.024,.024],6,0)
            fan.tube([(x,y,4.45),(x,y,4.64)],[.16,.13],10,0)
            for blade in range(5):
                angle=blade*math.tau/5+.18
                d=Vector((math.cos(angle),math.sin(angle),0))
                s=Vector((-d.y,d.x,0))
                center=Vector((x,y,4.5))
                fan.face([center+d*.14-s*.08,center+d*1.12-s*.12+Vector((0,0,.035)),center+d*1.22+s*.14+Vector((0,0,.035)),center+d*.15+s*.08],1)
            obj=fan.object(f"Hawker_Fan_{x}_{y}",[darkmetal,material(f"Hawker_FanBlade_{x}_{y}",(.23,.24,.20),.53,True)],True)
            objects.append(obj)
    bpy.context.view_layer.update()
    for obj in objects:
        obj["authoring"]="Original deterministic Blender mesh, GPT-6 Astra wave 2"
        obj["units"]="metres; centre ground origin; GLB exports Y-up"
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_OUT/"hawker_pavilion.blend"),check_existing=False)
    bpy.ops.export_scene.gltf(filepath=str(OUT/"hawker_pavilion.glb"),export_format="GLB",use_selection=True,export_yup=True,export_apply=True,export_materials="EXPORT",export_texcoords=True,export_normals=True)
    bounds=[obj.matrix_world@Vector(v) for obj in objects for v in obj.bound_box]
    report={"asset":"hawker_pavilion","dimensions_blender_xyz_m":[round(max(p[i] for p in bounds)-min(p[i] for p in bounds),3) for i in range(3)],"triangles":sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),"objects":len(objects),"clearance_m":{"eaves":5.5,"ridge":9,"fan_bottom":4.45,"truss_tie":5.09},"floor":False,"walls":False,"collisions":False,"source":"game/tools/build_pavilion.py","helper":"game/tools/build_foliage.py","seed":8112}
    (OUT/"hawker_pavilion_manifest.json").write_text(json.dumps(report,indent=2)+"\n")
    print("PAVILION_RESULT "+json.dumps(report),flush=True)


if __name__=="__main__":
    main()
