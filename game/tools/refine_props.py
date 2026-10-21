#!/usr/bin/env python3
"""Refine the original wave-1 provider props; raw source files are read-only.

Run Blender 4.5 LTS --background --factory-startup --threads 4 --python FILE.
Outputs remain in ignored providers/. Editable derived sources are outside the
Godot tree and ignored. This script makes no redistribution-rights claim.
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
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/"game/assets/providers"
SOURCE=ROOT/"art/provider-sources"
RAW=ROOT.parent/"relay-manager/assets"


def mesh_stats(obj):
    obj.data.calc_loop_triangles()
    vertices=[v.co for v in obj.data.vertices]
    triangles=obj.data.loop_triangles
    degenerate=sum(t.area<1e-12 for t in triangles)
    nonfinite=sum(not all(math.isfinite(c) for c in p) for p in vertices)
    lo=[min(v[i] for v in vertices) for i in range(3)]
    hi=[max(v[i] for v in vertices) for i in range(3)]
    return {"vertices":len(vertices),"triangles":len(triangles),"bounds_blender_xyz":[lo,hi],"dimensions_m":[hi[i]-lo[i] for i in range(3)],"surface_area_m2":sum(t.area for t in triangles),"degenerate_triangles":degenerate,"nonfinite_vertices":nonfinite}


def normalize(obj,kind):
    obj.data.transform(obj.matrix_world)
    obj.matrix_world=Matrix.Identity(4)
    if kind=="counter":
        # Raw long axis is Blender Y. Rotate it onto X; the open service side
        # becomes Blender +Y / Godot -Z (checked by exposed-face area below).
        obj.data.transform(Matrix.Rotation(math.pi*.5,4,"Z"))
    points=[v.co for v in obj.data.vertices]
    lo=Vector(tuple(min(v[i] for v in points) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in points) for i in range(3)))
    center=Vector(((lo.x+hi.x)*.5,(lo.y+hi.y)*.5,lo.z))
    size=hi-lo
    if kind=="counter":
        scale=Vector((2.8/size.x,1.2/size.y,2.4/size.z))
    else:
        radius=max(math.hypot(p.x-center.x,p.y-center.y) for p in points)
        scale=Vector((1.2/radius,1.2/radius,.75/size.z))
    for vertex in obj.data.vertices:
        p=vertex.co-center
        vertex.co=Vector((p.x*scale.x,p.y*scale.y,p.z*scale.z))
    obj.data.update()


def exposed_front_stats(obj):
    obj.data.calc_loop_triangles()
    bins={"negative_y_upper_vertical_area":0.0,"positive_y_upper_vertical_area":0.0}
    for face in obj.data.loop_triangles:
        coords=[obj.data.vertices[i].co for i in face.vertices]
        c=sum(coords,Vector())/3
        if 1.15<c.z<2.05 and abs(c.y)>.18 and abs(face.normal.y)>.75:
            key="positive_y_upper_vertical_area" if c.y>0 else "negative_y_upper_vertical_area"
            bins[key]+=face.area
    return bins


def repair_materials(obj,kind):
    for mat in obj.data.materials:
        if not mat or not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type=="BSDF_PRINCIPLED":
                for name,value in [("Metallic",.13 if kind=="table" else .18),("Roughness",.63 if kind=="table" else .67)]:
                    for link in list(node.inputs[name].links):
                        mat.node_tree.links.remove(link)
                    node.inputs[name].default_value=value
                # A noisy provider tangent normal exaggerated surface dents
                # after extreme decimation; retain geometry and atlas color.
                for link in list(node.inputs["Normal"].links):
                    mat.node_tree.links.remove(link)
        mat.diffuse_color=(.45,.43,.38,1)


def clean_and_decimate(obj,budget):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active=obj
    mesh=bmesh.new()
    mesh.from_mesh(obj.data)
    bmesh.ops.remove_doubles(mesh,verts=list(mesh.verts),dist=.00002)
    loose=[v for v in mesh.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(mesh,geom=loose,context="VERTS")
    bmesh.ops.dissolve_degenerate(mesh,edges=list(mesh.edges),dist=.00001)
    mesh.to_mesh(obj.data)
    mesh.free()
    obj.data.update()
    before=mesh_stats(obj)
    # Keep a deterministic reference sample before simplification.
    rng=random.Random(21021)
    sample_indices=rng.sample(range(len(obj.data.vertices)),min(12000,len(obj.data.vertices)))
    samples=[obj.data.vertices[i].co.copy() for i in sample_indices]
    modifier=obj.modifiers.new("SurfacePreservingBudget","DECIMATE")
    modifier.ratio=(budget-100)/before["triangles"]
    modifier.use_collapse_triangulate=True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    if obj.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for poly in obj.data.polygons:
        poly.use_smooth=True
    obj.data.update()
    return before,samples


def flatten_table_surface(obj):
    """Repair the main eating surface without changing stool/leg geometry."""
    pts=[v.co for v in obj.data.vertices if v.co.z>.69 and math.hypot(v.co.x,v.co.y)<.55]
    if not pts:
        return {"flattened_vertices":0,"note":"No top plane identified"}
    level=sorted(p.z for p in pts)[len(pts)//2]
    changed=0
    for vertex in obj.data.vertices:
        p=vertex.co
        if p.z>.69 and math.hypot(p.x,p.y)<.54:
            p.z=level
            changed+=1
    obj.data.update()
    return {"flattened_vertices":changed,"top_plane_m":level,"radius_m":.54}


def distance_check(obj,samples):
    obj.data.calc_loop_triangles()
    bvh=BVHTree.FromPolygons([v.co for v in obj.data.vertices],[tuple(t.vertices) for t in obj.data.loop_triangles],all_triangles=True)
    distances=sorted(bvh.find_nearest(p)[3] for p in samples)
    return {"samples":len(distances),"p50_m":distances[len(distances)//2],"p95_m":distances[int(len(distances)*.95)],"p99_m":distances[int(len(distances)*.99)],"maximum_m":distances[-1]}


def process(raw_id,name,kind,budget):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    raw=RAW/(raw_id+".glb")
    bpy.ops.import_scene.gltf(filepath=str(raw))
    objects=[o for o in bpy.context.scene.objects if o.type=="MESH"]
    assert len(objects)==1, "Unexpected provider assembly; inspect before changing it"
    obj=objects[0]
    obj.name=name
    normalize(obj,kind)
    front=exposed_front_stats(obj) if kind=="counter" else {}
    original=mesh_stats(obj)
    cleaned,samples=clean_and_decimate(obj,budget)
    plane=flatten_table_surface(obj) if kind=="table" else {}
    repair_materials(obj,kind)
    # Blender's exporter repairs invalid edge/custom-data bookkeeping itself;
    # do this explicitly before saving, testing and exporting so source and GLB
    # share the verified geometry and exporter warnings are not ignored.
    bookkeeping_repaired=obj.data.validate(verbose=True,clean_customdata=False)
    assert not obj.data.validate(verbose=False,clean_customdata=False)
    final=mesh_stats(obj)
    distance=distance_check(obj,samples)
    assert final["triangles"]<=budget
    assert final["nonfinite_vertices"]==0
    assert final["degenerate_triangles"]==0
    assert distance["p99_m"]<.06, "Simplification exceeds 6 cm at 99th percentile"
    obj["provenance"]=raw_id+" original wave-1 provider mesh; private derivative; rights not cleared for publication"
    obj["units"]="metres; ground-centred; Godot Y-up"
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active=obj
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+".blend")),check_existing=False)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")),export_format="GLB",use_selection=True,export_yup=True,export_apply=True,export_materials="EXPORT",export_texcoords=True,export_normals=True)
    result={"asset":name,"raw_id":raw_id,"budget":budget,"raw_normalized":original,"cleaned":cleaned,"final":final,"surface_distance":distance,"mesh_bookkeeping_repaired":bookkeeping_repaired,"tabletop_repair":plane,"counter_front_evidence":front,"front_axis_godot":"-Z after raw +90 degree Blender Z rotation; inferred from upper opening; verify in next rendered preview" if kind=="counter" else "radial seating; no functional front","rights":"UNVERIFIED; local private derivative only"}
    print("PROP_RESULT "+json.dumps(result),flush=True)
    return result


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--asset",choices=["all","counter","table"],default="all")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    OUT.mkdir(parents=True,exist_ok=True)
    SOURCE.mkdir(parents=True,exist_ok=True)
    ignore=SOURCE/".gitignore"
    if not ignore.exists():
        ignore.write_text("# Provider-derived binaries retain unverified redistribution rights.\n*\n!.gitignore\n")
    results=[]
    for raw,name,kind,budget in [("W1-HERO-009","hawker_counter_refined","counter",16000),("W1-PROP-010","hawker_table_refined","table",12000)]:
        if args.asset in ["all",kind]:
            results.append(process(raw,name,kind,budget))
    (OUT/"refined_props_manifest.json").write_text(json.dumps(results,indent=2)+"\n")


if __name__=="__main__":
    main()
