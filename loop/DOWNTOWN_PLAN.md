# DOWNTOWN PLAN: Marina Bay core (wave M)

Plan version **M-1 2026-10-23**. This document is the authoritative city plan behind the owner direction of
2026-10-23 ~04:45Z (loop/GOAL.md): the game is played in central Singapore around Marina Bay, and everything already
built is kept. Every number here also lives in `game/src/world/downtown/plan.gd` (`class_name DowntownPlan`).
**Pieces read numbers from plan.gd. They never hard-code them.** If the two ever disagree, plan.gd wins. Fix this
document in the same commit.

Real Marina Bay geography is the blueprint. All geometry is original. No Rockstar material and no copied models,
scans or map data are used. Real place and road names are public facts and are used for wayfinding.

---

## 1. Frame, compass and scale

The frame is the same metres frame as `world_builder.gd`, with y up. Ground and quay tops are at **+0.3**. The bay
water is one 16 km sea plane at **-0.9** (`BayWater.LEVEL`), and land slabs mask it. **To make water you leave out a
land slab. You do not add a water plane.**

The compass is real geography, rotated so that the bay lies "up" the minimap. It is **not mirrored**.

| Game axis | Real direction | What lies that way |
| --- | --- | --- |
| -z (minimap up) | East, toward the bay | Marina Bay Sands, Gardens by the Bay, the Marina Channel |
| +z | West, inland | The heritage district, then Chinatown and Tanjong Pagar (background) |
| -x | North | The Singapore River mouth, the Esplanade, Marina Centre, the Flyer |
| +x | South | Marina Bay Financial Centre, Shenton Way |

**Scale.** Landmark structures are true scale (1:1). Distances between places are compressed, because the near
promenade and Marina Bay Sands are fixed:

- The bay crossing (east to west) is about **0.45x**.
- North to south is about **0.65x**.

**Legacy finding.** The pre-wave-M far shore was a mirror image of reality. The Flyer and the ArtScience Museum sat
south (+x) of Marina Bay Sands, and the SkyPark cantilever pointed south. From the west shore, the real Flyer and the
real ArtScience Museum are on the left (north) of Marina Bay Sands, and the SkyPark cantilever points north. Wave M
corrects this (section 9). As a result, the iconic Fullerton/Merlion view reads like Singapore and not like its
mirror image.

## 2. What stays fixed (kept from before wave M)

- **The whole heritage district** keeps its layout, buildings and roads: `x,z in [-330,330]`, `X_LINES/Z_LINES` at
  -320, -160, 0, 160 and 320, and the 5 x 5 `traffic_nodes` grid. That covers the shophouses, the hawker centre, the
  HDB void decks, the safe room, the shop, the workshop, the aviation compound and the missions. The district is now
  the **Telok Ayer / Chinatown / Tanjong Pagar heritage belt** of one contiguous city. In reality those shophouse
  streets sit right beside Raffles Place, and Lau Pa Sat is a hawker centre in the CBD a few hundred metres from the
  bay.
- **The west shore promenade** stays at `PROMENADE_Z = -338` (z -349..-327, x -350..350), along with its near
  seawall, jetties, boats and the promenade helipad (0, -337).
- **The Merlion** stays on its existing pier at (64, 0.3, -371), with its tuned jet and the `merlion_jet_close` and
  `waterfront_promenade` views. See decision **O-1** in section 14.
- **The in-district Supertree Grove** stays at (-80, 0.16, -262). It belongs to the WORLD-03 opening composition.
- **Marina Bay Sands** stays at `MBS_POS = (-118, 0, -705)`, at true scale (GLB footprint 350 x 63 m, 208 m to the
  top of the SkyPark).
- **The player start** stays at (-171, 0.45, -22), yaw -8 deg, pitch -0.02. It looks down the x = -160 heritage
  avenue to Marina Bay Sands and the Grove (section 10).
- **The fixed capture cameras** in `photo_capture.gd` and `capture_director.gd` never move. Downtown views are added
  as new views only (`DowntownPlan.VIEWS`, section 7).

## 3. The map

The ASCII map below is a top view. Up is -z (east) and left is -x (north). Coordinates are game metres.

```
 z\x  -900      -790     -650 -590 -530 -470 -330        -118          60          350 400   560        760
-1060 +-------------------------+    |~~~~|------------- GARDENS BY THE BAY (Bay South) -----------+-----------+
      | MC far |  FLYER site    |    |~ch~|  Supertree Grove (-10,-905)   Flower Dome  Cloud Forest| MS 3/MBFC3|
 -780 |==RAFFLES AVE===BAYFRONT AVE N====[BAYFRONT BR]========== BAYFRONT AVENUE ==================+===========|
 -745 |        |  MC bay blocks ----[HELIX BRIDGE]---  MBS towers+SkyPark   | Bayfront Expo        |M| MBFC 3/2  |
 -660 | MC west| Promenade  NS Square |~lobe~|====== EVENT PLAZA =========|  The Lawn      ~~~~~~~|B| (towers   |
 -624 |        |ESPLANADE~|~~~~~~~~~~~ ASM ~~~~~~~~~ MARINA BAY BASIN ~~~~~~~~~~~~~~~~~~~~~~~~~~~|L| 200-245 m)|
      |        | theatres |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~|V| MBFC 1    |
 -400 |        | (-712)   |~~[JUBILEE]~ One Fullerton ~~~~~~~~~~~~ Merlion pier (64) ~~~~~~~~~~~~|D|           |
 -360 |==ESPLANADE DRIVE====[ESPLANADE BR]==Fullerton Rd                                             |           |
 -338 |        |   Esplanade| river|  peninsula|==== WEST SHORE PROMENADE (existing) ===============|M| waterfront|
 -320 |        |   Park     | mouth|Fullerton |== COLLYER QUAY (existing z=-320 road, extended) ==========+=======|
      | Padang |C           |~~~~~~|  Hotel   |CBD b1|                                         |  |Shenton W/E/F |
 -160 | civic  |O           |~~~~~~|BoatQuay|a2|Raffl.|        HERITAGE DISTRICT                |S | Robinson Rd  |
    0 |==NORTH BRIDGE RD====[ELGIN]==|row  |a3|Place |    (existing 5x5 grid, missions,        |H | Anson Rd     |
  160 |==COLEMAN ST=========[COLEMAN]|     |a4|b3 b4 |     aviation compound at (240,240))     |N | Maxwell Rd   |
  375 +--------------------------+~~~~~~+-----+--+------+-----------------------------------------+--+--------------+
              civic north bank    river  Boat Quay / CBD strip (Cecil St x=-430, Circular Rd x=-488)
```

| District | Rect (x min, z min, w, d) | Real counterpart |
| --- | --- | --- |
| heritage (existing) | (-336, -349, 672, 724) | Telok Ayer / Chinatown / Tanjong Pagar heritage belt |
| cbd_raffles | (-530, -349, 194, 724) | Raffles Place towers, Boat Quay, the Fullerton (south bank of the river) |
| fullerton_waterfront | (-530, -412, 90, 63) | One Fullerton and the Merlion Park site |
| civic_north_bank | (-900, -349, 310, 724) | Esplanade Park, the Padang and civic district, the Asian Civilisations Museum |
| esplanade_marina_centre | (-900, -660, 260, 311) | Esplanade - Theatres on the Bay and its waterfront |
| marina_centre | (-900, -1060, 430, 400) | Flyer, the Promenade, malls and hotels |
| bayfront | (-330, -1060, 680, 436) | Marina Bay Sands, Event Plaza, ArtScience, Gardens by the Bay |
| marina_south | (350, -1060, 410, 711) | Marina Bay Financial Centre (MBFC), Marina Boulevard |
| shenton | (336, -349, 424, 724) | Shenton Way and Anson Road offices |

## 4. Bay outline and shorelines

Water is any point inside a `WATER` rect that is not inside an `ISLANDS` rect (`DowntownPlan.is_water()`).

| Water | Rect | Notes |
| --- | --- | --- |
| basin | (-640, -624, 990, 275) | x -640..350, z -624..-349. The west shore is the existing seawall at z -349.9. The east shore is the existing far seawall at z -624. |
| basin_ne_lobe | (-640, -660, 310, 36) | The bay in front of the Promenade and NS Square, leading into the channel. |
| east_channel | (-470, -1100, 140, 440) | Runs between Marina Centre and the Bayfront, under the Helix and Bayfront bridges, toward the Marina Channel and Barrage (scenery beyond z -1060). |
| singapore_river | (-590, -349, 60, 1100) | 60 m wide. It runs inland (+z) past Boat Quay and leaves through the z = 375 edge as scenery. |

| Island (land inside water) | Rect | Use |
| --- | --- | --- |
| fullerton_peninsula | (-530, -412, 90, 63) | One Fullerton, the Merlion Park site, the Esplanade and Jubilee bridge landings |
| artscience_promontory | (-322, -626, 64, 56) | The ArtScience lotus and lily pond at the Bayfront tip |
| ns_square_float | (-640, -660, 120, 83) | The former Float@Marina Bay (real 120 x 83 m), now NS Square. It doubles as a helipad. |
| merlion_pier | (57, -375.5, 14, 27) | The existing pier |

Shoreline construction is owned by downtown-map:

- **Seawall.** Granite coping at +0.3, 1.2 m wide, with a dark wet band down to the water. This matches the existing
  near seawall in `bay.gd`.
- **Railings.** Every waterfront walk gets a railing, 1.1-1.35 m high with collision. The rails leave deliberate gaps
  only at stairs and jetties.
- **River walls.** The river walls are lower, with the coping at +0.3 and a step-down landing every 120 m.
- **Uniform land.** Every land rect has a single ground slab with collision (`BoxShape3D`, top at +0.0..+0.3), and
  there are no cracks where the old district slab ends.

## 5. Roads (all driveable, left-hand)

Left-hand traffic is the existing rule: the lane centre sits on the LEFT of the travel direction. On roads with
`lanes = n` per direction, lane i is centred `(i + 0.5) * 3.5 m` left of the centreline. A median adds half its width.

Kerbs are 16 cm. Footways are at least 3 m, with double yellow lines and white bays (the same vocabulary as
`_kerb_markings`). Junctions where two arterials meet have signals. Street names follow the real names.

| Road | Polyline (x,z) | Width | Lanes/dir | Kind |
| --- | --- | --- | --- | --- |
| collyer_quay | (400,-320) to (-470,-320). x -320..320 is the EXISTING road; downtown-map only extends it. | 16 | 1 | arterial |
| fullerton_road | (-470,-320), (-500,-332), (-520,-350), (-530,-360) | 16 | 1 | arterial |
| esplanade_drive | (-650,-360), (-790,-360), (-900,-360) | 20 | 2 | arterial |
| raffles_avenue | (-790,-360), (-790,-780), (-790,-1000) | 20 | 2 | arterial |
| bayfront_avenue_north | (-790,-780) to (-480,-780) | 24 + 3 median | 3 | arterial |
| bayfront_avenue | (-320,-780) to (400,-780) | 24 + 3 median | 3 | arterial |
| marina_boulevard | (400,-780) to (400,-320) | 20 | 2 | arterial |
| shenton_way | (400,-320) to (400,375) | 20 | 2 | arterial |
| central_boulevard | (560,-780) to (560,375) | 16 | 1 | street |
| marina_way | (400,-480) to (760,-480) | 16 | 1 | street |
| marina_view | (400,-640) to (760,-640) | 14 | 1 | street |
| cecil_street | (-430,-320) to (-430,375) | 14 | 1 | street |
| circular_road | (-488,-200) to (-488,375), one-way service lane behind Boat Quay | 7 | 1 | lane |
| chulia_street | (-320,-160) to (-488,-160) | 14 | 1 | street |
| market_street | (-320,0) to (-525,0), then Elgin Bridge | 16 | 1 | street |
| cross_street | (-320,160) to (-525,160), then Coleman Bridge | 16 | 1 | street |
| south_bridge_road | (-320,320) to (-488,320) | 14 | 1 | street |
| north_bridge_road | (-595,0) to (-900,0) | 16 | 1 | street |
| coleman_street | (-595,160) to (-900,160) | 16 | 1 | street |
| connaught_drive | (-660,-360) to (-660,0) | 14 | 1 | street |
| robinson_road / anson_road / maxwell_road / keppel_link | the z = -160 / 0 / 160 / 320 lines, from x 320 to 760 | 16 | 1 | street |

**Loops (WORLD-04).**

1. **The existing heritage grid**, unchanged.
2. **The Marina Bay loop**, about 2.8 km: Collyer Quay, Fullerton Rd, Esplanade Bridge, Esplanade Dr, Raffles Ave,
   Bayfront Ave N, Bayfront Bridge, Bayfront Ave, Marina Blvd and back to Collyer Quay (`BAY_LOOP`).
3. **The CBD / river loop**: Collyer Quay, Cecil St, Market St, Elgin Bridge, North Bridge Rd, Connaught Dr, Esplanade
   Dr, Esplanade Bridge, Fullerton Rd (`CBD_LOOP`).
4. **The Shenton loop**: Shenton Way, the four district z-lines and Central Blvd. These give alternative routes from
   the district to MBFC and the Bayfront.

**Lane graph.** `world.traffic_nodes` stays the legacy 5 x 5 grid, because tests, `drive_showcase` and
`capture_director` index it as `row * 5 + col`. downtown-map publishes the new roads in `world.downtown_graph`:

```
{
  "nodes": Array[Vector3],    # junction and bend nodes
  "edges": Array[Vector2i],   # undirected node pairs
  "lanes": Array[int],        # lanes per direction, one entry per edge
  "links": Array[Vector2i],   # downtown node -> legacy traffic_nodes index, e.g. the four z-line junctions at x = +-320
  "parked": Array[Dictionary] # kerbside parking spots on the new roads
}
```

It also publishes pedestrian polylines in `world.downtown_ped_lanes`. street-life adopts both when they are not
empty. downtown-map never appends to `traffic_nodes`, `ped_lanes` or `parked_spots`.

## 6. Bridges

The water is at -0.9. Ramps never exceed `max_grade`. Bridge decks have collision on the walk and drive surface, and
bridge piers have collision.

| Bridge | From to (x,z) | Width | Deck y / soffit y | Clearance over water | Kind | Owner | Real reference |
| --- | --- | --- | --- | --- | --- | --- | --- |
| esplanade_bridge | (-530,-360) to (-650,-360), 120 m over water plus approaches | 24 | 3.6 / 2.6 | 3.5 m | vehicle, 2+2 | map | 260 m low multi-arch bridge across the river mouth |
| bayfront_bridge | (-480,-780) to (-320,-780) | 28 | 3.6 / 2.4 | 3.3 m | vehicle, 3+3 | map | Bayfront Avenue bridge |
| helix_bridge | (-490,-745) to (-270,-745), curved | 6 walk (tube about 11) | 3.6 / 2.4 | 3.3 m; tubes up to about 14 m above the deck | pedestrian | **landmarks** | 280 m double-helix footbridge (220 m here) |
| jubilee_bridge | (-530,-400) to (-650,-400) | 6 | 2.6 / 1.8 | 2.7 m | pedestrian | map | 220 m footbridge, Merlion Park to the Esplanade |
| cavenagh_bridge | (-530,-208) to (-595,-208) | 6 | 2.4 / 1.8 | 2.7 m | pedestrian | map | 1869 suspension footbridge beside the Fullerton |
| elgin_bridge | (-525,0) to (-595,0) | 16 | 2.6 / 1.8 | 2.7 m | vehicle | map | low arch road bridge |
| coleman_bridge | (-525,160) to (-595,160) | 16 | 2.6 / 1.8 | 2.7 m | vehicle | map | low arch road bridge |
| sheares_bridge | scenery at z about -1120, x -1000..300, deck +29 | 30 | 29 / 26 | n/a | air-only collision | map | elevated expressway on the eastern horizon |

Boats from `bay.gd` must not cross a bridge whose soffit is under 3 m. They keep to the basin, which is the case
today. downtown-map checks the boat routes and adjusts them only if a route meets a pier.

## 7. Promenades, plazas, parks and views

| Walk | Polyline | Width | Notes |
| --- | --- | --- | --- |
| west_shore_promenade | (-440,-338) to (350,-338) | 22 | Existing from x -350 to 350; extended to the peninsula |
| fullerton_peninsula_walk | (-440,-380), (-528,-380), (-528,-340) | 10 | Merlion Park site, One Fullerton frontage |
| boat_quay_river_walk | x -525, z -215..375 | 10 | Al fresco dining edge under the shophouse awnings |
| north_bank_river_walk | x -595, z -345..375 | 10 | Asian Civilisations Museum and Esplanade Park side |
| esplanade_waterfront | x -647, z -372..-666 | 14 | Outdoor theatre steps |
| marina_promenade | (-648,-666), (-476,-666), (-476,-790) | 12 | Along NS Square to the Helix landing |
| bayfront_event_plaza | (-324,-642) to (350,-642) | 36 | Event Plaza steps in front of the Shoppes |
| mbfc_waterfront | x 368, z -640..-338 | 36 | Marina Bay Link frontage |
| channel_south_walk | x -324, z -642..-1060 | 12 | Gardens edge |

**Walking loop** (about 2.6 km, `WALK_LOOP`): promenade, Fullerton peninsula, Jubilee Bridge, Esplanade waterfront,
Marina Promenade, Helix Bridge, Event Plaza, MBFC waterfront, and back to the promenade.

**Plazas and parks**: raffles_place_plaza, esplanade_park, the_lawn, gardens_site and NS Square (see `BLOCKS` and
`ISLANDS`).

**Proposed downtown views** (`DowntownPlan.VIEWS`, added only): dt_merlion_park_to_mbs, dt_event_plaza_to_cbd,
dt_helix_walk, dt_bayfront_drive, dt_boat_quay_from_north_bank, dt_raffles_place, dt_cecil_street_canyon,
dt_esplanade_waterfront, dt_gardens_to_mbs, dt_mbfc_waterfront_to_mbs and dt_aerial_marina_bay. downtown-map adds
them to `photo_capture.gd` with one guarded loop placed after the existing views.

## 8. Block footprints (downtown-blocks unless marked)

Every rect keeps at least 3 m of pavement clear of every road kerb. `DowntownPlan.validate()` enforces this, together
with "no block in water" and "no block overlapping another block or the heritage district".

| Block | Rect (x,z,w,d) | Kind | Max h | Frontage |
| --- | --- | --- | --- | --- |
| fullerton_site | (-525,-309,85,94) | landmark site (landmarks) | 40 | river, Collyer Quay |
| boat_quay_1, _2, _3 | x -520..-502; z -200..-11, 11..149, 171..375 | boat_quay_row: 2-3 storey shophouses with river awnings; CBD towers loom behind | 14 | -x (river) |
| cbd_a2, a3, a4 | x -481..-440; z -150..-11, 11..149, 171..310 | cbd_tower | 280 / 245 / 200 | -x |
| cbd_b1, b3, b4 | x -420..-334; z -309..-170, 11..149, 171..310 | cbd_tower | 280 / 280 / 200 | Collyer Quay / Cecil St |
| raffles_place_plaza | (-420,-150,86,139) | plaza with MRT entrances, ringed by towers | 6 | all |
| cbd_b5 | (-420,331,86,44) | mid_rise | 80 | -z |
| civic_padang | (-900,-347,230,336) | civic (low colonial blocks and the green) | 40 | Connaught Dr, Esplanade Dr |
| esplanade_park | (-650,-347,50,336) | park | 12 | river walk |
| civic_museum / civic_upriver | x -900..-610; z 11..149 / 171..375 | civic / mid_rise | 35 / 90 | river |
| esplanade_site | (-775,-630,120,257) | landmark site (landmarks) | 45 | waterfront |
| marina_centre_west / _bay / _far | (-900,-765,97,392) / (-777,-765,282,93) / (-900,-1000,97,205) | malls and hotels on podiums | 180 / 160 / 120 | Raffles Ave, the Promenade |
| flyer_site | (-777,-1000,282,205) | landmark site (landmarks) | 170 | Raffles Ave |
| mbs_site | (-330,-765,390,105) | landmark site (landmarks) | 210 | Event Plaza, Bayfront Ave |
| the_lawn | (60,-700,290,74) | park | 6 | bay |
| bayfront_expo | (60,-765,327,60) | podium (convention halls) | 40 | Bayfront Ave |
| gardens_site | (-330,-1060,717,265) | landmark site (landmarks) | 60 | Bayfront Ave |
| mbfc_1, _2, _3 | x 413..549; z -469..-331, -629..-491, -765..-650 | mbfc_tower, 200-245 m, with podium and link mall | 245 | Marina Blvd |
| marina_south_1, _2, _3 | x 571..760, same rows | cbd_tower / mid_rise | 220 / 200 / 120 | Central Blvd |
| shenton_w1..w4 | x 331..387; rows z -309..-171, -149..-11, 11..149, 171..309 | mid_rise | 90 | Shenton Way |
| shenton_e1..e4 / f1..f4 | x 413..549 / 571..760, same rows | towers / residential | 240..120 / 140 | Shenton Way / Central Blvd |

**Street-frontage rule (all blocks).**

- Ground floors carry shopfronts, lobbies, canopies, five-foot-way arcades on the heritage-facing sides, and
  English-first signage.
- No blank walls longer than 25 m face a road.
- Unavailable doors are shown as closed (WORLD-05).
- Every massing volume has a box collider.

## 9. Landmark anchors (true scale)

| Anchor | Game pos (x,y,z) | Size (x / h / z) | Status | Real facts used |
| --- | --- | --- | --- | --- |
| marina_bay_sands | (-118, 0, -705) | 350 / 208 / 63 | existing; **mirror so the SkyPark cantilever points north (-x)**. The podium stays on the bay side (+z). | 3 towers, 55 storeys, about 194 m. SkyPark about 340 m long, cantilever about 67 m. |
| mbs_event_plaza | (-118, 0.3, -642) | 400 / - / 36 | new | Event Plaza steps |
| artscience_museum | (-290, 0.3, -598) | 80 / 60 / 80 | **move** from (80,0,-640) | lotus with 10 petals, about 60 m tall, lily pond |
| singapore_flyer | (-650, 0, -880), wheel yaw about -35 deg | 150 / 165 / 30 | **move** from (210,0,-700) | 165 m overall, 150 m wheel, 28 capsules, terminal |
| helix_bridge | (-380, 3.6, -745) | 220 / 14 / 12 | new | double-helix footbridge |
| esplanade_concert_hall | (-712, 0.3, -455) | 70 / 40 / 95 | new | spiky sunshade dome (approximate size; verify against photos) |
| esplanade_theatre | (-712, 0.3, -575) | 75 / 45 / 100 | new | second dome, outdoor theatre on the bay |
| merlion | (64, 0.3, -371) | 11 / 10.8 / 11 | existing, kept (O-1) | 8.6 m statue |
| merlion_park_true | (-470, 0.3, -405) | 60 / - / 30 | reserved (O-1) | geographic Merlion Park |
| fullerton_hotel | (-485, 0.3, -257) | 80 / 35 / 85 | new | granite neoclassical block, Doric colonnade |
| one_fullerton | (-488, 0.3, -392) | 75 / 12 / 34 | new | low waterfront dining pavilions |
| supertree_grove_district | (-80, 0.16, -262) | 61 / 44 / 40 | existing, kept | opening composition |
| gardens_supertree_grove | (-10, 0, -905) | 180 / 50 / 140 | new | 12 supertrees 25-50 m; OCBC Skyway about 128 m at about 22 m |
| flower_dome | (230, 0, -875) | 170 / 38 / 90 | new | about 1.2 ha glass conservatory |
| cloud_forest | (240, 0, -985) | 110 / 58 / 80 | new | taller dome around an indoor mountain |
| ns_square | (-580, 0.3, -618) | 120 / - / 83 | new (map) | the former Float, 120 x 83 m |
| raffles_place | (-377, 0.16, -80) | 86 / - / 139 | new (blocks) | plaza ringed by 280 m towers |
| boat_quay | (-511, 0, 90) | 18 / 14 / 560 | new (blocks) | shophouse row on the river |
| mbfc | (481, 0, -480) | 136 / 245 / 300 | new (blocks) | MBFC towers 200-245 m |
| sheares_bridge | (-350, 29, -1120) | 1300 / 4 / 30 | new (map, scenery) | elevated expressway |

**Reachability.** Landmarks are reachable at street level and have collision on all walkable surfaces:

- Marina Bay Sands: Event Plaza, the Shoppes arcade frontage and the tower bases (boxes).
- The SkyPark deck: collision so the helicopter can land, plus an optional lift to the Shoppes lobby. Without the
  lift, the SkyPark pad stays `reserved`.
- ArtScience: the pond edge and the petals (boxes).
- The Helix deck.
- The Flyer terminal and a capsule boarding deck.
- The Esplanade outdoor theatre steps.
- The Fullerton colonnade.
- Gardens paths, the Skyway (optional), and the dome entrances, which show as closed if the domes are not enterable.

Collision for the helicopter covers every tall mass: towers, the SkyPark, the Flyer rim (as a box ring) and the
Supertree trunks. The crowns stay open, as in the existing grove.

**Opening and sightline guard.**

- **Before and after the move:** the landmarks piece runs `--sightline-probe` before and after moving ArtScience and
  the Flyer and mirroring MBS.
- **The opening view** must keep all three towers and the SkyPark readable. The existing `self_test` landmark
  footprint test and the photo_06 Flyer test still pass at the new positions: the Flyer at (-650,-880) lies about 5
  deg off the photo_06 axis.
- **The MBS rect** in `_skyline_checks` may be updated for the mirrored footprint, but never weakened.

## 10. Bounds, boundaries, helicopter and start

**Playable ground.** `PLAYABLE = Rect2(-900, -1060, 1660, 1435)`, i.e. x -900..760 and z -1060..375. It is about
2.4 km2, of which about 1.6 km2 is land. Background scenery (procedural `SkylineCity` and `SkylineHorizon`) lies
beyond PLAYABLE only. Inside PLAYABLE, downtown land is cleared of procedural towers through the `skyline_clear` hook,
as soon as a piece builds that land.

**Edges** (downtown-map). Each edge has a physical barrier at least 2.4 m high with collision:

| Edge | Treatment |
| --- | --- |
| x = -900 | construction hoarding and railings at Stamford Rd / Bras Basah |
| x = 760 | Tanjong Pagar construction hoarding |
| z = 375 | the existing `boundary_railing` line, extended across the CBD, civic and Shenton strips; the river leaves under a gated weir rail |
| z = -1060 | the Gardens perimeter fence and the Marina Channel rail |

Roads that reach an edge end at a barrier with a turning head. Nothing reachable is a painted backdrop.

**Air.** `AIR = Rect2(-1300, -1400, 2450, 2220)` and `AIR_CEILING = 420`. The tallest structures are the 280 m CBD
towers. downtown-map replaces `helicopter.gd`'s symmetric `AIR_LIMIT_*` with `DowntownPlan.in_air_envelope()` and
keeps the current turn-back behaviour.

**Helicopter exit rule** (replaces the old `|x| > 395 or z < -365 or z > 405` check in `exit_vehicle`). The pilot may
exit when the helicopter is landed (`is_on_floor`, speed below 2) and `DowntownPlan.heli_exit_allowed(pos)` is true:

- the position is on playable land, meaning inside PLAYABLE and not water (islands, including the Merlion pier,
  count as land), and
- the position is at street, plaza or bridge-deck level (`y <= 4.5`), **or** within (radius + 4 m) of a non-reserved
  pad in `HELIPADS`.

Rooftops are refused with "Land at street level or on a helipad to exit." The existing downed-aircraft recovery to
the last safe point stays. The new pads are ns_square (-580,-618), the_lawn (205,-662), esplanade_park (-625,-250)
and gardens_east (345,-1030). The `skypark` pad is reserved until a lift exists. The `_waterfront_exit_check`
fixture at (0.4, -329.6) stays valid, because it is on land at ground level.

**Player start.** The start is unchanged: (-171, 0.45, -22), yaw -8 deg, looking down the heritage avenue to Marina
Bay Sands and the district Grove. That composition passed WORLD-03 and is kept as is.

The first minute of play now leads naturally downtown:

1. Walk down the x = -160 avenue to the promenade.
2. Turn left along the promenade to the Fullerton peninsula.
3. Take the Jubilee or Esplanade Bridge to the Esplanade.

Missions are not moved this wave.

## 11. Performance plan

The machine is the Mac Studio. Measure with `--perf-probe` and the rendered `--photos` before and after every piece
merge. Each piece reports its numbers.

**Visibility ranges.** Use `GeometryInstance3D.visibility_range_*` with self fade and a 30 m hysteresis:

| Content | Visible to |
| --- | --- |
| facade detail, signage, railings, street furniture | 250 m |
| simplified tower shells, shophouse rows | 900 m |
| landmark shells and tower massing | no end (they are the skyline) |

**Shadows.** Shadow casting is off for anything detailed beyond 600 m, and for every small prop. Landmarks and tower
masses do cast shadows.

**Batching.**

- Use MultiMesh for every repeated element: shophouse bay modules, window mullions (preferably the curtain-wall shader
  instead of per-floor boxes), lamps, trees, bollards, railings, Flyer capsules, Supertree panels and Esplanade
  sunshades.
- Use one material set per piece, through the existing `LandmarkLooks` / `Palette` style. Road surfaces are one
  ArrayMesh per material per piece. Markings use the `_marking_batch` MultiMesh approach.
- Plain `_box()` primitives under `_world_root` are already merged by `_batch_static_primitives()`.

**Collision budget.** Each piece puts its shapes in one StaticBody3D on layer 1.

| Piece | BoxShape3D budget |
| --- | --- |
| map | 700 |
| landmarks | 300 |
| blocks | 600 |

At most 6 trimesh shapes in total (Helix deck, SkyPark deck, if needed). No per-prop bodies.

**Other budgets.**

- At most 1,200 extra draw calls in the busiest downtown view.
- At most 48 new omni or spot lights; use emissive windows instead.
- At most 4 s extra headless build time.
- At most 10 % frame-time regression in any existing fixed view.

**Water.** No new water meshes. Land slabs define every shoreline.

**Crowds and traffic** (street-life). Use the WORLD-07 near-player budgets (24-40 pedestrians, 8-12 moving cars in
the busiest view), cell-based spawning (about 250 m cells around the player and camera), off-camera despawn beyond
300 m, and no simulation in far cells.

## 12. Integration hooks (already in `world_builder.gd`)

`WorldBuilder.build()` loads every script in `DowntownPlan.PIECE_SCRIPTS` that exists. An absent piece costs nothing,
so each piece can land independently. These are `res://src/world/downtown/map.gd`, `landmarks.gd` and `blocks.gd`.

Contract for each piece entry script:

```gdscript
extends RefCounted
func replaces() -> PackedStringArray: return ["far_shore_ground"]   # optional, DowntownPlan.LEGACY_KEYS
func skyline_clear(world: WorldBuilder, city: SkylineCity) -> void   # optional: city.clear_zone(rect, max_h)
func build(world: WorldBuilder, root: Node3D) -> void                # after _far_shore_landmarks()
func build_lanes(world: WorldBuilder) -> void                        # optional, after _build_lane_graph()
func finish(world: WorldBuilder) -> void                             # optional, after static batching
```

- **Pieces may call WorldBuilder's helpers.** These are `_box`, `_solid_box`, `_collision_box`, `_authored`,
  `_helipad`, `_tree`, `_street_lamp` and `_reserve`. Pieces may also read and write `world.locations`,
  `world.downtown_graph` and `world.downtown_ped_lanes`. Pieces never edit `world_builder.gd`.
- **Legacy keys.** A piece that takes over a legacy section lists its key in `replaces()`, and WorldBuilder then
  skips that section. The keys are `district_ground`, `far_shore_ground`, `far_shore_landmarks`,
  `boundary_rails_x`, `boundary_rails_south` and `bay_rails`.
- **The far_shore_landmarks contract.** A piece that replaces `far_shore_landmarks` must set
  `locations["marina_bay_sands"]`, `["artscience_museum"]` and `["singapore_flyer"]`.
- **Tests.** The self-test runs `_downtown_plan_checks()`. This check asserts `DowntownPlan.validate()` is empty and
  that the plan's copies of PLAYER_START, MBS_POS, GROVE_POS and PROMENADE_Z still match WorldBuilder. It then runs
  each existing `res://src/systems/downtown_tests/<piece>_test.gd`: `extends RefCounted`, with
  `func run(world, suite)` calling `suite._check(name, ok, detail)`.

## 13. File ownership (four parallel pieces)

| Piece | Creates and owns | May edit (only these parts) | Replaces (legacy keys) | Must deliver |
| --- | --- | --- | --- | --- |
| **downtown-map** | `game/src/world/downtown/map.gd`, `roads.gd`, `shoreline.gd`, `bridges.gd`, `bounds.gd`, `minimap.gd`; `game/src/systems/downtown_tests/map_test.gd` | `helicopter.gd`: the `AIR_LIMIT_*` envelope block and the bounds check in `exit_vehicle()` only. `hud.gd`: the `_draw_minimap()` body only. `bay.gd`: boat routes only, if they meet piers. `photo_capture.gd`: one appended guarded loop over `DowntownPlan.VIEWS`. | `district_ground`, `far_shore_ground`, `boundary_rails_x`; `bay_rails` only if it rebuilds them | ground for every land rect and island; seawalls, quays and rails; every road in section 5 with kerbs, markings and signals; bridges except Helix; promenade paving; edge barriers; `downtown_graph` and `downtown_ped_lanes`; NS Square and the new helipads; minimap downtown layer; the helicopter envelope and exit rule; Sheares Bridge scenery |
| **downtown-landmarks** | `game/src/world/downtown/landmarks.gd`, `game/src/world/downtown/landmarks/*.gd`; new `game/assets/authored/{esplanade_theatres,helix_bridge,fullerton_hotel,one_fullerton,gardens_supertrees,flower_dome,cloud_forest}.glb` and their `art/source/*.blend`; `downtown_tests/landmarks_test.gd` | `game/tools/build_landmarks.py`: new builders, plus the MBS mirror and SkyPark deck. `landmark_looks.gd`: new material keys only. `landmarks_manifest.json`: own rows. `marina_bay_sands.glb`, `artscience_museum.glb`, `singapore_flyer.glb`. `self_test.gd`: `_skyline_checks` numbers for the moved and mirrored footprints only. | `far_shore_landmarks` | full-scale reachable landmarks of section 9 with collision; ArtScience and Flyer moves; MBS mirror; Helix Bridge, structure plus walkable deck; Gardens; Esplanade; Fullerton and One Fullerton; the locations keys; a sightline-probe before/after |
| **downtown-blocks** | `game/src/world/downtown/blocks.gd`, `game/src/world/downtown/block_kits/*.gd`, `game/src/world/downtown/block_looks.gd`, optional `game/assets/authored/dt_*.glb`; `downtown_tests/blocks_test.gd` | none outside its own files; RoofKit, Palette and LandmarkLooks are used read-only | none; it uses `skyline_clear` | every `BLOCKS` entry not owned by landmarks: CBD and MBFC towers (varied crowns, setbacks and facades; no two adjacent towers sharing a model), the Boat Quay row, civic and Marina Centre podium blocks, Shenton strip; street frontage rule; collision boxes |
| **street-life** | `game/src/systems/crowd*.gd` (new), `downtown_tests/street_life_test.gd` | `traffic_manager.gd`, `npc.gd`, the AI and spawn parts of `car.gd` | none | traffic and crowd reliability and density in the existing district first (the parked fix branches), then adopting `world.downtown_graph` and `downtown_ped_lanes` when present: merged graph internally, the legacy 5 x 5 `nodes` indexing kept for existing callers, density per section 11 |

**Shared and append-only.**

- `docs/asset-manifest.csv` and `docs/ASSET_RIGHTS.md`: each piece appends its own rows for every new or changed
  asset. The integrator resolves conflicts.
- `loop/PIECES.md`, `loop/RUN.md` and `progress/`: the orchestrator.

**Planner-owned.** `plan.gd`, this document, the hook block in `world_builder.gd` and `_downtown_plan_checks()` in
`self_test.gd` belong to the planner. Changes go through a plan amendment (section 14).

**Never touched by any piece**: the fixed cameras in `photo_capture.gd` and `capture_director.gd`, the heritage
district builders in `world_builder.gd`, `mission.gd` routes and `main` branch.

**Merge order.**

1. **downtown-map** lands first. It owns the ground everything stands on.
2. **downtown-landmarks and downtown-blocks** merge in either order. Until map has landed, they develop against the
   plan rects. Their Esplanade, Marina Centre and MBFC footprints only stand on solid ground once the map has merged.
3. **street-life** adopts the graph last.

Every merge re-runs headless `--import`, the full `--test` suite and headless `--capture` (13/13), then a rendered
`--photos` pass through `loop/render.sh`.

## 14. Decisions, deviations and amendments

- **O-1 (owner or orchestrator decision): the Merlion.** It is kept at the existing pier (64,-371) in M-1, to preserve
  the tuned jet, the fixed comparison views and "keep what was made". Geographically, the Merlion belongs at the
  river mouth (`merlion_park_true` (-470,-405)). Moving it is a single landmarks-piece change and needs sign-off.
- **D1 compression.** Distances are compressed (east-west 0.45x, north-south 0.65x). Structures are 1:1. The basin is
  990 x 275 m, against a real basin of roughly 650 x 600 m.
- **D2 mirror fix.** The legacy far shore was mirrored. M-1 moves ArtScience and the Flyer north and mirrors MBS's
  cantilever north.
- **D3 two groves.** The district Grove stays for the opening. The geographic Gardens by the Bay grove is added behind
  MBS.
- **D4 CBD order.** The real Raffles Place sits where the heritage district now is. The CBD towers occupy the 194 m
  strip between the heritage district and the river, so Boat Quay keeps its real image (shophouses on the river with
  towers behind).
- **D5 omissions.** Anderson Bridge is omitted. The Helix is 220 m against the real 280 m. The Esplanade dome sizes
  are approximate and should be checked against reference photos.

| Version | Date (UTC) | Change |
| --- | --- | --- |
| M-1 | 2026-10-23 | Initial plan (wave M planner). |
| S-1 | 2026-10-23 | downtown-polish: `marina_centre_bay` starts at x -765 (was -777): a 12 m corner plaza at the Raffles Avenue / Bayfront Avenue North right turn. |

## Astra-6 public-access amendment — 2026-10-25

The owner requested continuous heritage-to-central-Singapore gameplay with fewer cars. `PLAN_VERSION` is now `Astra-6 R1 2026-10-25`.

- `PEDESTRIAN_JOINS.jubilee_fullerton` joins the bridge-side measured floor at (-534, 0.212, -400) to the Fullerton peninsula floor at (-528, 0.36, -400), width 5.4 m. The same pitched body carries the visible surface and collision. This fixes the reverse-walking lip; it does not change the bridge profile or water layout.
- MBS north promenade now has a visible/collision ramp at z=-632 from x=-322/y0.10 to x=-316.8/y0.36, eliminating the access lip discovered by the physical courier route.
- MBS SkyPark public access is a limited collision-enclosed terrace connected to the Shoppes by labelled E lift interactions. `HELIPADS.skypark` is now a small game landing area at (-63,200,-698), with a stricter 2.5 m exit radius, only together with the installed return-lift module. Other rooftop areas remain restricted. This is a game adaptation, not a claim about real-world helicopter access.
- `PEDESTRIAN_JOINS.fullerton_heritage` joins the flat Fullerton-side walk (x=-445/y0.02) onto the raised heritage extension (x=-438/y0.30) at z=-338, width8m. The normal return walk exposed this one-way drop/vertical lip after crossing Jubilee; no bridge or existing promenade is removed.
