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
| shop_signs_atlas + `sign_*.png` (8) | `sign_teck_huat_kopitiam`, `sign_sin_leong_hardware`, `sign_mei_ling_tailor`, `sign_joo_heng_medical_hall`, `sign_ah_kow_prawn_noodle`, `sign_kim_seng_provision`, `sign_golden_lotus_money_changer`, `sign_happy_cycles` (~995x465–506 each) | shophouse signboards above five-foot ways; replaces blank sign faces | not tiling; one per shop, ~3.5–4.5 m wide boards; original fictional names, bilingual; mild emission (0.2–0.4) for backlit boards at dusk |
| foliage cards (alpha) | `foliage_mondo_spiderlily`, `foliage_ixora`, `foliage_croton`, `foliage_birdsnest_fern` (1024², RGBA) + `foliage_median_atlas` | median planters, kerb beds, void-deck gardens; replaces faceted low-poly blades | alpha-scissor (~0.4) or alpha-hash on 2–3 crossed quads per clump, bottom edge = ground; vary scale 0.6–1.2 and hue slightly; enable backlight/transmission |
| sky_panorama | `sky_panorama_albedo.png` (3380x1648) | sky backdrop / cloud layer replacing small cloud sprites | wraps horizontally (u 0..1); map on a horizon cylinder or dome band behind fog, bottom = horizon haze; sun is low to the right of the image centre — align with the lighting sun azimuth |
| road_signs_atlas | `road_signs_atlas_albedo.png` (2048x1152, grey background) | sign faces: stop, keep-left, no-entry, 50, pedestrian crossing, give way, no parking, street-name "TEMBUSU ROAD" | 4x2 grid, cells ~512x576; cut each face with a shape mask (octagon/circle/triangle/rect) or alpha-scissor on the grey; keep-left goes on the median sign islands |
| vfx_muzzle_flash_atlas | `vfx_muzzle_flash_atlas.png` (2048², RGBA, 2x2) | pistol muzzle flash sprites (combat) | barrel points +U (right); pick a random quadrant per shot, show 1–2 frames, additive or unshaded alpha with emission, scale ~0.25–0.4 m, add a 1-frame OmniLight |
| vfx_bullet_impacts_atlas | `vfx_bullet_impacts_atlas.png` (2048², RGBA, 3x3) | bullet-hole Decals (combat): row 1 concrete, row 2 plaster, row 3 metal, metal, glass | Godot Decal with albedo+alpha, ~0.12–0.2 m; pick the row by surface material; fade after ~20 s; cap count |
| vfx_puffs_atlas | `vfx_puffs_atlas.png` (2048², RGBA, 2x2) | particles: TL tyre smoke, TR dust, BL gun smoke, BR water spray | billboard particles, alpha blend, grow + fade; TL for burnouts/handbrake, TR for heli downwash on ground + car off-road, BL after shots, BR for heli downwash on water / bow waves |
| vfx_skid_mark | `vfx_skid_mark.png` (1520x2366, RGBA) | tyre skid trails (driving) | strip along V (wraps vertically, already blurred along V); ~0.25 m wide; build a ribbon mesh behind each sliding wheel, alpha ~0.6, fade over ~30 s |
| fabric_flannel_plaid | `_albedo` `_normal` `_rough` | player / NPC flannel shirts (judge cited GTA V's flannel) | wraps by whole plaid periods but is stretched ~1.7x horizontally by the period crop: use UV scale (1.72, 1.0); one plaid repeat ≈ 10–12 cm on the garment |
| fabric_denim | `_albedo` `_normal` `_rough` | jeans/trousers | seamless; twill runs diagonally; ~0.6 tiles per trouser leg width; add darker AO in creases |
| fabric_batik | `_albedo` `_normal` `_rough`, `fabric_batik_single_albedo` | batik shirts for NPC variety (Singapore identity) | the seamless version ghosts flowers in blend zones — prefer `fabric_batik_single_albedo` (unblended) when one tile covers the garment |
| fabric_cotton_jersey | `_albedo` `_normal` `_rough`, `_neutral` | T-shirts; `_neutral` is tintable for crowd colour variety | seamless; multiply `_neutral` by any tee colour; normal strength low (knit is fine) |
| skin_detail_male / skin_detail_neutral | `skin_detail_male_albedo/_normal/_rough`, `skin_detail_neutral` (mid-grey overlay) | character face/skin micro-detail (judges: pores, stubble, creases, uneven shine) | seamless; tile ~4-6x across a face as a DETAIL layer over the base skin albedo (overlay blend with `_neutral` so any skin tone works); use `_normal` at low strength for pores and `_rough` to break up uniform shine; keep stubble to the jaw/upper lip with a mask |
| hair cards | `hair_card_black_straight`, `hair_card_brown_straight`, `hair_card_black_wavy`, `hair_card_brown_short_coarse` (RGBA) + `hair_cards_atlas` | strand-detail hair cards to replace sculpted-shell hair | alpha-hash or alpha-scissor (~0.35) with soft depth; layer 20-60 cards following the scalp; top = root, bottom = tips; anisotropic sheen along V |
| plaza_granite_pavers | `_albedo` `_normal` `_rough` (1024²) | plazas, Raffles Place / Merlion / Bayfront promenades, near-field floors (judges: "uniform beige slab, seam lines only") | seamless 4x4 slabs of 600 mm granite in mixed grey/beige with stains, gum spots, cracks; 1 tile ≈ 2.4 m (UV 1/2.4 per m); add a world-space macro-noise tint and decals (drains, kerb edges) so the 4x4 repeat doesn't read from the air |
| tower_curtainwall_mullion | `_albedo` `_normal` `_rough` (1016x850) | NEAR and mid CBD towers (judges: "flat repeating window tile", "untextured pale slabs") | wraps by whole bays/floors: 1 tile = 7 bays × 6 floors (~10.5 m × ~24 m at 1.5 m bays, 4 m floors); mullion fins + spandrel bands baked with side shadows, panes vary (sky reflections, lit offices, blinds); pair with low roughness on glass areas, random per-building UV offset and hue shift, and real geometry fins on the nearest faces |
| tower_stone_punched | `_albedo` `_normal` `_rough` (1024x600) | second near/mid CBD facade so towers alternate glass curtain wall and stone (judges: "flat repeating window tile") | wraps by whole bays/floors: 1 tile = 6 bays × 4 floors (~9 m × ~16 m); warm granite with recessed punched windows, pilasters, floor bands, varied panes incl. bronze tint; reveal shadows are baked, so pair the normal map at moderate strength and keep the sun-facing side from double-shadowing |

## Requests
Priority note (owner, ~17:45Z): playable mechanics first (locomotion, combat, driving, helicopter), then the world.
- (builders append here: `- name — purpose — piece`)
