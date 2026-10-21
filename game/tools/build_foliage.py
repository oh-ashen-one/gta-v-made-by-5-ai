#!/usr/bin/env python3
"""Original deterministic foliage authored in Blender; metres, ground origin.

Run Blender 4.5 LTS --background --factory-startup --threads 4 --python FILE.
No rendering, external sources, network access or paid generation is used.
The saved .blend files preserve named bark/foliage meshes and materials.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "authored"
SOURCE_OUT = ROOT.parent / "art" / "source"
TAU = math.tau


class MeshBuilder:
    def __init__(self):
        self.vertices, self.faces, self.materials, self.uvs = [], [], [], []

    def face(self, vertices, material=0, uvs=None):
        first = len(self.vertices)
        self.vertices.extend(tuple(v) for v in vertices)
        self.faces.append(tuple(range(first, first + len(vertices))))
        self.materials.append(material)
        self.uvs.append(uvs or [(0, 0)] * len(vertices))

    def tube(self, points, radii, sides=7, material=0):
        points = [Vector(p) for p in points]
        rings = []
        distance = 0.0
        lengths = []
        for i, (point, radius) in enumerate(zip(points, radii)):
            if i:
                distance += (point - points[i - 1]).length
            lengths.append(distance)
            tangent = points[min(i + 1, len(points)-1)] - points[max(i-1, 0)]
            tangent.normalize()
            helper = Vector((0, 0, 1)) if abs(tangent.z) < .9 else Vector((1, 0, 0))
            axis_x = tangent.cross(helper).normalized()
            axis_y = tangent.cross(axis_x).normalized()
            rings.append([point + radius * (math.cos(TAU*j/sides)*axis_x + math.sin(TAU*j/sides)*axis_y) for j in range(sides)])
        for i in range(len(rings)-1):
            for j in range(sides):
                k = (j+1) % sides
                self.face([rings[i][j], rings[i][k], rings[i+1][k], rings[i+1][j]], material,
                          [(j/sides, lengths[i]), ((j+1)/sides, lengths[i]), ((j+1)/sides, lengths[i+1]), (j/sides, lengths[i+1])])
        self.face(list(reversed(rings[0])), material)
        self.face(rings[-1], material)

    def leaf(self, center, direction, length, width, rng, material=0, fold=.10):
        """A tapered leaf with a raised midrib; four real triangles, no alpha card."""
        center, axis = Vector(center), Vector(direction).normalized()
        helper = Vector((0, 0, 1)) if abs(axis.z) < .9 else Vector((0, 1, 0))
        side = axis.cross(helper).normalized()
        normal = side.cross(axis).normalized()
        # Vary leaf roll rather than creating a single horizontal leaf sheet.
        angle = rng.uniform(-.8, .8)
        side, normal = side*math.cos(angle) + normal*math.sin(angle), normal*math.cos(angle)-side*math.sin(angle)
        base = center-axis*length*.45
        tip = center+axis*length*.55
        left = center+side*width*.5
        right = center-side*width*.5
        ridge = center+normal*width*fold
        self.face([base, left, ridge], material, [(0.5,0),(0,.45),(.5,.45)])
        self.face([left, tip, ridge], material, [(0,.45),(.5,1),(.5,.45)])
        self.face([tip, right, ridge], material, [(.5,1),(1,.45),(.5,.45)])
        self.face([right, base, ridge], material, [(1,.45),(.5,0),(.5,.45)])

    def small_leaf(self, center, direction, length, width, rng, material=0):
        """Two folded triangles let a mature crown contain many smaller leaves."""
        center,axis=Vector(center),Vector(direction).normalized()
        side=axis.cross(Vector((0,0,1))).normalized()
        normal=side.cross(axis).normalized()
        roll=rng.uniform(-.9,.9)
        side,normal=side*math.cos(roll)+normal*math.sin(roll),normal*math.cos(roll)-side*math.sin(roll)
        base=center-axis*length*.45
        tip=center+axis*length*.55
        left=center+side*width*.5-normal*width*.12
        right=center-side*width*.5-normal*width*.12
        self.face([base,left,tip],material,[(.5,0),(0,.45),(.5,1)])
        self.face([base,tip,right],material,[(.5,0),(.5,1),(1,.45)])

    def object(self, name, materials, smooth=False):
        mesh = bpy.data.meshes.new(name + "_Mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        for mat in materials:
            mesh.materials.append(mat)
        uv = mesh.uv_layers.new(name="UVMap")
        for polygon, index, uvs in zip(mesh.polygons, self.materials, self.uvs):
            polygon.material_index = index
            polygon.use_smooth = smooth
            for loop_index, texcoord in zip(polygon.loop_indices, uvs):
                uv.data[loop_index].uv = texcoord
        if smooth:
            editable = bmesh.new()
            editable.from_mesh(mesh)
            bmesh.ops.remove_doubles(editable, verts=list(editable.verts), dist=.00001)
            editable.to_mesh(mesh)
            editable.free()
            mesh.update()
        return obj


def material(name, color, roughness=.75, double=False, texture=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    mat.use_backface_culling = not double
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = 0
    if double:
        shader.inputs["Subsurface Weight"].default_value = .035
        shader.inputs["Sheen Weight"].default_value = .08
    if texture:
        image = mat.node_tree.nodes.new("ShaderNodeTexImage")
        image.image = texture
        image.extension = "REPEAT"
        mat.node_tree.links.new(image.outputs["Color"], shader.inputs["Base Color"])
        bump = mat.node_tree.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = .28
        bump.inputs["Distance"].default_value = .045
        mat.node_tree.links.new(image.outputs["Color"], bump.inputs["Height"])
        mat.node_tree.links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    return mat


def bark_texture():
    width, height = 256, 512
    texture = bpy.data.images.new("Authored_RainTree_Bark", width, height)
    rng = random.Random(83317)
    pixels = []
    for y in range(height):
        for x in range(width):
            groove = abs(math.sin(x*.41 + math.sin(y*.035)*.7 + math.sin(x*.037)*3))
            fine = math.sin(x*1.17 + y*.023)*.035 + rng.uniform(-.055,.055)
            shade = .23 + groove*.15 + fine
            pixels.extend((shade*.90, shade*.77, shade*.64, 1))
    texture.pixels.foreach_set(pixels)
    texture.filepath_raw = str(OUT / "rain_tree_bark.png")
    texture.file_format = "PNG"
    texture.save()
    texture.pack()
    return texture


def bark_normal_texture():
    size=256
    image=bpy.data.images.new("Authored_RainTree_Bark_Normal",size,size)
    image.colorspace_settings.name="Non-Color"
    values=[]
    for y in range(size):
        for x in range(size):
            phase=x*.41+math.sin(y*.035)*.7+math.sin(x*.037)*3
            nx=math.cos(phase)*.58+math.sin(x*1.17+y*.023)*.14
            ny=math.sin(y*.31+x*.12)*.075
            vector=Vector((nx,ny,1)).normalized()
            values.extend((vector.x*.5+.5,vector.y*.5+.5,vector.z*.5+.5,1))
    image.pixels.foreach_set(values)
    image.filepath_raw=str(OUT/"rain_tree_bark_normal.png")
    image.file_format="PNG"
    image.save(); image.pack()
    return image


def foliage_materials(prefix):
    return [material(f"{prefix}_Leaf_{i:02}", color, .63+i*.035, True) for i, color in enumerate([
        (.035,.105,.018), (.055,.16,.025), (.075,.21,.034), (.10,.25,.043), (.045,.135,.024), (.125,.235,.052)
    ])]


def rain_tree(seed=21021):
    rng = random.Random(seed)
    bark, leaves = MeshBuilder(), MeshBuilder()
    trunk = [(0,0,0),(.08,-.05,.7),(-.04,.04,2.4),(.2,.04,4.2),(.08,.1,5.5)]
    bark.tube(trunk, [.82,.65,.57,.5,.36], 12)
    # Uneven buttress roots meet the ground, not a cylindrical pole end.
    for j in range(7):
        angle = j*TAU/7 + rng.uniform(-.2,.2)
        d = Vector((math.cos(angle), math.sin(angle), 0))
        bark.tube([d*1.65+Vector((0,0,.05)), d*.65+Vector((0,0,.2)), Vector((.05,0,1.2))], [.05,.25,.28], 6)
    for i in range(9):
        angle = i*TAU/9 + rng.uniform(-.13,.13)
        radial = Vector((math.cos(angle),math.sin(angle),0))
        tangent = Vector((-radial.y, radial.x,0))
        reach = rng.uniform(4.7,6.0)
        root = Vector((.08,.1,rng.uniform(3.5,5.3)))
        end = radial*reach+Vector((0,0,rng.uniform(8.5,10.0)))
        path = [root, root*.75+end*.25+Vector((0,0,.7)), root*.50+end*.5+Vector((0,0,1)), root*.25+end*.75+Vector((0,0,.6)), end]
        bark.tube(path,[.37,.31,.24,.16,.08],8)
        for j in range(5):
            start = Vector(path[2 if j<2 else 3])
            fan = (j-2)*.34 + rng.uniform(-.12,.12)
            branch_direction = Vector((math.cos(angle+fan),math.sin(angle+fan),0))
            radius = rng.uniform(7.1,9.2)
            endpoint = branch_direction*radius+Vector((0,0,rng.uniform(10.2,12.2)))
            mid = (start+endpoint)*.5+Vector((0,0,.6))+tangent*rng.uniform(-.3,.3)
            bark.tube([start,start.lerp(mid,.6)+Vector((0,0,.15)),mid,endpoint],[.13,.10,.075,.018],6)
            for k in range(8):
                branch_tangent = Vector((-branch_direction.y,branch_direction.x,0))
                # Inner sprays cover the formerly empty centre; staggered height
                # makes a volumetric umbrella rather than a ring of branch tips.
                if k<3:
                    leafcenter=mid.lerp(endpoint,rng.uniform(.10,.58))+Vector((0,0,rng.uniform(1.1,2.3)))
                elif k<5:
                    leafcenter=mid.lerp(endpoint,rng.uniform(.5,.9))+Vector((0,0,rng.uniform(.2,1.3)))
                else:
                    leafcenter=endpoint+branch_direction*rng.uniform(-.35,.7)+Vector((0,0,rng.uniform(-.5,.6)))
                leafcenter+=branch_tangent*rng.uniform(-1.0,1.0)
                twig_start = mid.lerp(endpoint,rng.uniform(.45,.85))
                bark.tube([twig_start,twig_start.lerp(leafcenter,.55)+Vector((0,0,.08)),leafcenter],[.028,.015,.004],4)
                # Asymmetric foliar sprays make layered crown lobes with real holes.
                for leaf_index in range(30):
                    position = leafcenter + branch_tangent*rng.gauss(0,.54) + branch_direction*rng.gauss(0,.49) + Vector((0,0,rng.gauss(0,.34)))
                    leaf_angle = angle+rng.uniform(-2.5,2.5)
                    direction = Vector((math.cos(leaf_angle),math.sin(leaf_angle),rng.uniform(-.5,.65)))
                    leaves.small_leaf(position,direction,rng.uniform(.27,.47),rng.uniform(.15,.25),rng,rng.randrange(6))
    bark_material=material("RainTree_Bark",(.20,.15,.10),.96, texture=bark_texture())
    normal_image=bark_material.node_tree.nodes.new("ShaderNodeTexImage")
    normal_image.image=bark_normal_texture()
    normal_map=bark_material.node_tree.nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value=.7
    bark_material.node_tree.links.new(normal_image.outputs["Color"],normal_map.inputs["Color"])
    bark_material.node_tree.links.new(normal_map.outputs["Normal"],bark_material.node_tree.nodes.get("Principled BSDF").inputs["Normal"])
    wood = bark.object("RainTree_BranchNetwork", [bark_material],True)
    foliage = leaves.object("RainTree_ModeledLeaves",foliage_materials("RainTree"),False)
    return [wood, foliage]


def palm(seed=21022):
    rng = random.Random(seed)
    bark, leaves = MeshBuilder(), MeshBuilder()
    trunk = [Vector((.12*math.sin(i*.3),.025*i, i*.9)) for i in range(12)]
    bark.tube(trunk,[.25-i*.005 for i in range(12)],12)
    # Raised narrow leaf-scar rings, following the gently leaning trunk.
    for i in range(37):
        z = .3+i*.25
        c = Vector((.12*math.sin(z/.9*.3), .025*z/.9,z))
        bark.tube([c,c+Vector((0,0,.045))],[.258-z*.0055,.25-z*.0055],10,1)
    crown = trunk[-1]+Vector((0,0,.1))
    bark.tube([crown-Vector((0,0,.9)),crown,crown+Vector((0,0,.8))],[.28,.3,.14],10,2)
    for i in range(18):
        angle = i*2.39996322973
        radial = Vector((math.cos(angle),math.sin(angle),0))
        side = Vector((-radial.y,radial.x,0))
        length = rng.uniform(3.1,4.25)
        lift = rng.uniform(.8,2.2) if i%4 else 2.7
        droop = rng.uniform(1.2,2.7)
        points=[]
        for j in range(9):
            t=j/8
            points.append(crown+radial*length*t+Vector((0,0,lift*math.sin(math.pi*t*.9)-droop*t*t)))
        bark.tube(points,[.045*(1-j/9)+.005 for j in range(9)],4,2)
        for j in range(1,18):
            t=j/18
            base=crown+radial*length*t+Vector((0,0,lift*math.sin(math.pi*t*.9)-droop*t*t))
            leaf_length=(.5+.55*math.sin(math.pi*t))*(1-t*.4)
            for sign in [-1,1]:
                direction=(side*sign*.8+radial*.4+Vector((0,0,-.4-t*.6))).normalized()
                leaves.leaf(base+direction*leaf_length*.40,direction,leaf_length,.10+.05*(1-t),rng,rng.randrange(5),.22)
    bark_mats=[material("Palm_Trunk",(.27,.235,.17),.9),material("Palm_Scars",(.19,.16,.11),.9),material("Palm_Crown",(.12,.21,.045),.8)]
    return [bark.object("Palm_TrunkAndFrondStems",bark_mats,True),leaves.object("Palm_ArchingModeledFronds",foliage_materials("Palm"))]


def fern(seed=21023):
    rng=random.Random(seed)
    stems,leaves=MeshBuilder(),MeshBuilder()
    for clump in range(4):
        c=Vector((rng.uniform(-.38,.38),rng.uniform(-.38,.38),0))
        for i in range(10):
            angle=i*TAU/10+rng.uniform(-.2,.2)
            radial=Vector((math.cos(angle),math.sin(angle),0))
            side=Vector((-radial.y,radial.x,0))
            length=rng.uniform(.65,1.2)
            height=rng.uniform(.45,.85)
            path=[c+radial*(length*t)+Vector((0,0,height*math.sin(t*math.pi*.8))) for t in [0,.2,.4,.6,.8,1]]
            stems.tube(path,[.012,.011,.009,.006,.004,.001],4)
            for j in range(1,11):
                t=j/11
                point=c+radial*(length*t)+Vector((0,0,height*math.sin(t*math.pi*.8)))
                for sign in [-1,1]:
                    leaf_length=.22*math.sin(math.pi*t)**.6+.04
                    direction=(side*sign*.9+radial*.4+Vector((0,0,.1))).normalized()
                    leaves.leaf(point+direction*leaf_length*.35,direction,leaf_length,.045*(1-t*.5),rng,rng.randrange(6),.14)
    return [stems.object("Fern_FrondStems",[material("Fern_Stems",(.055,.12,.021),.8)]),leaves.object("Fern_ModeledPinnae",foliage_materials("Fern"))]


def save_asset(name, objects):
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    points=[obj.matrix_world@Vector(v) for obj in objects for v in obj.bound_box]
    dimensions=[max(p[i] for p in points)-min(p[i] for p in points) for i in range(3)]
    triangles=sum(sum(len(poly.vertices)-2 for poly in obj.data.polygons) for obj in objects)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_OUT/f"{name}.blend"), check_existing=False)
    bpy.ops.export_scene.gltf(filepath=str(OUT/f"{name}.glb"),export_format="GLB",use_selection=True,export_yup=True,export_apply=True,export_materials="EXPORT",export_texcoords=True,export_normals=True)
    return {"asset":name,"dimensions_blender_xyz_m":[round(v,3) for v in dimensions],"triangles":triangles,"objects":len(objects),"source":"game/tools/build_foliage.py","seed":21021 if name=="rain_tree" else 21022 if name=="palm" else 21023}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--asset",choices=["all","rain_tree","palm","fern"],default="all")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    OUT.mkdir(parents=True,exist_ok=True)
    SOURCE_OUT.mkdir(parents=True,exist_ok=True)
    report=[]
    for name,builder in [("rain_tree",rain_tree),("palm",palm),("fern",fern)]:
        if args.asset not in ["all",name]:
            continue
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete(use_global=False)
        objects=builder()
        # Preserve source provenance inside editable artifacts.
        for obj in objects:
            obj["authoring"]="Original deterministic Blender mesh, GPT-6 Astra wave 2"
            obj["units"]="metres; ground origin; GLB exports Y-up"
        report.append(save_asset(name,objects))
    manifest_path=OUT/"foliage_manifest.json"
    existing=json.loads(manifest_path.read_text()) if manifest_path.exists() else []
    replacements={entry["asset"]:entry for entry in existing+report}
    manifest_path.write_text(json.dumps(list(replacements.values()),indent=2)+"\n")
    print("FOLIAGE_RESULT "+json.dumps(report),flush=True)


if __name__=="__main__":
    main()
