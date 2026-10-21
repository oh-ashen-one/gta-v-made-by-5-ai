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
| ART-02 Partial | Real world-space 3D geometry with collision throughout. Provider hero assets (sedan, helicopter, shophouse module, character) were generated in wave 1 through Customuse and are now integrated where staged (see `docs/asset-manifest.csv`); the character is still unrigged, and the coupe, van, props and Tripo set are still outstanding |
| ART-03 | Partial | Arcades, columns, awnings, shutters, roof ridges, kerbs modelled; module count far below the 6–8 kit target |
| ART-04 | Partial | Material separation by family (plaster, tile, concrete, glass, metal, foliage); no texture maps, so material response is flat |
| ART-05 | Fail (partial rig) | Procedural limb swing, aim and reload poses; no skinning, no blending, no foot planting, no NPC rig variety |
| ART-06 Partial | The generated sedan (with separated, spinning wheels) and the generated helicopter (with separated, spinning main and tail rotors) are integrated when staged; the coupe and van remain procedural. Cabin detail — glazing, seats, dash, right-hand steering wheel — comes from the generated model |
| ART-07 | Partial | One warm late-afternoon preset with sun, sky fill, fog, glow; no contact-shadow tuning pass |
| ART-08 | Fail | Debug-free but visibly placeholder geometry; **this is the largest known gap** |

## Player, combat, NPCs

| ID | Status | Evidence / gap |
| --- | --- | --- |
| PLAYER-01 | Implemented — not verified | Walk/sprint/jump, acceleration/friction tuning, kerb and step handling via CharacterBody3D |
| Implemented — not verified | Spring-arm over-the-shoulder camera with wall collision, mouse look, sensitivity/invert/reduced-shake settings, aim and drive transitions |
| PLAYER-03 | Partial | One control owner, published on `Game`. The wave-1 independent review found the `busy` transition guard was inert (declared, never set), which allowed repeated interaction; the guard is now set across the car and helicopter transitions and the invariants are listed in `docs/TRANSITION_TABLE.md` |
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
| TRAFFIC-01 | Partial | 25-junction lane graph with a geometrically correct **left-hand** lane offset and corner queueing. No signal phase table, no junction priority rules and no pedestrian-crossing response — the world draws signal heads but nothing drives them |
| TRAFFIC-02 Partial | AI cars now detect a blocker ahead and slow to a crawl instead of driving through it (TRAFFIC-02). No reroute around a permanently blocked lane, and no signal cycle |
| TRAFFIC-03 | Partial | Cars persist when the player leaves them; traffic never resets or reverses |
| AIR-01 | Implemented — not verified | Helicopter on the primary pad, walk-up prompt, boarding, rotor spin, flight |
| AIR-02 | Partial | Arcade lift/yaw/pitch/hover with stabilisation; no fuel, no damage model in flight |
| AIR-03 | Partial | Same district visible from the air with completed roofs; no streaming |
| AIR-04 | Implemented — not verified | Landing at the second pad, exit on foot, state continuity |
| AIR-05 | Partial | Hard impacts damage the aircraft; water/void and flight limits not fully handled |
| LAW-01 | Implemented — not verified | Three escalation tiers; heat decays while no responder has line of sight (the review found the decay was dead code) and the HUD shows the level and the SPOTTED / SEARCHING state |
| LAW-02 | Partial | Police spawn out of sight at 28–55 m and pursue |
| LAW-03 | Partial | Vehicle pursuit plus on-foot officers; helicopter boarding does not clear attention |
| LAW-04 Partial | Pursuit now has two phases: **SPOTTED** (heat held) and **SEARCHING** (heat decays, police sweep the last known position, HUD shows the countdown). No concealment mechanic yet |
| LAW-05 | Partial | Responders are bounded, stand down and are removed when the wanted level reaches zero (the review found the cleanup was never called), and a pursuit car is re-spawned when it is wrecked or falls far behind |

## Mission, UI, audio, save, systems

| ID | Status | Evidence / gap |
| --- | --- | --- |
| MISSION-01 | Partial | "Harbour Relay": safe room → hawker package → theft → drive → police → helicopter → landing → delivery, and the drive leg now keys on the controlled body instead of the player node. The step that requires a *real pursuit and escape* and the return to clean free roam are still not implemented |
| MISSION-02 | Partial | Stage machine keyed on real system state (mode, positions, pickups) |
| MISSION-03 | Partial | One checkpoint at the package; restart from checkpoint available |
| MISSION-04 | Fail | Replay cleanliness not exercised; mission actors are not reset on restart |
| UI-01 | Partial | Title, pause, controls text, notifications; no working New/Continue/Quit buttons (keyboard only) |
| UI-02 | Partial | Health, ammo, wanted, objective, prompt, minimap, speed/altitude; minimap is schematic |
| UI-03 Partial | Settings panel (F3) with mouse sensitivity, invert-Y, reduced shake and HUD visibility; outline-scaled text and contrast are in place. No remapping, no colour-blind mode |
| AUDIO-01 | Partial | Procedural sound bank (`game/src/core/audio.gd`): gunshots, footsteps, impacts, pickup, engine loop (pitch tracks speed), rotor loop, police siren. All synthesised in code — original material, no sampled audio. No spatial attenuation or per-actor mixing yet |
| AUDIO-02 | Pass (for what exists) | Only code-generated sound; no music, no speech, no third-party audio. Nothing to clear, and nothing to attribute |
| SAVE-01 | Implemented — not verified | Versioned JSON save/load of health, stage, position, ammo, wanted level and heat, checkpoint and safe position. The wave-1 review found the stored values were never applied to the world; loading now moves the player, restores the mission stage and re-marks the checkpoint. Free-roam policy is "reset to checkpoint" |
| SAVE-02 | Partial | A corrupt or incompatible save now returns false **with a visible message** instead of failing silently; duplicate-object re-entry on repeated loads is still untested |
| SYSTEM-01 | Implemented — not verified | `Game` autoload owns health, mode, wanted, stage; `Events` is the only cross-system bus. The explicit transition table that END_GOAL asks for is now written down in `docs/TRANSITION_TABLE.md` and its invariants are covered by the automated checks |
| SYSTEM-02 | Partial | Debug diagnostics exist (`F1`), fixtures exist, but they are not in the shipped HUD |
| SYSTEM-03 | Partial | Transitions guard against double entry; repeated-action stress not run |

## Engine, assets, performance, verification

| ID | Status | Evidence / gap |
| --- | --- | --- |
| TECH-01 | Pass (decision recorded) | Godot 4.7.1 stable chosen and locked in `waves/01/READINESS.md` with rejected alternatives |
| TECH-02 | Pass (packaged build produced) | `game/build/mac/OrchardReach.zip` exported from the macOS preset; the build was exported, **launching the packaged .app is still to be re-verified after the final build** |
| ASSET-01 Partial | Tripo and Customuse were **not exposed in this CLI**, so requests were published in `ASSET_REQUESTS.json` and the manager executed four Customuse jobs; the results were cleaned in Blender (`game/tools/cleanup_provider_assets.py`) and integrated. Remaining Tripo props are still pending |
| ASSET-02 | Fail (for now) | No external assets imported; procedural geometry only; no scale/UV/collision pipeline exercised on imported files |
| ASSET-03 Pass | `docs/asset-manifest.csv` records every asset, including the four provider exports with provider terms, source URLs, SHA256 and the fact that they are **not** MIT-licensed and are not committed to the public repository |
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
| QA-012 Cross-mode pursuit | Partial — the wanted level, heat and responder set now survive foot/car/aircraft changes (one authority, `Game`), police sweep the last known position when sight is broken, and the HUD shows SPOTTED vs SEARCHING. Not yet verified across a full pursuit |
| QA-013 Full-3D district | Partial — geometry exists, fidelity is placeholder |
| QA-014 Singapore identity | NOT TESTED by an independent reviewer |
| QA-015 Population/cohesion | Partial |
| QA-016 Mission | Implemented — not verified |
| QA-017 State invariants | Partial |
| QA-018 Continuous golden path | Partial — the automated playthrough drives the real systems through the real input actions and (after the review found that scripted presses never reached the game) now completes the interaction steps; it is still not an uncut human run |
| QA-019 Failure/restart/save | Partial |
| QA-020 Performance/stability | NOT TESTED |

## Wave-1 independent review and what it changed

An independent critic (a subagent of the **same MiniMax model** — this profile has no Opus/Fable access, so VERIFY-02 remains only partially satisfied) reviewed commit `c1d4d40` with six headless runtime probes and a static read of every system file. It found, and the wave then fixed or recorded, the following:

| Finding | Severity | Outcome in this wave |
| --- | --- | --- |
| Death while driving or flying left the player bound to the vehicle, unable to move or interact — a hard softlock | critical | **Fixed**: `Player.respawn_at` releases the vehicle, clears `current_vehicle` and `busy`, restores the gameplay camera; covered by the "death in a vehicle releases control" check |
| Every civilian traffic car was wrecked within ten seconds of play (contact damage was applied every frame at the commanded speed) | critical | **Fixed**: damage now comes from the closing speed along the contact normal, once per contact with a 0.6 s cooldown; street props were moved out of the carriageway; covered by the "no civilian traffic car is wrecked by street contact" check |
| Scripted input never reached the game: `Input.action_press()` does not synthesise an event, and the player only reacted inside `_unhandled_input` — so the automated playthrough could not interact at all | critical | **Fixed**: fire, reload, weapon swap and interact are polled in `_process`, so scripted and human presses share one path; covered by the "a scripted interact press takes the vehicle" check |
| The wanted level never decayed and responders were never stood down | high | **Fixed**: heat decays while nobody has sight, responders are removed at zero wanted, and a pursuit car is re-spawned when wrecked or far behind |
| The player node did not follow the vehicle, so the "drive to the aviation compound" objective, the pursuit target and the minimap all used a stale position | high | **Fixed**: `Player.controlled_actor()` is the single authoritative body and is used by the mission, the police, the HUD and the save file |
| Pause did not pause: the world kept running behind the menu | high | **Fixed**: the player, NPCs, traffic and the mission all freeze while paused; covered by the "world is frozen while paused" check |
| Save/load stored values nothing read; a corrupt save failed silently | high | **Fixed**: loading now applies the position, mission stage and checkpoint, and an unreadable save reports a message |
| The `busy` transition guard was declared but never set | medium | **Fixed**: the guard is now set across the vehicle transitions and documented in the transition table |
| Car exit only tried one side and could place the player inside geometry | medium | **Fixed**: both sides are ray-tested and the exit is refused with a message when neither is clear |
| Stealing a moving vehicle raised no heat and left the car in the lane | medium | **Fixed**: any player entry into a vehicle the player did not own raises heat |
| A displaced driver had no lane and no flee direction, so it froze at the kerb | medium | **Fixed**: the displaced driver gets a flee direction and stays visible |
| The "driver" of a parked car stood inside the car's own collider | medium | **Fixed**: parked drivers are hidden until they are displaced |
| Traffic has no signal phase, priority or crossing behaviour; pedestrians cannot route around geometry | structural | **Not fixed — recorded as a successor task.** It needs a junction model and a navigation mesh, not a patch |
| The audio bank has no spatialisation, and the shot ray starts at the camera while the muzzle flash sits on the arm | medium | **Not fixed — recorded as a successor task** (COMBAT-02, COMBAT-05) |
| No frame-time capture, stress route or soak harness | medium | **Not fixed — recorded as a successor task** (PERF-02/03/04, QA-020) |
