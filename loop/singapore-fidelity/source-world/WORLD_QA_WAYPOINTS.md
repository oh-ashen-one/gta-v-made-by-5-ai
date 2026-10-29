# Native helicopter approach around the observed parked car

## Retained actual WorldR3 proof

WorldR3 completed29checks with one failure: no clear straight helicopter approach. It already booted the actual nine-tile world, saved/reloaded through the production controller, walked17.43m, selected/boarded the car through nativeE, drove11.264m, braked and exited. Every helicopter endpoint was capsule-clear, but the actual native approach ray hit `SingaporePlayerCar`. This is a real obstacle, not permission to exclude its collider or move it aside. Flight was not reached or verified by R3.

## Bounded route candidate

The test preserves the original direct-approach failure and all its probes. Only when direct approach fails does it construct a small directed visibility graph: actual start, at most eight corners derived from the enabled parked car BoxShape in its current native body transform, and actual production helicopter interaction footpoints. Expanded-corner reserves include the unchanged arrival radius/capsule radius and turn space. The graph is limited to16nodes and a selected route to six legs; there is no unbounded navigation search.

Each candidate is projected onto actual native walkable support. Standing-root height comes from the real upright capsule offset/radius, sampled plane normal and existing safe margin, rather than a raised proxy over low obstacles. The existing Runtime native floor-contact clearance helper validates the unchanged capsule against every player-obstacle layer. It is used only for geometry/contact inspection, not to assert territory/water truth. A fresh source-residency envelope covers each entire sampled segment, including any intermediate height extrema.

Edges sample ground at0.50m maximum spacing and run actual native capsule casts between samples in both directions. Only the player's own RID is excluded. The parked car, helicopter, walls and props remain present. Initial overlap is permitted solely for the current matching support already clear under Runtime's unchanged floor-contact solver policy; other overlaps reject. This acknowledges `cast_motion`'s native initial-overlap behavior without excluding a supporting body wholesale or accepting a car/wall overlap. Actual movement still uses production physics and can fail if a predicted edge is not traversable.

## Real execution remains authoritative

Before every actual leg, the segment is swept again from the player's real post-stop position. The test uses normalW input and its existing heading steering, then releases movement and waits for three quiet native samples before turning into the next leg. It never assigns actor position/velocity, changes geometry/layers, moves the parked car, uses direct boarding calls or teleports around the obstruction.

The0.65m arrival gate remains. All aircraft legs together retain the original15simulation-second movement-command budget; the separate native stop samples are recorded. The parked car's observed displacement must remain below0.02m after its legitimate braking/exit, and actual native interaction selection/E must reach the helicopter. The original drive/climb/flight evidence thresholds and180/300/180frame substantive inputs remain unchanged. Whole-run600internal/660outer bounds remain diagnostic limits, not performance acceptance.

The report retains every source waypoint, ground support/capsule/segment probe, selected route, per-leg source revalidation, actual input travel/stop and parked-car observation. The failed direct result remains distinguishable from the waypoint result. Planning itself is not a functional pass: the complete walk→drive→exit→detour→helicopter/flight sequence still must run natively. No production source was edited and no child engine/GPU/Git action occurred.

At freeze only lexical bracket balancing was checked; Godot import and the revised actual-world run are pending Root. Whole city/MBS/fidelity/owner acceptance remain separate and unmet by this test repair.
