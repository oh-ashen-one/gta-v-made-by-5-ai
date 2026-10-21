# Helicopter refinement — wave 2

This repairs the inherited provider mesh's orientation and moving-part partition. It uses the existing raw Customuse output `W1-HERO-004.glb`; no new asset generation, credit spend or download occurred.

## Observed failure

The actual route captures `docs/wave-02/route-render-r1/08_helicopter_boarding.png` and `09_aerial_view.png` showed the nose facing +X while control forward is -Z, with orbital fragments around the main rotor.

Reading the inherited `helicopter_clean.glb` showed:

- All three mesh nodes had the same origin `(0, 1.871572, 0)` and scale `8.112126`; neither rotor had a shaft-centered pivot.
- `main_rotor` contained only 131 vertices, representing part of the blades.
- `tail_rotor` contained 16,114 vertices in the source +X cockpit/nose region. This was a classification error, not a tail fan.
- Runtime spin used the physics body's world axes, despite the visible provider root having independent pitch/roll. The spin owner needs to be the visible provider root.

## New derivative

`game/tools/refine_helicopter.py` runs in Blender 4.5.11 with `--background --factory-startup --threads 4`. It welds identical positions **for component classification only**, preserving the original mesh data and UV seams in the output. It classifies the isolated upper rotor assembly and outboard tail blades, retains all ambiguous or body-linked components on the static body, bakes the nose orientation to Godot -Z, and sets the measured rotor origins.

| Part | Triangles | Components | Pivot in Godot metres | Axis |
| --- | ---: | ---: | --- | --- |
| body | 41,001 | 181 | (0, 0, 0) | static |
| main_rotor | 7,328 | 67 | (0.077240, 3.430000, -0.841712) | Y |
| tail_rotor | 1,118 | 3 | (-0.646000, 2.311243, 3.208409) | X |

All **49,447 source triangles** remain represented exactly once. Source UVs, custom normals and materials are retained. The source-to-forward coordinate assertion and rest geometry reconstruction differ by less than 0.00000024 m. Checks at 0, 45, 90, 180 and 270 degrees preserve each rotor's shaft-axis coordinate. The raw and output SHA256 values are in `refinement-report.json`.

- Private runtime derivative: `game/assets/providers/helicopter_refined.glb`.
- Private editable source: `art/source/helicopter/helicopter_refined.blend`, outside Godot's auto-import tree.
- Numeric report: `docs/wave-02/helicopter/refinement-report.json`.
- CPU projection: `rotor_partition_spin.png`. Cyan identifies the main assembly, orange the tail blades, and red marks their pivots. This is **not an in-engine render or acceptance capture**.

## Integration

Load `helicopter_refined.glb`. The expected node names remain `body`, `main_rotor` and `tail_rotor`. No corrective yaw is needed.

Use `_provider_root` as the `owner_body` argument to `AssetLibrary.spin_part`, so Y/X axes follow visual pitch and roll. The current helicopter collision box has its bottom at local Y=0.30, while the new asset is grounded at Y=0. Set the visual root position Y to 0.30 to align skids with that existing collision contract; changing physics remains the root agent's decision.

## Remaining limits

The generated rotor geometry is not perfectly symmetric. Lower swashplate rods, tail motor/shaft, stabilizers and ambiguous body-linked thin pieces remain static. Some thin generated mast/strut artifacts remain visible; they were not silently discarded. No claim is made about aerodynamics or a complete physical collision hull. Actual rendered spin during visual tilt, nose/control alignment, landing clearance and vehicle transitions remain separate runtime gates.

This is a private derivative under the existing asset provenance. Repartitioning does not establish blanket public redistribution clearance.
