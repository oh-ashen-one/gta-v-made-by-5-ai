# Look-development sheet — "Orchard Reach" (END_GOAL ART-01)

One look, inherited by every wave. The board below is the authority for palette, scale, material response, exposure and lighting. Every wave inherits it; a wave may refine it but must log the change.

**Primary art direction:** `docs/concepts/singapore-on-foot.png`, `docs/concepts/singapore-driving.png`, `docs/concepts/singapore-helicopter.png` — generated concepts of *this* game. They set composition, density, material richness, warm late-afternoon light and the CBD-over-water horizon.
**Secondary evidence:** `docs/visual-references.json` — GTA VI stills and Singapore location photography (links only; nothing is copied).

## Palette (locked family)

| Role | Colour | Where it is used |
| --- | --- | --- |
| Warm off-white plaster | `#D9CFBB` | shophouse upper walls, civic volumes |
| Muted pastel frontage | `#9FB5AF` / `#C7A8A0` / `#CCB37A` / `#ADB6A0` / `#B8AEC2` | shophouse shopfronts, one per unit, never more than two of a kind side by side |
| Red-brown clay roof tile | `#6B3327` | shophouse pitched roofs, hawker roof trim |
| Pale concrete | `#A8A6A0` | void-deck slabs, kerbs, platforms, carpark |
| Dark asphalt | `#1C1C1E` | carriageways |
| Granite kerb | `#8E8C87` | kerb edge, bollards, planters |
| Deep green (foliage) | `#2A5329` | rain tree / angsana canopies |
| Cool glass | `#6E8A9E` | HDB windows, tower glazing, vehicle windows |
| Warm shop light | `#FFC26B` | shopfront glow, hawker practicals, street lamps |
| Rust / copper accent | `#8C4A2F` | roller shutters, service doors, railings |
| Signal colour (HUD only) | `#3FD9A6` | objective marker, minimap marker |

Rules: one accent per façade band, no saturated neon, no pure black (use `#1C1C1E` instead), no pure white (use `#D9CFBB`), foliage stays deep and desaturated so it never fights the built form.

## Scale

- Player 1.75 m; kerb 0.13 m; five-foot-way arcade 2.4 m deep × 2.6 m clear; shophouse module 10.6 m frontage × 13 m deep × 9.5–12 m tall; HDB slab 22 × 13 m footprint, 46–58 m tall; hawker stall 8 × 3.2 m with 2.6 m canopy; street lamp 6 m; carriageway 16 m (two lanes each way, **left-hand** traffic).

## Lighting

Opus 5.5 wave A (lighting piece) replaced the wave-1..5 rig; code in `game/src/world/lighting.gd`, sky in
`game/assets/authored/shaders/golden_hour_sky.gdshader`. Logged change: the earlier 46-degree noon key and the
flat grey-pink haze sky are retired.

- One time-of-day preset: warm, dry, late afternoon ("golden hour"). Key sun at ~14.5 deg elevation from the
  east-south-east of the map (rotation -14.5, 58, 0), colour `#FFBD80`, energy 3.1, PCSS soft shadows (angular
  size 1.1 deg), 4 blended splits to 280 m, 8192 directional atlas.
- Sky: procedural, HDR. Saturated blue zenith (`#214A99`), lighter mid sky, warm gold horizon toward the sun
  and cool blue-grey away from it, domain-warped cumulus lit from the sun side with silver linings, HDR sun disc.
  The sky reads LIGHT0, so glow, clouds and shadows always agree.
- Ambient and reflections from the sky (75 % sky, 25 % warm grey `#A89480`): shade is blue-lifted, never black.
  SSAO (radius 1.6, intensity 2.6) for contact darkening in five-foot ways; SSIL for warm pavement bounce; a
  0.16 warm upward "ground bounce" directional (no specular, not in the sky).
- Atmosphere: exponential fog 0.00055 with aerial perspective 0.55 and sun scatter 0.35 (sky left clear), light
  height fog, volumetric fog 0.0016 (anisotropy 0.62, 140 m) for sun shafts.
- Exposure and grade: ACES, exposure 1.0, white 6. Glow threshold 1.05, intensity 0.42 (only HDR emitters bloom).
  Procedural 3D LUT: slight teal in shadows, warm highlights, gentle S-curve; contrast 1.06, saturation 1.08.
- Practicals (all shadowless, distance-culled, each with a modelled fixture): street lamps (warm spot + glowing
  head), five-foot-way pendants (warm omni per shophouse bay), void-deck fluorescent tubes on the soffit
  (cool-white omni grid; void-deck lower third mean luminance >= 60/255), hawker stall tubes and dining pendants.
- Debug A/B switches: `--lighting-gi=sdfgi`, `--lighting-tonemap=agx`, `--lighting-off=vfog,ssil,ssao,lut,pcss,fog,glow,skyamb,practicals`.

## Materials

| Surface | Roughness | Metallic | Note |
| --- | --- | --- | --- |
| Plaster / painted render | 0.88 | 0 | subtle procedural breakup, value separation between units |
| Clay roof tile | 0.80 | 0 | ridged repetition, no mirror sheen |
| Concrete / kerb | 0.92 | 0 | matte, slightly warmer than asphalt |
| Asphalt | 0.90 | 0 | cellular breakup, never mirror-like |
| Glass | 0.08 | 0.35 | cool tint, slight transparency, visible interior depth |
| Painted metal | 0.55 | 0.6 | shutters, shutters, railings, lamp posts |
| Foliage | 0.95 | 0 | dimensional canopy, leaf cards only inside the crown |
| Vehicle paint | 0.35 | 0.55 | clearcoat feel, road dust near the sill |

## Camera treatment

- Third-person over-the-shoulder: camera 1.62 m, lateral offset 0.85 m, arm 4.6 m (2.2 m aiming), so the character never sits on the reticle.
- FOV 68° on foot, 72° driving, 75° flight.
- No camera shake by default; reduced-shake setting halves it further.
- Capture convention: 16:9, 1280×720 internal, HUD visible for gameplay shots and hidden for beauty shots.

## What is still placeholder (honest)

Every wave-1 mesh is procedural geometry standing in for the hero assets requested in `ASSET_REQUESTS.json`: vehicles, helicopter, characters, shophouse module, HDB slab, hawker stall and the prop set. The palette, lighting, scale and camera rules above are locked; the geometry is not final.
