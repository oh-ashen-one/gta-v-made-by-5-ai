# Planned source architecture transition guard

`source_world_guard.gd` subclasses the Root source-runtime adapter. Existing frame/context/collider/residency checks remain active through `super.motion_allowed`. Root explicitly configures it with the approved mask file, exact SHA and a lifecycle assessment callback. The mask loader never changes canonical data or uses its polygons as land/support geometry.

The approved initial masks contain four exact OSM hotel/retail polygons and one separately declared reconstructed public-loft exclusion. The guard uses their float64 MultiPolygon rings and holes directly. Swept center segments are partitioned at ring intersections; intermediate inclusion checks catch a thin crossed polygon even when both endpoints are outside. No simplification, buffering, XY snapping or broad bounding-box-as-floor operation occurs.

The callback signature is `assessment(mask_id, canonical_xyz, actor) -> Dictionary`:

- `state="required"`, `floor_ids=[...]`, `ready=bool`, `provenance=...`: these precise source-bound architectural floors/neighbors are needed for this transition. `ready` must represent current native same-context/same-origin collision, not a plan, file, cached Boolean or successful data decode.
- `state="known_physical_void"` with provenance: a courtyard/atrium/other actual planned void is allowed to retain ordinary physics. The guard adds no surface or water claim.
- `state="not_required"` with provenance: this point is outside that planned floor's vertical/program domain, even though its horizontal source mask matches.
- `state="unknown"` with provenance: this planned area is not resolved and the transition holds. It never becomes outside-city, dry land, death-plane damage or a teleport.

Unready/unknown required architecture emits a bounded `architecture_required` request and holds the actor. The Root can queue `FloorStack.ensure_floor` and neighbor preparation, then make the callback ready only after actual native commit. Requests repeat when the mask/floor/epoch requirement changes, and deduplication resets once the transition becomes allowed. This is a request, not an automatic geometry or rebase mutation.

Aircraft flight uses actual native collision/residency without imposing a floor beneath open air. A foot position proposed during vehicle exit takes the same architectural readiness check after Root's current native support/clearance/territory exit checks. Grounded car/player movement follows the callback; the callback must not label every height of a tower footprint the same floor.

Initial limitation: this component guards the actor center's exact swept source segment. Generic Runtime already bounds the full swept physical envelope for residency, but this architectural predicate does not yet perform a full swept capsule/rotating vehicle-vs-footprint Minkowski intersection. Root must review body-edge clearance and the actual doorway/landing route natively. Do not promote this component to whole-body architecture-streaming acceptance from point predicates alone.

The Root-run native fixture is `res://src/systems/fidelity_tests/source_world_guard_test.tscn`, with a new owned `--qa-session` beneath `/private/tmp/singapore-fidelity/`. It verifies the exact current Root mask hash and a real T1 source edge. Its small floor slabs and lifecycle mapping are explicitly synthetic: they exercise a native production Player walking to a missing required-floor boundary, holding without a fabricated inside slab, then continuously crossing after actual collider/support commit. The fixture also preserves known-void semantics and unknown outdoor hydrology. It is not proof of actual MBS floor layout, outside-to-hotel traversal, visuals or whole-country play.

Root's first four-script project import gate passed before this guard integration. The entry now preloads the guard and provides a source-bound lifecycle callback. It hashes and copies the actual MBS inventory, uses the existing exact Root registered public/floor/stair source volumes, calls actual FloorStack.floor_state, and requires the live public-site collision region. Unready floor IDs are queued sequentially through the same existing FloorStack. Unmapped retail and source-footprint/constructed-volume disagreements remain unknown rather than becoming a completed floor.

Moving-cabin passage has a distinct check: the production Player must currently have stamped native support from that exact cabin and a live shaft lease; the proposed entire capsule footprint must remain inside the actual native slab, using its current PhysicsServer transform. This permits physical rides between storeys without using a broad enclosed-shaft volume as permission to walk out into a missing landing. Door/shaft travel readiness remains the existing Hotel authority.

Guard-integrated parsing/native QA remain pending. No child engine/GPU/Git action occurred. The road binding is deliberately hard-blocked while known-rejectedR2 is pinned. Root will verify the small guard lifecycle fixture independently, then corrected road and actual neighborhood/MBS routes. No synthetic slab fixture is relabeled actual MBS geometry proof.

## Retained native R1 failure and correction

Root's `/private/tmp/singapore-fidelity/source-world-guard-r1` exited1 cleanly/reaped, without fatal errors. Five setup checks passed, then configuration of the correctly pinned mask bytes failed. No movement gate ran. The actual file SHA remained exactly `9d91185dab9c936316b1397a7faad778556b28fb29e44f01f03b4fe04d498625`; the defect was the loader accepting only MultiPolygon while Root's fifth, explicitly constructed public-loft footprint is a Polygon.

The correction preserves the exact bytes/hash and all coordinates/rings: a Polygon's ring array is wrapped once into the same iteration structure; each row retains its original geometry type. The actual Root schema and snapshot are additionally checked, and configuration failures now have diagnostic text. The fixture adds an explicit4MultiPolygon+1Polygon type/count check; all existing native movement/support thresholds remain unchanged. Corrected native R2 is pending. The R1 failure is not overwritten or relabeled a pass.

## Retained native R2 contact-assertion failure

Root's `source-world-guard-r2` completed20checks with2failures, exit1/no fatal/reaped. The actual player held at edge side+0.001187m, then crossed continuously to−1.587180m after native commit, with new interior support, clear capsule and no teleport. Both failures came from the fixture testing Player rootY>−0.02m as if that root were its physical feet.

The production capsule is1.75m tall at centerY0.9m, so its actual bottom is0.025m above the Player root. R2 held rootY−0.024195 therefore put the capsule bottom approximately+0.000805m above supportY0; the final rootY−0.024156 put the bottom approximately+0.000844m above support. A negative node-origin coordinate did not establish penetration or a fall.

The corrected fixture changes no production guard, actor, floor or movement geometry. It measures the actual enabled production capsule and current native support, records the settled baseline before approach, and checks physical capsule-bottom gap using the existing Runtime solver-safe-margin×2 plus local-float-roundoff envelope. This remains a millimetre contact bound, not a broad vertical tolerance. The exact boundary-side, required-unready state, exterior/interior support identity, clearance, continuous crossing and no-teleport conditions remain. Corrected native R3 is pending; R2 remains failed evidence.
