# Pieces — Opus 5.5 enhancement loop

Smallest independently improvable and judgeable pieces. Reference IDs come from `loop/REFERENCES.md`
(GTAV-xx = quality bar, CONCEPT-0x / SG-0x = Singapore identity). Verdicts are blind critic verdicts
against GTA V; "best so far" is not "accepted". Wave A runs first (the critic's biggest named gaps).

| Piece | Wave | Matched refs | Capture spec / play scenario | Owns (files) | Current verdict | Open biggest gap |
| --- | --- | --- | --- | --- | --- | --- |
| street-life | A | GTAV traffic, on-foot street, driving chase; CONCEPT-01/02, SG-01 | `--gameplay-photos` 01/03/05, route `05_car_entered`, `06_driving`; `--photos` 06_aerial_district | traffic_manager.gd, npc.gd, spawn/density parts of car.gd, new src/systems/crowd*.gd | rA2 OURS LOSES (f59dd48); NOT MERGED (better_than_baseline=false both rounds; rendered route stall, gridlock, camera through bus) | A, sidewalk life and density. Acceptance check: in this same eye-level sidewalk framing, at least 12 distinct pedestrians are visible on the sidewalk within about 40 m, with no repeated body-and-outfit combinations. At least a third of them are doing something other than walking (a conversation group, phone or drink in hand, window-shopping, waiting at a shopfront), and people move both toward and |
| lighting | A | GTAV lighting / golden hour, on-foot street; CONCEPT-01 | `--photos` 01/02/04, `--gameplay-photos` 01/02 | `_environment()` → new src/world/lighting.gd, `_street_lamp`, new void-deck/arcade practicals | rA4 OURS LOSES (301a7c9); MERGED in integration A (ffc3b01) with regression fixes (4d9af26) | Acceptance check for A: no element larger than about 2% of the frame may look like a placeholder. The supertrees must read as opaque structures with texture and planting (vertical-garden trunks, canopy members with visible thickness and shading, no thin pink-white wire lines with sky showing through). The foreground sign must stand on a textured kerb or pavement, not a plain white box. The median  |
| water | A | GTAV coast/water, aerial; CONCEPT-03, SG-03 | `--photos` 05/07/16, `--gameplay-photos` 06, route `09_aerial_view` | `_waterfront_edge()` water, assets/authored/shaders/*water*, boats, Merlion jet | rA4 OURS LOSES, better than baseline (e3eef3e); MERGED in integration A (ca6591d) + foam/spray fixes (0c36d4b) | The boat must visibly interact with the water. Check for a bow wave and side spray sheet peeling off the hull. Behind it there must be a turbulent foam trail with ragged, streaky edges that spreads into a V and fades into churned water, not a flat white band with a straight edge. Airborne spray must read as translucent mist or streaked droplets. Fail if any crisp, opaque, round white dot is visibl |
| skyline | A | GTAV aerial helicopter / skyline; CONCEPT-03, SG-03 | `--photos` 06/07/16, route `09_aerial_view`, `--gameplay-photos` 07 | landmarks (build_landmarks.py, *.glb), `_infill_building` roofs, `_hdb_block` roofs, `_background_city`, `_perimeter` | rA4 OURS LOSES, better than baseline (5e58313); MERGED in integration A (9d849b4) | B, acceptance check: from the same camera about 109 m above the harbour, the water filling the lower half of the frame must not be one flat tone. It must show wave normal detail, a sun specular glint band and soft, wave-broken reflections of the waterfront towers and trees, with at least two or three boats or wakes breaking up the surface. |
| driving | B | GTAV driving chase cam | route 05–07, driving scenario | car.gd handling/camera/visuals | rC2 OURS LOSES (f38e77e); MERGED in final integration C (8017454) | Hero car under backlight. At 100% zoom on the chase car, all of the following must hold. The paint is clean and has no grain. The trunk and rear glass show clear-coat reflections of the sky and street. A bright specular or rim line runs along the roof and trunk edges from the sun ahead. The tail lamps are emissive with visible bloom. The car's cast shadow keeps readable asphalt texture instead of  |
| on-foot | B | GTAV close character, on-foot | `--gameplay-photos`, character review | player.gd, character_visual.gd | rC2 OURS LOSES (35c1ba4); MERGED (bf7929a) | Character fidelity at medium-close-up range. Pass only if all of these are visible in the frame: hair broken into strands or clumps with a soft, non-solid edge against the background; a face with skin micro-variation, defined eyes and brows and a readable expression; skin whose specular varies, with no uniform plastic sheen on the forearms; at least several readable cloth folds at the shoulders, e |
| helicopter | B | GTAV helicopter | route 08–10 | helicopter.gd | rC2 OURS LOSES (ceb507a); MERGED (96920d1) + photo_09 mast fix (32e08ba) | Image A needs a clear directional sun across the whole frame. Every building, and the helicopter, must show distinct lit and shadowed faces, with the shadow side at least about 35% darker. Buildings and trees must cast visible shadows onto streets, rooftops and water. Glass towers and the helicopter body must show specular highlights or sky reflections. The skyline must also fade with distance: to |
| hud | B | GTAV HUD readability (bar only, no copying) | route 09/11 HUD frames | hud.gd | 98b41b2 fixes never rendered | — |
| police | B | GTAV police | pursuit scenario | police parts of traffic/npc | not started | — |
| missions | B | GTAV mission staging | 13-gate route | mission.gd | not started | — |
| perf | B | — | rendered route frame times, market hitch | export_presets.cfg, shader warmup | 1.06 s market hitch | — |

## Wave A integration (2026-10-22, integrator Opus 5.5)

| Piece | Rounds (verdict vs GTA V / better than baseline) | Decision | Merged commit | Merge commit |
| --- | --- | --- | --- | --- |
| water | A1–A4 all OURS LOSES / better=true | merged latest | `e3eef3e` | `ca6591d` |
| skyline | A1–A2 better=false, A3–A4 better=true (all OURS LOSES) | merged latest | `5e58313` | `9d849b4` |
| lighting | A1–A4 all OURS LOSES / better=false | merged latest, per the orchestrator's 08:39Z guidance (critics set better=false on any regression; A3/A4 critics: "piece's own views clearly better"); A4 regressions fixed in `4d9af26` | `301a7c9` | `ffc3b01` |
| street-life | A1–A2 OURS LOSES / better=false | NOT merged: real regressions (rendered route run stalled at gate 1 between a parked coupe and a stopped bus; junction gridlock; chase camera inside the bus; box-primitive buses and bikes; clone crowds; NPCs intruding into fixed views). Branch `opus55/street-life` kept with its worktree for a later round. | — | — |

Seam fixes on the integration branch: Merlion jet/pier follow the skyline piece's moved statue (`4d9af26`); skyline haze reads the lighting sky horizon (`4d9af26`); lighting A4 fixes (neutral-cool shade fill, thinner distance fog, more sun normal bias) (`4d9af26`); QA save guard and render-gate `godot` count (`4d9af26`); water foam lattice / spray discs / seawall mosaic (`0c36d4b`); added `merlion_jet_close` view re-aimed (`d3133d1`).

## Wave B/C and final integration (2026-10-22, pre-integrator + final integrator, Opus 5.5)

| Piece | Rounds (verdict vs GTA V / better than baseline) | Decision | Merged commit | Merge commit |
| --- | --- | --- | --- | --- |
| materials | B1–B3 all OURS LOSES / better=false (B2 regression grassed hard-standing, fixed by r3) | merged (pre-integrator) | `24634e2`, then r3 head `98490b9` | `e83385b`, `e4ab271` |
| on-foot | C1–C2 OURS LOSES / better=false (prop pass-through, camera clip into a pedestrian head) | merged (pre-integrator): net-positive gait, arm swing, contact shadows | `35c1ba4` | `bf7929a` |
| helicopter | C1 OURS LOSES / better=true; C2 OURS LOSES / better=false (rotor invisible in chase frames, photo_09 flood mast) | merged (pre-integrator); photo_09 mast regression fixed by the final integrator (`32e08ba`, rendered-verified) | `ceb507a` | `96920d1` |
| driving | C1–C2 OURS LOSES / better=false (C2 critic: "no regression found" in other views; own acceptance check A fails, empty junctions) | merged (final integrator): solid medians + keep-left scripted drive fix the open "car drives through the median planters" regression; tyre smoke/marks, brake lamps, sprung body, SG plates, drive showcase | `f38e77e` | `8017454` |
| street-life | A1–A2 OURS LOSES / better=false | NOT merged: fix branch `opus55/street-life-fix` (`5a98b9f`) failed 2 of 4 headless routes on the merged line (player-car/ambient deadlock; player car destroyed by ambient collisions); no time to make it safe before feature freeze | — | — |

Final verification (game code `32e08ba`): headless `--test` 140/140; headless `--capture` route 13/13, 0 deaths, 153.4 s; rendered route, `--photos` (18) and `--gameplay-photos` (7) at 1280x720 through `loop/render.sh`. Images: `progress/img/integration/C/`. See `HANDOFF.md` and `loop/RUN.md`.


## Run 2 pieces

| Piece | Wave | Matched refs | Capture spec / play scenario | Owns (files) | Current verdict | Open biggest gap |
| --- | --- | --- | --- | --- | --- | --- |
| street-life | D | traffic, crowds, driving-chase, on-foot-street | junction/street views + route drive leg | traffic_manager.gd, npc.gd, avenue_dressing.gd, crowd code | run 1: OURS LOSES, unmerged | junctions empty; scripted drive unreliable with ambient traffic |
| characters | D | close-character, crowds | --character-review, close third-person, crowd views | player.gd, character_visual.gd, character assets | run 1 (on-foot): OURS LOSES | hair/face/skin/cloth at close range; shirt shadow blotches; clone NPCs |
| nearfield | D | on-foot-street, driving-chase | bottom-40% street views | palette.gd, surfaces/shaders, street props/placeholders | run 1 (materials): OURS LOSES | blockout kerbs, sign bases, median plants, asphalt mottling, placeholder props |
| aerial | D | aerial-helicopter, skyline-aerial | photo_06/07/16, route 09 | lighting.gd sun/sky/fog, skyline far-shore materials | run 1: OURS LOSES | tower lit/shadow contrast, glass specular, aerial perspective beyond ~3 km |
| driving-2 | E | driving-chase | route 05-07 + chase footage | car.gd visuals/collision | run 1: OURS LOSES | hero car paint grain, no clear-coat, dead-stop collisions |
| helicopter-2 | E | aerial-helicopter | route 08-10 + flight footage | helicopter.gd, aviation block | run 1: OURS LOSES | rotor invisible in chase frames, bare dirt lots |
| locomotion | P | close-character, on-foot-street | gait footage + cycle strips | player.gd movement, character_visual.gd, rig_characters.py (new v2 exports) | owner: walk/run look terrible | walk clip played ~2.5x; wide stance; need real walk/run/sprint/jump |
| combat | P | close-character, police | firefight footage, 03_combat | new combat files + hooks | not started | muzzle/impact FX, recoil, hit reactions |
| driving | P | driving-chase, traffic | chase footage, route 05-07 | car.gd | run 1: OURS LOSES | dead-stop collisions, paint, feel |
| helicopter | P | aerial-helicopter | flight footage, route 08-10 | helicopter.gd | run 1: OURS LOSES | rotor invisible, downwash |
