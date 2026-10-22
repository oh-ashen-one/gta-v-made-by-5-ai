# Pieces — Opus 5.5 enhancement loop

Smallest independently improvable and judgeable pieces. Reference IDs come from `loop/REFERENCES.md`
(GTAV-xx = quality bar, CONCEPT-0x / SG-0x = Singapore identity). Verdicts are blind critic verdicts
against GTA V; "best so far" is not "accepted". Wave A runs first (the critic's biggest named gaps).

| Piece | Wave | Matched refs | Capture spec / play scenario | Owns (files) | Current verdict | Open biggest gap |
| --- | --- | --- | --- | --- | --- | --- |
| street-life | A | GTAV traffic, on-foot street, driving chase; CONCEPT-01/02, SG-01 | `--gameplay-photos` 01/03/05, route `05_car_entered`, `06_driving`; `--photos` 06_aerial_district | traffic_manager.gd, npc.gd, spawn/density parts of car.gd, new src/systems/crowd*.gd | inherited: empty streets (critic 5) | ≥8 vehicles, ≥10 pedestrians, canopy over road in 06_driving and photo_06 |
| lighting | A | GTAV lighting / golden hour, on-foot street; CONCEPT-01 | `--photos` 01/02/04, `--gameplay-photos` 01/02 | `_environment()` → new src/world/lighting.gd, `_street_lamp`, new void-deck/arcade practicals | rA2 OURS LOSES (cc5c2b9) | Gap in A. Same toward-sun street view: the near ~80 m of street (the bottom half of the frame) must be dressed and worn. Required: at least 4 parked or moving vehicles; visible street furniture and props (signs, bins, bikes, lamp posts, planters) in the lane and sidewalk band; asphalt and pavers with patching, stains, cracks and worn lane paint, and no visible repeating tile seams; the median as k |
| water | A | GTAV coast/water, aerial; CONCEPT-03, SG-03 | `--photos` 05/07/16, `--gameplay-photos` 06, route `09_aerial_view` | `_waterfront_edge()` water, assets/authored/shaders/*water*, boats, Merlion jet | rA2 OURS LOSES (3a10309) | A, populated and detailed waterfront: in this water-level frame at least one vessel under way must be visible in the nearest half of the water, with a white bow wave and a foam wake. At least 4 more boats, moored or moving, must sit at varied distances, and the shoreline band must show at least 5 distinct signs of activity (vehicles, pedestrians, signage, kiosks, flags). No two adjacent buildings  |
| skyline | A | GTAV aerial helicopter / skyline; CONCEPT-03, SG-03 | `--photos` 06/07/16, route `09_aerial_view`, `--gameplay-photos` 07 | landmarks (build_landmarks.py, *.glb), `_infill_building` roofs, `_hdb_block` roofs, `_background_city`, `_perimeter` | rA2 OURS LOSES (aec2319) | Atmosphere and sun (A): from about 110 m altitude, the skyline across the water (about 1-2 km away) must show clear aerial perspective. It must look visibly lower in contrast and tinted toward the haze or sky colour compared with the blocks directly under the helicopter. The sky must show clouds or a visible sun with bloom. The bay water must reflect the skyline and sky with a sun glint, not read  |
| driving | B | GTAV driving chase cam | route 05–07, driving scenario | car.gd handling/camera/visuals | not started | — |
| on-foot | B | GTAV close character, on-foot | `--gameplay-photos`, character review | player.gd, character_visual.gd | not started | — |
| helicopter | B | GTAV helicopter | route 08–10 | helicopter.gd | not started | — |
| hud | B | GTAV HUD readability (bar only, no copying) | route 09/11 HUD frames | hud.gd | 98b41b2 fixes never rendered | — |
| police | B | GTAV police | pursuit scenario | police parts of traffic/npc | not started | — |
| missions | B | GTAV mission staging | 13-gate route | mission.gd | not started | — |
| perf | B | — | rendered route frame times, market hitch | export_presets.cfg, shader warmup | 1.06 s market hitch | — |
