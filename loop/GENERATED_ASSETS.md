# Generated assets (Higgsfield, owner-approved 2026-10-22 ~17:30Z)

Files live in the git-ignored `game/assets/providers/higgsfield/` (symlinked into every `.worktrees/*` checkout; run
`godot --headless --path game --import` after new files appear). Raw downloads are in the git-ignored
`art/provider-sources/higgsfield/`. Machine-readable records (job id, prompt, sha256): `loop/generated_assets.jsonl`
(committed; it holds no image data). **Never commit the images** — provider outputs, not MIT, not cleared for public
redistribution. When you ship one in the game, add a `docs/asset-manifest.csv` row (provider "Higgsfield GPT Image 2.5",
terms "Higgsfield terms; not MIT; private build use only", publication "NO").

Only the orchestrator generates, one image at a time, reviewed before the next. Builders: request new ones under
"Requests" below (one line each: name, purpose, piece) and keep working; they appear here when done.

All are 2048x2048. `_albedo` is sRGB colour; `_normal` is an OpenGL-style normal map derived from luminance (Godot's
convention; strength is moderate, scale it with `normal_scale`); `_rough` is a roughness map (use as roughness texture,
channel R). Use world-space or triplanar UVs with macro variation (noise-modulated tint or a second sample at a different
scale) — every tile repeats visibly if sampled at one scale.

| Name | Files | Use for | Tiling / scale notes |
| --- | --- | --- | --- |
| road_asphalt | `_albedo` `_normal` `_rough` | carriageways | seamless; 1 tile ≈ 6–8 m; wheel-track bands run along V, align with lanes; one patch repair repeats per tile, so break up with macro noise |
| footpath_pavers | `_albedo` `_normal` `_rough` | pavements, five-foot-way floors, plazas | seamless by whole paver periods; texture is ~0.88 aspect-stretched vertically, use UV scale (1.0, 0.88); 1 tile ≈ 3 m |
| concrete_weathered | `_albedo` `_normal` `_rough` | kerbs, sign bases, median kerbs, planter walls, void-deck columns, seawalls | seamless; streaks run along V (vertical faces: V = down); 1 tile ≈ 2–3 m |
| plaster_weathered | `_albedo` `_normal` `_rough` `_neutral` | shophouse walls, render | seamless; albedo is mint; `_neutral` is a tintable detail map — multiply by a LOOK_DEV pastel; weathering is heavy, lerp toward clean for front facades |
| tower_glass_bluegreen | `_albedo` `_normal` `_rough` | office/CBD towers (aerial and mid distance) | wraps every 8 bays × 6 floors; 1 tile ≈ 8 bays (~12 m) × 6 floors (~24 m); baked sky reflections, pair with low roughness + metallic ~0.3 so real sun specular also shows |
| hdb_facade | `_albedo` `_normal` `_rough` | HDB slabs, residential blocks | wraps every 6 bays × 5 floors (~15 m × ~14 m); laundry poles + AC ledges baked in |
| rooftop_flat | `_albedo` `_normal` `_rough` | flat roofs seen from the helicopter | do NOT repeat-tile across one roof (equipment repeats obviously): map one texture per roof, random 90° rotation/offset per building; faint blend ghosts at tile centre lines |

## Requests
- (builders append here: `- name — purpose — piece`)
