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

- One time-of-day preset: warm, dry, late afternoon. Key sun at 46° elevation, colour `#FFF0D2`, energy 2.6, shadows on, 220 m shadow distance.
- Sky fill: procedural sky, horizon `#D4C7AE`, top `#3D6BAD`, ambient from sky, energy 1.0.
- Practical lights: warm `#FFCC9E` emissive geometry with matching omni/spot lights; every visible light source has a modelled fixture.
- Fill light: cool `#B8CCF2` directional at 0.35 energy, no shadows.
- Atmosphere: light fog, density 0.0012, colour `#C7C2B3` — depth cue only, never a haze curtain.
- Exposure: Filmic tonemap, exposure 1.05, bloom 0.35 (restrained; bloom must not hide flat assets).

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
