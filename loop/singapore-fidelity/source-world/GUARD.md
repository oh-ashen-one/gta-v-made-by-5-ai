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

At author freeze, parsing/native QA are pending. No child engine/GPU/Git action occurred. The initial six SourceWorld entry files were held stable for Root's syntax check while this new guard/fixture was authored; switching the entry's Runtime preload and supplying the exact MBS lifecycle callback must be coordinated after that check.
