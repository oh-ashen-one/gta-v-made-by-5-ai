# First real source neighborhood — incremental native QA

## Retained R1 evidence

`/private/tmp/singapore-fidelity/source-world-r1` booted the actual nine-cell source world and passed eight setup/support/domain checks. The ninth check was the240second wall watchdog. The engine exited1/no fatal/reaped after254.13seconds. Its first `_walk_to(car)` had not returned, so the report contained no incremental walking metrics. This cannot distinguish slow simulation from an obstructed target and is not a gameplay/FPS pass.

The old target was `car.global_position + Vector3(2.4,0,1)` in world axes, regardless of the actual rotated vehicle. The R1 report records actual car arrival at source `[456.073486328125,7.65753364562988,585.590942382812]`, distinct from the preferred source-node arrival. Endpoint clearance and straight-approach clearance must therefore be checked on the actual instance. An opposite-side endpoint can be valid while the W-only route crosses the hull; that is a hypothesis until the new native probes report it.

## Native approach selection

The revised test records the original endpoint in the enabled production BoxShape's current native body frame, its actual player-capsule overlaps, an eye-height native ray from the current player, and a nonmutating `PhysicsServer3D.body_test_motion` query using the actual player RID/shapes. The approach ray and body/capsule diagnostics include the destination vehicle and ordinary player collision layers. The only explicit exclusion is the player's own RID in space queries.

Candidate foot positions come from the existing production `Car.find_safe_exit` query, with its native support, source-context exit and capsule checks. The original offset is retained if it is physically valid and its approach is clear. Otherwise the production side/front/rear offsets are tried nearest-first. Selected candidates must additionally pass an independent actual-capsule test, an approach ray including the vehicle, no hard nonwalkable body-motion contact, and the unchanged interaction-distance gate. The shared production exit helper's own internal vehicle exclusion is not used as a QA bypass: these additional approach/capsule/body tests include it.

Long body tests can report ordinary walkable terrain support; that alone does not prove a wall. The diagnostic distinguishes support normals from hard obstructions. Ultimately the real W-only movement must still reach the target. It never jumps, assigns actor position/velocity, disables collision or teleports to satisfy an approach. Existing heading steering is retained and recorded explicitly. If no clear straight approach exists, it reports that fact instead of inventing a route. No actual approach correction is claimed successful until the revised run.

## Incremental observations and bounds

The fixture logs `PROGRESS` every10wall seconds and at phase transitions, retaining the same rows in the terminal report. Boot rows record completed tiles and physics/simulation/wall time. Walking rows update current target, distance/best distance, traveled distance, current frame/simulation/wall budgets and no-progress clocks on each physics step. Native snapshots record actual pose/velocity, controls/hold/alive/visibility state, fresh source support/residency/clearance/water, last-move slide contacts and runtime profiling counters. Last-move contacts are labeled as such; a held actor may not have executed a new slide. Diagnostic query cost is recorded.

Every walk preserves the0.65m arrival threshold, rechecks it after native input-release settling, and has a15simulation-second command bound. No approach improvement of0.10m over2.5simulation seconds has an explicit terminal reason;60wall seconds without progress records low-throughput/no-progress rather than silently waiting. The whole diagnostic run has a600wall-second timer and must use Root's660second outer supervisor. Those bounds are diagnostic limits, not a performance target or acceptance. Progress is still logged if the global timeout interrupts a pending walker.

Initial/player-exit settling waits for three actually quiet grounded physics samples, with finite90/30frame maxima and0.12m/s bound. Braking keeps the normal brake input until three quiet grounded samples,0.25m/s maximum, within its original150frame cap. Drive180frames, climb300frames and forward-flight180frames are unchanged. No substantive driving/flight proof was shortened. Car interaction remains<4m; real production interaction selection and E input now replace direct boarding/exit method calls.

Use the existing Root engine/lease/gate wrapper with scene `res://src/systems/fidelity_tests/source_world_test.tscn`, a fresh private `--qa-session`, `--source-world-test-approved-roads`, and **`--profile-source-runtime`**. The latter enables the actual Runtime counters; the report records whether it was present. Keep600internal/660outer. Source/data/controller/service/Runtime code was not changed by this test repair.

## Actual-world F5/F6 integration

Before walking, the fixture verifies that the installed controller/service owns a source sibling within the actual private QA session. Native F5 and F6 key events go through SourceWorld's production input handler and Game/controller/service routing. It performs immediate save/load at the genuine on-foot terrain anchor without arbitrary stats, geometry or actor changes. The exact canonical pose and heading are captured synchronously in the real restored signal, with actual native support/residency and UNKNOWN land/water retained. Legacy existence/hash and complete source bytes are checked unchanged by load.

That legitimate production restore is explicitly outside the continuous walking traces. It is not counted as a fixture teleport or misrepresented as uninterrupted walking through the city. A failed/pending integration receives its own phase/result instead of being hidden in the car walk.

## Verified components preceding this run

Root native Context broadphase passed670checks/0fail. Its synthetic189floor×8volume/32query microbenchmark had exact equal outputs,12,283µs broadphase versus323,232µs exhaustive, and256exact candidate volumes versus48,384exhaustive checks. These are shared-CPU component observations, not city FPS or a controlled end-to-end speedup.

Root source-save R2 passed82/82, exit0/no fatal/reaped. It covers the revised ownership/checkpoint/policy/type cases in a labeled native fixture. Those component passes do not establish that this actual source world can yet walk, drive and fly through its full route. Normal main migration, complete MBS/whole-country traversal, actual rendered fidelity and owner acceptance remain separate gates.

The revised WorldQA is frozen for Root execution. No child engine/GPU/Git action occurred.
