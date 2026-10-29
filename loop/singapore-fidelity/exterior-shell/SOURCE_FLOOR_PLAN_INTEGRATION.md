# Source-conforming floor allocation candidate

This is a **spatial feasibility candidate**, with actual source-envelope and full furniture/program reservations. It is not a finished hotel layout, native room implementation, private as-built plan, luxury visual acceptance or a substitute for the remaining program floors. The owner delegated undocumented private layouts; exact public facts and source ground rings stay separate from these reconstruction choices.

## What is preserved

All1,850 original room IDs,775 suite flags, bedroom counts, unit kinds, original wing labels and metadata are retained exactly. Every159 original guest floor remains occupied. The allocation retains all57 non-guest floor records, including all original private/public/service/retail/casino/expo/theatre/museum/roof programs. Those57 records are **not yet assigned complete source-conforming geometry**; the runtime planner deliberately refuses to return them as completed guest plans.

Current allocation changes the physical floor of176 rooms, all within the same tower. Tower totals remain625/600/625. Stable room IDs remain intact; each record has original floor/label and an explicit reconstructed physical floor/display label. No cross-tower moves are required. This changes the old invented per-floor assignment; it does not claim the new numbering is MBS's real room schedule.

## Geometry decisions

The compiler derives each floor and ceiling polygon from the current shell's individual tower axes and continuous taper. No source ring, scale, upper profile, core bank or boat dimensions are enlarged. Upper floors use connected rows around2.6m circulation and an explicit bank connector. Lower floors keep a large open central atrium and add reconstructed occupied end-room banks and end galleries above ground level. These replace the prior full-length rectangular void, which left T1's lower floors physically unable to contain the original room schedule. Ground public L1 is not modified by this component. Root must connect the joined atrium geometry and actual public path before runtime use.

The audit proves continuous full-storey room containment through the inverse-affine source-profile sweep, not just floor-point samples. It checks exact polygon subtraction/intersection against source, core, void, other rooms and corridors; all corridors connect to the physical core hall and every room approach contains the full0.36m capsule plus0.02m margin. These are geometric proofs, not native movement.

`source_core_geometry.gd` owns bank slabs, holes and stairs. This planner's bank polygon is a reservation, not a solid slab. It names the core support owner and supplies outside corridor geometry. Where corridor links meet the core hall, they share a boundary/short overlap for continuous support; the eventual factory must union or clip coincident floor surfaces rather than emit duplicate floors. Room floors/partitions/furnishings remain a separate factory responsibility. The persistent exterior shell owns outer facade geometry; never add the old rectangular outer walls.

## Rooms and furnishing contracts

Every room supplies:

- Exact own-axis footprint, front-left origin, proper uncompressed frontage/depth axes,1.30m entrance threshold and full-capsule approach.
- Explicit original prototype dimensions and reconstructed allocated dimensions.
- Full-size bed/bath/wardrobe/desk/lounge/suite bedroom requirements and local fitout coordinates.
- Stable bedroom/private entertainment IDs, window aisles and furniture scale1.0.

The old Guest factory ignores the inventory entertainment field. The candidate fixes that planning omission: all268 billiards suites reserve a2.54x1.27m playing bed inside a2.83x1.56m full table body and a5.73x4.46m conservative cue rectangle (1.45m cue clearance each side), and all267 media suites retain a physical screen/living program. Billiards rooms have a6.0m living bay and minimum9.4m depth. Full-size beds/nightstands remain; no furniture scaling was used. Twin-room desks move to the foyer-side bay to avoid the old two-bed/desk overlap. Factory integration must use these explicit contracts rather than reusing `_premier_fitout` or `_suite_fitout` unchanged.

**Fidelity still needs work:** old generic room rectangles totaled274,886m² because they exceeded the source envelopes. This minimum candidate totals113,391m². Each change is recorded; no hidden shrink is claimed. The operator's Premier average45m² and Signature example140m² are retained reference facts; current compact suite minima fall below that Signature example. The existing inventory explicitly says these examples are not surveyed dimensions for every reconstructed unit, but this candidate is not permission to call compact minima the final luxury target. Spare floor geometry should become larger living, wardrobe and connected annex spaces, followed by actual furnished visual/traversal critique. Minimum-fit success is not final MBS room-quality acceptance.

## Files and usage

- Authoring compiler: `plan_source_floors.py`; regenerates `SOURCE_FLOOR_ALLOCATION_CANDIDATE.json` deterministically from current source geometry/inventory.
- Independent CPU audit: `audit_source_floor_allocation.py`; current27,350 corrected-body checks pass, with all IDs, named entertainment programs, geometry, connected circulation and fixed furniture envelopes covered.
- Runtime boundary: `game/src/world/mbs_interior/source_floor_plan.gd`. Create a fresh RefCounted planner, call `configure(document)` once, then `floor_plan(floor_id)`. It rechecks actual source/core polygons and inventory identity. Raw GDScript hashes remain provenance only; runtime does not rely on reading exported/compiled `.gd` source text.
- Native validation fixture: `res://src/systems/fidelity_tests/mbs_source_floor_plan_test.tscn`, with `--allocation-plan <absolute candidate JSON path>`. Root owns the guarded engine. A90s outer bound is suitable. It validates all rooms, retrieves159 plans and tests missing/duplicate room, core collision, inventory mutation, stale source profile, anisotropic compression, lost program and shrunken billiards negatives. It prints a report to the task log.

The candidate JSON currently lives in the loop evidence directory, not an installed game resource. Root decides when to install a reviewed version in the source-world package. Do not silently select it as a finished standalone hotel.

Corrected-body freezeR2 supersedes the first billiards receipt. Exact old bytes/receipt are archived in `minimum-v1-before-table-body-correction/`. The source-profile outer Z construction reserve is now0.20m, retaining the0.15m wall body and exact polygon containment; capsule, door and corridor sizes are unchanged. The playing-bed/full-body distinction is explicit and furnishings are never scaled to hide it.
