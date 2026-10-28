# Complete interior reconstruction inventory and reusable guest-floor factory

The owner explicitly directed autonomous implementation without further plan requests. The target remains the **whole fully explorable building and linked resort programs**. Documented public facts are retained; undocumented private floor assignments, unit numbering, dimensions, cores and fit-out are a coherent **game reconstruction**, not certified current as-built records. No permanently empty private guest floors are chosen as a substitute for this target.

## Inventory coverage

`game/data/mbs-interior/inventory.json` contains a deterministic, reproducible inventory:

- 1,850 normalized game guest units, including 775 suites and 1,075 standard units.
- 159 guest-floor recipes across three towers; each recipe feeds the same furnished/colliding factory.
- 189 hotel floor records: L1–L57 and B1/B2M/B2/B3/B4/B5 in each tower, with every non-guest record assigned a nonempty public/service/roof program.
- 27 additional retail, Expo, casino, theatre and museum program-floor records.
- 1,150 connection records, with no orphaned floor/program nodes in the graph.

The operator says **approximately** 1,850 units and 775 suites across 55 floors. Our exact game normalization, 625/600/625 tower allocation, 260/290/225 suite allocation, room labels and all per-floor assignments are reconstruction. Roof level numbers 56/57 are kept separately from the operator's 55-floor description; the data is not a surveyed numbered-level schedule. Current operator facts include T2 L55 Paiza Sky Residence, T2 L5 spa, Expo L3 Fitness Centre, T1 L55 Jin Ting Wan, T3 L56 public observation and L57 pool/dining. Historical spa/gym L55 brochures do not override current pages. The future 2027 lobby closures are not represented as current 2026 closures.

Regenerate with `python3 game/data/mbs-interior/generate_inventory.py`. `inventory-check.json` records totals, graph integrity and the deterministic SHA256. Static dimensional checks in `STATIC_CHECKS.json` are not engine evidence.

## Runtime API

```gdscript
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const GuestFloor = preload("res://src/world/mbs_interior/guest_floor.gd")
var record = Inventory.floor_record("T1-L02") # canonical ID is T1-L2; padded alias accepted
var module = GuestFloor.new()
owned_floor_root.add_child(module)
var result = module.build(record)
```

`Inventory.guest_floor_ids()` enumerates all guest recipes. `floor_record`, `unit_record`, `connections_for` return copies, while cached parsing avoids reparsing/copying the whole inventory for each floor. `validate_inventory()` checks normalized totals/IDs/connections. JSON export inclusion must be verified in the packaged build.

`GuestFloor.plan(record)` validates bounded geometry and produces all unit cells without node creation. `build(record)` consumes it once, preserving local metre coordinates and rejecting compressed scale. The module never assigns source coordinates or changes an actor's transform. Root owns source placement, declared floor elevation and alignment to the exterior.

Each guest floor builds:

- Two room wings with supported, clear 2.6 m corridors, material floor/ceiling slabs, physical external glazing/party walls, and no slab or ceiling across the conservatively projected atrium void.
- Every inventoried room, with actual hinged entry and bathroom doors, a materially furnished bedroom, bathtub, shower enclosure, basin/mirror/vanity/WC, armoire, desk/TV, bedding/headboard/curtains and lighting. Suites have separate bedroom compartments, living furniture/bar and larger suites include dining seating. Private layouts and collection distribution are reconstructed, not copied sample plans.
- Physical enclosed linen service rooms, guest and service lift landing doors, and U-shaped stairs with treads, continuous walk collision, landings and guards. The smoothing ramp occupies the visible stair footprint; it is not an actor teleport or a test bypass.
- Actual door collision remains enabled. Reconstructed components have diagnostic shape names. Visible doors are `AnimatableBody3D` hinge objects, not skeletal character motion clips.

`request_interaction(door_id)` handles ordinary room/service doors. For a lift door it emits `transition_requested(floor_id, portal_id, kind)` **without opening or relocating an actor**. The root coordinator must install a real cabin/shaft, load destination landing collision and satisfy its interlocks before calling `confirm_transition_ready`. Do not confirm readiness merely to make a test pass. `set_door_open`, `closest_interaction`, `serialize_state` and `restore_state` support parent controls and persistent ordinary room doors. Lift readiness is deliberately not restored as an unconditional open state.

`rooms` exposes `entry_local`, `inside_local`, `view_local`, bathroom approach points and unit identity. `portals` exposes physical stair walking waypoints, lift thresholds/cabin expectations and service-room landings. These are geometry/control interfaces, never instructions to teleport players between floors.

## Atrium, source placement and streaming

The source tower footprints/centroids and existing public atrium profile are read to derive conservative open-void bounds. For a private level beneath any intersecting part of that atrium's roof, the whole affected central strip remains unplated. Separate wing stairs/lifts serve these levels. Their X/Z axes stay fixed across all levels, including the level where the central void closes; each end bay supplies a physical horizontal corridor from the changing central corridor to those fixed landings. `cores.local_x_m` and `cores.threshold_z_m` record the same reconstructed axes for guest/public/program integration. Above the atrium roof, the two corridor strips join normally. Storey height 3.45 m after the reconstructed L2 elevation of 5 m, basement elevations and all private core positions are explicit reconstruction choices.

Root must replace corresponding old solid-mass colliders with complete hollow architecture. Do not drop these room slabs into old solid towers, cap the public atrium with a low whole-plate collider, or indiscriminately remove supports. The local factory supplies geometry for **all 159 appropriate guest-floor records**, not one finished demonstration room. Remaining public/service/retail/roof factory implementations and their source-frame integration are still required.

Stream current and adjacent floors, retaining loaded collision before stairs/cabin/door transitions. Prefer only the current floor rendered, with adjacent collision/landings ready and visibility activated before a physical crossing. The suggested ceiling is three full guest-floor modules, not 1,850 simultaneous room instances. Never unload a floor occupied by the player, a persistent actor or an active cabin. Save floor ID and local position with the root coordinator's source frame, validated after reload; this worker does not change shared save or domain code.

## Parent verification

```sh
bash loop/singapore-fidelity/run_engine.sh mbs-guest-floor-r2 960 \
  /private/tmp/singapore-fidelity/mbs-guest-floor-r2 -- \
  --headless res://src/systems/fidelity_tests/mbs_guest_floor_test.tscn -- \
  --qa-session /private/tmp/singapore-fidelity/mbs-guest-floor-r2/session
```

The dedicated test validates all 159 recipes, then selects and builds the tightest suite case for each wing x bedroom-count tuple (east/west x 1/2/3 bedrooms). It reuses the actual production capsule/transform, checks closed/open room doors, walks actual rooms/bathrooms/service rooms and U stairs without jumps, verifies door persistence and lift interlocks, and prints real contact shapes on a stall. The setup relocation between explicitly independent fixtures is labeled; it cannot prove travel across the real site or between all real floors. Optional parent-rendered captures: omit `--headless`, add `--mbs-guest-stills-dir=/private/tmp/singapore-fidelity/mbs-guest-floor-r2/stills`.

**No engine/GPU was launched by this worker.** Compile, runtime/packaged behavior, rendered quality, performance, global stair/lift continuity and all 1,850 rooms' runtime quality remain unverified. Inventory coverage and one factory test do not complete the whole-building goal.

## Sources and art

Primary operator URLs and scope are embedded in the inventory `facts`. Premier's published average 45 m² and Signature's 140 m² are example reference facts, not imposed as invented surveyed sizes for every reconstructed unit; actual generated cell areas are reported separately. Operator pages explicitly caution that illustrative layouts vary. Room reference JPG retrieval timed out and no image pixels were inspected by this worker; subsequent rendered critique should compare official room imagery through the parent's connected browser. No source PDF/JPG, hotel branding art or proprietary fit-out is committed.

The current `gaming-ralph-loops/ASSETS.md` and existing MBS asset-candidate ledger were consulted. Fab's free furniture candidate has unresolved acquired-license/format details; ThreeJS Assets' low-poly seating is a weak fidelity fit and requires an account; SimReady provides industrial/medical USD assets, with no selected suitable hotel pack and per-package license/dependency requirements. Those access limits do not prove no suitable stock asset exists. Existing original project Kit/Looks/Realm and Palette materials are reused/adapted. No marketplace download, account action, purchase, generated texture or character motion was performed. Optional small unbranded dressing is listed in `ASSET_REQUESTS.json` for parent Tripo-browser handling; requests are not generation/delivery claims.


## Production E interaction and full-size suite-bed correction

Every SwingDoor now joins the production interactables group and implements interact(actor), can_interact() and prompt_text. Its collision body's origin follows the visible leaf centre while hinge coordinates remain fixed. This keeps the production Player's exact target/LOS mechanism pointed at the leaf rather than a pier boundary. The production Player source is unchanged. Ordinary doors call the floor's existing interaction handler; lift doors only emit cabin requests and remain interlocked. Hidden streamed floors reject interaction through is_visible_in_tree().

QA no longer calls request_interaction and labels that native input. Before pressing the actual interact action, it requires Player._interaction_target() to return the exact intended door and _interaction_visible() to permit it. A temporary obstruction checks that LOS rejects the same door and actual E cannot open it through the wall. Then actual E opens the hotel room, bathroom, every suite bedroom and linen room; it requests both guest and service lifts while their no-cabin interlocks stay closed. Persistence API checks are separately labeled. No test invokes _try_interact as a substitute for action input.

Private bedroom counts were never sourced facts. Instead of shrinking beds or weakening capsule margins, the reconstruction now reallocates tight multi-bedroom units to fewer proper bedrooms. Every suite uses a 1.95 m bed, 2.11 m bedframe and 2.51 m complete bed/nightstand envelope. Beds sit toward the right wall, reserving a continuous left-side window aisle; nightstands also have matching physical collision. Across all 775 suites / 804 reconstructed bedrooms, minimum bedroom width is 3.803651 m and minimum clear window aisle is 1.068651 m. Ninety-nine initially assumed bedroom counts were revised. Exact game totals remain 1,850 units and 775 suites. One-, two- and three-bedroom variants remain present in both mirrored wings. VARIANT_COVERAGE.json lists the counts, worst cases and explicit unverified runtime state.

The default test covers all six worst-clearance cases with actual production Player walking through each bedroom's native-E door, along the bed-side aisle to the window and back. It then exercises the same wing's service and lift/stair routes. A 900-second internal watchdog bounds the whole matrix. To run one case at a time with the normal bounded helper, use a new evidence label, an outer budget of 330 seconds, and append --mbs-guest-variant=east:1 (or west:1, east:2, west:2, east:3, west:3). A filtered pass explicitly reports only the variant exercised; it is not a six-case runtime pass. All 159 recipe plans and all 804 suite-bedroom clearances are checked in every run.

All correction results remain code/static only until the parent runs fresh tests. No new compile, native-E, physical traversal, rendered or whole-building acceptance is claimed.


## Retained east:1 runtime failures and atomic door-pose correction

The first parent run failed before traversal because JSON bedroom counts formed float-spelled variant labels. The canonical integer selector fix is retained; the second parent run selected east:1 and passed exact native door selection, LOS, the negative obstruction test and actual E-state change. It then failed the opened-door capsule sweep and stopped at (-21.15592, -0.024878, -2.201563), before the room threshold at Z=-2.6. Evidence remains in /private/tmp/singapore-fidelity/mbs-guest-east1-r1 and mbs-guest-east1-r2. Neither is physical traversal acceptance.

The stopped Z matches the CLOSED 0.075 m leaf's outer face plus the actual 0.36 m capsule radius: -2.6 + 0.0375 + 0.36 = -2.2025, within 0.000937 m of the stop. A 0.15 m wall-pier contact would occur at -2.165 instead. This points to a physical leaf pose problem rather than insufficient doorway width.

Godot's AnimatableBody3D sync path queues a requested transform and restores the last accepted node transform after a setter. The old tick set rotation, then read that restored rotation to calculate/set position, overwriting the queued orientation. The corrected tick integrates an independent motion_angle and submits ONE complete Transform3D for rotation and leaf-centre position. Physics synchronization, full collision and all clearances stay enabled. Constructor setup is also one complete transform. No actor position or controller code is changed.

Primary implementation reference: https://raw.githubusercontent.com/godotengine/godot/master/scene/3d/physics/animatable_body_3d.cpp ; API contract: https://docs.godotengine.org/en/stable/classes/class_animatablebody3d.html . Exact installed-runtime pose is verified by the new diagnostics, not presumed from a different source branch.

After actual E and settling, the test now records commanded angle, node pose, PhysicsServer3D body pose, hinge and sync flag, and requires the physical/node poses to agree with the commanded open/closed orientation. A failed capsule sweep reports exact hit body/shape names, sizes and transforms. The production Player's existing QA motion probe is enabled without editing its controller; a stall records input strengths, busy/mode/pause state, requested/resolved velocity, recent samples, nearby door physics states and actual slide contacts. These diagnostics do not disable avoidance, collision, margins, steering or movement thresholds.

The atomic correction and diagnostic additions are source-only until a fresh parent run. Earlier failures remain preserved.


## Retained R3 obstruction and planned-foyer repair

The actual parent east:1 R3 run passed the atomic door pose and opened-roomdoor capsule gate, then stopped at (-18.99408, -0.024885, -4.05146), approaching bathroom waypoint (-18.67061, 0, -3.95). Its full trace shows forward/sprint held, alive/unpaused/not busy, nonzero requested motion and zero resolved motion. The room door's node and physics angles were both correctly open. The failure is retained at /private/tmp/singapore-fidelity/mbs-guest-east1-r3/run.log.

The solid social bar occupied X[-18.65592,-17.65592], Z[-3.925,-3.275]. The stopped capsule centre is 0.361032 m from that corner; the waypoint is only 0.028996 m from it. A radius-0.36 capsule cannot stand at that target. The old bar also straddled the bathroom wall in narrow units.

The same solid bar now sits against the front wall and is clamped wholly outside the bathroom footprint. Dining is kept in its own front bay, clear of a dedicated side approach to the bath. The coffee table stays behind the rear cross-gallery, including shallow suites. Bathroom access uses that real cross-gallery and side aisle instead of a diagonal line through furnished seating. All furniture collision, bed sizes and capsule/query margins remain intact.

The test sweeps the full production capsule along every intended bath-approach segment before walking it. Turn waypoints use a stricter 0.10 m arrival radius so the controller cannot cut across a 1.10 m clear gallery; the full capsule plus query margins occupies 0.74 m, leaving 0.36 m total lateral tolerance. This tightens the route requirement; no arrival tolerance was loosened. Bathroom-door standing points and physical passage checks are unchanged.

CIRCULATION_REPAIR_R3.json independently checks all 775 suite recipes / 2,325 axis-aligned bath approach segments against the actual bar, dining/chairs, sofa and coffee-table bounds. Minimum obstacle distance is 0.54 m, exceeding radius plus query margin (0.37 m). This is static geometry evidence, not a runtime pass. A fresh parent run remains required.


## Retained R4 core-crossing route failure

The parent east:1 R4 run passed native E for the hotel room, bath, bedroom and linen room, including correct physical door poses and bedroom/window walking. It then attempted a direct walk from the north linen core to the opposite lift, behind the guest-room row. The full trace at /private/tmp/singapore-fidelity/mbs-guest-east1-r4/run.log shows held forward/sprint, unpaused/not busy, requested velocity (0.139032,-0.5,-0.003777) and zero resolved velocity. This is not an idle-input or long-leg budget failure.

The room-row end wall is at X=-22.00592. Its 0.15 m thickness plus the actual 0.36 m capsule predicts contact X=-22.44092; the observed X=-22.44203 differs by about 1.1 mm. The attempted Z around -11.9 is within the guest-room band, not the main corridor. The floor-only slide normal does not turn that inaccessible straight line into a valid route.

The factory now exposes public_route_local(start,target,wing): a pure same-wing public-floor route through the main corridor and connected end bays. It rejects private-room starts and low atrium crossings. Points in the same end bay can connect directly; opposite end bays must return to the actual corridor before traveling longitudinally. No actor transform changes, wall deletion, collision disable or invisible bridge is involved. Root remains responsible for other floors/cabins and source placement.

QA uses that route for linen/lift approaches and for reaching the physical stair's lower landing. It checks full-capsule clearance for each planned segment, then uses the production Player to walk every segment. Analytic route points use the finished floor reference Y=0, matching the module's existing waypoint convention; only the sweep-reference value is projected, never the actor. A private-room shortcut is explicitly refused. Walk speed, capsule/query margins and the per-leg distance/time formula are unchanged. Failure traces now also include initial/remaining distance, elapsed and allowed time, and displacement for the actual leg.

R4 remains retained failure evidence. The corrected corridor routing requires a fresh parent run and does not imply a full-building or whole-variant pass.


## R6: receiving-floor fixture and lift-motion invariants

R5 passed all six native E paths (room, bath, bedroom, linen, guest lift and service lift) and actual U-stair ascent. It failed on the first return leg after the top landing: the leg started only 0.610 m from its target, then displaced 1.001 m and ended 1.571 m away. The turn overshot the 1.2 m top landing and landed on the current-floor core ceiling at 3.28 m. Actor foot Y=3.255836 matches ceiling top minus the capsule's approximately 0.025 m foot offset. The true receiving floor is at 3.45 m; the standalone fixture had not loaded it despite the stair portal's existing adjacent-floor-collision requirement.

The fixture now looks up the ACTUAL next inventory level and checks its elevation delta against the stair rise. It loads a temporary physical receiving-core interface at that elevation using the SAME core-approach helper used by normal guest/program floors, and rays verify support at 3.45 m rather than the lower 3.28 m ceiling. The player physically crosses onto that loaded approach and returns down the stairs. This is not a current-ceiling raise, collider deletion, actor relocation or invisible recovery plane. It is explicitly only a QA receiving interface, not a completed next floor or a permanent empty program fallback. Full building transitions still require the complete next guest/program floor from the root coordinator.

Protected _build_stair, _floor_ceiling, lift and door signatures remain unchanged. The pre-existing core-floor loop moved into _build_core_approaches(kit,wing,g,with_ceiling=true), preserving its normal geometry and allowing the same structural interface to be exercised independently. The program builder was notified.

The old outer lift check compared Vector3 positions exactly across approximately a second of normal physics. R5 did not log its before/after delta, so its magnitude cannot be reconstructed. The native E helper's existing less-than-0.02 m short-transaction bound passed; the fixture handler receives no actor reference and only counts a request. R6 retains that bound and adds a stricter per-physics-step monitor through the complete transaction: zero movement/jump input, peak step below 0.02 m, and displacement minus resolved-velocity integration bounded by the production safe_margin plus calculated floating-point noise. Before/after positions, actual delta, peak residual, bound and recent per-frame samples are logged. This tests unexplained relocation rather than assuming a supported body's float coordinates never settle. It does not edit controller velocity, positions, collision or margins. Stair arrival thresholds remain unchanged.

Historical limitation: earlier failures retain raw traces, supervisor metadata, hashes and repair descriptions, but not every untracked failed source body is recoverable as a complete Git tree. They are not advertised as fully replayable checkpoints. Root will commit the exact frozen R6 source/inventory as verification PENDING before the next run. R6 has no runtime acceptance until that new run completes.


## R7: mirrored bedroom return-line alignment

The committed R6 source passed the standalone east:1 run (1,047 clean checks, 309.81 m native walking, six native-E doors and ascent/return across the receiving floor). The subsequent full matrix retained an east:1 completed fixture, then failed west:1. This is partial coverage, not an all-suite or full-building pass.

The west:1 trace at /private/tmp/singapore-fidelity/mbs-guest-matrix-r1/run.log shows a 0.318707 m initial leg, 1.677155 m displacement and a final stop at the bedroom's left front-pier corner. Source geometry explains the repeated target: the old window-aisle start X=-19.2716375 returned sideways to door-inside X=-19.574965 at the SAME Z=7.5, a 0.3033275 m jog. That short lateral maneuver after sprinting back from the window caused a turn/skid outside the opening. The observed corner distance is 0.361111 m, matching the full capsule and collision tolerance. The physical door angle and ideal open-door capsule check had already passed. NPC/street-prop avoidance has no fixture obstacles to steer around.

Reconstructed door centres now align with the actual bed/window aisle, clamped only to retain a proper 0.15 m left jamb. For this west:1 room the line is exactly collinear; its door moves 0.3033275 m within the same bedroom front wall. No source-certified door position exists here. The test walks entry-to-window and back along that continuous route instead of inserting a short sideways return point. It still requires native E, the full window visit, the same 1.15 m doorway, production capsule, 1.95 m beds, query margins and unchanged arrival radii. Every complete bedroom route receives a full-capsule sweep before physical traversal; stage/segment labels now disambiguate repeated targets in diagnostics.

DOOR_ALIGNMENT_REPAIR.json audits all 804 suite bedrooms: minimum planned distance to the complete bed/nightstand envelope is 0.418651 m, to the side wall 0.534325 m and to the open leaf 0.421825 m, all above the unchanged 0.37 m radius-plus-query-margin bound. The small jamb-clamped door/aisle offsets in the narrowest rooms are traversed gradually on the long route rather than as separate lateral waypoints. These are static bounds, not current-revision runtime acceptance.

Root reported R6 commit 734008e and combined pushed checkpoint aa06956. R7 is frozen for its own new commit before the selected west:1 rerun; the exact previous matrix failure remains retained.


## R8: measured failed approach, native sweep diagnostics, and constrained walking

The committed R7 source fd33dd5 failed selected west:1 after 1,006 checks, at the FIRST bedroom-entry leg. The actual starting position was (-18.10734,-0.02416,5.835666), while its planned doorway approach was (-19.27164,0,6.0): more than a metre of longitudinal alignment had been lost before this leg. Forward and sprint remained held; repeated requested/resolved velocity was (-2.775994,0,6.207565). The stopped Z=6.215035 matches the bedroom-front wall face 6.65 minus half-thickness 0.075 minus capsule radius 0.36 (=6.215). Its X lies essentially at the right jamb edge, not the opening centre. This supports a broad turning approach against the front pier, but floor-only slide contacts do not prove the exact collider. The complete failure remains at /private/tmp/singapore-fidelity/mbs-guest-west1-r1/run.log.

There are NO further production geometry or Player changes in R8. Before attempting any more layout revisions, QA now queries the actual production body RID at that retained pose using PhysicsServer3D.body_test_motion, with the actual safe margin and recorded requested step. It separately queries a short horizontal target-directed step and the full production capsule's overlaps at the unchanged stricter 0.01 m query margin. Native hit shape indices, names, transforms, box sizes, normals, fractions and contact points are logged. Supplying a hypothetical query pose never assigns the actor transform; a same-pose assertion verifies no actor relocation. Fresh runtime timeouts also take a body sweep BEFORE releasing held movement and record controller input/state. These reports still require the parent's native run; there is no invented hit result in this note.

The fixture no longer demands sprint-speed turns or a 180-degree sprint reversal beside a hotel bed. It releases all movement inputs, waits a bounded period for the real controller to settle below 0.05 m/s for three physics ticks, turns the camera while stopped, then uses W plus the production WALK action (1.5 m/s) for constrained room and stair legs. Braking uses ordinary input release; no actor position, velocity, controller speed or heading is assigned. Only explicit long straight public-corridor legs may sprint, and they return to walking before arrival. The actual gait and per-leg records are in the test report. Per-leg time is based on the selected real gait, rather than assuming walking travels at sprint speed; the outer watchdog remains bounded.

All existing capsule dimensions, bed dimensions, doorway widths, query margins and arrival radii are unchanged. Every metre is still traversed by the production controller and all ideal full-capsule route sweeps remain. The previous permissive final comparison radius plus 0.08 m is unchanged, not widened. Native E also now holds release/press over process-frame boundaries because Player consumes it in _process; exact target, LOS, action-state, physical door angle, negative obstruction and lift-interlock checks remain strict. Program-floor inheritance keeps the same two-argument walk_to signature.

R8 is frozen code-only pending the parent's committed selected west:1 run. East:1 R6 was a real partial pass; the six-variant matrix, all 1,850 units, source-site integration and full building remain unaccepted.
