"""Blender cleanup for the provider-generated wave-1 assets.

Run headless:
  blender --background --python game/tools/cleanup_provider_assets.py

For every GLB in the provider folder it:
  * imports the raw export,
  * normalises it to real-world metres with the ground at Y=0 and forward -Z,
  * separates loose parts and names the functional ones (wheels, rotors, doors),
  * exports a cleaned GLB next to the raw file,
  * renders a small preview PNG so the builder can look at the asset.

Nothing here replaces provider geometry: the generated mesh is preserved, only
its scale, origin and part naming are fixed.
"""
import os
import sys
import math

import bpy
from mathutils import Vector

from pathlib import Path
PROJECT_ROOT = Path(__file__).resolve().parents[2]
# Explicit sources, never a hard-coded predecessor checkout. Existing outputs
# are retained unless OR_FORCE=1. Preview rendering is opt-in and needs a slot.
RAW_DIR = os.environ.get("OR_RAW_DIR", str(PROJECT_ROOT / "assets/raw"))
OUT_DIR = os.environ.get("OR_OUT_DIR", str(PROJECT_ROOT / "game/assets/providers"))
PREVIEW_DIR = os.environ.get("OR_PREVIEW_DIR", str(PROJECT_ROOT / "docs/asset-previews"))

# id -> (target length/height, longest axis in glTF space, rules)
ASSETS = {
    "W1-HERO-001": {
        "out": "sedan_clean.glb",
        "mode": "car",
        "length_m": 4.4,       # glTF X is the length for this export
        "axis": "X",
    },
    "W1-HERO-004": {
        "out": "helicopter_clean.glb",
        "mode": "heli",
        "length_m": 6.5,       # Blender Y carries the fuselage length
        "axis": "Y",
    },
    "W1-HERO-005": {
        "out": "player_clean.glb",
        "mode": "figure",
        "length_m": 1.75,      # Blender Z is the height
        "axis": "Z",
    },
    "W1-HERO-007": {
        "out": "shophouse_clean.glb",
        "mode": "building",
        "length_m": 11.5,      # Blender Z is the height
        "axis": "Z",
        # this module is instanced along every heritage street, so it carries
        # a tight triangle budget
        "budget": 20000,
    },
    "W1-HERO-002": {
        "out": "coupe_clean.glb",
        "mode": "car",
        "length_m": 4.3,
        "axis": "X",
        "budget": 45000,
    },
    "W1-HERO-003": {
        "out": "van_clean.glb",
        "mode": "car",
        "length_m": 5.2,
        "axis": "X",
        "budget": 45000,
    },
    "W1-HERO-006": {
        "out": "officer_clean.glb",
        "mode": "figure",
        "length_m": 1.78,
        "axis": "Z",
        "budget": 30000,
    },
    "W1-HERO-008": {
        "out": "hdb_slab_clean.glb",
        "mode": "building",
        "length_m": 42.0,     # Blender Z is the height
        "axis": "Z",
        "budget": 40000,
    },
    "W1-HERO-009": {
        "out": "hawker_counter_clean.glb",
        "mode": "prop",
        "length_m": 1.6,
        "axis": "MAX",
        "budget": 4000,
    },
    "W1-PROP-010": {
        "out": "hawker_table_clean.glb",
        "mode": "prop",
        "length_m": 1.6,
        "axis": "MAX",
        "budget": 4000,
    },
    "W1-PROP-011": {
        "out": "food_trolley_clean.glb",
        "mode": "prop",
        "length_m": 1.4,
        "axis": "MAX",
        "budget": 4000,
    },
    "W1-PROP-012": {
        "out": "ac_unit_clean.glb",
        "mode": "prop",
        "length_m": 0.85,
        "axis": "MAX",
        "budget": 3000,
    },
    "W1-PROP-013": {
        "out": "street_lamp_clean.glb",
        "mode": "prop",
        "length_m": 6.0,
        "axis": "Z",
        "budget": 4000,
    },
    "W1-PROP-014": {
        "out": "service_clutter_clean.glb",
        "mode": "prop",
        "length_m": 1.2,
        "axis": "MAX",
        "budget": 4000,
    },
    "W1-PROP-015": {
        "out": "planter_clean.glb",
        "mode": "prop",
        "length_m": 0.9,
        "axis": "MAX",
        "budget": 3000,
    },
    "W1-PROP-016": {
        "out": "pistol_clean.glb",
        "mode": "prop",
        "length_m": 0.19,
        "axis": "MAX",
        "budget": 2500,
    },
    "W1-PROP-017": {
        "out": "smg_clean.glb",
        "mode": "prop",
        "length_m": 0.62,
        "axis": "MAX",
        "budget": 3000,
    },
    "W1-PROP-018": {
        "out": "airfield_clutter_clean.glb",
        "mode": "prop",
        "length_m": 2.0,
        "axis": "MAX",
        "budget": 4000,
    },
}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
    bpy.ops.import_scene.gltf(filepath=path)


def scene_bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            lo = Vector((min(lo[i], world[i]) for i in range(3)))
            hi = Vector((max(hi[i], world[i]) for i in range(3)))
    return lo, hi


def normalise_scale(target_len, axis):
    lo, hi = scene_bounds()
    size = hi - lo
    if axis == "MAX":
        current = max(size.x, size.y, size.z)
    else:
        current = {"X": size.x, "Y": size.y, "Z": size.z}[axis]
    scale = target_len / max(current, 1e-6)
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.scale = (obj.scale.x * scale, obj.scale.y * scale, obj.scale.z * scale)
    bpy.context.view_layer.update()
    return scale


def drop_to_ground():
    lo, _ = scene_bounds()
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.location.z -= lo.z
    bpy.context.view_layer.update()


def centre_on_origin():
    lo, hi = scene_bounds()
    centre = (lo + hi) * 0.5
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.location.x -= centre.x
            obj.location.y -= centre.y
    bpy.context.view_layer.update()


def triangle_count(obj):
    try:
        obj.data.calc_loop_triangles()
        return len(obj.data.loop_triangles)
    except Exception:
        return 0


def decimate(obj, target_tris):
    """Reduce a dense generator export to a runtime-friendly triangle budget."""
    tris = triangle_count(obj)
    if tris <= target_tris or tris == 0:
        return tris
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.ratio = maxf = max(0.0005, target_tris / tris)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.update()
    return triangle_count(obj)


def set_part_origins(names=None):
    """Move a part's origin to its own geometry so wheels and rotors spin in place.

    Only the functional parts need this: the thousands of body fragments are
    joined afterwards, and re-origining each of them is prohibitively slow.
    """
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if names is not None and obj.name not in names:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    bpy.context.view_layer.update()


def rotate_assembly(degrees_z):
    """Rotate the whole assembly about the scene origin (keeps parts together)."""
    empty = bpy.data.objects.new("ASSEMBLY", None)
    bpy.context.scene.collection.objects.link(empty)
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            continue
        obj.parent = empty
        obj.matrix_parent_inverse = empty.matrix_world.inverted()
    empty.rotation_euler = (0.0, 0.0, math.radians(degrees_z))
    bpy.context.view_layer.update()
    return empty


def separate_loose_parts():
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if len(objs) != 1:
        return objs
    obj = objs[0]
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def part_stats(obj):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for corner in obj.bound_box:
        world = obj.matrix_world @ Vector(corner)
        lo = Vector((min(lo[i], world[i]) for i in range(3)))
        hi = Vector((max(hi[i], world[i]) for i in range(3)))
    return lo, hi, (lo + hi) * 0.5


def classify_car(parts):
    """Wheels are small parts low down near the four corners."""
    lo, hi = scene_bounds()
    length = hi.x - lo.x
    width = hi.y - lo.y
    height = hi.z - lo.z
    wheel_radius = height * 0.42
    names = ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]
    slots = {}
    for obj in parts:
        plo, phi, centre = part_stats(obj)
        size = phi - plo
        biggest = max(size.x, size.y, size.z)
        if biggest > wheel_radius * 1.9:
            obj.name = "body"
            continue
        if centre.z > wheel_radius * 1.35:
            obj.name = "body"
            continue
        front = centre.x > 0.0
        left = centre.y > 0.0
        key = (front, left)
        if key in slots:
            obj.name = "body"
            continue
        slots[key] = obj
        obj.name = names[(0 if front else 2) + (0 if left else 1)]
    return len(slots)


def classify_heli(parts):
    lo, hi = scene_bounds()
    length = hi.x - lo.x
    height = hi.z - lo.z
    main_rotor = 0
    tail_rotor = 0
    for obj in parts:
        plo, phi, centre = part_stats(obj)
        size = phi - plo
        biggest = max(size.x, size.y, size.z)
        if centre.z > height * 0.82 and biggest > length * 0.25:
            obj.name = "main_rotor"
            main_rotor += 1
        elif centre.x > length * 0.30 and biggest < length * 0.30:
            obj.name = "tail_rotor"
            tail_rotor += 1
        else:
            obj.name = "body"
    return main_rotor, tail_rotor


def join_by_prefix(parts, prefix, target_name):
    """Join every part whose name starts with `prefix` into one object."""
    # Always re-query the scene: joining removes the merged objects.
    matches = [o for o in bpy.context.scene.objects
               if o.type == "MESH" and (o.name == prefix or o.name.startswith(prefix + "."))]
    if len(matches) < 2:
        for o in matches:
            o.name = target_name
        return len(matches)
    bpy.ops.object.select_all(action="DESELECT")
    for o in matches:
        o.select_set(True)
    bpy.context.view_layer.objects.active = matches[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = target_name
    return len(matches)


def render_preview(path, target_height):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT" if hasattr(scene, "blender") else "BLENDER_EEVEE"
    scene.render.resolution_x = 480
    scene.render.resolution_y = 360
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    scene.render.image_settings.file_format = "PNG"
    # simple three-point studio light
    for name, loc, energy, size in (
        ("key", (span * 1.0, -span * 1.3, span * 1.5), 2400.0, span * 1.2),
        ("fill", (-span * 1.3, -span * 0.8, span * 0.6), 900.0, span * 1.5),
        ("rim", (0.0, span * 1.5, span * 1.0), 1400.0, span),
    ):
        light_data = bpy.data.lights.new(name, type="AREA")
        light_data.energy = energy
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        light.location = loc
        scene.collection.objects.link(light)
        direction = Vector((0, 0, span * 0.45)) - Vector(loc)
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    lo, hi = scene_bounds()
    span = max((hi - lo).x, (hi - lo).y, (hi - lo).z)
    cam.location = (span * 1.1, -span * 1.5, span * 0.85)
    look = Vector((0, 0, span * 0.45))
    cam.rotation_euler = (look - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.28, 0.32, 0.38, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scene.world = world
    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    for asset_id, spec in ASSETS.items():
        raw = os.path.join(RAW_DIR, asset_id + ".glb")
        if not os.path.exists(raw):
            print("SKIP missing", raw)
            continue
        target = os.path.join(OUT_DIR, spec["out"])
        if os.path.exists(target) and os.environ.get("OR_FORCE") != "1":
            print("SKIP already cleaned", asset_id)
            continue
        reset_scene()
        import_glb(raw)
        normalise_scale(spec["length_m"], spec["axis"])
        budget = int(spec.get("budget", 90000))
        for obj in bpy.context.scene.objects:
            if obj.type == "MESH":
                before = triangle_count(obj)
                after = decimate(obj, budget)
                if before != after:
                    print("  decimated %s: %d -> %d tris" % (obj.name, before, after))
        drop_to_ground()
        centre_on_origin()
        if spec["mode"] in ("car", "heli"):
            parts = separate_loose_parts()
        else:
            parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        functional = {"wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR", "main_rotor", "tail_rotor"}
        set_part_origins(functional)
        if spec["mode"] == "prop":
            for obj in bpy.context.scene.objects:
                if obj.type == "MESH":
                    obj.name = "body"
            centre_on_origin()
            drop_to_ground()
        if spec["mode"] == "car":
            # the export runs along glTF +X; turn it so the nose points -Z
            # (engine forward) once converted back to glTF
            rotate_assembly(90.0)
            centre_on_origin()
            drop_to_ground()
        lo, hi = scene_bounds()
        if spec["mode"] == "car":
            found = classify_car(parts)
            print(asset_id, "car: %d parts, %d wheels" % (len(parts), found))
            height = hi.z - lo.z
        elif spec["mode"] == "heli":
            m, t = classify_heli(parts)
            print(asset_id, "heli: %d parts, main_rotor=%d tail_rotor=%d" % (len(parts), m, t))
            height = hi.z - lo.z
        else:
            for obj in parts:
                obj.name = "body"
            print(asset_id, "static: %d parts" % len(parts))
            height = hi.z - lo.z
        parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        if spec["mode"] == "car":
            join_by_prefix(parts, "body", "body")
            for w in ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]:
                join_by_prefix(parts, w, w)
        elif spec["mode"] == "heli":
            join_by_prefix(parts, "body", "body")
            join_by_prefix(parts, "main_rotor", "main_rotor")
            join_by_prefix(parts, "tail_rotor", "tail_rotor")
        else:
            join_by_prefix(parts, "body", "body")
        parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        remaining = [o.name for o in bpy.context.scene.objects if o.type == "MESH"]
        print(asset_id, "final objects:", remaining)
        out_glb = os.path.join(OUT_DIR, spec["out"])
        bpy.ops.export_scene.gltf(
            filepath=out_glb,
            export_format="GLB",
            export_apply=True,
            export_yup=True,
            export_materials="EXPORT",
            export_animations=True,
            export_skins=True,
        )
        preview = os.path.join(PREVIEW_DIR, asset_id + "_preview.png")
        if os.environ.get("OR_RENDER_PREVIEWS") == "1":
            try:
                render_preview(preview, height)
                print("preview", preview)
            except Exception as exc:  # rendering is a convenience, not a blocker
                print("preview failed:", exc)
        print("exported", out_glb, "size", hi.z - lo.z, "height")


if __name__ == "__main__":
    main()
