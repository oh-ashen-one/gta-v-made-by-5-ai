class_name DowntownPlan
extends RefCounted
## Authoritative machine-readable city plan for the Marina Bay downtown (wave M).
## Human-readable version, rationale and ownership: loop/DOWNTOWN_PLAN.md.
##
## Every downtown piece (map, landmarks, blocks, street-life) reads its numbers
## from here instead of hard-coding them. Changing a value is a plan amendment:
## bump PLAN_VERSION and log it in loop/DOWNTOWN_PLAN.md section 12.
##
## Frame: metres, the same frame as world_builder.gd. y is up; ground/quay top
## is +0.3, bay water is at BayWater.LEVEL (-0.9).
## Compass (non-mirrored, real geography rotated so the bay lies "up" the map):
##   game -z = real EAST (bayward, toward Marina Bay Sands)
##   game +z = real WEST (inland, Chinatown / Tanjong Pagar heritage side)
##   game -x = real NORTH (river mouth, Esplanade, Marina Centre, Flyer)
##   game +x = real SOUTH (Marina Bay Financial Centre, Shenton Way)
## Rect2 values are (x_min, z_min, width_x, depth_z) on the ground plane.
## Loading this file changes nothing in game; only pieces act on it.

const PLAN_VERSION := "Singapore fidelity R1 2026-10-28; geographic migration pending"

const WATER_LEVEL := -0.9
const QUAY_TOP := 0.3
const NORTH := Vector3(-1.0, 0.0, 0.0)
const EAST := Vector3(0.0, 0.0, -1.0)
## Distance compression of real geography (landmark structures stay 1:1).
const DISTANCE_SCALE_EAST_WEST := 0.45   # bay crossing (fixed promenade -> fixed MBS)
const DISTANCE_SCALE_NORTH_SOUTH := 0.65

## Copies of existing world_builder.gd values the plan is built around. The
## self-test asserts they still match WorldBuilder (never edit them here alone).
const LEGACY := {
	"player_start": Vector3(-171.0, 0.45, -22.0),
	"player_start_yaw_deg": -8.0,
	"mbs_pos": Vector3(-118.0, 0.0, -705.0),
	"grove_pos": Vector3(-80.0, 0.16, -262.0),
	"promenade_z": -338.0,
	"district": Rect2(-330.0, -330.0, 660.0, 660.0),
	"promenade": Rect2(-350.0, -349.0, 700.0, 22.0),
	"near_seawall_z": -349.9,
	"far_seawall_z": -624.0,
	"x_lines": [-320.0, -160.0, 0.0, 160.0, 320.0],
	"z_lines": [-320.0, -160.0, 0.0, 160.0, 320.0],
}

## ---------------------------------------------------------------- bounds
## Ground-level playable area (walk + drive). Everything inside that is land
## must be finished street, plaza, park or building; water inside it is real
## water you can fall into (recovery by the existing ditch rule).
const PLAYABLE := Rect2(-900.0, -1060.0, 1660.0, 1435.0)   # x -900..760, z -1060..375
## Helicopter envelope (turn-back beyond it) and ceiling.
const AIR := Rect2(-1300.0, -1400.0, 2450.0, 2220.0)       # x -1300..1150, z -1400..820
const AIR_CEILING := 420.0
## Boundary treatment per edge of PLAYABLE (owner: downtown-map).
const EDGES := {
	"north_x_-900": "construction hoarding + railings along Stamford Rd / Bras Basah; background city beyond",
	"south_x_760": "construction hoarding along Tanjong Pagar; background estates beyond",
	"west_z_375": "existing boundary_railing line extended over the CBD, civic and Shenton strips",
	"east_z_-1060": "Gardens by the Bay perimeter fence and Marina Channel waterfront rail; Sheares Bridge beyond",
}

## ---------------------------------------------------------------- water
## Water = inside any WATER rect and not inside any ISLAND rect.
const WATER := {
	"basin": Rect2(-640.0, -624.0, 990.0, 275.0),          # x -640..350, z -624..-349
	"basin_ne_lobe": Rect2(-640.0, -660.0, 310.0, 36.0),   # x -640..-330, z -660..-624
	"east_channel": Rect2(-470.0, -1100.0, 140.0, 440.0),  # x -470..-330, z -1100..-660 (to Marina Channel)
	"singapore_river": Rect2(-590.0, -349.0, 60.0, 1100.0),# x -590..-530, z -349..751 (inland, west)
}
## Land that juts into the water (built by downtown-map; dressed by landmarks).
const ISLANDS := {
	"fullerton_peninsula": Rect2(-530.0, -412.0, 90.0, 63.0),   # One Fullerton / Merlion Park site
	"artscience_promontory": Rect2(-322.0, -626.0, 64.0, 56.0), # lotus at the Bayfront tip
	"ns_square_float": Rect2(-640.0, -660.0, 120.0, 83.0),      # ex-Float@Marina Bay, 120 x 83 m
	"merlion_pier": Rect2(57.0, -375.5, 14.0, 27.0),            # EXISTING pier (world_builder._waterfront_edge)
}

## ---------------------------------------------------------------- districts
const DISTRICTS := {
	"heritage": {"rect": Rect2(-336.0, -349.0, 672.0, 724.0), "real": "Chinatown / Telok Ayer / Tanjong Pagar heritage belt (EXISTING district, unchanged)"},
	"cbd_raffles": {"rect": Rect2(-530.0, -349.0, 194.0, 724.0), "real": "Raffles Place towers, Boat Quay, Fullerton (south bank of the river)"},
	"fullerton_waterfront": {"rect": Rect2(-530.0, -412.0, 90.0, 63.0), "real": "One Fullerton, Merlion Park site, Jubilee Bridge landing"},
	"civic_north_bank": {"rect": Rect2(-900.0, -349.0, 310.0, 724.0), "real": "Esplanade Park, Padang / civic district, Asian Civilisations Museum (north bank)"},
	"esplanade_marina_centre": {"rect": Rect2(-900.0, -660.0, 260.0, 311.0), "real": "Esplanade theatres and waterfront"},
	"marina_centre": {"rect": Rect2(-900.0, -1060.0, 430.0, 400.0), "real": "Marina Centre: Flyer, Promenade, malls and hotels"},
	"bayfront": {"rect": Rect2(-330.0, -1060.0, 680.0, 436.0), "real": "Bayfront: Marina Bay Sands, Event Plaza, ArtScience, Gardens by the Bay (Bay South)"},
	"marina_south": {"rect": Rect2(350.0, -1060.0, 410.0, 711.0), "real": "Marina Bay Financial Centre, Marina Boulevard"},
	"shenton": {"rect": Rect2(336.0, -349.0, 424.0, 724.0), "real": "Shenton Way / Anson Road office strip"},
}

## ---------------------------------------------------------------- anchors
## size = (extent along x, height, extent along z) in metres, true scale.
## status: existing = keep where it is; move = landmarks piece relocates it;
## new = not built yet; reserved = not built without an owner decision.
const ANCHORS := {
	"marina_bay_sands": {"pos": Vector3(-118.0, 0.0, -705.0), "yaw_deg": 0.0, "size": Vector3(350.0, 208.0, 63.0), "status": "existing", "owner": "landmarks",
		"real": "3 hotel towers, 55 storeys, ~194 m; SkyPark ~340 m long, ~38 m wide, cantilever ~67 m past the north tower; Shoppes podium on the bay side",
		"note": "keep MBS_POS; mirror so the SkyPark cantilever points NORTH (-x), podium stays bay side (+z)"},
	"mbs_event_plaza": {"pos": Vector3(-118.0, 0.3, -642.0), "yaw_deg": 0.0, "size": Vector3(400.0, 0.0, 36.0), "status": "new", "owner": "landmarks", "real": "Event Plaza steps and Bayfront promenade"},
	"artscience_museum": {"pos": Vector3(-290.0, 0.3, -598.0), "yaw_deg": 12.0, "size": Vector3(80.0, 60.0, 80.0), "status": "move", "owner": "landmarks",
		"real": "lotus with 10 petals, ~60 m tall, lily pond, on the promontory at the Bayfront tip", "from": Vector3(80.0, 0.0, -640.0)},
	"singapore_flyer": {"pos": Vector3(-650.0, 0.0, -880.0), "yaw_deg": -35.0, "size": Vector3(150.0, 165.0, 30.0), "status": "move", "owner": "landmarks",
		"real": "165 m overall, 150 m wheel, 28 capsules, 3-storey terminal under it", "from": Vector3(210.0, 0.0, -700.0)},
	"helix_bridge": {"pos": Vector3(-380.0, 3.6, -745.0), "yaw_deg": 0.0, "size": Vector3(220.0, 14.0, 12.0), "status": "new", "owner": "landmarks",
		"real": "280 m curved pedestrian double-helix steel bridge beside the Bayfront vehicular bridge"},
	"esplanade_concert_hall": {"pos": Vector3(-712.0, 0.3, -455.0), "yaw_deg": 0.0, "size": Vector3(70.0, 40.0, 95.0), "status": "new", "owner": "landmarks",
		"real": "Esplanade - Theatres on the Bay: spiky aluminium sunshade dome (concert hall)"},
	"esplanade_theatre": {"pos": Vector3(-712.0, 0.3, -575.0), "yaw_deg": 0.0, "size": Vector3(75.0, 45.0, 100.0), "status": "new", "owner": "landmarks",
		"real": "second dome (theatre), outdoor waterfront theatre on the bay side"},
	"merlion": {"pos": Vector3(64.0, 0.3, -371.0), "yaw_deg": -135.0, "size": Vector3(11.0, 10.8, 11.0), "status": "existing", "owner": "legacy",
		"real": "8.6 m statue spouting into the bay", "note": "kept at the existing pier (fixed comparison views, tuned jet); see merlion_park_true / decision O-1"},
	"merlion_park_true": {"pos": Vector3(-470.0, 0.3, -405.0), "yaw_deg": 180.0, "size": Vector3(60.0, 0.0, 30.0), "status": "reserved", "owner": "landmarks",
		"real": "geographic Merlion Park at the river mouth; statue moves here only on owner decision O-1"},
	"fullerton_hotel": {"pos": Vector3(-485.0, 0.3, -257.0), "yaw_deg": 0.0, "size": Vector3(80.0, 35.0, 85.0), "status": "new", "owner": "landmarks",
		"real": "neoclassical granite block with Doric colonnade and flagpole lantern on the river mouth"},
	"one_fullerton": {"pos": Vector3(-488.0, 0.3, -392.0), "yaw_deg": 0.0, "size": Vector3(75.0, 12.0, 34.0), "status": "new", "owner": "landmarks",
		"real": "low waterfront dining pavilions on the peninsula"},
	"supertree_grove_district": {"pos": Vector3(-80.0, 0.16, -262.0), "yaw_deg": 0.0, "size": Vector3(61.0, 44.0, 40.0), "status": "existing", "owner": "legacy",
		"real": "existing in-district grove: kept for the WORLD-03 opening composition"},
	"gardens_supertree_grove": {"pos": Vector3(-10.0, 0.0, -905.0), "yaw_deg": 0.0, "size": Vector3(180.0, 50.0, 140.0), "status": "new", "owner": "landmarks",
		"real": "12 supertrees 25-50 m in a ring; OCBC Skyway ~128 m long at ~22 m"},
	"flower_dome": {"pos": Vector3(230.0, 0.0, -875.0), "yaw_deg": 0.0, "size": Vector3(170.0, 38.0, 90.0), "status": "new", "owner": "landmarks", "real": "glass shell conservatory ~1.2 ha"},
	"cloud_forest": {"pos": Vector3(240.0, 0.0, -985.0), "yaw_deg": 0.0, "size": Vector3(110.0, 58.0, 80.0), "status": "new", "owner": "landmarks", "real": "taller glass dome ~0.8 ha around an indoor mountain"},
	"ns_square": {"pos": Vector3(-580.0, 0.3, -618.0), "yaw_deg": 0.0, "size": Vector3(120.0, 0.0, 83.0), "status": "new", "owner": "map", "real": "floating platform / stadium-seating square"},
	"raffles_place": {"pos": Vector3(-377.0, 0.16, -80.0), "yaw_deg": 0.0, "size": Vector3(86.0, 0.0, 139.0), "status": "new", "owner": "blocks", "real": "plaza ringed by the 280 m Raffles Place towers, MRT entrances"},
	"boat_quay": {"pos": Vector3(-511.0, 0.0, 90.0), "yaw_deg": 0.0, "size": Vector3(18.0, 14.0, 560.0), "status": "new", "owner": "blocks", "real": "curved row of 2-3 storey shophouses facing the river with CBD towers behind"},
	"mbfc": {"pos": Vector3(481.0, 0.0, -480.0), "yaw_deg": 0.0, "size": Vector3(136.0, 245.0, 300.0), "status": "new", "owner": "blocks", "real": "Marina Bay Financial Centre towers 200-245 m + Marina Bay Link Mall"},
	"sheares_bridge": {"pos": Vector3(-350.0, 29.0, -1120.0), "yaw_deg": 0.0, "size": Vector3(1300.0, 4.0, 30.0), "status": "new", "owner": "map", "real": "elevated expressway bridge on the eastern horizon (air-only collision)"},
}

## ---------------------------------------------------------------- roads
## pts: centreline polyline (y = 0). width: kerb to kerb. lanes: per direction
## (left-hand traffic: lane i centre = (i + 0.5) * lane_w to the LEFT of the
## centreline in the travel direction). legacy: geometry already exists in
## world_builder (do not rebuild it, only connect to it). Roads never cross
## water; crossings are BRIDGES entries.
const ROADS := {
	"collyer_quay": {"pts": [Vector3(400.0, 0.0, -320.0), Vector3(-470.0, 0.0, -320.0)], "width": 16.0, "lanes": 1, "kind": "arterial", "speed_kmh": 50, "legacy_span_x": Vector2(-320.0, 320.0)},
	"fullerton_road": {"pts": [Vector3(-470.0, 0.0, -320.0), Vector3(-500.0, 0.0, -332.0), Vector3(-520.0, 0.0, -350.0), Vector3(-530.0, 0.0, -360.0)], "width": 16.0, "lanes": 1, "kind": "arterial", "speed_kmh": 40},
	"esplanade_drive": {"pts": [Vector3(-650.0, 0.0, -360.0), Vector3(-790.0, 0.0, -360.0), Vector3(-900.0, 0.0, -360.0)], "width": 20.0, "lanes": 2, "kind": "arterial", "speed_kmh": 50},
	"raffles_avenue": {"pts": [Vector3(-790.0, 0.0, -360.0), Vector3(-790.0, 0.0, -780.0), Vector3(-790.0, 0.0, -1000.0)], "width": 20.0, "lanes": 2, "kind": "arterial", "speed_kmh": 50},
	"bayfront_avenue_north": {"pts": [Vector3(-790.0, 0.0, -780.0), Vector3(-480.0, 0.0, -780.0)], "width": 24.0, "lanes": 3, "median": 3.0, "kind": "arterial", "speed_kmh": 60},
	"bayfront_avenue": {"pts": [Vector3(-320.0, 0.0, -780.0), Vector3(400.0, 0.0, -780.0)], "width": 24.0, "lanes": 3, "median": 3.0, "kind": "arterial", "speed_kmh": 60},
	"marina_boulevard": {"pts": [Vector3(400.0, 0.0, -780.0), Vector3(400.0, 0.0, -320.0)], "width": 20.0, "lanes": 2, "kind": "arterial", "speed_kmh": 50},
	"shenton_way": {"pts": [Vector3(400.0, 0.0, -320.0), Vector3(400.0, 0.0, 375.0)], "width": 20.0, "lanes": 2, "kind": "arterial", "speed_kmh": 50},
	"central_boulevard": {"pts": [Vector3(560.0, 0.0, -780.0), Vector3(560.0, 0.0, 375.0)], "width": 16.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
	"marina_way": {"pts": [Vector3(400.0, 0.0, -480.0), Vector3(760.0, 0.0, -480.0)], "width": 16.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
	"marina_view": {"pts": [Vector3(400.0, 0.0, -640.0), Vector3(760.0, 0.0, -640.0)], "width": 14.0, "lanes": 1, "kind": "street", "speed_kmh": 30},
	"cecil_street": {"pts": [Vector3(-430.0, 0.0, -320.0), Vector3(-430.0, 0.0, 375.0)], "width": 14.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
	"circular_road": {"pts": [Vector3(-488.0, 0.0, -200.0), Vector3(-488.0, 0.0, 375.0)], "width": 7.0, "lanes": 1, "oneway": true, "kind": "lane", "speed_kmh": 20},
	"chulia_street": {"pts": [Vector3(-320.0, 0.0, -160.0), Vector3(-488.0, 0.0, -160.0)], "width": 14.0, "lanes": 1, "kind": "street", "speed_kmh": 30},
	"market_street": {"pts": [Vector3(-320.0, 0.0, 0.0), Vector3(-525.0, 0.0, 0.0)], "width": 16.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
	"cross_street": {"pts": [Vector3(-320.0, 0.0, 160.0), Vector3(-525.0, 0.0, 160.0)], "width": 16.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
	"south_bridge_road": {"pts": [Vector3(-320.0, 0.0, 320.0), Vector3(-488.0, 0.0, 320.0)], "width": 14.0, "lanes": 1, "kind": "street", "speed_kmh": 30},
	"north_bridge_road": {"pts": [Vector3(-595.0, 0.0, 0.0), Vector3(-900.0, 0.0, 0.0)], "width": 16.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
	"coleman_street": {"pts": [Vector3(-595.0, 0.0, 160.0), Vector3(-900.0, 0.0, 160.0)], "width": 16.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
	"connaught_drive": {"pts": [Vector3(-660.0, 0.0, -360.0), Vector3(-660.0, 0.0, 0.0)], "width": 14.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
	"robinson_road": {"pts": [Vector3(320.0, 0.0, -160.0), Vector3(760.0, 0.0, -160.0)], "width": 16.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
	"anson_road": {"pts": [Vector3(320.0, 0.0, 0.0), Vector3(760.0, 0.0, 0.0)], "width": 16.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
	"maxwell_road": {"pts": [Vector3(320.0, 0.0, 160.0), Vector3(760.0, 0.0, 160.0)], "width": 16.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
	"keppel_link": {"pts": [Vector3(320.0, 0.0, 320.0), Vector3(760.0, 0.0, 320.0)], "width": 16.0, "lanes": 1, "kind": "street", "speed_kmh": 40},
}

## The driveable Marina Bay loop (left-hand, clockwise seen from above is the
## kerb-side lane): ordered road / bridge names.
const BAY_LOOP := ["collyer_quay", "fullerton_road", "esplanade_bridge", "esplanade_drive", "raffles_avenue", "bayfront_avenue_north", "bayfront_bridge", "bayfront_avenue", "marina_boulevard"]
const CBD_LOOP := ["collyer_quay", "cecil_street", "market_street", "elgin_bridge", "north_bridge_road", "connaught_drive", "esplanade_drive", "esplanade_bridge", "fullerton_road"]

## ---------------------------------------------------------------- bridges
## deck_y = finished deck at mid-span; ramps never exceed max_grade.
## soffit_y = underside at the navigation span (water at -0.9).
const BRIDGES := {
	"esplanade_bridge": {"from": Vector3(-530.0, 0.0, -360.0), "to": Vector3(-650.0, 0.0, -360.0), "width": 24.0, "lanes": 2, "deck_y": 3.6, "soffit_y": 2.6, "max_grade": 0.06, "kind": "vehicle", "owner": "map",
		"real": "260 m low multi-arch road bridge across the river mouth (Esplanade Drive)"},
	"bayfront_bridge": {"from": Vector3(-480.0, 0.0, -780.0), "to": Vector3(-320.0, 0.0, -780.0), "width": 28.0, "lanes": 3, "deck_y": 3.6, "soffit_y": 2.4, "max_grade": 0.06, "kind": "vehicle", "owner": "map",
		"real": "6-lane Bayfront Avenue bridge, Marina Centre to the Bayfront"},
	"helix_bridge": {"from": Vector3(-490.0, 0.0, -745.0), "to": Vector3(-270.0, 0.0, -745.0), "width": 6.0, "lanes": 0, "deck_y": 3.6, "soffit_y": 2.4, "max_grade": 0.05, "kind": "pedestrian", "owner": "landmarks",
		"real": "real 280 m curved double-helix footbridge (220 m here: channel compressed); tubes rise ~14 m above the deck"},
	"jubilee_bridge": {"from": Vector3(-530.0, 0.0, -400.0), "to": Vector3(-650.0, 0.0, -400.0), "width": 6.0, "lanes": 0, "deck_y": 2.6, "soffit_y": 1.8, "max_grade": 0.05, "kind": "pedestrian", "owner": "map",
		"real": "220 m footbridge from Merlion Park / One Fullerton to the Esplanade waterfront"},
	"cavenagh_bridge": {"from": Vector3(-530.0, 0.0, -208.0), "to": Vector3(-595.0, 0.0, -208.0), "width": 6.0, "lanes": 0, "deck_y": 2.4, "soffit_y": 1.8, "max_grade": 0.05, "kind": "pedestrian", "owner": "map",
		"real": "1869 steel suspension footbridge beside the Fullerton"},
	"elgin_bridge": {"from": Vector3(-525.0, 0.0, 0.0), "to": Vector3(-595.0, 0.0, 0.0), "width": 16.0, "lanes": 1, "deck_y": 2.6, "soffit_y": 1.8, "max_grade": 0.06, "kind": "vehicle", "owner": "map",
		"real": "low concrete arch road bridge, cast-iron lamps"},
	"coleman_bridge": {"from": Vector3(-525.0, 0.0, 160.0), "to": Vector3(-595.0, 0.0, 160.0), "width": 16.0, "lanes": 1, "deck_y": 2.6, "soffit_y": 1.8, "max_grade": 0.06, "kind": "vehicle", "owner": "map",
		"real": "low arch road bridge upstream of Boat Quay"},
}

## ---------------------------------------------------------------- blocks
## Building plots (downtown-blocks). Each rect keeps >= 3 m of pavement clear
## of every road kerb. front = the side(s) that must carry a full street
## frontage (shopfronts, lobbies, canopies, signage).
const BLOCKS := {
	"fullerton_site": {"rect": Rect2(-525.0, -309.0, 85.0, 94.0), "kind": "landmark_site", "owner": "landmarks", "max_h": 40.0},
	"boat_quay_1": {"rect": Rect2(-520.0, -200.0, 18.0, 189.0), "kind": "boat_quay_row", "max_h": 14.0, "front": "-x (river)"},
	"boat_quay_2": {"rect": Rect2(-520.0, 11.0, 18.0, 138.0), "kind": "boat_quay_row", "max_h": 14.0, "front": "-x (river)"},
	"boat_quay_3": {"rect": Rect2(-520.0, 171.0, 18.0, 204.0), "kind": "boat_quay_row", "max_h": 14.0, "front": "-x (river)"},
	"cbd_a2": {"rect": Rect2(-481.0, -150.0, 41.0, 139.0), "kind": "cbd_tower", "max_h": 280.0, "front": "-x"},
	"cbd_a3": {"rect": Rect2(-481.0, 11.0, 41.0, 138.0), "kind": "cbd_tower", "max_h": 245.0, "front": "-x"},
	"cbd_a4": {"rect": Rect2(-481.0, 171.0, 41.0, 139.0), "kind": "cbd_tower", "max_h": 200.0, "front": "-x"},
	"cbd_b1": {"rect": Rect2(-420.0, -309.0, 86.0, 139.0), "kind": "cbd_tower", "max_h": 280.0, "front": "-z (Collyer Quay)"},
	"raffles_place_plaza": {"rect": Rect2(-420.0, -150.0, 86.0, 139.0), "kind": "plaza", "max_h": 6.0, "front": "all"},
	"cbd_b3": {"rect": Rect2(-420.0, 11.0, 86.0, 138.0), "kind": "cbd_tower", "max_h": 280.0, "front": "+x (Cecil St)"},
	"cbd_b4": {"rect": Rect2(-420.0, 171.0, 86.0, 139.0), "kind": "cbd_tower", "max_h": 200.0, "front": "+x"},
	"cbd_b5": {"rect": Rect2(-420.0, 331.0, 86.0, 44.0), "kind": "mid_rise", "max_h": 80.0, "front": "-z"},
	"civic_padang": {"rect": Rect2(-900.0, -347.0, 230.0, 336.0), "kind": "civic", "max_h": 40.0, "front": "+x (Connaught Dr), -z (Esplanade Dr)"},
	"esplanade_park": {"rect": Rect2(-650.0, -347.0, 50.0, 336.0), "kind": "park", "max_h": 12.0, "front": "+x (river walk)"},
	"civic_museum": {"rect": Rect2(-900.0, 11.0, 290.0, 138.0), "kind": "civic", "max_h": 35.0, "front": "+x (river)"},
	"civic_upriver": {"rect": Rect2(-900.0, 171.0, 290.0, 204.0), "kind": "mid_rise", "max_h": 90.0, "front": "+x (river)"},
	"esplanade_site": {"rect": Rect2(-775.0, -630.0, 120.0, 257.0), "kind": "landmark_site", "owner": "landmarks", "max_h": 45.0},
	"marina_centre_west": {"rect": Rect2(-900.0, -765.0, 97.0, 392.0), "kind": "marina_centre", "max_h": 180.0, "front": "+x (Raffles Ave)"},
	# S-1 (downtown-polish): starts 12 m further from Raffles Avenue, so the
	# right turn from Raffles Avenue onto Bayfront Avenue North has a corner
	# plaza and sightline instead of a podium 6 m off the kerb return.
	"marina_centre_bay": {"rect": Rect2(-765.0, -765.0, 270.0, 93.0), "kind": "marina_centre", "max_h": 160.0, "front": "+z (Promenade), -z (Bayfront Ave)"},
	"marina_centre_far": {"rect": Rect2(-900.0, -1000.0, 97.0, 205.0), "kind": "marina_centre", "max_h": 120.0, "front": "+x"},
	"flyer_site": {"rect": Rect2(-777.0, -1000.0, 282.0, 205.0), "kind": "landmark_site", "owner": "landmarks", "max_h": 170.0},
	"mbs_site": {"rect": Rect2(-330.0, -765.0, 390.0, 105.0), "kind": "landmark_site", "owner": "landmarks", "max_h": 210.0},
	"the_lawn": {"rect": Rect2(60.0, -700.0, 290.0, 74.0), "kind": "park", "max_h": 6.0, "front": "+z (bay)"},
	"bayfront_expo": {"rect": Rect2(60.0, -765.0, 327.0, 60.0), "kind": "podium", "max_h": 40.0, "front": "-z (Bayfront Ave)"},
	"gardens_site": {"rect": Rect2(-330.0, -1060.0, 717.0, 265.0), "kind": "landmark_site", "owner": "landmarks", "max_h": 60.0},
	"mbfc_1": {"rect": Rect2(413.0, -469.0, 136.0, 138.0), "kind": "mbfc_tower", "max_h": 245.0, "front": "-x (Marina Blvd), +z"},
	"mbfc_2": {"rect": Rect2(413.0, -629.0, 136.0, 138.0), "kind": "mbfc_tower", "max_h": 245.0, "front": "-x"},
	"mbfc_3": {"rect": Rect2(413.0, -765.0, 136.0, 115.0), "kind": "mbfc_tower", "max_h": 245.0, "front": "-x, -z"},
	"marina_south_1": {"rect": Rect2(571.0, -469.0, 189.0, 138.0), "kind": "cbd_tower", "max_h": 220.0, "front": "-x"},
	"marina_south_2": {"rect": Rect2(571.0, -629.0, 189.0, 138.0), "kind": "cbd_tower", "max_h": 200.0, "front": "-x"},
	"marina_south_3": {"rect": Rect2(571.0, -765.0, 189.0, 115.0), "kind": "mid_rise", "max_h": 120.0, "front": "-x"},
	"shenton_w1": {"rect": Rect2(331.0, -309.0, 56.0, 138.0), "kind": "mid_rise", "max_h": 90.0, "front": "+x (Shenton Way)"},
	"shenton_w2": {"rect": Rect2(331.0, -149.0, 56.0, 138.0), "kind": "mid_rise", "max_h": 90.0, "front": "+x"},
	"shenton_w3": {"rect": Rect2(331.0, 11.0, 56.0, 138.0), "kind": "mid_rise", "max_h": 90.0, "front": "+x"},
	"shenton_w4": {"rect": Rect2(331.0, 171.0, 56.0, 138.0), "kind": "mid_rise", "max_h": 90.0, "front": "+x"},
	"shenton_e1": {"rect": Rect2(413.0, -309.0, 136.0, 138.0), "kind": "cbd_tower", "max_h": 240.0, "front": "-x"},
	"shenton_e2": {"rect": Rect2(413.0, -149.0, 136.0, 138.0), "kind": "cbd_tower", "max_h": 200.0, "front": "-x"},
	"shenton_e3": {"rect": Rect2(413.0, 11.0, 136.0, 138.0), "kind": "cbd_tower", "max_h": 180.0, "front": "-x"},
	"shenton_e4": {"rect": Rect2(413.0, 171.0, 136.0, 138.0), "kind": "mid_rise", "max_h": 120.0, "front": "-x"},
	"shenton_f1": {"rect": Rect2(571.0, -309.0, 189.0, 138.0), "kind": "mid_rise", "max_h": 120.0, "front": "-x"},
	"shenton_f2": {"rect": Rect2(571.0, -149.0, 189.0, 138.0), "kind": "mid_rise", "max_h": 100.0, "front": "-x"},
	"shenton_f3": {"rect": Rect2(571.0, 11.0, 189.0, 138.0), "kind": "residential", "max_h": 140.0, "front": "-x"},
	"shenton_f4": {"rect": Rect2(571.0, 171.0, 189.0, 138.0), "kind": "residential", "max_h": 140.0, "front": "-x"},
}

## ---------------------------------------------------------------- public realm
## Promenades, river walks and parks (paving/kerbs/rails: downtown-map; trees,
## furniture: map; landmark-specific dressing: landmarks).
const PROMENADES := {
	"west_shore_promenade": {"pts": [Vector3(-440.0, 0.3, -338.0), Vector3(350.0, 0.3, -338.0)], "width": 22.0, "legacy_span_x": Vector2(-350.0, 350.0)},
	"fullerton_peninsula_walk": {"pts": [Vector3(-440.0, 0.3, -380.0), Vector3(-528.0, 0.3, -380.0), Vector3(-528.0, 0.3, -340.0)], "width": 10.0},
	"boat_quay_river_walk": {"pts": [Vector3(-525.0, 0.3, -215.0), Vector3(-525.0, 0.3, 375.0)], "width": 10.0},
	"north_bank_river_walk": {"pts": [Vector3(-595.0, 0.3, -345.0), Vector3(-595.0, 0.3, 375.0)], "width": 10.0},
	"esplanade_waterfront": {"pts": [Vector3(-647.0, 0.3, -372.0), Vector3(-647.0, 0.3, -666.0)], "width": 14.0},
	"marina_promenade": {"pts": [Vector3(-648.0, 0.3, -666.0), Vector3(-476.0, 0.3, -666.0), Vector3(-476.0, 0.3, -790.0)], "width": 12.0},
	"bayfront_event_plaza": {"pts": [Vector3(-324.0, 0.3, -642.0), Vector3(350.0, 0.3, -642.0)], "width": 36.0},
	"mbfc_waterfront": {"pts": [Vector3(368.0, 0.3, -640.0), Vector3(368.0, 0.3, -338.0)], "width": 36.0},
	"channel_south_walk": {"pts": [Vector3(-324.0, 0.3, -642.0), Vector3(-324.0, 0.3, -1060.0)], "width": 12.0},
}
## Walking loop around the basin (~2.6 km): promenade -> Fullerton -> Jubilee
## Bridge -> Esplanade -> Promenade -> Helix Bridge -> Event Plaza -> MBFC.
const WALK_LOOP := ["west_shore_promenade", "fullerton_peninsula_walk", "jubilee_bridge", "esplanade_waterfront", "marina_promenade", "helix_bridge", "bayfront_event_plaza", "mbfc_waterfront"]

## ---------------------------------------------------------------- helicopter
## Legacy gameplay landing markers and navigation hints.
## They do not authorize or forbid exits: Helicopter validates actual physical
## landing support and foot clearance on any roof, as requested28Oct2026.
const HELIPADS := {
	"aviation_primary": {"pos": Vector3(240.0, 0.3, 240.0), "radius": 16.0, "status": "existing"},
	"promenade_secondary": {"pos": Vector3(0.0, 0.3, -337.0), "radius": 11.0, "status": "existing"},
	"ns_square": {"pos": Vector3(-580.0, 0.3, -618.0), "radius": 16.0, "status": "new"},
	"the_lawn": {"pos": Vector3(205.0, 0.3, -662.0), "radius": 14.0, "status": "new"},
	"esplanade_park": {"pos": Vector3(-625.0, 0.3, -250.0), "radius": 12.0, "status": "new"},
	"gardens_east": {"pos": Vector3(345.0, 0.3, -1030.0), "radius": 12.0, "status": "new"},
	"skypark": {"pos": Vector3(-63.0, 200.0, -698.0), "radius": 5.0, "hint_radius": 2.5, "status": "public", "rooftop": true},
}
const GROUND_EXIT_MAX_Y := 4.5   # bridge decks are 2.4-3.6 m

## Short public-surface joins. The Jubilee reverse walk exposed a 23 cm
## vertical lip at the peninsula edge; these endpoints overlap both floors.
const PEDESTRIAN_JOINS := {
	"jubilee_fullerton": {"from": Vector3(-534.0, 0.212, -400.0), "to": Vector3(-528.0, 0.36, -400.0), "width": 5.4},
	"fullerton_heritage": {"from": Vector3(-445.0, 0.02, -338.0), "to": Vector3(-438.0, 0.30, -338.0), "width": 8.0},
}

## ---------------------------------------------------------------- views
## Proposed ADDITIONAL comparison views for the downtown (the existing fixed
## views in photo_capture.gd / capture_director.gd are never moved). The
## downtown-map piece appends these to photo_capture.gd behind one guarded
## loop; critics pair them with GTA V / SG references.
const VIEWS := [
	{"name": "dt_merlion_park_to_mbs", "pos": Vector3(-470.0, 1.7, -395.0), "look": Vector3(-118.0, 90.0, -705.0), "fov": 60.0},
	{"name": "dt_event_plaza_to_cbd", "pos": Vector3(-150.0, 1.7, -640.0), "look": Vector3(-450.0, 80.0, -200.0), "fov": 64.0},
	{"name": "dt_helix_walk", "pos": Vector3(-470.0, 5.3, -745.0), "look": Vector3(-300.0, 20.0, -745.0), "fov": 62.0},
	{"name": "dt_bayfront_drive", "pos": Vector3(100.0, 1.4, -772.0), "look": Vector3(-300.0, 10.0, -780.0), "fov": 70.0},
	{"name": "dt_boat_quay_from_north_bank", "pos": Vector3(-595.0, 1.7, 60.0), "look": Vector3(-480.0, 40.0, -40.0), "fov": 62.0},
	{"name": "dt_raffles_place", "pos": Vector3(-377.0, 1.7, -20.0), "look": Vector3(-400.0, 120.0, -160.0), "fov": 70.0},
	{"name": "dt_cecil_street_canyon", "pos": Vector3(-430.0, 1.7, -250.0), "look": Vector3(-430.0, 30.0, 100.0), "fov": 64.0},
	{"name": "dt_esplanade_waterfront", "pos": Vector3(-650.0, 1.7, -390.0), "look": Vector3(-712.0, 15.0, -500.0), "fov": 64.0},
	{"name": "dt_gardens_to_mbs", "pos": Vector3(40.0, 1.7, -960.0), "look": Vector3(-118.0, 90.0, -705.0), "fov": 66.0},
	{"name": "dt_mbfc_waterfront_to_mbs", "pos": Vector3(368.0, 1.7, -360.0), "look": Vector3(-118.0, 60.0, -705.0), "fov": 62.0},
	{"name": "dt_aerial_marina_bay", "pos": Vector3(-900.0, 260.0, -200.0), "look": Vector3(-150.0, 0.0, -650.0), "fov": 62.0},
]

## ---------------------------------------------------------------- performance
const PERF := {
	"vis_detail_end": 250.0,     # facade props, signage, window frames, railings
	"vis_mid_end": 900.0,        # simplified tower shells / shophouse rows
	"vis_hysteresis": 30.0,
	"shadow_cast_max": 600.0,    # beyond: SHADOW_CASTING_SETTING_OFF
	"collision_shapes_budget": {"map": 700, "landmarks": 300, "blocks": 600},
	"trimesh_shapes_max": 6,
	"draw_calls_added_busiest_view": 1200,
	"new_omni_spot_lights_max": 48,
	"build_time_added_s": 4.0,
	"frame_time_regression_max": 0.10,
}

## ---------------------------------------------------------------- integration
## Piece entry scripts WorldBuilder loads when present (see world_builder.gd
## "Downtown integration hooks"). Each is `extends RefCounted` with
## build(world, root); optional replaces(), skyline_clear(world, city),
## build_lanes(world), finish(world).
const PIECE_SCRIPTS := [
	"res://src/world/downtown/map.gd",
	"res://src/world/downtown/landmarks.gd",
	"res://src/world/downtown/blocks.gd",
]
## Per-piece regression checks the self-test runs when present: each
## `extends RefCounted` with run(world, suite) calling suite._check(...).
const PIECE_TESTS := [
	"res://src/systems/downtown_tests/map_test.gd",
	"res://src/systems/downtown_tests/landmarks_test.gd",
	"res://src/systems/downtown_tests/blocks_test.gd",
	"res://src/systems/downtown_tests/street_life_test.gd",
	"res://src/systems/downtown_tests/polish_test.gd",
	"res://src/systems/downtown_tests/fill_test.gd",
]
## Legacy builder sections a piece may take over via replaces(). WorldBuilder
## skips a section only when some present piece lists its key.
const LEGACY_KEYS := {
	"district_ground": "world_builder._ground(): 1500 x 1100 concrete slab (covers the river line)",
	"far_shore_ground": "_far_shore_landmarks() plaza/turf/collision slab + _perimeter() far ground, seawall z=-624, asphalt strip",
	"far_shore_landmarks": "_far_shore_landmarks() MBS / ArtScience / Flyer meshes, collisions and locations keys",
	"boundary_rails_x": "_perimeter() railings + colliders at x = +-375",
	"boundary_rails_south": "_perimeter() railings + colliders at z = 375",
	"bay_rails": "_perimeter() low bay railings at z = -348.5",
}

# ================================================================ queries
static func is_water(p: Vector3) -> bool:
	for key in ISLANDS:
		if (ISLANDS[key] as Rect2).has_point(Vector2(p.x, p.z)):
			return false
	for key in WATER:
		if (WATER[key] as Rect2).has_point(Vector2(p.x, p.z)):
			return true
	return false

static func in_playable(p: Vector3) -> bool:
	return PLAYABLE.has_point(Vector2(p.x, p.z))

static func is_land(p: Vector3) -> bool:
	return in_playable(p) and not is_water(p)

static func in_air_envelope(p: Vector3) -> bool:
	return AIR.has_point(Vector2(p.x, p.z)) and p.y <= AIR_CEILING

## Legacy marker/ground-navigation hint only; never a physics permission.
## A false value on an unmarked roof must not prevent a supported safe exit.
static func is_marked_landing_hint(p: Vector3) -> bool:
	if not is_land(p):
		return false
	for key in HELIPADS:
		var pad: Dictionary = HELIPADS[key]
		if pad["status"] == "reserved":
			continue
		var c: Vector3 = pad["pos"]
		if Vector2(p.x - c.x, p.z - c.z).length() <= float(pad.get("hint_radius", float(pad["radius"]) + 4.0)) and absf(p.y - c.y) < 3.0:
			return true
	return p.y <= GROUND_EXIT_MAX_Y

static func road_points(road_name: String) -> Array:
	return (ROADS.get(road_name, {}) as Dictionary).get("pts", [])

static func anchor(anchor_name: String) -> Vector3:
	return (ANCHORS.get(anchor_name, {}) as Dictionary).get("pos", Vector3.ZERO)

static func block_rect(block_name: String) -> Rect2:
	return (BLOCKS.get(block_name, {}) as Dictionary).get("rect", Rect2())

## Internal consistency of the plan itself. Returns a list of problems.
static func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var district: Rect2 = LEGACY["district"]
	# Roads: inside playable, never over water, sampled every 4 m.
	for key in ROADS:
		var pts: Array = ROADS[key]["pts"]
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var steps := maxi(1, int(a.distance_to(b) / 4.0))
			for s in steps + 1:
				var p := a.lerp(b, float(s) / steps)
				if not PLAYABLE.grow(1.0).has_point(Vector2(p.x, p.z)):
					problems.append("road %s leaves PLAYABLE at %s" % [key, p]); break
				if is_water(p):
					problems.append("road %s crosses water at %s (use a bridge)" % [key, p]); break
	# Bridges: both ends on land, mid-span over water.
	for key in BRIDGES:
		var a2: Vector3 = BRIDGES[key]["from"]
		var b2: Vector3 = BRIDGES[key]["to"]
		if is_water(a2) or is_water(b2):
			problems.append("bridge %s lands in water" % key)
		if not is_water(a2.lerp(b2, 0.5)):
			problems.append("bridge %s mid-span is not over water" % key)
		if float(BRIDGES[key]["soffit_y"]) <= WATER_LEVEL + 2.0:
			problems.append("bridge %s clearance under 2 m" % key)
	# Blocks: on land, inside playable, clear of road kerbs (+3 m), off the
	# existing district, not overlapping each other.
	var names := BLOCKS.keys()
	for i in names.size():
		var r: Rect2 = BLOCKS[names[i]]["rect"]
		if not PLAYABLE.encloses(r):
			problems.append("block %s outside PLAYABLE" % names[i])
		if r.intersects(district):
			problems.append("block %s overlaps the existing district" % names[i])
		for corner in [r.position, r.position + Vector2(r.size.x, 0.0), r.position + Vector2(0.0, r.size.y), r.end, r.get_center()]:
			if is_water(Vector3(corner.x, 0.0, corner.y)):
				problems.append("block %s has a corner in water" % names[i]); break
		for j in range(i + 1, names.size()):
			if r.intersects(BLOCKS[names[j]]["rect"]):
				problems.append("blocks %s and %s overlap" % [names[i], names[j]])
		for key in ROADS:
			var clear := float(ROADS[key]["width"]) * 0.5 + 3.0
			var pts2: Array = ROADS[key]["pts"]
			var hit := false
			for k in pts2.size() - 1:
				var a3: Vector3 = pts2[k]
				var b3: Vector3 = pts2[k + 1]
				var steps2 := maxi(1, int(a3.distance_to(b3) / 2.0))
				for s2 in steps2 + 1:
					var p2 := a3.lerp(b3, float(s2) / steps2)
					if r.grow(clear - 0.01).has_point(Vector2(p2.x, p2.z)):
						hit = true; break
				if hit: break
			if hit:
				problems.append("block %s is within the kerb clearance of %s" % [names[i], key])
	# Anchors: inside playable (scenery may sit outside), on land unless a bridge.
	for key in ANCHORS:
		var a4: Dictionary = ANCHORS[key]
		var p4: Vector3 = a4["pos"]
		if key in ["sheares_bridge", "helix_bridge"]:
			continue
		if not in_playable(p4):
			problems.append("anchor %s outside PLAYABLE" % key)
		elif is_water(p4):
			problems.append("anchor %s stands in water" % key)
	for key in HELIPADS:
		if not is_land(HELIPADS[key]["pos"]):
			problems.append("helipad %s not on land" % key)
	if not AIR.encloses(PLAYABLE):
		problems.append("AIR envelope must enclose PLAYABLE")
	return problems
