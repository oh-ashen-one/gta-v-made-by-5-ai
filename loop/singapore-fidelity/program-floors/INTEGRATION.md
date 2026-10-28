# Program-floor factory — component handoff, runtime pending

The builder owns only the new `program_floor.gd`, new dedicated test/scene and this folder. No engine, GPU, UI, Git, account operation, provider job, download, upload or purchase was run by the builder. Root owns compile, physical/rendered verification, independent critique, site assembly and publication. This component does not complete the whole-building goal.

## API and inherited interfaces

Preload `res://src/world/mbs_interior/program_floor.gd` and call **`ProgramFloor.program_plan(record)`**, then `module.build(record)`. The inherited **GuestFloor `plan(record)` still means guest-room planning** and must not be used for program records. This deliberate separate static planner avoids changing the guest factory or its callers.

`build()` accepts an actual `factory: program_module` record. It creates colliding program rooms, fixtures, a real full-height native E door for each room, shared corridors and fixed core geometry. It returns `report()` with per-space coverage, objects, doors, portals and explicit reconstructed/as-built/runtime limits. `floor_record` is a deep copy; source facts/status are retained. Placement is local uncompressed X=south/Z=west/Y=up; the module never repositions an actor or chooses world placement.

GuestFloor's production SwingDoor, normal E/LOS adapter, physical hinge motion, `request_interaction`, `set_door_open`, `confirm_transition_ready`, `transition_requested`, `door_state_changed`, `serialize_state`, `restore_state`, `closest_interaction`, `public_route_local`, `_build_core_approaches`, `_build_stair`, `_build_service_closet` and `_build_lift_landing` are reused. Their current signatures/IDs and exact core axes remain intact. Source dependency is intentional: keep later guest fixes compatible.

Native lift doors remain interlocked until the root confirms a real cabin, matching loaded destination and collision. The module only emits requests; it never transports an actor, inserts a fake shaft floor or claims that a cabin exists. JSON door state is floor-scoped and excludes transition doors, so reload cannot revive an old cabin-ready condition.

Terminal hotel L57 and top listed resort levels receive the floor below rather than inventing another storey. `record.has_upper_floor` may explicitly override this boolean. Normal levels emit the exact inherited U flight; terminal stair portals include `receiving_only: true`, a landing and no fabricated outgoing walk route. Root must load the actual lower neighbour to provide the incoming stair. Root must align `geometry.storey_height_m` to the actual adjacent elevation difference: inventory hotel basements currently carry 3.45 m geometry while some connection heights differ. No relabeling that discrepancy as verified geometry.

## Full program coverage, not full runtime proof

The current inventory contains **30 hotel program records + 27 resort records**. Offline arithmetic covers all **57**, planning **323 furnished program rooms and 3,976 fit-out objects across the complete inventory**, not all loaded at once. Core/circulation programs are mapped to actual shared corridor/core elements. Every non-core named space gets a concrete furnished recipe; unknown IDs/programs, duplicate spaces, missing fields, invalid dimensions, excessive counts and unsupported fit are rejected before child/state construction. There is no permanent empty-room fallback.

Recipes include laundry/linen, engineering stores, staff changing/pantry, parking/loading, tanks/electrical plant, concierge/check-in, restaurants/private dining/tea/bar, kitchens, toilets with actual native-door cubicles, spa treatment/relaxation/wet rooms, planted gardens, roof deck/observation, recessed pool segments, retail displays/counters, exhibition booths/meeting rooms, gym/studio equipment, gaming tables/machine banks, theatre seats/stage/backstage and museum galleries. These are coherent reconstructed forms, not copies of a branded fit-out or a current private plan. Gaming machines are static furniture, not gambling gameplay. Static parked sedans are dressing, not drivable vehicle actors. No new character or whole-motion animation was authored.

`STATIC_PLAN_COVERAGE.json` and `audit_plans.py` record reproducible **Python source/inventory arithmetic only**. No result here is a Godot compile, physics, rendered quality, human play or performance pass. The report always leaves full-building, private-as-built and all-program-runtime flags false.

## Geometry and circulation contract

Every hotel record uses its complete inventory geometry. Resort records lack geometry; raw records therefore use explicit named reconstructed profiles: SHOPPES 140×76 m, EXPO 128×90 m, CASINO 100×70 m, THEATRE 92×60 m and MUSEUM 100×70 m. These are **not sourced building extents**. Root should inject a complete `record.geometry` derived from its actual source footprint/local frame before integration; partial dictionaries fail. Required fields: `length_m`, `cross_m`, `clear_height_m`, `storey_height_m`, `core_bay_m`, `corridor_width_m`, `void_min_z_m`, `void_max_z_m`, `atrium_void_active`.

Construction supports length 30–320 m, cross 28–180 m, clear height 2.7–5.25 m, storey at least clear height+.20 m and at most5.5 m, core bay6.2–10 m, corridor2.6–5 m. A physical wing must retain at least7 m room depth and each cell at least7 m frontage; exact furnishing fit can impose stronger limits. No compression is applied to force a failed layout through.

Rooms reserve a door-side longitudinal aisle, a 2.7 m clear entry gallery and a back gallery. Furnishings are packed entirely in a bounded content rectangle, with .85 m horizontal/.95 m longitudinal gaps between full object envelopes. Larger rooms repeat their appropriate fixtures within bounded grids; they do not remain a huge empty labeled floor. Full-size table/chair/cabinet/machine components have matching physical boxes/cylinders; the QA capsule remains the production radius.36/height1.75/offset.9 and margin.01 minimum. No collider, door or furniture is hidden to pass the route.

## Assembly requirements and material limits

- **L1:** raw inventory L1 has no void. Do not use its low ceiling as the grand public atrium. Root must supply the real tall-atrium void/edge-wing geometry and integrate the continuous public module without duplicate slabs/solids.
- **SkyPark:** each hotel roof record creates its named pool segment/deck rooms. It does not join them into the real long shared pool/SkyPark. Root owns correct whole-roof assembly and source shape.
- **Recessed pool:** the actual slab is cut, with basin bottom/walls and visible entry treads plus continuous inclined collision. Water has no fake walkable surface; `mbs_program_water` areas only identify volumes. Root must coordinate the L56 ceiling/structure below the recess, integrate appropriate water behavior, and test it. No swimming, pool physics or lower-floor clearance pass is claimed.
- **Core continuity:** actual adjacent floors, physical cabins, no-fall/cabin interlocks, loaded collision and cross-building/road-separated links remain root work. The standalone factory is not a normal exterior entry.
- **Materials/art:** existing project material and original furniture/plant mesh sources are reused/adapted. High visual quality remains a runtime critique gate. No commissioned artwork, named operator decorative motif, private architectural plan or commercial raw asset was copied.
- **Performance:** grids and geometry are bounded, but the total reconstruction is not a 60 fps proof. Stream at floor/room scope and measure the heaviest actual rendered view on Studio under the current shared GPU rules.

## Root commands

The root must **commit the frozen source before either run**, then use ONLY the current-task `loop/singapore-fidelity/run_engine.sh` helper. It supplies the private single-engine lock, current installed shared coordinator/namespace, last-moment renderer gate, stream-aware frame cap and bounded supervisor. This is the current ongoing goal; no expired four-hour pass/deadline or old render helper applies. The builder did not run these commands.

Headless root gate, still through the same manager helper:

```sh
bash loop/singapore-fidelity/run_engine.sh mbs-program-spa-west-headless-r1 900 /private/tmp/singapore-fidelity/program-spa-west-headless-r1 -- --headless res://src/systems/fidelity_tests/mbs_program_floor_test.tscn -- --qa-session /private/tmp/singapore-fidelity/program-spa-west-headless-r1/session --mbs-program-floor=T2-L5 --mbs-program-wing=west --mbs-program-report=/private/tmp/singapore-fidelity/program-spa-west-headless-r1/report.json
```

Actual rendered root run, after the normal capacity/identity/stream checks:

```sh
bash loop/singapore-fidelity/run_engine.sh mbs-program-spa-west-render-r1 900 /private/tmp/singapore-fidelity/program-spa-west-render-r1 -- res://src/systems/fidelity_tests/mbs_program_floor_test.tscn -- --qa-session /private/tmp/singapore-fidelity/program-spa-west-render-r1/session --mbs-program-floor=T2-L5 --mbs-program-wing=west --mbs-program-report=/private/tmp/singapore-fidelity/program-spa-west-render-r1/report.json --mbs-program-stills-dir=/private/tmp/singapore-fidelity/program-spa-west-render-r1/stills
```

The new fixture reuses the guest test's exact production Player/native E/LOS/capsule/door-physics diagnostics. It plans all57 records but continuously walks only the selected floor+wing, default **T2-L5 west**, the narrow spa wing (about7.47 m room depth). One explicitly labeled setup pose is followed by every room traversal and both guest/service lift approaches without actor relocation or jumping. It tests an actual LOS blocker, closed/open door capsule passage, native E hinge poses, serialized JSON room-door state and lift requests that cannot teleport/open without a cabin. It turns in place with input released before straight walking legs to avoid the QA driver sprinting a broad180° arc into nearby furniture. Route widths, sizes and collision margins are unchanged. It does not exercise program-floor stairs/swimming, the other wing, outside-to-inside, every recipe, rendered quality or performance.

For further recipe gates use the same scene/isolated sessions and select `T3-B5` (service/parking), `T3-L57` (pool/deck), `T3-L56` (observation), `SHOPPES-L1` (retail), `EXPO-L3` (fitness), `EXPO-L1` (exhibition), `CASINO-L1` (gaming), `THEATRE-L1` (theatre), `MUSEUM-L1` (gallery). Each result must name its actual selected wing. Inspect actual gameplay PNGs and get a fresh independent critic against the documented public references/exterior quality before accepting any visual result. Headless checks alone do not close those gates.
