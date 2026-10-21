# Requirements ledger — wave 1 (MiniMax M3.1 Flash)

Status vocabulary follows END_GOAL §15 (VERIFY-01): `Pass`, `Fail`, `Implemented — not verified`, `Not started`, `Blocked`, `NOT TESTED`.
Nothing here is claimed as verified unless a runtime artefact is linked. The wave-1 build is a **playable experimental slice**, not an accepted north star.

- **Build under test:** `game/` (Godot 4.7.1 stable, Forward+, macOS export), branch `feature/wave-01-orchard-reach` (pushed to `origin/codex/minimax-wave-01`).
- **Reference machine:** Apple M3 Ultra, 256 GB RAM, macOS 27.0.1.
- **Automated evidence:** `godot --headless --path game -- --test` (headless checks) and the automated playthrough capture packet in `game/captures/` plus `game/captures/capture_log.json`.

## World

| ID | Status | Evidence / gap |
| --- | --- | --- |
| WORLD-01 | Implemented — not verified | ~640 × 640 m authored core on a 5 × 5 road grid (`world_builder.gd`); aerial envelope not separately dimensioned |
| WORLD-02 | Implemented — not verified | Five precincts present: shophouse street, void-deck HDB blocks, roofed hawker hall, waterfront edge, aviation compound; seen in capture packet |
| WORLD-03 | Implemented — not verified | Frontage rhythm, arcades, void decks, hawker layout, canopy trees, kerbs, signage bands; no independent identity review yet |
| WORLD-04 | Partial | Orthogonal 25-junction network with three connected loops; alternative routes exist; driving times not measured |
| WORLD-05 | Partial | Safe room, hawker hall and delivery point are modelled interiors; shop/workshop/mission-room interiors are **not** built |
| WORLD-06 | Implemented — not verified | Water to the north, background city silhouettes, helipad boundaries; flight bounds are soft |
| WORLD-07 | Implemented — not verified | 34 pedestrians + 14 traffic vehicles spawned; busiest-view density not profiled |

## Art

| ID | Status | Evidence / gap |
| --- | --- | --- |
| ART-01 | Partial | One palette module (`palette.gd`) shared by every surface; consistency plausible but not independently reviewed |
| ART-02 | Partial | Everything is real world-space 3D geometry with collision, but **procedural placeholder forms**, not hero assets (Tripo/Customuse unavailable — see `ASSET_REQUESTS.json`) |
| ART-03 | Partial | Arcades, columns, awnings, shutters, roof ridges, kerbs modelled; module count far below the 6–8 kit target |
| ART-04 | Partial | Material separation by family (plaster, tile, concrete, glass, metal, foliage); no texture maps, so material response is flat |
| ART-05 | Fail (partial rig) | Procedural limb swing, aim and reload poses; no skinning, no blending, no foot planting, no NPC rig variety |
| ART-06 | Partial | Cars have separate rotating wheels, glazing, seats, dash, right-hand steering wheel, lights; helicopter has fuselage, rotors, skids, seat |
| ART-07 | Partial | One warm late-afternoon preset with sun, sky fill, fog, glow; no contact-shadow tuning pass |
| ART-08 | Fail | Debug-free but visibly placeholder geometry; **this is the largest known gap** |

## Player, combat, NPCs

| ID | Status | Evidence / gap |
| --- | --- | --- |
| PLAYER-01 | Implemented — not verified | Walk/sprint/jump, acceleration/friction tuning, kerb and step handling via CharacterBody3D |
| PLAYER-02 | Partial | Spring-arm third-person camera with wall collision and mouse look; no sensitivity/invert settings UI yet |
| PLAYER-03 | Implemented — not verified | Single control owner: foot / car / helicopter transitions guard with `busy`; mode changes published on `Game` |
| PLAYER-04 | Partial | Contextual prompts for vehicles and interactables; no line-of-sight test |
| PLAYER-05 | Partial | Title screen, pause panel, controls list; no settings sliders, no full menu shell |
| COMBAT-01 | Partial | Pistol and compact SMG, hitscan, recoil cadence, reload, ammo pools; weapon meshes are placeholder boxes |
| COMBAT-02 | Partial | Camera-ray hitscan with muzzle obstruction and world collision; no damage falloff model |
| COMBAT-03 | Implemented — not verified | NPC health, damage reaction, death with body on ground and persistence; no ragdoll |
| COMBAT-04 | Partial | Player damage, health bar, respawn at checkpoint; no cover or safe-respawn logic beyond checkpoint |
| COMBAT-05 | Partial | Muzzle flash, impact spark, events; no pooled VFX, no spatial audio yet |
| NPC-01 | Partial | Pedestrians walk lane graphs, idle, queue and flee; routes are rectangular loops |
| NPC-02 | Partial | Gunfire within 26 m panics civilians; no witness reporting chain |
| NPC-03 | Partial | Hostiles and officers pursue and fire with ray tests; simple line-of-fire logic |
| NPC-04 | Partial | Panic state overrides idle; displaced driver becomes a pedestrian; defeat stops reporting |
| NPC-05 | Partial | Seeded spawn, fixed population budget; ownership rules exist for mission actors |

## Vehicles, traffic, law

| ID | Status | Evidence / gap |
| --- | --- | --- |
| CAR-01 | Partial | Sedan, coupe, van and a response variant; arcade handling tuned for district speeds |
| CAR-02 | Implemented — not verified | Empty entry and occupied-car takeover with driver displacement; theft raises heat |
| CAR-03 | Partial | Exit beside the car; blocked-exit rejection not implemented |
| CAR-04 | Partial | Collision damage, health, disabled state; no visible deformation |
| TRAFFIC-01 | Implemented — not verified | 25-junction lane graph with **left-hand** lane offset, queueing at corners; no signals |
| TRAFFIC-02 | Fail | No congestion response or rerouting around blockers; cars can pile up |
| TRAFFIC-03 | Partial | Cars persist when the player leaves them; traffic never resets or reverses |
| AIR-01 | Implemented — not verified | Helicopter on the primary pad, walk-up prompt, boarding, rotor spin, flight |
| AIR-02 | Partial | Arcade lift/yaw/pitch/hover with stabilisation; no fuel, no damage model in flight |
| AIR-03 | Partial | Same district visible from the air with completed roofs; no streaming |
| AIR-04 | Implemented — not verified | Landing at the second pad, exit on foot, state continuity |
| AIR-05 | Partial | Hard impacts damage the aircraft; water/void and flight limits not fully handled |
| LAW-01 | Partial | Three escalation tiers with heat decay; HUD shows the level |
| LAW-02 | Partial | Police spawn out of sight at 28–55 m and pursue |
| LAW-03 | Partial | Vehicle pursuit plus on-foot officers; helicopter boarding does not clear attention |
| LAW-04 | Fail | Escape is heat decay only; no search phase, no concealment mechanic |
| LAW-05 | Partial | Responders are bounded and cleaned up when pursuit ends |

## Mission, UI, audio, save, systems

| ID | Status | Evidence / gap |
| --- | --- | --- |
| MISSION-01 | Implemented — not verified | "Harbour Relay": safe room → hawker package → theft → drive → police → helicopter → landing → delivery |
| MISSION-02 | Partial | Stage machine keyed on real system state (mode, positions, pickups) |
| MISSION-03 | Partial | One checkpoint at the package; restart from checkpoint available |
| MISSION-04 | Fail | Replay cleanliness not exercised; mission actors are not reset on restart |
| UI-01 | Partial | Title, pause, controls text, notifications; no working New/Continue/Quit buttons (keyboard only) |
| UI-02 | Partial | Health, ammo, wanted, objective, prompt, minimap, speed/altitude; minimap is schematic |
| UI-03 | Partial | Outline-scaled text, contrast, sensitivity missing |
| AUDIO-01 | **Not started** | No audio at all — a hard gap against ART/AUDIO-01 |
| AUDIO-02 | Not started | No music, no speech; nothing to licence yet |
| SAVE-01 | Implemented — not verified | Versioned JSON save/load of health, stage, position, ammo, wanted level; free-roam policy is "reset to checkpoint" |
| SAVE-02 | Partial | Corrupt/incompatible save returns false and offers new game; no duplicate-object re-entry test |
| SYSTEM-01 | Implemented — not verified | `Game` autoload owns health, mode, wanted, stage; `Events` is the only cross-system bus |
| SYSTEM-02 | Partial | Debug diagnostics exist (`F1`), fixtures exist, but they are not in the shipped HUD |
| SYSTEM-03 | Partial | Transitions guard against double entry; repeated-action stress not run |

## Engine, assets, performance, verification

| ID | Status | Evidence / gap |
| --- | --- | --- |
| TECH-01 | Pass (decision recorded) | Godot 4.7.1 stable chosen and locked in `waves/01/READINESS.md` with rejected alternatives |
| TECH-02 | Pass (packaged build produced) | `game/build/mac/OrchardReach.zip` exported from the macOS preset; the build was exported, **launching the packaged .app is still to be re-verified after the final build** |
| ASSET-01 | Partial | Tripo and Customuse are **not exposed in this CLI**; requests published in `ASSET_REQUESTS.json`; Blender available for DCC work |
| ASSET-02 | Fail (for now) | No external assets imported; procedural geometry only; no scale/UV/collision pipeline exercised on imported files |
| ASSET-03 | Pass (manifest exists) | `docs/asset-manifest.csv` records every wave-1 asset as procedural/original with redistribution status |
| ASSET-04 | Pass | No GTA assets, no third-party models, no credentials; all wave-1 content is generated geometry and original text |
| ASSET-05 | Partial | `.gitignore` excludes engine caches and build output; capture PNGs are committed as evidence |
| PERF-01 | Partial | Reference machine recorded; per-run frame metrics **not yet captured** |
| PERF-02 | Not started | 1080p60 / p95 ≤ 25 ms contract is declared but not measured |
| PERF-03 | Not started | No stress-route profiling |
| PERF-04 | Not started | No 30-minute soak, no three consecutive mission runs |
| PERF-05 | Not started | No pooling/LOD work yet |
| VERIFY-01 | Pass (ledger maintained) | This file |
| VERIFY-02 | Partial | Independent-context critic pass performed in-wave, but **the critic is the same MiniMax model** — no Opus/Fable access exists in this profile, so this is not a different-vendor review |
| VERIFY-03 | Partial | Commit, run instructions, capture packet and state log exist; frame-time traces do not |
| VERIFY-04 | Partial | Test records name the tester, machine, build and result for executed checks; most visual gates remain NOT TESTED |
| VERIFY-05 | Pass (no hard blockers known) | No crash, no secret, no uncleared asset in the tree |
| VERIFY-06 | Fail | Placeholder art quality and missing audio are major quality blockers against the GTA VI bar |
| VERIFY-07 | Partial | One critic round performed in-wave with fixes applied; retest coverage partial |
| VERIFY-08 | Pass (honest verdict) | **Playable experimental build with unmet requirements** — not "north star accepted" |

## QA gate table (END_GOAL §15.1)

| Gate | Status |
| --- | --- |
| QA-001 Clean launch | Implemented — not verified (packaged build exported; packaged launch re-verified at handoff) |
| QA-002 Pedestrian controls | Implemented — not verified |
| QA-003 Camera | Partial |
| QA-004 Shooting | Partial |
| QA-005 NPC continuity | Partial |
| QA-006 Car theft | Implemented — not verified |
| QA-007 Driving | Implemented — not verified |
| QA-008 Traffic | Partial — no blocker-response behaviour |
| QA-009 Helicopter lifecycle | Implemented — not verified |
| QA-010 Aerial world | Partial |
| QA-011 Police causality | Partial |
| QA-012 Cross-mode pursuit | Fail — pursuit state does not survive controller changes as designed |
| QA-013 Full-3D district | Partial — geometry exists, fidelity is placeholder |
| QA-014 Singapore identity | NOT TESTED by an independent reviewer |
| QA-015 Population/cohesion | Partial |
| QA-016 Mission | Implemented — not verified |
| QA-017 State invariants | Partial |
| QA-018 Continuous golden path | Partial — automated run exists; not an uncut human run |
| QA-019 Failure/restart/save | Partial |
| QA-020 Performance/stability | NOT TESTED |
