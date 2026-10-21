#!/usr/bin/env python3
"""Original interior kits for the Singapore slice. CPU-only Blender authoring.

All coordinates in authoring helpers use Godot's metres: X right, Y up, Z front.
Blender source files stay in art/source, outside the Godot import tree.
"""
from __future__ import annotations
import json
import math
import random
from pathlib import Path
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/"game/assets/authored"
SOURCE=ROOT/"art/source"
M={}


def pos(p): return (p[0],-p[2],p[1])


def material(name,color,rough=.7,metal=0,emission=0):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    node=mat.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value=(*color,1)
    node.inputs["Roughness"].default_value=rough
    node.inputs["Metallic"].default_value=metal
    if emission:
        node.inputs["Emission Color"].default_value=(*color,1)
        node.inputs["Emission Strength"].default_value=emission
    mat.diffuse_color=(*color,1)
    return mat


def setup():
    global M
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M={name:material("Interior_"+name,*args) for name,args in {
        "plaster":((.62,.58,.47),.94),"tile":((.33,.36,.32),.83),
        "trim":((.055,.115,.105),.65),"wood":((.24,.105,.043),.81),
        "wood_edge":((.12,.049,.018),.85),"steel":((.19,.22,.22),.47,.5),
        "darksteel":((.045,.058,.059),.6,.35),"fabric":((.12,.22,.20),.95),
        "cushion":((.34,.32,.22),.94),"rubber":((.022,.025,.024),.91),
        "glass":((.09,.18,.21),.22,.18),"white":((.79,.76,.65),.7),
        "red":((.48,.055,.029),.65),"gold":((.62,.33,.035),.66),
        "green":((.08,.28,.09),.7),"blue":((.035,.19,.31),.64),
        "light":((1,.73,.38),.4,0,2),"coollight":((.6,.83,1),.4,0,1.3)
    }.items()}
    atlas=OUT/"packaging_atlas.png"
    if atlas.exists():
        m=material("Interior_original_packaging",(1,1,1),.72)
        image=bpy.data.images.load(str(atlas),check_existing=True)
        tex=m.node_tree.nodes.new("ShaderNodeTexImage");tex.image=image
        m.node_tree.links.new(tex.outputs["Color"],m.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
        M["packaging"]=m


def label_package(obj,index):
    if "packaging" not in M:return
    obj.data.materials.clear();obj.data.materials.append(M["packaging"])
    uv=obj.data.uv_layers.active or obj.data.uv_layers.new(name="UVMap")
    col=index%4;row=(index//4)%4
    coords=[v.co for v in obj.data.vertices]
    lo=[min(v[i] for v in coords) for i in range(3)]
    hi=[max(v[i] for v in coords) for i in range(3)]
    cylinder="_Tin" in obj.name
    for poly in obj.data.polygons:
        half=0
        if cylinder:
            half=1 if sum(uv.data[k].uv.x for k in poly.loop_indices)/len(poly.loop_indices)>=.5 else 0
        for loopid in poly.loop_indices:
            if cylinder:
                u,v=uv.data[loopid].uv
                u=max(0,min(1,(u-.5*half)*2))
            else:
                point=obj.data.vertices[obj.data.loops[loopid].vertex_index].co
                axis=max(range(3),key=lambda k:abs(poly.normal[k]))
                ua,va=(0,2) if axis==1 else ((1,2) if axis==0 else (0,1))
                u=(point[ua]-lo[ua])/max(hi[ua]-lo[ua],1e-6)
                v=(point[va]-lo[va])/max(hi[va]-lo[va],1e-6)
            uv.data[loopid].uv=((col+.012+u*.976)/4,(3-row+.012+v*.976)/4)


def finish(obj,name,mat):
    obj.name=name
    obj.data.materials.append(M[mat])
    return obj


def box(name,center,size,mat,bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos(center))
    obj=bpy.context.object;obj.dimensions=(size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        modifier=obj.modifiers.new("AuthoredRoundedEdges","BEVEL")
        modifier.width=min(bevel,min(size)*.23);modifier.segments=2
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        modifier=obj.modifiers.new("WeightedSurfaceNormals","WEIGHTED_NORMAL")
        modifier.keep_sharp=True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return finish(obj,name,mat)


def cylinder(name,center,radius,height,mat,vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=height,location=pos(center))
    obj=finish(bpy.context.object,name,mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth=len(polygon.vertices)==4
    return obj


def torus(name,center,major,minor,mat,vertical=False):
    bpy.ops.mesh.primitive_torus_add(major_segments=20,minor_segments=6,location=pos(center),major_radius=major,minor_radius=minor)
    obj=finish(bpy.context.object,name,mat)
    if vertical:obj.rotation_euler.x=math.pi*.5
    for polygon in obj.data.polygons:polygon.use_smooth=True
    return obj


def text(name,content,center,size,mat="white"):
    curve=bpy.data.curves.new(name,"FONT");curve.body=content;curve.align_x="CENTER";curve.align_y="CENTER";curve.size=size;curve.extrude=.0015;curve.bevel_depth=.0005;curve.resolution_u=3
    obj=bpy.data.objects.new(name,curve);bpy.context.collection.objects.link(obj)
    obj.location=pos(center);obj.rotation_euler.x=math.pi*.5
    obj.data.materials.append(M[mat]);bpy.context.view_layer.objects.active=obj
    obj.select_set(True);bpy.ops.object.convert(target="MESH");obj.select_set(False)
    return obj


def leg_table(name,x,z,width,depth,height=.78):
    box(name+"_Top",(x,height-.045,z),(width,.09,depth),"wood",.045)
    box(name+"_Apron",(x,height-.17,z),(width-.12,.18,depth-.12),"wood_edge",.018)
    for dx in [-1,1]:
        for dz in [-1,1]:
            box(name+"_Leg",(x+dx*(width*.5-.12),(height-.2)*.5,z+dz*(depth*.5-.12)),(.075,height-.2,.075),"darksteel",.015)


def chair(name,x,z):
    box(name+"_Seat",(x,.49,z),(.57,.11,.58),"fabric",.07)
    box(name+"_Back",(x,.91,z+.25),(.57,.70,.11),"fabric",.07)
    for dx in [-.22,.22]:
        for dz in [-.22,.22]:box(name+"_Leg",(x+dx,.23,z+dz),(.045,.46,.045),"darksteel",.008)


def bottle(name,x,y,z,color="green"):
    cylinder(name+"_Body",(x,y+.12,z),.055,.24,color,10)
    cylinder(name+"_Neck",(x,y+.275,z),.025,.09,color,10)
    cylinder(name+"_Cap",(x,y+.326,z),.029,.025,"white",10)
    cylinder(name+"_Label",(x,y+.13,z),.056,.105,"white",10)


def shelving(name,x,z,width=2.5,height=1.8,depth=.65,stock=True):
    for dx in [-width*.5,width*.5]:
        for dz in [-depth*.45,depth*.45]:box(name+"_Upright",(x+dx,height*.5,z+dz),(.055,height,.055),"darksteel",.008)
    for tier,y in enumerate([.17,.63,1.09,1.55]):
        box(name+"_Shelf",(x,y,z),(width+.08,.055,depth),"white",.012)
        box(name+"_PriceStrip",(x,y+.025,z+depth*.5+.008),(width,.055,.022),"gold",.003)
        if stock:
            for j in range(max(3,int(width/.23))):
                xx=x-width*.45+j*(width*.9/max(1,int(width/.23)-1))
                if tier%2==0:
                    tin=cylinder(name+"_Tin",(xx,y+.15,z),.075,.24,["red","gold","blue","green"][j%4],16)
                    label_package(tin,(j+tier*3)%16)
                    cylinder(name+"_TinRim",(xx,y+.275,z),.077,.015,"steel",12)
                else:
                    pack=box(name+"_Pack",(xx,y+.16,z),(.15,.27,.20),["white","red","gold","blue"][j%4],.015)
                    label_package(pack,(j+tier*3)%16)


def cabinet(name,x,z,width=2.5,height=2.1):
    box(name+"_Case",(x,height*.5,z),(width,height,.7),"trim",.04)
    for j in range(3):
        xx=x+(j-1)*width/3
        box(name+"_Door",(xx,height*.5,z+.365),(width/3-.045,height-.09,.045),"wood",.018)
        box(name+"_Handle",(xx+width/9,height*.55,z+.41),(.028,.22,.035),"steel",.01)
        for y in [.12,height-.12]:box(name+"_Hinge",(xx-width/7,y,z+.4),(.045,.1,.025),"darksteel",.004)


def fixture(name,x,y,z,length=1.4):
    box(name+"_Housing",(x,y,z),(length,.12,.28),"darksteel",.035)
    box(name+"_Diffuser",(x,y-.075,z),(length-.15,.04,.19),"light",.018)


def envelope(name,width,depth,height,door):
    box(name+"_Floor",(0,-.05,0),(width,.10,depth),"tile",.012)
    box(name+"_BackWall",(0,height*.5,-depth*.5),(width,height,.23),"plaster",.045)
    for sign in [-1,1]:
        box(name+"_SideWall",(sign*width*.5,height*.5,0),(.23,height,depth),"plaster",.045)
        side=(width-door)*.5
        box(name+"_FrontPier",(sign*(door*.5+side*.5),height*.5,depth*.5),(side,height,.23),"plaster",.045)
        box(name+"_DoorJamb",(sign*(door*.5+.025),1.38,depth*.5+.04),(.12,2.76,.32),"trim",.02)
    box(name+"_EntryLintel",(0,(height+2.75)*.5,depth*.5),(door,height-2.75,.23),"plaster",.035)
    box(name+"_RoofSlab",(0,height+.10,0),(width+.4,.20,depth+.4),"trim",.035)
    for side in [-1,1]:
        box(name+"_RoofParapet",(side*(width*.5+.1),height+.35,0),(.15,.45,depth+.5),"plaster",.025)
        box(name+"_Skirting",(side*(width*.5-.14),.10,0),(.055,.20,depth-.2),"trim",.008)
    box(name+"_BackSkirting",(0,.1,-depth*.5+.14),(width-.2,.2,.055),"trim",.008)
    box(name+"_FrontCanopy",(0,2.9,depth*.5+.50),(width+.6,.13,1.2),"trim",.035)
    for x in [-width*.5+.3,width*.5-.3]:
        box(name+"_CanopyBracket",(x,2.66,depth*.5+.2),(.06,.5,.06),"steel",.009)


def safe_room():
    leg_table("SafeDesk",-3.6,-3.5,2.8,1.1,.8)
    chair("SafeDeskChair",-3.6,-2.3)
    box("LaptopKeyboard",(-3.65,.825,-3.2),(.62,.035,.42),"darksteel",.018)
    box("LaptopScreen",(-3.65,1.08,-3.43),(.64,.46,.035),"darksteel",.018)
    box("LaptopDisplay",(-3.65,1.08,-3.405),(.57,.38,.01),"glass",.005)
    text("LaptopHeading","RELAY",(-3.65,1.12,-3.39),.075,"coollight")
    for j in range(7):
        for k in range(3):box("KeyboardKey",(-3.88+j*.075,.848,-3.31+k*.07),(.055,.006,.045),"steel",.002)
    for j in range(3):box("DeskBook",(-2.65,.84+j*.065,-3.4),(.31,.055,.43),["red","gold","white"][j],.008)
    cylinder("Mug",(-4.65,.93,-3.2),.07,.17,"white",18)
    torus("MugHandle",(-4.56,.93,-3.2),.055,.012,"white",True)
    cabinet("SafeStorage",4.3,-4.15,2.6,2.2)
    box("SofaBase",(2.2,.25,2.95),(3.1,.38,1.1),"wood_edge",.07)
    box("SofaBack",(2.2,.85,3.40),(3.2,1.0,.25),"fabric",.10)
    for x in [.6,3.8]:box("SofaArm",(x,.64,2.95),(.25,.65,1.12),"fabric",.09)
    for x in [1.18,2.2,3.22]:
        box("SofaSeatCushion",(x,.52,2.93),(.96,.23,.89),"cushion",.10)
        box("SofaBackCushion",(x,.96,3.22),(.94,.62,.19),"fabric",.08)
    box("WovenRug",(1.5,.012,1.5),(5.2,.018,4.2),"wood",.006)
    for j in range(19):box("RugWeave",(-1+j*.28,.024,1.5),(.035,.006,4.05),"cushion",.002)
    leg_table("CoffeeTable",1.5,.7,1.8,.85,.44)
    for j in range(2):box("CoffeeBook",(1.3,.48+j*.045,.7),(.35,.04,.48),["white","blue"][j],.008)
    box("SafeNoticeFrame",(.2,2.1,-4.73),(2.5,1.25,.075),"wood_edge",.03)
    box("SafeNoticePaper",(.2,2.1,-4.68),(2.35,1.1,.012),"white",.006)
    text("SafeRoomTitle","HARBOUR RELAY",(.2,2.4,-4.66),.23,"trim")
    text("SafeRoomNotice","REST  /  PLAN  /  RETURN",(.2,1.99,-4.66),.11,"trim")
    fixture("SafeDeskLight",-3.6,2.8,-3.4,1.5)


def shop():
    envelope("Shop",14,10,3.65,3.2)
    box("ShopSignBacking",(0,3.24,5.15),(10.7,.62,.16),"red",.035)
    text("ShopName","ORCHARD DAILY",(0,3.27,5.25),.42)
    text("ShopTagline","GROCERIES  -  DRINKS  -  EVERYDAY GOODS",(0,2.99,5.26),.105)
    for x in [-4.7,4.7]:
        box("ShopFrontWindow",(x,1.55,5.14),(2.5,1.65,.035),"glass",.02)
        for dx in [-1.29,1.29]:box("WindowFrame",(x+dx,1.55,5.18),(.065,1.78,.09),"trim",.009)
        for y in [.69,2.41]:box("WindowFrame",(x,y,5.18),(2.64,.065,.09),"trim",.009)
    for x in [-3.1,3.1]:shelving("ShopIsland",x,-.5,2.35,1.85,.8)
    shelving("BackDryGoods",1.7,-4.35,4.5,1.85,.65)
    box("CoolerCabinet",(-4.6,1.16,-4.35),(3.1,2.32,.75),"white",.07)
    for j in [-1,0,1]:
        x=-4.6+j*1.0
        box("CoolerGlassDoor",(x,1.2,-3.95),(.91,2.12,.045),"glass",.025)
        box("CoolerDoorPull",(x+.34,1.2,-3.9),(.035,.6,.035),"steel",.012)
        for tier in range(3):
            for k in range(4):bottle("DisplayBottle",x-.31+k*.2,.42+tier*.48,-3.89,["green","blue","gold"][tier])
    text("CoolerLabel","COLD DRINKS",(-4.6,2.48,-3.9),.17,"gold")
    box("CheckoutCabinet",(4.65,.48,2.5),(3.1,.96,1.05),"trim",.06)
    box("CheckoutTop",(4.65,1.0,2.5),(3.25,.095,1.13),"wood",.04)
    box("CashRegister",(4.1,1.13,2.5),(.48,.22,.42),"darksteel",.035)
    box("RegisterDisplay",(4.1,1.32,2.4),(.37,.19,.07),"glass",.02)
    text("CheckoutWord","CHECKOUT",(4.65,.62,3.04),.21)
    for j in range(3):bottle("CheckoutBottle",5.25+j*.2,1.06,2.55,["red","blue","gold"][j])
    for x in [-3.1,3.1]:text("AisleLabel","PANTRY" if x<0 else "SNACKS",(x,2.03,-.02),.18,"gold")
    for x in [-4,0,4]:fixture("ShopCeilingFixture",x,3.48,0,1.65)


def workshop():
    envelope("Workshop",20,12,4.3,4.8)
    box("WorkshopSignBacking",(0,3.46,6.15),(12.3,.85,.18),"trim",.04)
    text("WorkshopName","HARBOUR MOTOR WORKS",(0,3.53,6.26),.39,"gold")
    text("WorkshopServices","SERVICING  /  TYRES  /  REPAIRS",(0,3.18,6.27),.14)
    for x in [-8.5,8.5]:
        for y in [1.2,1.7,2.2]:box("VentLouvre",(x,y,6.15),(1.5,.22,.16),"darksteel",.025)
    leg_table("MainWorkbench",0,-4.9,7.0,1.25,.95)
    box("PegboardFrame",(0,2.05,-5.71),(7.1,1.75,.12),"wood_edge",.035)
    box("Pegboard",(0,2.05,-5.62),(6.9,1.58,.055),"wood",.02)
    for x in range(-15,16):
        for y in [1.5,1.8,2.1,2.4,2.7]:
            box("PegboardHole",(x*.2,y,-5.58),(.018,.018,.009),"darksteel",.002)
    for i in range(6):
        x=-2.4+i*.85
        box("HangingToolShaft",(x,2.12,-5.53),(.045,.62,.04),"steel",.008)
        torus("HangingSpannerRing",(x,2.48,-5.53),.09,.023,"steel",True)
        box("SpannerJaw",(x,1.78,-5.52),(.12,.09,.06),"steel",.02)
    for i in range(5):bottle("WorkshopOil",-2.5+i*.32,1.0,-4.6,["red","gold","blue"][i%3])
    shelving("WorkshopPartsRack",-7.7,-3.8,3.0,1.85,.8)
    cabinet("WorkshopLockers",7.5,-5.2,3.0,2.25)
    box("ToolChest",(5.1,.7,-3.2),(1.5,1.1,.74),"red",.06)
    for j in range(5):
        y=.28+j*.19
        box("ToolDrawer",(5.1,y,-2.81),(1.38,.15,.04),"red",.016)
        box("ToolDrawerPull",(5.1,y,-2.76),(.95,.025,.04),"steel",.008)
    for x in [4.55,5.65]:
        for z in [-3.45,-2.95]:torus("ChestCaster",(x,.14,z),.08,.035,"rubber",True)
    for j in range(3):
        torus("TyreStack",(-8,.18+j*.27,3),.36,.145,"rubber")
        cylinder("TyreRim",(-8,.18+j*.27,3),.19,.12,"steel",20)
    for x in [-2.0,2.0]:
        box("ServiceBayMark",(x,.012,1.1),(.075,.014,5.6),"gold",.002)
    for z in [-1.7,3.9]:box("ServiceBayMark",(0,.012,z),(4.05,.014,.075),"gold",.002)
    # Small bench vice with separately modeled jaws, screw and handle.
    box("ViceBase",(1.85,1.05,-4.9),(.45,.13,.32),"blue",.025)
    for x in [1.7,2.0]:box("ViceJaw",(x,1.2,-4.9),(.09,.25,.34),"steel",.02)
    box("ViceScrew",(1.8,1.14,-4.9),(.62,.05,.05),"steel",.01)
    for x in [-6,0,6]:fixture("WorkshopFixture",x,4.1,0,2.0)
    text("WorkshopSafety","KEEP THE SERVICE BAY CLEAR",(0,3.25,-5.68),.23,"white")


def save(name):
    bpy.ops.object.select_all(action="DESELECT")
    objects=[o for o in bpy.context.scene.objects if o.type=="MESH"]
    for obj in objects:
        obj["authoring"]="Original Blender geometry; GPT-6 Astra wave 2"
        obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    # Retain individual named components in the source; consolidate only export.
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+".blend")),check_existing=False)
    bpy.ops.object.join()
    obj=bpy.context.object;obj.name=name
    # Runtime attaches collision shapes relative to the prefab's ground-centre
    # origin, so the exported mesh node must not inherit the first component's
    # nonzero location when the many components are joined.
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    obj.data.validate(clean_customdata=False)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")),export_format="GLB",use_selection=True,export_yup=True,export_apply=True,export_materials="EXPORT",export_normals=True)
    bounds=[obj.matrix_world@Vector(v) for v in obj.bound_box]
    result={"asset":name,"authoring_objects":len(objects),"triangles":sum(len(p.vertices)-2 for p in obj.data.polygons),"dimensions_blender_xyz":[max(v[i] for v in bounds)-min(v[i] for v in bounds) for i in range(3)],"source":"game/tools/build_interiors.py","rights":"Original authored geometry and plain English fictional signage"}
    print("INTERIOR_RESULT "+json.dumps(result),flush=True)
    return result


def main():
    OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)
    reports=[]
    for name,builder in [("interior_safe_furnishings",safe_room),("interior_convenience_shop",shop),("interior_workshop",workshop)]:
        setup();builder();reports.append(save(name))
    (OUT/"interior_manifest.json").write_text(json.dumps(reports,indent=2)+"\n")


if __name__=="__main__":main()
