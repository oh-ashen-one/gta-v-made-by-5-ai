#!/usr/bin/env python3
"""Original Blender-authored 3D Singapore waterfront & skyline landmarks.
Run with:
  /Users/midir/Applications/Blender-4.5.11.app/Contents/MacOS/Blender --background --factory-startup --threads 4 --python game/tools/build_landmarks.py

Generates in game/assets/authored/:
  - marina_bay_sands.glb     (3 splayed/tapered towers + cantilevered boat-shaped SkyPark)
  - supertree_grove.glb      (7 branching vertical-garden Supertrees + flared canopy crowns + OCBC Skyway)
  - artscience_museum.glb    (10-finger sculpted lotus museum on reflection pond base)
  - merlion_landmark.glb     (sculpted Merlion statue on wave plinth + arching water jet)
  - singapore_flyer.glb      (giant spoked observation wheel + 28 viewing capsules + terminal podium)
"""
from __future__ import annotations
import bpy
import json
import math
import random
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/assets/authored"
SRC = ROOT / "art/source"
OUT.mkdir(parents=True, exist_ok=True)
SRC.mkdir(parents=True, exist_ok=True)
random.seed(20261021)


def make_material(name: str, color: tuple[float, float, float], rough: float = 0.55, metal: float = 0.0, emission: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if emission > 0.0:
            bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission
    return mat


class MeshBuilder:
    """Fast procedural mesh builder in Blender coordinates (X right, Y depth, Z up)."""

    def __init__(self) -> None:
        self.data: dict[str, list[list]] = defaultdict(lambda: [[], []])

    def box(self, mat: bpy.types.Material, pos: tuple[float, float, float], size: tuple[float, float, float]) -> None:
        v, f = self.data[mat.name]
        k = len(v)
        x, y, z = pos
        a, b, c = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        v.extend([
            (x - a, y - b, z - c), (x + a, y - b, z - c), (x + a, y + b, z - c), (x - a, y + b, z - c),
            (x - a, y - b, z + c), (x + a, y - b, z + c), (x + a, y + b, z + c), (x - a, y + b, z + c),
        ])
        f.extend([
            (k + 0, k + 3, k + 2, k + 1),
            (k + 4, k + 5, k + 6, k + 7),
            (k + 0, k + 1, k + 5, k + 4),
            (k + 1, k + 2, k + 6, k + 5),
            (k + 2, k + 3, k + 7, k + 6),
            (k + 3, k + 0, k + 4, k + 7),
        ])

    def loft_quad_sections(self, mat: bpy.types.Material, sections: list[list[tuple[float, float, float]]], cap_ends: bool = True) -> None:
        """Loft a sequence of 4-vertex rings (counter-clockwise in XY when viewed from +Z)."""
        v, f = self.data[mat.name]
        base_k = len(v)
        for ring in sections:
            v.extend(ring)
        n = len(sections)
        for i in range(n - 1):
            a = base_k + i * 4
            b = base_k + (i + 1) * 4
            for j in range(4):
                jn = (j + 1) % 4
                f.append((a + j, a + jn, b + jn, b + j))
        if cap_ends and n >= 2:
            f.append((base_k + 0, base_k + 3, base_k + 2, base_k + 1))
            last = base_k + (n - 1) * 4
            f.append((last + 0, last + 1, last + 2, last + 3))

    def loft_rings(self, mat: bpy.types.Material, rings: list[list[tuple[float, float, float]]], cap_bottom: bool = False, cap_top: bool = False) -> None:
        """Loft a sequence of M-vertex polygon rings."""
        if len(rings) < 2 or not rings[0]:
            return
        v, f = self.data[mat.name]
        m = len(rings[0])
        base_k = len(v)
        for ring in rings:
            v.extend(ring)
        for i in range(len(rings) - 1):
            a = base_k + i * m
            b = base_k + (i + 1) * m
            for j in range(m):
                jn = (j + 1) % m
                f.append((a + j, a + jn, b + jn, b + j))
        if cap_bottom:
            f.append(tuple(base_k + j for j in range(m - 1, -1, -1)))
        if cap_top:
            last = base_k + (len(rings) - 1) * m
            f.append(tuple(last + j for j in range(m)))

    def strut(self, mat: bpy.types.Material, p0: tuple[float, float, float], p1: tuple[float, float, float], radius: float, sides: int = 6) -> None:
        """Create a tubular strut between two 3D points p0 and p1."""
        dx, dy, dz = p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]
        length = math.sqrt(dx * dx + dy * dy + dz * dz)
        if length < 1e-4:
            return
        ux, uy, uz = dx / length, dy / length, dz / length
        if abs(uz) < 0.9:
            rx, ry, rz = -uy, ux, 0.0
        else:
            rx, ry, rz = 0.0, -uz, uy
        rl = math.sqrt(rx * rx + ry * ry + rz * rz)
        rx, ry, rz = rx / rl, ry / rl, rz / rl
        sx, sy, sz = uy * rz - uz * ry, uz * rx - ux * rz, ux * ry - uy * rx
        ring0, ring1 = [], []
        for i in range(sides):
            ang = (2.0 * math.pi * i) / sides
            ca, sa = math.cos(ang) * radius, math.sin(ang) * radius
            ox = rx * ca + sx * sa
            oy = ry * ca + sy * sa
            oz = rz * ca + sz * sa
            ring0.append((p0[0] + ox, p0[1] + oy, p0[2] + oz))
            ring1.append((p1[0] + ox, p1[1] + oy, p1[2] + oz))
        self.loft_rings(mat, [ring0, ring1], cap_bottom=True, cap_top=True)

    def cylinder_z(self, mat: bpy.types.Material, center: tuple[float, float, float], r0: float, r1: float, h: float, sides: int = 16, cap: bool = True) -> None:
        cx, cy, cz = center
        z0, z1 = cz - h * 0.5, cz + h * 0.5
        ring0, ring1 = [], []
        for i in range(sides):
            ang = (2.0 * math.pi * i) / sides
            ca, sa = math.cos(ang), math.sin(ang)
            ring0.append((cx + ca * r0, cy + sa * r0, z0))
            ring1.append((cx + ca * r1, cy + sa * r1, z1))
        self.loft_rings(mat, [ring0, ring1], cap_bottom=cap, cap_top=cap)

    def finish(self, root_name: str) -> dict:
        total_tris = 0
        for name, (v, f) in self.data.items():
            if not v or not f:
                continue
            me = bpy.data.meshes.new(f"{root_name}_{name}")
            me.from_pydata(v, [], f)
            me.materials.append(bpy.data.materials[name])
            for poly in me.polygons:
                poly.use_smooth = False
            me.update()
            ob = bpy.data.objects.new(f"{root_name}_{name}", me)
            ob["authoring"] = "Original Blender landmark geometry; Wave 4 Argon"
            bpy.context.collection.objects.link(ob)
            total_tris += sum(len(p.vertices) - 2 for p in me.polygons)
        bpy.ops.wm.save_as_mainfile(filepath=str(SRC / f"{root_name}.blend"), check_existing=False)
        bpy.ops.export_scene.gltf(
            filepath=str(OUT / f"{root_name}.glb"),
            export_format="GLB",
            export_yup=True,
            export_apply=True,
        )
        return {"file": f"{root_name}.glb", "triangles": total_tris, "rights": "MIT original authored mesh"}


def build_marina_bay_sands() -> dict:
    """Three splayed/tapered hotel towers supporting the cantilevered boat-shaped SkyPark."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = MeshBuilder()

    steel = make_material("mbs_champagne_steel", (0.76, 0.74, 0.69), 0.34, 0.68)
    hull_metal = make_material("mbs_skypark_hull", (0.82, 0.80, 0.76), 0.28, 0.74)
    glass_dark = make_material("mbs_curtain_glass", (0.09, 0.20, 0.28), 0.16, 0.62)
    glass_mid = make_material("mbs_curtain_glass_mid", (0.14, 0.27, 0.36), 0.18, 0.58)
    warm_win = make_material("mbs_warm_suite", (0.96, 0.76, 0.44), 0.35, 0.0, 2.2)
    beacon_gold = make_material("mbs_skypark_glow", (1.0, 0.80, 0.42), 0.25, 0.0, 3.4)
    podium_stone = make_material("mbs_podium_stone", (0.64, 0.61, 0.56), 0.78, 0.05)
    deck_wood = make_material("mbs_skypark_deck", (0.48, 0.35, 0.22), 0.72, 0.0)
    pool_aqua = make_material("mbs_infinity_pool", (0.12, 0.74, 0.88), 0.12, 0.1, 1.4)
    foliage = make_material("mbs_sky_foliage", (0.14, 0.38, 0.16), 0.85, 0.0)

    # Waterfront podium & colonnade base connecting the three towers
    b.box(podium_stone, (0.0, 0.0, 2.4), (104.0, 38.0, 4.8))
    b.box(steel, (0.0, 0.0, 5.0), (106.0, 40.0, 0.5))
    for ix in range(-12, 13):
        b.box(glass_dark, (ix * 4.0, -18.8, 2.4), (3.1, 0.4, 3.8))
        b.box(glass_dark, (ix * 4.0, 18.8, 2.4), (3.1, 0.4, 3.8))

    # Three iconic towers (X = -36, 0, +36), each with two splayed legs that merge upward
    tower_xs = [-36.0, 0.0, 36.0]
    tower_h = 104.0
    floors = 29
    for t_idx, tx in enumerate(tower_xs):
        # Leg 1 (South/East inclined leg) and Leg 2 (North/West steeper leg)
        for leg_sign in (-1.0, 1.0):
            sections = []
            steps = 14
            for s in range(steps + 1):
                u = s / steps
                z = 4.8 + u * (tower_h - 4.8)
                # At base (u=0), legs are separated by y = +-8.6m; by u=0.58 they converge into the main slab
                spread = max(0.0, (1.0 - u * 1.45)) * 7.8
                # Characteristic lean in +Y as tower rises
                lean_y = (1.0 - u) * (-3.2 if leg_sign < 0 else 4.8) + leg_sign * spread
                half_w = 9.2 - u * 1.4
                half_d = 4.6 - u * 1.1
                sections.append([
                    (tx - half_w, lean_y - half_d, z),
                    (tx + half_w, lean_y - half_d, z),
                    (tx + half_w, lean_y + half_d, z),
                    (tx - half_w, lean_y + half_d, z),
                ])
            b.loft_quad_sections(glass_dark if leg_sign < 0 else glass_mid, sections)

        # Horizontal balcony slabs, vertical spine fins, and warm illuminated hotel bays
        for fl in range(floors):
            u = fl / floors
            z = 6.5 + fl * ((tower_h - 6.5) / floors)
            spread = max(0.0, (1.0 - u * 1.45)) * 7.8
            y_min = (1.0 - u) * (-3.2) - spread - (4.6 - u * 1.1)
            y_max = (1.0 - u) * (4.8) + spread + (4.6 - u * 1.1)
            yc = 0.5 * (y_min + y_max)
            yd = (y_max - y_min) + 0.9
            xw = (9.2 - u * 1.4) * 2.0 + 0.9
            # Balcony edge band
            b.box(steel, (tx, yc, z), (xw, yd, 0.28))
            # Illuminated hotel rooms on alternating floors
            if (fl + t_idx) % 3 == 0:
                b.box(warm_win, (tx + ((fl % 3) - 1) * 4.2, yc, z + 1.4), (3.6, yd + 0.12, 1.9))

        # Central structural spine fins on East/West faces of each tower
        for fin_x in (-9.1, -3.0, 3.0, 9.1):
            b.strut(steel, (tx + fin_x * 0.95, -1.0, 5.0), (tx + fin_x * 0.82, 0.2, tower_h), 0.32, sides=4)

    # SkyPark ("Boat on top") spanning all 3 towers and cantilevering +28m past Tower 3
    # X range: -50m (stern) to +66m (bow cantilever), total length 116m
    hull_sections = []
    deck_sections = []
    xs = [-50.0, -44.0, -36.0, -18.0, 0.0, 18.0, 36.0, 48.0, 58.0, 64.0, 67.5]
    half_ys = [4.5, 9.5, 13.0, 14.5, 14.8, 14.2, 13.2, 11.2, 7.8, 4.0, 1.2]
    keel_zs = [106.2, 104.2, 103.2, 103.0, 103.0, 103.0, 103.2, 103.8, 104.6, 105.6, 106.8]
    deck_z = 108.0

    for x, hy, kz in zip(xs, half_ys, keel_zs):
        keel_hy = max(0.6, hy * 0.58)
        hull_sections.append([
            (x, -keel_hy, kz),
            (x, keel_hy, kz),
            (x, hy, deck_z),
            (x, -hy, deck_z),
        ])
        deck_sections.append([
            (x, -hy * 0.96, deck_z),
            (x, hy * 0.96, deck_z),
            (x, hy * 0.96, deck_z + 0.55),
            (x, -hy * 0.96, deck_z + 0.55),
        ])
    b.loft_quad_sections(hull_metal, hull_sections)
    b.loft_quad_sections(deck_wood, deck_sections)

    # Illuminated golden rim around the SkyPark boat hull so silhouette pops at dusk
    for i in range(len(xs) - 1):
        for side in (-1.0, 1.0):
            p0 = (xs[i], side * half_ys[i], deck_z + 0.15)
            p1 = (xs[i + 1], side * half_ys[i + 1], deck_z + 0.15)
            b.strut(beacon_gold, p0, p1, 0.34, sides=6)

    # SkyPark Infinity Pool along the bayside (-Y) edge & rooftop observation pavilion
    b.box(pool_aqua, (-4.0, -8.2, deck_z + 0.65), (74.0, 6.2, 0.38))
    b.box(hull_metal, (-18.0, 4.2, deck_z + 2.2), (26.0, 8.4, 3.4))
    b.box(beacon_gold, (-18.0, 4.2, deck_z + 4.0), (27.2, 9.2, 0.45))

    # Rooftop tropical palms/trees across the SkyPark garden
    for tx in range(-42, 58, 9):
        for ty in (-2.5, 6.5):
            if abs(tx) > 48 and abs(ty) > 4.0:
                continue
            b.cylinder_z(deck_wood, (tx, ty, deck_z + 2.0), 0.28, 0.20, 3.0, sides=6)
            b.cylinder_z(foliage, (tx, ty, deck_z + 4.1), 2.4, 0.8, 2.2, sides=8)

    return b.finish("marina_bay_sands")


def build_supertree_grove() -> dict:
    """Gardens by the Bay Supertree Grove ('electric tree forest') + OCBC Skyway."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = MeshBuilder()

    trunk_green = make_material("st_living_trunk", (0.11, 0.34, 0.15), 0.86, 0.0)
    canopy_purple = make_material("st_lattice_purple", (0.46, 0.16, 0.48), 0.38, 0.35, 0.65)
    canopy_magenta = make_material("st_crown_magenta", (0.78, 0.22, 0.68), 0.30, 0.20, 2.4)
    glow_gold = make_material("st_warm_gold_glow", (1.0, 0.74, 0.28), 0.25, 0.10, 3.2)
    glow_cyan = make_material("st_solar_cap_cyan", (0.24, 0.78, 0.92), 0.25, 0.20, 1.8)
    skyway_steel = make_material("st_skyway_steel", (0.78, 0.75, 0.70), 0.35, 0.65)
    mound_stone = make_material("st_planter_stone", (0.38, 0.39, 0.36), 0.82, 0.0)

    # 7 Supertrees: (x, y, height, base_r, crown_r)
    trees = [
        (0.0, 0.0, 48.0, 4.4, 15.5),       # Central flagship Supertree
        (-24.0, -8.0, 40.0, 3.6, 13.0),    # West Skyway anchor Supertree
        (24.0, -6.0, 41.0, 3.7, 13.2),     # East Skyway anchor Supertree
        (-16.0, 18.0, 33.0, 3.0, 10.8),    # North-West Supertree
        (17.0, 19.0, 35.0, 3.1, 11.2),     # North-East Supertree
        (-34.0, 12.0, 28.0, 2.6, 9.2),     # Outer West Supertree
        (33.0, 14.0, 30.0, 2.8, 9.8),      # Outer East Supertree
    ]

    for idx, (cx, cy, h, br, cr) in enumerate(trees):
        # Landscaped planter mound at base
        b.cylinder_z(mound_stone, (cx, cy, 0.7), br + 3.2, br + 2.2, 1.4, sides=16)
        b.cylinder_z(trunk_green, (cx, cy, 1.5), br + 2.0, br + 1.4, 0.6, sides=16)

        # Tapered planted core trunk (waist narrows at 55% height, then flares into crown)
        trunk_rings = []
        sides = 14
        levels = [
            (0.0, br),
            (0.22, br * 0.76),
            (0.52, br * 0.58),
            (0.74, br * 0.72),
            (0.86, br * 1.15),
        ]
        for u, rad in levels:
            z = 1.4 + u * (h - 1.4)
            ring = []
            for s in range(sides):
                ang = (2.0 * math.pi * s) / sides
                ring.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad, z))
            trunk_rings.append(ring)
        b.loft_rings(trunk_green, trunk_rings, cap_bottom=True, cap_top=True)

        # Outer biomimetic exoskeleton ribs & glowing horizontal rings along trunk
        rib_count = 12
        for r_i in range(rib_count):
            ang = (2.0 * math.pi * r_i) / rib_count
            ca, sa = math.cos(ang), math.sin(ang)
            pts = []
            for u, rad in levels:
                z = 1.4 + u * (h - 1.4)
                pts.append((cx + ca * (rad + 0.32), cy + sa * (rad + 0.32), z))
            for k in range(len(pts) - 1):
                b.strut(canopy_purple, pts[k], pts[k + 1], 0.18, sides=5)

            # Flared inverted-umbrella / trumpet canopy branches from 72% height to 100% height
            z_branch0 = 1.4 + 0.72 * (h - 1.4)
            r_branch0 = br * 0.72 + 0.32
            z_mid = 1.4 + 0.88 * (h - 1.4)
            r_mid = cr * 0.64
            z_top = h
            r_top = cr
            p0 = (cx + ca * r_branch0, cy + sa * r_branch0, z_branch0)
            pm = (cx + ca * r_mid, cy + sa * r_mid, z_mid)
            pt = (cx + ca * r_top, cy + sa * r_top, z_top)
            b.strut(canopy_purple, p0, pm, 0.22, sides=5)
            b.strut(canopy_magenta if r_i % 2 == 0 else glow_gold, pm, pt, 0.20, sides=5)
            # Secondary fork branch for dense organic canopy silhouette
            ang2 = ang + math.pi / rib_count
            pt2 = (cx + math.cos(ang2) * (r_top * 0.94), cy + math.sin(ang2) * (r_top * 0.94), z_top - 0.6)
            b.strut(canopy_magenta, pm, pt2, 0.15, sides=4)

        # Concentric glowing canopy crown rings at the top of each Supertree
        for frac, mat in [(0.62, glow_gold), (0.82, canopy_magenta), (1.0, glow_gold)]:
            ring_r = cr * frac
            ring_z = h - (1.0 - frac) * 3.8
            for r_i in range(rib_count):
                a0 = (2.0 * math.pi * r_i) / rib_count
                a1 = (2.0 * math.pi * (r_i + 1)) / rib_count
                b.strut(
                    mat,
                    (cx + math.cos(a0) * ring_r, cy + math.sin(a0) * ring_r, ring_z),
                    (cx + math.cos(a1) * ring_r, cy + math.sin(a1) * ring_r, ring_z),
                    0.22,
                    sides=5,
                )

        # Glowing trunk collar rings + solar photovoltaics cap at center of crown
        for collar_u in (0.35, 0.55, 0.74):
            cz = 1.4 + collar_u * (h - 1.4)
            crad = br * 0.78
            b.cylinder_z(glow_gold if idx % 2 == 0 else canopy_magenta, (cx, cy, cz), crad, crad, 0.42, sides=12)
        b.cylinder_z(glow_cyan, (cx, cy, h * 0.89), br * 1.35, br * 1.05, 0.65, sides=12)

    # OCBC Skyway: curved elevated walkway at Z = 22m linking the main Supertrees
    skyway_z = 22.0
    skyway_pts = [
        (-24.0, -8.0),
        (-16.0, -4.5),
        (-8.0, -1.5),
        (0.0, 0.0),
        (8.5, -1.0),
        (16.5, -3.5),
        (24.0, -6.0),
        (21.0, 6.5),
        (17.0, 19.0),
        (0.0, 21.5),
        (-16.0, 18.0),
        (-21.0, 5.0),
        (-24.0, -8.0),
    ]
    for i in range(len(skyway_pts) - 1):
        x0, y0 = skyway_pts[i]
        x1, y1 = skyway_pts[i + 1]
        b.strut(skyway_steel, (x0, y0, skyway_z), (x1, y1, skyway_z), 0.65, sides=6)
        b.strut(glow_gold, (x0, y0, skyway_z + 0.95), (x1, y1, skyway_z + 0.95), 0.18, sides=4)

    return b.finish("supertree_grove")


def build_artscience_museum() -> dict:
    """Lotus-shaped ArtScience Museum with 10 sculpted white petals over a lily pond."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = MeshBuilder()

    white_shell = make_material("asm_lotus_white", (0.92, 0.91, 0.88), 0.36, 0.08)
    pond_water = make_material("asm_lily_pond", (0.08, 0.26, 0.34), 0.14, 0.25)
    pond_rim = make_material("asm_pond_stone", (0.56, 0.55, 0.52), 0.78, 0.0)
    skylight_glass = make_material("asm_finger_glass", (0.65, 0.88, 0.98), 0.18, 0.35, 1.6)
    under_shadow = make_material("asm_pedestal_dark", (0.22, 0.24, 0.27), 0.62, 0.2)

    # Reflection lily pond & central tripod pedestal
    b.cylinder_z(pond_rim, (0.0, 0.0, 0.45), 16.5, 16.2, 0.9, sides=24)
    b.cylinder_z(pond_water, (0.0, 0.0, 0.92), 15.4, 15.4, 0.12, sides=24)
    b.cylinder_z(under_shadow, (0.0, 0.0, 3.2), 5.6, 7.8, 5.2, sides=16)

    # Central lotus bowl base
    bowl_rings = []
    for k, (z, r) in enumerate([(4.8, 6.2), (6.8, 10.5), (9.2, 13.2), (11.5, 11.8)]):
        ring = []
        for s in range(20):
            ang = (2.0 * math.pi * s) / 20
            ring.append((math.cos(ang) * r, math.sin(ang) * r, z))
        bowl_rings.append(ring)
    b.loft_rings(white_shell, bowl_rings, cap_bottom=True, cap_top=True)

    # 10 Asymmetric sculpted lotus fingers rising and curving outward + upward
    finger_heights = [29.0, 24.5, 20.5, 17.5, 22.0, 27.5, 31.0, 25.0, 19.0, 23.5]
    for i, fh in enumerate(finger_heights):
        ang = (2.0 * math.pi * i) / 10.0
        ca, sa = math.cos(ang), math.sin(ang)
        tx, ty = -sa, ca  # tangent vector
        sections = []
        steps = 8
        for s in range(steps + 1):
            u = s / steps
            # Curve outward from radius 5.5m to 14.5m while curving upward to fh
            r = 5.2 + u * 9.6 - (u * u) * 1.8
            z = 5.5 + (u ** 1.15) * (fh - 5.5)
            w = 3.2 * (1.0 - u * 0.42)
            thick = 2.4 * (1.0 - u * 0.45)
            cx, cy = ca * r, sa * r
            sections.append([
                (cx - ca * thick - tx * w, cy - sa * thick - ty * w, z - 0.6),
                (cx + ca * thick - tx * w, cy + sa * thick - ty * w, z),
                (cx + ca * thick + tx * w, cy + sa * thick + ty * w, z),
                (cx - ca * thick + tx * w, cy - sa * thick + ty * w, z - 0.6),
            ])
        b.loft_quad_sections(white_shell, sections)
        # Skylight glass window at the tip of each lotus finger
        tip = sections[-1]
        tip_cx = sum(p[0] for p in tip) * 0.25
        tip_cy = sum(p[1] for p in tip) * 0.25
        tip_cz = sum(p[2] for p in tip) * 0.25
        b.box(skylight_glass, (tip_cx, tip_cy, tip_cz + 0.35), (1.8, 1.8, 1.2))

    return b.finish("artscience_museum")


def build_merlion_landmark() -> dict:
    """Waterfront Merlion statue on wave plinth with arching water jet."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = MeshBuilder()

    ivory = make_material("merlion_ivory_stone", (0.93, 0.91, 0.86), 0.48, 0.04)
    plinth_stone = make_material("merlion_plinth_granite", (0.58, 0.57, 0.54), 0.74, 0.05)
    wave_blue = make_material("merlion_wave_crest", (0.22, 0.56, 0.72), 0.32, 0.1)
    water_jet = make_material("merlion_water_spray", (0.68, 0.94, 1.0), 0.12, 0.0, 2.2)
    warm_spot = make_material("merlion_plinth_light", (1.0, 0.82, 0.48), 0.25, 0.0, 2.8)

    # Stepped circular pier plinth & sculpted wave base
    b.cylinder_z(plinth_stone, (0.0, 0.0, 0.5), 5.2, 4.8, 1.0, sides=18)
    b.cylinder_z(plinth_stone, (0.0, 0.0, 1.35), 3.8, 3.4, 0.8, sides=18)
    b.cylinder_z(wave_blue, (0.0, 0.0, 2.05), 2.9, 2.5, 0.7, sides=16)
    for s in range(6):
        ang = (2.0 * math.pi * s) / 6.0
        b.box(warm_spot, (math.cos(ang) * 3.5, math.sin(ang) * 3.5, 1.82), (0.35, 0.35, 0.22))

    # Merlion body: curving S-shaped fish-tail rising into muscular lion chest & head (facing +Y in Blender -> -Z North into bay in Godot)
    spine = [
        (0.0, -0.9, 2.2, 1.85, 2.10),  # Lower fish tail base
        (0.0, -1.2, 3.4, 1.65, 1.90),  # Tail curve back
        (0.0, -0.8, 4.8, 1.50, 1.75),  # Mid scaled torso
        (0.0, -0.2, 6.2, 1.60, 1.85),  # Upper torso
        (0.0, 0.25, 7.6, 1.78, 2.05),  # Broad lion chest
        (0.0, 0.35, 9.0, 1.65, 1.90),  # Lion neck & mane collar
        (0.0, 0.45, 10.2, 1.45, 1.68), # Lion head core
        (0.0, 0.35, 11.1, 1.05, 1.20), # Crown of head
    ]
    rings = []
    sides = 14
    for _, cy, cz, rx, ry in spine:
        ring = []
        for s in range(sides):
            ang = (2.0 * math.pi * s) / sides
            ring.append((math.cos(ang) * rx, cy + math.sin(ang) * ry, cz))
        rings.append(ring)
    b.loft_rings(ivory, rings, cap_bottom=True, cap_top=True)

    # Sculpted tail fin curling up behind the lower back
    b.strut(ivory, (0.0, -1.6, 2.6), (0.0, -2.5, 4.6), 0.65, sides=6)
    b.box(ivory, (0.0, -2.7, 5.0), (1.9, 0.55, 1.3))

    # Sculpted lion mane ridges around neck/head & snout facing +Y (bayward)
    for z_mane in (8.2, 9.0, 9.8, 10.5):
        b.cylinder_z(ivory, (0.0, 0.15, z_mane), 1.92, 1.72, 0.52, sides=12)
    # Lion snout, lower jaw, and ears
    b.box(ivory, (0.0, 1.65, 10.15), (1.35, 1.45, 0.82))
    b.box(ivory, (0.0, 1.55, 9.45), (1.15, 1.25, 0.42))
    for sx in (-1.05, 1.05):
        b.box(ivory, (sx, 0.25, 11.15), (0.42, 0.45, 0.62))

    # Luminous water jet arching from mouth (0, 2.1, 9.8) out to (0, 13.5, 0.6) in the bay
    jet_pts = []
    for k in range(13):
        u = k / 12.0
        jy = 2.1 + u * 11.5
        jz = 9.8 + u * 2.2 - (u * u) * 11.4
        jet_pts.append((0.0, jy, jz))
    for k in range(len(jet_pts) - 1):
        rad = 0.22 + (k / len(jet_pts)) * 0.26
        b.strut(water_jet, jet_pts[k], jet_pts[k + 1], rad, sides=8)
    # Splash foam ring where jet hits the bay water
    b.cylinder_z(water_jet, (0.0, 13.6, 0.45), 2.4, 1.6, 0.35, sides=14)

    return b.finish("merlion_landmark")


def build_singapore_flyer() -> dict:
    """Giant spoked observation wheel with 28 viewing capsules and waterfront terminal."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = MeshBuilder()

    wheel_steel = make_material("flyer_white_steel", (0.86, 0.87, 0.89), 0.32, 0.65)
    hub_metal = make_material("flyer_hub_champagne", (0.76, 0.72, 0.64), 0.35, 0.70)
    capsule_glass = make_material("flyer_capsule_glass", (0.18, 0.42, 0.58), 0.16, 0.45, 0.8)
    capsule_glow = make_material("flyer_capsule_light", (1.0, 0.80, 0.44), 0.25, 0.10, 2.6)
    rim_neon = make_material("flyer_rim_glow", (0.45, 0.82, 1.0), 0.22, 0.10, 2.0)
    podium_mat = make_material("flyer_terminal_stone", (0.54, 0.56, 0.58), 0.72, 0.1)

    # Waterfront boarding terminal podium
    b.box(podium_mat, (0.0, 0.0, 4.2), (46.0, 28.0, 8.4))
    b.box(capsule_glass, (0.0, 0.0, 5.2), (42.0, 29.0, 4.5))
    b.box(hub_metal, (0.0, 0.0, 8.8), (48.0, 30.0, 0.6))

    # Wheel parameters: centered at Z = 62m, radius = 50m (top at 112m)
    cz = 62.0
    radius_outer = 50.0
    radius_inner = 45.5
    wheel_half_y = 3.8

    # Twin A-frame support legs on North and South sides of wheel hub
    for sy in (-1.0, 1.0):
        hy = sy * (wheel_half_y + 1.8)
        b.strut(wheel_steel, (-22.0, sy * 12.0, 8.0), (0.0, hy, cz), 1.05, sides=6)
        b.strut(wheel_steel, (22.0, sy * 12.0, 8.0), (0.0, hy, cz), 1.05, sides=6)
    # Central axle spindle
    b.strut(hub_metal, (0.0, -wheel_half_y - 3.2, cz), (0.0, wheel_half_y + 3.2, cz), 2.6, sides=12)

    # Outer and inner concentric rim trusses + cross braces + 28 viewing capsules
    num_capsules = 28
    for i in range(num_capsules):
        a0 = (2.0 * math.pi * i) / num_capsules
        a1 = (2.0 * math.pi * (i + 1)) / num_capsules
        c0, s0 = math.cos(a0), math.sin(a0)
        c1, s1 = math.cos(a1), math.sin(a1)

        for sy in (-wheel_half_y, wheel_half_y):
            p_out0 = (c0 * radius_outer, sy, cz + s0 * radius_outer)
            p_out1 = (c1 * radius_outer, sy, cz + s1 * radius_outer)
            p_in0 = (c0 * radius_inner, sy, cz + s0 * radius_inner)
            p_in1 = (c1 * radius_inner, sy, cz + s1 * radius_inner)
            b.strut(wheel_steel, p_out0, p_out1, 0.42, sides=5)
            b.strut(rim_neon if i % 2 == 0 else wheel_steel, p_in0, p_in1, 0.32, sides=5)
            b.strut(wheel_steel, p_in0, p_out0, 0.24, sides=4)
            # Tension spoke to hub every 2nd segment
            if i % 2 == 0:
                b.strut(wheel_steel, (0.0, sy * 0.85, cz), p_in0, 0.16, sides=4)

        # Cross-tie between front and back rims + cylindrical viewing capsule outside the rim
        cap_x = c0 * (radius_outer + 1.8)
        cap_z = cz + s0 * (radius_outer + 1.8)
        b.strut(
            wheel_steel,
            (c0 * radius_outer, -wheel_half_y, cz + s0 * radius_outer),
            (c0 * radius_outer, wheel_half_y, cz + s0 * radius_outer),
            0.28,
            sides=4,
        )
        # Capsule shell + glowing interior band
        b.strut(capsule_glass, (cap_x, -2.6, cap_z), (cap_x, 2.6, cap_z), 1.45, sides=8)
        b.strut(capsule_glow, (cap_x, -1.8, cap_z), (cap_x, 1.8, cap_z), 1.52, sides=8)
        for end_y in (-2.7, 2.7):
            b.box(hub_metal, (cap_x, end_y, cap_z), (2.2, 0.35, 2.2))

    return b.finish("singapore_flyer")


def main() -> None:
    manifest = [
        build_marina_bay_sands(),
        build_supertree_grove(),
        build_artscience_museum(),
        build_merlion_landmark(),
        build_singapore_flyer(),
    ]
    (OUT / "landmarks_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("LANDMARKS_MANIFEST " + json.dumps(manifest), flush=True)


if __name__ == "__main__":
    main()
