#!/usr/bin/env python3
"""Original Blender-authored 3D Singapore waterfront & skyline landmarks.
Run with:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python game/tools/build_landmarks.py
(wave A, Opus 5.5: rebuilt MBS, Supertrees and Merlion with Blender 5.2)

Generates in game/assets/authored/:
  - marina_bay_sands.glb     (3 curved-leg towers + cantilevered boat-hulled SkyPark, true scale)
  - supertree_grove.glb      (7 vertical-garden Supertrees, rust-purple steel, planted funnel throats under open perforated steel-lattice crowns, skyway)
  - artscience_museum.glb    (10-finger sculpted lotus museum on reflection pond base)
  - merlion_landmark.glb     (metaball-sculpted Merlion on wave plinth + arching water jet)
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
    """Three curved-leg hotel towers under a cantilevered, boat-hulled SkyPark.

    Wave A (Opus 5.5) rebuild at true scale (no non-uniform scale in Godot):
    towers ~194 m, SkyPark ~300 m long with a ~75 m cantilever off the west
    tower. Seen from the bay (Blender -Y face), each tower is a straight leg
    plus a leg that curves out toward the ground, split by a thin atrium slit
    that closes ~75 m up. The SkyPark is a thick tapered hull (dark soffit,
    champagne sides) carrying a pool, palms and pavilions, so it reads as a
    mass rather than a plank. Facade floor banding comes from the Godot
    landmark glass shader (material name mbs_curtain_glass).
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = MeshBuilder()

    steel = make_material("mbs_champagne_steel", (0.50, 0.47, 0.41), 0.38, 0.62)
    hull_side = make_material("mbs_skypark_hull", (0.30, 0.30, 0.30), 0.30, 0.6)
    soffit = make_material("mbs_skypark_soffit", (0.20, 0.21, 0.22), 0.70, 0.30)
    glass = make_material("mbs_curtain_glass", (0.30, 0.40, 0.47), 0.14, 0.55)
    gap_dark = make_material("mbs_atrium_shadow", (0.06, 0.07, 0.08), 0.85, 0.0)
    podium_stone = make_material("mbs_podium_stone", (0.42, 0.40, 0.37), 0.80, 0.05)
    podium_glass = make_material("mbs_podium_glass", (0.16, 0.22, 0.26), 0.20, 0.45)
    deck_wood = make_material("mbs_skypark_deck", (0.50, 0.38, 0.26), 0.75, 0.0)
    pool_aqua = make_material("mbs_infinity_pool", (0.10, 0.52, 0.62), 0.06, 0.15)
    foliage = make_material("mbs_sky_foliage", (0.13, 0.30, 0.13), 0.90, 0.0)
    pavilion = make_material("mbs_skypark_pavilion", (0.62, 0.61, 0.58), 0.45, 0.10)

    H = 192.0          # tower top (SkyPark soffit sits on it)
    JOIN = 78.0        # legs fuse above this height
    DEPTH = 24.0
    tower_xs = [-92.0, 0.0, 92.0]

    def ring_xy(x0: float, x1: float, y0: float, y1: float, z: float) -> list:
        return [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]

    for t_idx, tx in enumerate(tower_xs):
        half_top = 15.0
        slit_x = tx + 3.0
        left_sec, right_sec, upper_sec = [], [], []
        steps = 18
        for s in range(steps + 1):
            z = 4.0 + (H - 4.0) * (s / steps)
            u = min(1.0, (z - 4.0) / (H * 0.62))
            # Curved east leg: concave flare toward the ground (~15 m wider at the base).
            bulge = 15.0 * (1.0 - u) ** 1.8
            # Slight inward lean of the whole tower above the join, as built.
            lean = -2.2 * (z / H)
            xl = tx - half_top + lean
            xr = tx + half_top + bulge + lean
            # The curved leg also rakes back in depth near the ground.
            y0 = -DEPTH * 0.5 - 2.0 * (1.0 - u) ** 2
            y1 = DEPTH * 0.5
            if z <= JOIN:
                g = 1.6 * (1.0 - z / JOIN) ** 0.8
                left_sec.append(ring_xy(xl, slit_x - g + lean, y0 + 1.0, y1, z))
                right_sec.append(ring_xy(slit_x + g + lean, xr, y0, y1, z))
            if z >= JOIN - (H - 4.0) / steps:
                upper_sec.append(ring_xy(xl, xr, y0, y1, z))
        b.loft_quad_sections(glass, left_sec)
        b.loft_quad_sections(glass, right_sec)
        b.loft_quad_sections(glass, upper_sec)
        # Dark atrium slit behind the gap so it reads as depth, not sky.
        b.box(gap_dark, (slit_x - 0.6, 0.0, JOIN * 0.5), (2.6, DEPTH - 3.0, JOIN))
        # Vertical steel fins on the bay face at the leg edges and slit.
        for fx, top in ((tx - half_top, H), (slit_x, JOIN), (tx + half_top, H)):
            b.strut(steel, (fx - 0.4, -DEPTH * 0.5 - 0.5, 4.0), (fx - 2.2 * (top / H), -DEPTH * 0.5 - 0.5, top), 0.45, sides=4)
        # Crown band where the tower meets the SkyPark: a recessed dark reveal.
        b.box(gap_dark, (tx - 2.2, 0.0, H - 1.2), (half_top * 2.0 - 1.0, DEPTH - 1.0, 2.4))
        # Ground lobby canopy.
        b.box(steel, (tx + 4.0, -DEPTH * 0.5 - 5.0, 9.0), (36.0, 10.0, 0.8))

    # ---------------------------------------------------------------- SkyPark
    # Plan stations (x, half-width). The bow cantilevers west (-X) ~75 m past
    # the west tower; the stern is rounded just past the east tower.
    stations = [
        (-185.0, 1.5), (-176.0, 7.0), (-160.0, 13.0), (-135.0, 17.0), (-100.0, 19.0),
        (-40.0, 19.5), (20.0, 19.5), (80.0, 19.0), (106.0, 17.0), (116.0, 12.0), (120.0, 5.0),
    ]
    deck_z = H + 9.0
    hull_rings, deck_rings, soffit_rings = [], [], []
    for x, hy in stations:
        # The keel rises toward the cantilever bow so it reads as a hull.
        rise = max(0.0, (-110.0 - x) / 75.0)
        keel_z = H + 0.2 + rise * 4.5
        keel_hy = max(0.5, hy * 0.62)
        hull_rings.append([(x, -keel_hy, keel_z), (x, keel_hy, keel_z), (x, hy, deck_z - 1.2), (x, -hy, deck_z - 1.2)])
        soffit_rings.append([(x, -keel_hy - 0.05, keel_z - 0.15), (x, keel_hy + 0.05, keel_z - 0.15), (x, keel_hy * 0.8, keel_z - 0.6), (x, -keel_hy * 0.8, keel_z - 0.6)])
        deck_rings.append([(x, -hy, deck_z - 1.2), (x, hy, deck_z - 1.2), (x, hy * 0.97, deck_z), (x, -hy * 0.97, deck_z)])
    b.loft_quad_sections(hull_side, hull_rings)
    b.loft_quad_sections(soffit, soffit_rings)
    b.loft_quad_sections(deck_wood, deck_rings)
    # Edge fascia line (thin dark band) along both long sides for a crisp read.
    for i in range(len(stations) - 1):
        for side in (-1.0, 1.0):
            x0, h0 = stations[i]
            x1, h1 = stations[i + 1]
            b.strut(soffit, (x0, side * (h0 + 0.1), deck_z - 1.4), (x1, side * (h1 + 0.1), deck_z - 1.4), 0.35, sides=4)
            b.strut(steel, (x0, side * h0, deck_z + 0.7), (x1, side * h1, deck_z + 0.7), 0.18, sides=4)
            # Pale fascia band along the top edge: the crisp line the SkyPark
            # reads as from the bay, over the darker hull below.
            b.strut(pavilion, (x0, side * (h0 + 0.15), deck_z - 0.5), (x1, side * (h1 + 0.15), deck_z - 0.5), 0.6, sides=4)
    # Infinity pool along the bay (-Y) edge, with a pale stone surround.
    b.box(pavilion, (-10.0, -12.5, deck_z + 0.25), (150.0, 9.0, 0.5))
    b.box(pool_aqua, (-10.0, -13.0, deck_z + 0.55), (146.0, 6.5, 0.3))
    # Pavilions / restaurants along the spine.
    for px, w, d, h in ((-140.0, 18.0, 14.0, 5.0), (-85.0, 24.0, 12.0, 6.0), (50.0, 30.0, 14.0, 6.5), (98.0, 14.0, 12.0, 5.0)):
        b.box(pavilion, (px, 5.0, deck_z + h * 0.5), (w, d, h))
        b.box(steel, (px, 5.0, deck_z + h + 0.3), (w + 2.0, d + 2.0, 0.6))
    # Garden: dense palm/tree rows (round crowns, not cones) on the land side.
    for tx in range(-168, 112, 7):
        for ty in (3.0, 12.0):
            if any(abs(tx - px) < w * 0.5 + 2 for px, w, _d, _h in ((-140.0, 18.0, 0, 0), (-85.0, 24.0, 0, 0), (50.0, 30.0, 0, 0), (98.0, 14.0, 0, 0))) and ty < 10:
                continue
            hy = next(h for x, h in stations if x >= tx) if tx < 120 else 5.0
            if abs(ty) > hy - 2.0:
                continue
            b.cylinder_z(deck_wood, (tx, ty, deck_z + 1.6), 0.35, 0.25, 3.2, sides=5)
            b.cylinder_z(foliage, (tx, ty, deck_z + 3.8), 2.6, 1.4, 2.0, sides=7)
            b.cylinder_z(foliage, (tx, ty, deck_z + 5.0), 1.4, 0.2, 0.9, sides=7)

    # ---------------------------------------------------------------- podium
    # Low waterfront podium (shoppes/convention) in front of the towers, with
    # three shallow vaulted roofs so the base is not one flat slab.
    # Kept north of the far-shore road (Godot z > -665 is roadway).
    b.box(podium_stone, (-20.0, -27.0, 6.0), (300.0, 20.0, 12.0))
    b.box(podium_glass, (-20.0, -37.2, 5.0), (296.0, 0.6, 8.0))
    for vx in (-130.0, -20.0, 90.0):
        # shallow vault as stepped bands (cheap, reads at distance)
        for k in range(5):
            w = 92.0 - k * 10.0
            b.box(podium_stone if k % 2 == 0 else steel, (vx, -27.0, 12.4 + k * 1.0), (w, 19.0 - k * 3.4, 1.0))
    b.box(podium_stone, (0.0, 0.0, 2.0), (330.0, 50.0, 4.0))

    # Mirror in X so the SkyPark cantilever points east (+X): from the street
    # vista the towers then stay clear of the Supertree Grove to their west.
    for name, (v, f) in b.data.items():
        v[:] = [(-x, y, z) for x, y, z in v]
        f[:] = [tuple(reversed(face)) for face in f]

    return b.finish("marina_bay_sands")


def build_supertree_grove() -> dict:
    """Supertree Grove: vertical-garden trunks, rust-purple steel exoskeletons,
    and solid inverted-funnel canopies with a steel lattice, plus a skyway.

    Wave A (Opus 5.5) rebuild. The wave-5 crowns were open wire rings in
    emissive magenta and white, which read as cocktail glasses. Each canopy is
    now a double-sided planted funnel shell (mass) dressed with radial ribs,
    concentric hoops and diagonal bracing in a weathered rust-purple steel.
    Daylight look, no emission. The layout is compacted so the grove stands
    clear of the Marina Bay Sands silhouette from the street vista.
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = MeshBuilder()

    garden = make_material("st_vertical_garden", (0.20, 0.32, 0.16), 0.92, 0.0)
    # Linear values: a weathered purple-brown steel that stays dark in warm light.
    steel = make_material("st_steel_rust", (0.11, 0.045, 0.06), 0.55, 0.45)
    steel_dark = make_material("st_steel_dark", (0.06, 0.03, 0.04), 0.60, 0.40)
    canopy_shell = make_material("st_canopy_shell", (0.075, 0.035, 0.05), 0.80, 0.15)
    canopy_plant = make_material("st_canopy_planting", (0.22, 0.30, 0.15), 0.92, 0.0)
    skyway_steel = make_material("st_skyway_steel", (0.48, 0.46, 0.43), 0.40, 0.55)
    mound_stone = make_material("st_planter_stone", (0.26, 0.25, 0.22), 0.85, 0.0)

    S = 0.70
    trees = [
        (0.0, 0.0, 50.0, 4.6, 14.5),
        (-22.0, -7.0, 42.0, 3.8, 12.5),
        (22.0, -5.0, 43.0, 3.9, 12.8),
        (-14.0, 17.0, 33.0, 3.1, 10.0),
        (15.0, 18.0, 36.0, 3.3, 10.6),
        (-31.0, 11.0, 27.0, 2.7, 8.6),
        (30.0, 13.0, 29.0, 2.8, 9.0),
    ]
    # Heights x0.85 (real Supertrees are 25-50 m): the tallest crown now fits
    # the street-vista frame instead of being cut off by its top edge.
    # The layout is mirrored north-south: the tall skyway pair stands on the far
    # (bay) side, the short trees face the street, so the grove steps up.
    trees = [(x * S, -y * S, h * 0.85, br * 0.92, cr * 0.9) for x, y, h, br, cr in trees]

    def ring(cx, cy, z, r, sides, phase=0.0, wobble=0.0, seed=0):
        pts = []
        for s in range(sides):
            ang = 2.0 * math.pi * s / sides + phase
            rr = r * (1.0 + wobble * math.sin(ang * 5.0 + seed + z * 0.7) * math.cos(ang * 3.0 + z * 0.33 + seed))
            pts.append((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr, z))
        return pts

    for idx, (cx, cy, h, br, cr) in enumerate(trees):
        # Planter mound and bench ring.
        b.cylinder_z(mound_stone, (cx, cy, 0.6), br + 3.6, br + 2.8, 1.2, sides=20)
        b.cylinder_z(garden, (cx, cy, 1.35), br + 2.6, br + 1.6, 0.4, sides=20)

        # Trunk profile: base -> waist -> collar under the canopy.
        prof = [(0.0, 1.00), (0.12, 0.90), (0.30, 0.74), (0.50, 0.62), (0.60, 0.64), (0.66, 0.74)]
        z_of = lambda u: 1.4 + u * (h - 1.4)
        sides = 20
        rings_g = [ring(cx, cy, z_of(u), br * f, sides, wobble=0.10, seed=idx * 3.1) for u, f in prof]
        b.loft_rings(garden, rings_g, cap_bottom=True, cap_top=True)

        # Exoskeleton: 10 ribs following the trunk then flaring into the canopy.
        ribs = 10
        z_c0 = z_of(0.66)
        r_c0 = br * 0.78 + 0.45
        for r_i in range(ribs):
            ang = 2.0 * math.pi * r_i / ribs
            ca, sa = math.cos(ang), math.sin(ang)
            pts = [(cx + ca * (br * f + 0.45), cy + sa * (br * f + 0.45), z_of(u)) for u, f in prof]
            for k in range(len(pts) - 1):
                b.strut(steel, pts[k], pts[k + 1], 0.20, sides=5)
            # Spiral cross-bracing between neighbouring ribs (diamond lattice on the trunk).
            ang_n = 2.0 * math.pi * (r_i + 1) / ribs
            for k in range(len(prof) - 1):
                u0, f0 = prof[k]
                u1, f1 = prof[k + 1]
                p0 = (cx + ca * (br * f0 + 0.45), cy + sa * (br * f0 + 0.45), z_of(u0))
                p1 = (cx + math.cos(ang_n) * (br * f1 + 0.45), cy + math.sin(ang_n) * (br * f1 + 0.45), z_of(u1))
                b.strut(steel_dark, p0, p1, 0.12, sides=4)
        # Horizontal hoops on the trunk.
        for u, f in prof[1:]:
            pts = ring(cx, cy, z_of(u), br * f + 0.5, 16)
            for k in range(16):
                b.strut(steel_dark, pts[k], pts[(k + 1) % 16], 0.13, sides=4)

        # Canopy: an inverted funnel. Inner planted shell + outer steel shell,
        # both double-sided so the mass reads from above and below.
        cz0 = z_c0
        # Trumpet flare: narrow throat, then a wide shallow lip.
        crown = [(0.0, r_c0), (0.35, cr * 0.30), (0.62, cr * 0.55), (0.86, cr * 0.84), (1.0, cr)]
        cz = lambda t: cz0 + t * (h - cz0)
        shell_sides = 24
        outer = [ring(cx, cy, cz(t), r, shell_sides) for t, r in crown]
        # Round 2: only the throat is a solid planted funnel. The outer bowl is
        # an open steel lattice with perforated panels on a checkerboard and
        # planted pockets, so sky shows through the crown as on the real
        # Supertrees (the critic read the solid bowls as planters).
        throat = outer[:3]
        b.loft_rings(canopy_shell, throat)
        b.loft_rings(canopy_shell, [list(reversed(rg)) for rg in throat])
        inner = [ring(cx, cy, cz(t) + 0.6, r * 0.93, shell_sides, phase=0.05) for t, r in crown[1:3]]
        b.loft_rings(canopy_plant, [list(reversed(rg)) for rg in inner])

        def panel(mat, ra, rb, j, inset=0.0):
            jn = (j + 1) % len(ra)
            quad = [ra[j], ra[jn], rb[jn], rb[j]]
            if inset:
                quad = [(x, y, z + inset) for x, y, z in quad]
            v, f = b.data[mat.name]
            k = len(v)
            v.extend(quad)
            f.append((k, k + 1, k + 2, k + 3))
            f.append((k + 3, k + 2, k + 1, k))

        for k in range(2, len(outer) - 1):
            for j in range(shell_sides):
                cell = (j + k) % 4
                if cell == 0:
                    panel(canopy_shell, outer[k], outer[k + 1], j)
                elif cell == 2 and (j // 2 + idx) % 2 == 0:
                    panel(canopy_plant, outer[k], outer[k + 1], j, inset=0.5)
        # Radial ribs on the outside of the funnel.
        n_r = 16
        for r_i in range(n_r):
            ang = 2.0 * math.pi * r_i / n_r
            ca, sa = math.cos(ang), math.sin(ang)
            pts = [(cx + ca * (r + 0.35), cy + sa * (r + 0.35), cz(t) - 0.2) for t, r in crown]
            for k in range(len(pts) - 1):
                b.strut(steel, pts[k], pts[k + 1], 0.26, sides=5)
            # Diagonal bracing between ribs: the lattice that gives the funnel texture.
            ang_n = 2.0 * math.pi * (r_i + 1) / n_r
            for k in range(1, len(crown) - 1):
                t0, r0 = crown[k]
                t1, r1 = crown[k + 1]
                p0 = (cx + ca * (r0 + 0.4), cy + sa * (r0 + 0.4), cz(t0) - 0.2)
                p1 = (cx + math.cos(ang_n) * (r1 + 0.4), cy + math.sin(ang_n) * (r1 + 0.4), cz(t1) - 0.2)
                b.strut(steel_dark, p0, p1, 0.14, sides=4)
                p2 = (cx + math.cos(ang_n) * (r0 + 0.4), cy + math.sin(ang_n) * (r0 + 0.4), cz(t0) - 0.2)
                p3 = (cx + ca * (r1 + 0.4), cy + sa * (r1 + 0.4), cz(t1) - 0.2)
                b.strut(steel_dark, p2, p3, 0.14, sides=4)
        # Concentric hoops, with a heavy rim at the lip.
        for k, (t, r) in enumerate(crown[1:]):
            pts = ring(cx, cy, cz(t) - 0.2, r + 0.4, n_r * 2)
            rad = 0.55 if k == len(crown) - 2 else 0.22
            for j in range(n_r * 2):
                b.strut(steel, pts[j], pts[(j + 1) % (n_r * 2)], rad, sides=5)
        # Top rim planting tufts (irregular silhouette instead of a perfect ring).
        for j in range(12):
            a = 2.0 * math.pi * (j + 0.5) / 12
            px, py = cx + math.cos(a) * cr * 0.9, cy + math.sin(a) * cr * 0.9
            b.cylinder_z(canopy_plant, (px, py, h + 0.5), 1.4 + (j % 3) * 0.4, 0.4, 1.4 + (j % 2) * 0.6, sides=6)

    # Skyway between the two flanking trees and the flagship, at 22 m.
    sk = [(trees[1][0], trees[1][1]), (-9.0 * S, 3.0 * S), (trees[0][0], trees[0][1]), (9.0 * S, 2.0 * S), (trees[2][0], trees[2][1])]
    skz = 22.0
    for i in range(len(sk) - 1):
        x0, y0 = sk[i]
        x1, y1 = sk[i + 1]
        b.strut(skyway_steel, (x0, y0, skz), (x1, y1, skz), 1.0, sides=4)
        for side in (-1.0, 1.0):
            dx, dy = x1 - x0, y1 - y0
            ln = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / ln * side * 1.1, dx / ln * side * 1.1
            b.strut(skyway_steel, (x0 + nx, y0 + ny, skz + 1.2), (x1 + nx, y1 + ny, skz + 1.2), 0.08, sides=4)

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
    """Merlion: lion head with a heavy mane on an upright fish body that sits
    on a curled tail, spouting an arc of water, on a wave-carved plinth.

    Wave A (Opus 5.5) rebuild. The wave-5 figure was a lofted capsule, which
    read as a white blob. The figure is now sculpted from metaballs (lion
    head, muzzle, open mouth, ears, mane locks, chest, flippers, scaled body,
    curled tail and fin) and converted to a smooth mesh, then scaled to the
    real statue's ~8.6 m figure height. Facing +Y (Godot -Z before yaw).
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = MeshBuilder()

    ivory = make_material("merlion_ivory_stone", (0.74, 0.71, 0.64), 0.6, 0.0)
    plinth_stone = make_material("merlion_plinth_granite", (0.24, 0.23, 0.22), 0.78, 0.05)
    wave_stone = make_material("merlion_wave_stone", (0.52, 0.50, 0.46), 0.66, 0.0)
    water_jet = make_material("merlion_water_spray", (0.80, 0.90, 0.94), 0.10, 0.0, 0.35)

    mb = bpy.data.metaballs.new("merlion_figure")
    mb.resolution = 0.075
    mb.render_resolution = 0.075
    mb.threshold = 0.6

    def ball(co, r, neg=False):
        e = mb.elements.new(type="BALL")
        e.co = co
        e.radius = r
        e.use_negative = neg
        return e

    def ell(co, size, r=1.0, rot=(1.0, 0.0, 0.0, 0.0), neg=False):
        e = mb.elements.new(type="ELLIPSOID")
        e.co = co
        e.radius = r
        e.size_x, e.size_y, e.size_z = size
        e.rotation = rot
        e.use_negative = neg
        return e

    def qx(deg):
        a = math.radians(deg) * 0.5
        return (math.cos(a), math.sin(a), 0.0, 0.0)

    # Curled fish tail behind and below the body (spiral rising backward then up).
    tail = [((0.0, -1.2, 1.25), 1.55), ((0.0, -2.2, 1.45), 1.30), ((0.0, -3.0, 2.0), 1.10),
            ((0.0, -3.35, 2.8), 0.92), ((0.0, -3.25, 3.55), 0.78), ((0.0, -2.8, 4.05), 0.66)]
    for co, r in tail:
        ball(co, r)
    # Tail fin: two flattened lobes flaring up and back from the curl tip.
    ell((0.0, -2.75, 4.65), (0.16, 0.95, 0.75), 1.0, qx(-20))
    # Upright scaled body rising from the tail to the chest.
    body = [((0.0, -0.55, 1.6), 1.65), ((0.0, -0.30, 2.7), 1.55), ((0.0, -0.05, 3.8), 1.50), ((0.0, 0.25, 4.8), 1.62)]
    for co, r in body:
        ball(co, r)
    # (Scale texture is left to shading: sculpted bumps read as knobs at range.)
    # Front flippers / forelegs braced against the chest (kept inside the
    # body's field so they merge instead of floating as separate blobs).
    for sx in (-1.0, 1.0):
        ell((sx * 0.7, 0.85, 3.4), (0.40, 0.60, 0.9), 1.15, qx(-18))
    # Neck and the lion head.
    ball((0.0, 0.35, 5.6), 1.55)
    ell((0.0, 0.60, 6.40), (1.10, 1.0, 1.0), 1.40)
    # Mane: one heavy ruff framing the face plus merged locks flowing down the
    # back of the neck (separate small balls read as fingers at range).
    ell((0.0, -0.10, 6.35), (1.65, 1.0, 1.45), 1.75)
    # Mane (skyline round 2): the round-1 rim of 20 equal curls on one circle
    # read as a gear. The ruff is now three staggered layers of tufts that
    # shrink and step back from the face, with irregular sizes, so the
    # silhouette is a shaggy, layered lion's mane with depth.
    rng_m = random.Random(512)
    for layer, (rad_x, rad_z, depth, n, rr) in enumerate(((1.45, 1.35, 0.30, 13, 0.80), (1.70, 1.55, -0.20, 11, 0.78), (1.35, 1.30, -0.75, 9, 0.85))):
        for k in range(n):
            a = 2.0 * math.pi * (k + 0.5 * layer) / n
            if layer == 0 and math.sin(a) < -0.75:
                continue  # chin stays clear for the beard
            jitter = 1.0 + rng_m.uniform(-0.12, 0.12)
            ball((math.cos(a) * rad_x * jitter, depth + rng_m.uniform(-0.12, 0.12), 6.35 + math.sin(a) * rad_z * jitter), rr * rng_m.uniform(0.85, 1.12))
    ball((0.0, 0.9, 4.95), 1.05)
    for k in range(10):
        a = 2.0 * math.pi * k / 10.0
        ca, sa = math.cos(a), math.sin(a)
        if sa > 0.4:  # leave the face open
            continue
        ball((ca * 1.25, 0.15 + sa * 0.6, 6.3 + 0.6 * math.cos(a)), 1.05)
    for k, (yy, zz, rr) in enumerate(((-0.55, 7.0, 1.0), (-0.85, 6.2, 1.05), (-0.95, 5.4, 1.0), (-0.85, 4.7, 0.85))):
        ball((0.0, yy, zz), rr)
    # Ears.
    for sx in (-1.0, 1.0):
        ell((sx * 0.7, 0.55, 7.45), (0.34, 0.24, 0.40), 1.0)
    # Muzzle pushed forward, nose bridge and tip, brow ridge.
    ell((0.0, 1.80, 6.25), (0.75, 1.05, 0.62), 1.15)
    ell((0.0, 1.40, 6.80), (0.50, 0.70, 0.30), 1.0)
    ball((0.0, 2.35, 6.42), 0.42)
    ell((0.0, 1.05, 7.05), (0.85, 0.45, 0.32), 1.0)
    # Lower jaw, dropped open.
    ell((0.0, 1.75, 5.50), (0.50, 0.78, 0.28), 1.0, qx(14))
    # Open mouth (negative) between the jaws.
    ell((0.0, 2.30, 5.90), (0.46, 0.85, 0.18), 1.0, neg=True)
    # Eye sockets.
    for sx in (-1.0, 1.0):
        ball((sx * 0.45, 1.65, 6.75), 0.24, neg=True)

    ob = bpy.data.objects.new("merlion_figure", mb)
    bpy.context.collection.objects.link(ob)
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(deps))
    bpy.data.objects.remove(ob)
    # Normalise: figure stands on z=2.4 (top of plinth + wave base) and its
    # crown reaches 2.4 + 8.6 m.
    zs = [v.co.z for v in me.vertices]
    z0, z1 = min(zs), max(zs)
    k = 8.6 / max(0.01, (z1 - z0))
    for v in me.vertices:
        v.co.x *= k
        v.co.y *= k
        v.co.z = (v.co.z - z0) * k + 2.2
    for p in me.polygons:
        p.use_smooth = True
    me.materials.clear()
    me.materials.append(ivory)
    fig = bpy.data.objects.new("merlion_landmark_figure", me)
    fig["authoring"] = "Original Blender metaball sculpt; Wave A Opus 5.5"
    bpy.context.collection.objects.link(fig)
    mouth = (0.0, 2.45 * k, (5.9 - z0) * k + 2.2)

    # Stepped granite plinth and carved wave base.
    b.cylinder_z(plinth_stone, (0.0, 0.0, 0.5), 5.4, 5.0, 1.0, sides=24)
    b.cylinder_z(plinth_stone, (0.0, 0.0, 1.25), 4.2, 3.9, 0.5, sides=24)
    for j in range(9):
        a = 2.0 * math.pi * j / 9.0
        b.cylinder_z(wave_stone, (math.cos(a) * 2.4, math.sin(a) * 2.4 - 0.6, 1.75), 1.35, 0.55, 0.9, sides=10)
    # Water jet arcing from the mouth into the bay.
    pts = []
    for i in range(15):
        u = i / 14.0
        pts.append((0.0, mouth[1] + u * 12.0, mouth[2] + u * 2.6 - u * u * (mouth[2] + 2.0)))
    for i in range(len(pts) - 1):
        b.strut(water_jet, pts[i], pts[i + 1], 0.16 + 0.18 * i / 14.0, sides=8)

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
