# Pieces — Opus 5.5 enhancement loop

Smallest independently improvable and judgeable pieces. Reference IDs come from `loop/REFERENCES.md`
(GTAV-xx = quality bar, CONCEPT-0x / SG-0x = Singapore identity). Verdicts are blind critic verdicts
against GTA V; "best so far" is not "accepted". Wave A runs first (the critic's biggest named gaps).

| Piece | Wave | Matched refs | Capture spec / play scenario | Owns (files) | Current verdict | Open biggest gap |
| --- | --- | --- | --- | --- | --- | --- |
| street-life | A | GTAV traffic, on-foot street, driving chase; CONCEPT-01/02, SG-01 | `--gameplay-photos` 01/03/05, route `05_car_entered`, `06_driving`; `--photos` 06_aerial_district | traffic_manager.gd, npc.gd, spawn/density parts of car.gd, new src/systems/crowd*.gd | inherited: empty streets (critic 5) | ≥8 vehicles, ≥10 pedestrians, canopy over road in 06_driving and photo_06 |
| lighting | A | GTAV lighting / golden hour, on-foot street; CONCEPT-01 | `--photos` 01/02/04, `--gameplay-photos` 01/02 | `_environment()` → new src/world/lighting.gd, `_street_lamp`, new void-deck/arcade practicals | rA1 OURS LOSES (d8c19c7) | A fails on surface wear and street clutter. To pass, no surface larger than about 5% of the frame may read as clean uniform tiling or flat colour. The facade must show stains or peeling paint and dirt at its base. The paving must show wear and tonal grime. The asphalt must show cracks, patches and tyre wear. At least 8 distinct street-level clutter props (signage, bins, poles with overhead wires,  |
| water | A | GTAV coast/water, aerial; CONCEPT-03, SG-03 | `--photos` 05/07/16, `--gameplay-photos` 06, route `09_aerial_view` | `_waterfront_edge()` water, assets/authored/shaders/*water*, boats, Merlion jet | rA1 OURS LOSES (e0bb480) | Near and mid-ground surface detail: in the bottom 40% of A there is no flat, untextured, single-colour building mass. Every roof shows parapets, rooftop plant and weathering variation; facades show windows and trim; streets show lane markings, kerbs and visible traffic or pedestrians; trees have self-shadowed leaf-cluster canopies. The skyline uses at least 6 visibly distinct tower designs, with n |
| skyline | A | GTAV aerial helicopter / skyline; CONCEPT-03, SG-03 | `--photos` 06/07/16, route `09_aerial_view`, `--gameplay-photos` 07 | landmarks (build_landmarks.py, *.glb), `_infill_building` roofs, `_hdb_block` roofs, `_background_city`, `_perimeter` | rA1 OURS LOSES (7904499) | Lighting and atmospheric depth (image A). With the same camera, (1) one directional sun must make every building cast a crisp shadow onto the streets and neighbouring roofs (no building without a visible cast shadow), and (2) the far downtown towers across the bay must sit in sun-tinted haze: their facades clearly lower in contrast and shifted toward the sky colour, roughly half the near-block con |
| driving | B | GTAV driving chase cam | route 05–07, driving scenario | car.gd handling/camera/visuals | not started | — |
| on-foot | B | GTAV close character, on-foot | `--gameplay-photos`, character review | player.gd, character_visual.gd | not started | — |
| helicopter | B | GTAV helicopter | route 08–10 | helicopter.gd | not started | — |
| hud | B | GTAV HUD readability (bar only, no copying) | route 09/11 HUD frames | hud.gd | 98b41b2 fixes never rendered | — |
| police | B | GTAV police | pursuit scenario | police parts of traffic/npc | not started | — |
| missions | B | GTAV mission staging | 13-gate route | mission.gd | not started | — |
| perf | B | — | rendered route frame times, market hitch | export_presets.cfg, shader warmup | 1.06 s market hitch | — |
