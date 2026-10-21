# Wave 2 character rig work

Author: current GPT-6 Astra subagent through the actual Codex tools. This is source and asset preparation evidence; gameplay acceptance is recorded by the main wave agent.

## Source and scope

- Inputs: `game/assets/providers/player_clean.glb` and `officer_clean.glb`, inherited from the manager's 152-file SHA256-verified provider copy. Original inputs are unchanged.
- New derivatives: `player_rigged.glb`, `officer_rigged.glb`, `civilian_rigged.glb`, and associated `*_rig_report.json`, under the ignored provider directory.
- Editable copies: `art/source/characters/{player,officer,civilian}_rigged.blend`, deliberately outside the Godot project so `.blend` auto-import cannot launch an unattended Blender listener.
- Durable authoring source: `game/tools/rig_characters.py`. It runs in Blender 4.5.11 without rendering/network access and can also write CPU-evaluated pose samples with `--diagnostics /tmp/astra_rig_samples`.
- Runtime presentation component: `game/src/actors/character_visual.gd`. The owning Player/NPC still controls health, movement, collision and gameplay transitions.

## Measured derivatives

| Asset | Triangles | Skeleton | Clips |
| --- | ---: | ---: | --- |
| Player | 52,914 | 24 bones | idle, walk, run, aim, aim_walk, aim_run, reload, hit, jump, fall, seated, drive |
| Officer | 29,999 | 24 bones | same |
| Civilian | 18,000 | 24 bones | same |

The characters are normalized to 1.75 m (player/civilian) and 1.78 m (officer), grounded at zero and aligned to Godot -Z. A measured baked source yaw is corrected before rigging. The original PBR maps and UVs are retained; clothing uses a separately addressable duplicate material so NPC color variation does not tint skin.

## Iteration evidence

1. Source views were inspected in four orthographic directions. These are CPU-projected mesh diagnostics, not engine captures. The models were unrigged and were not facing the gameplay forward axis.
2. A symmetric geometric envelope produced obvious hand/torso stretching in the first aim pose. This failed inspection and was replaced.
3. Texture-based skin classification still caught UV atlas-edge bleed and failed pose edge-stretch checks. It was replaced by connected forearm/hand component classification below the sleeve cut, with exact seam-coordinate welding.
4. Civilian decimation originally separated small hand islands before classification. Applying decimation **after** skinning preserves their inherited weights and fixes the detached fragments.
5. Baked pose evaluation now uses linear skinning, matching glTF/Godot, rather than Blender's preserve-volume deformation. Ground contact is corrected using evaluated mesh bounds. Aiming uses a baked two-bone solve to bring both hands toward one gun, with one finger-curl bone per hand.

`*_source_views.png` and `*_rig_round01.png` are **CPU-projected diagnostics of the actual supplied/evaluated mesh**, labelled on-image. They are not photographs, generated concepts, or in-game/rendered acceptance evidence. The final gameplay render remains a separate gate.

## Integration API

```gdscript
var visual := CharacterVisual.new()
body_root.add_child(visual)
if visual.configure("player"): # "officer", or "civilian", wardrobe_variant
    # Use this visual in place of the legacy block body.
    pass
visual.set_motion(horizontal_speed, aiming, is_on_floor(), reloading)
visual.play_hit()
visual.play_death()
visual.reset_alive()
visual.attach_weapon(imported_weapon, "pistol")
visual.set_seated(true) # diner; true, true for a driver pose
visual.set_seated(false) # stand on panic / resume locomotion
```

`weapon_socket` is a `BoneAttachment3D` bound to `hand.r`. Use `pistol_held.glb` or `smg_held.glb` with `attach_weapon(node, weapon_kind)`. The source pistol was visually verified to point along -X; the source SMG was diagonally tilted. These new derivatives face -Z and use an estimated grip origin. `set_aim_pitch(pitch)` and `weapon_muzzle_position()` support barrel and flash alignment. Their final socket fit still needs an in-engine view. The body root remains the parent that faces movement/aim direction. On NPC death, play the `fall` clip instead of rotating the whole visual a second time. On respawn, reset the clip state. Preserve gameplay collision shapes and vehicle hide/show semantics.

## Runtime and rights gates

- **Verified:** Blender 4.5.11 CPU import/export exited 0; exported GLBs each contain one skin, 24 joints and twelve named animations; source geometry/PBR map preservation; CPU pose diagnostics.
- **Numeric refinement:** after the first actual Godot review, broader sleeve blending and pelvis-centered crotch weights removed all player/civilian aim and walk-contact edges extending over 10 cm in the sampled poses. Officer aim still has 32 such gear/cloth edges. The hit pose is now grounded. These sampled metrics are diagnostic bounds rather than a blanket deformation pass; see `asset-verification.json`.
- **Actual Godot evidence:** the root-controlled `docs/wave-02/character-render/` fixture showed the imported player, idle/aim/run/reload/fall clips and aimed pistol socket in the real district. The first capture exposed a visible sleeve flap, which drove the next weight correction. These are fixture captures, not mission evidence.
- **Still pending after the latest asset changes:** repeated rendered sleeve/shoe inspection, seated/driver placement, full locomotion transitions, hit/death/respawn during gameplay, camera occlusion and population performance. The root wave agent owns these checks.
- **Open quality gaps:** procedural authored gait rather than mocap; no runtime foot-placement IK; no facial articulation and only one curl bone per hand; limited body/outfit diversity; grip and shoulder deformation still need actual engine inspection. These assets improve the primitive avatar but do not meet the GTA VI fidelity target.
- **Rights remain unverified:** the source player has visible generated sneaker marks. The new player/civilian derivative replaces only low shoe surfaces with original charcoal textile and plain rubber materials, disconnecting their inherited logo normal map. The original meshes/UVs/source files remain intact. This cleanup needs repeated rendered inspection and does not certify the whole asset. The officer retains generated uniform/badge/text details. No public binary redistribution is authorized or claimed.
- **Blender safety:** default sandboxed Blender 5.2 crashed once during Metal capability probing before Python. A controlled, escalated CPU-only run with installed `/Users/midir/Applications/Blender-4.5.11.app/Contents/MacOS/Blender` succeeded. No second 5.2 launch was attempted, and no renderer/listener was started by this lane.

The seated clips place the pelvis approximately 0.45 m above the visual origin. For a cushion at height h, place the visual origin at h minus 0.45 m. This is a visual pose; the NPC controller still owns its state and must call `set_seated(false)` before fleeing. Use `ignore_simulation_pause = true` only in explicit pose fixtures; ordinary character animation freezes with `Game.simulation_paused`.
