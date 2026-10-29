# Partial service-floor dispatch — independent read-only Stack review

This review changed no source, ran no engine/Git operation and does not establish six-recipe runtime, stair/cabin or visual acceptance.

## Findings needing follow-up

**P1: current whole-source-world pin/capacity policy can prevent further travel.** SourceWorld configures12active floors and permanently pins all three L1s. Their direct neighbors protect nine unique floors. With an actor onT1-L4, itsL3/L4/L5 neighborhood adds three more, filling12. PreparingL5 requires the newL6 while every current floor remains protected, so `_evict_for` cannot release a candidate and returns protected_capacity. The partial group produces a similar boundary: nine pinned-entry floors plusT1-B2/B2M/B3 fill12; preparingB3 needsB4. This is a concrete set/count/code-path finding, not a native traversal observation, and is partly pre-existing with permanent pins. Test transition capacity and choose an explicit pin/temporary-capacity/interlock policy before claiming complete hotel travel. Do not evict occupied support merely to force a pass.

**P2: existing FloorStack native regression retains the superseded rejection expectation.** `mbs_floor_stack_test.gd` still expects `ensure_floor("T2-B2M")` to reject with pending_root_recipe_change and create no children. That contradicts the new supported Partial factory. Replace the stale assertion with meaningful positive group/native ownership/probe/void/retirement gates. A trivial readiness Boolean alone would lose coverage.

**Dependency asymmetry needs an explicit gate test, not an automatic rejection.** B2/B2M use the complete partial group, butB1's required set remains its immediateB2M/L1 neighbors. ThusB1-ready does not implyB2-ready or B2M-ready. This can be safe because the Hotel target-landing callback asks the destination's own `floor_ready`; a B1→B2M transition should remain closed until the lower complete group is prepared. Test B1-only cold request, held B2M landing, then actual B2/B2M/B1 completion and release. Also test thatB1 cannot be evicted while an actor/pin onB2 orB2M needs its ceiling.

## Coherent paths found

- `_uses_partial` dispatches towerB2/B2M records to the explicit Partial factory. `partial_plan` preserves actual inventory elevations/program IDs and produces the reconstructed2.30m service clearance; the recipe retains the actual2.5m rise/headroom+slab check.
- `adjacent_floor_ids` continues to describe immediate physical topology. `required_floor_ids` adds assembly dependencies without teaching Hotel stairs thatB1 is directly aboveB2. The Hotel upper-landing selection still uses adjacency.
- Partial inherits ProgramFloor→GuestFloor. The existing stable-structure check therefore recognizes its plain `ProgramFloorSolidCollision` body, while excluding moving doors from persistent support IDs. Doors remain in the complete collision list.
- Partial source dry volumes come from its exact local geometry descriptor. The mezzanine's central void is not replaced by a whole-floor box; the lower base separates low edges from the double-height center. Source placement remains the common frame/axes/base.
- The four partial probe locations use actual native rays with no collider exclusions. A hit must be the stable owned structure at the expected height/normal. An overlapping other floor/terrain body cannot satisfy ownership merely by occupying the probe.
- Registration identity includes adapted record, placement, precise volumes, datum and declared geometry version. Immutable previous-definition mismatch still rejects. Region/support stamps are committed only after native body/probe checks; retirement still retires the runtime region before freeing nodes.
- `planned_floor_record` returns a detached adapted record rather than the unmodified inventory clearance, allowing Hotel to pass2.10m partial receiving doors to cabin/stair guards. It constructs/validates a recipe but creates no scene geometry or lifecycle lease.

## Native coverage to add or retain

Exercise B2 and B2M in each source tower, actual four owned probes, lower central double-height support, absence of upper dry/support in the mezzanine hole, correct B1 ceiling/headroom, and low receiving door alignment. A pending/failed group member must keep `floor_ready` false without advertising travel readiness. Verify unload protection, immutable reload/door state and source geometry identity after retirement/recommit.

For `planned_floor_record`, mutate a returned copy and verify no inventory/recipe change. Distinguish its empty result for a required origin/mapping/recipe failure from a nonexistent floor in consumers; it currently uses `_recipe`, including active-local-frame projection. That is conservative in the current MBS window but is not a general remote-country planning API. Profile repeated full recipe planning only if actual hotel-boot evidence identifies it; this review proposes no speculative caching overhaul.

The whole building, current as-built private plans, normal city bootstrap, rendered quality and owner gameplay acceptance remain unverified by this source review.
