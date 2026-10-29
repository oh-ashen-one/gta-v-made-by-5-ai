# Explicit source-tower core geometry — integration candidate

The existing floor factories derive stairs/lifts from common-axis rectangle ends. The actual source tower profiles need their own axes and the independently packed four-lift/two-stair core bank. These new components provide that geometry without changing the tested legacy implementation or pretending source rooms are already integrated.

`source_core_geometry.gd` consumes a planned floor record with exact tower/floor ID, finite storey and clear heights, and explicit `has_lower_floor` / `has_upper_floor` flags. Its poses come from `source_core_layout.gd`. It provides:

- A non-overlapping rectangular slab decomposition around four real shaft openings and two incoming stair openings, limited to256cells.
- Exact existing3.2m U-stairs with1.25m flights,2.7m run,1.2m landings, corrected1.54m side guards and unchanged full-sized capsules.
- Rigid±90-degree stair poses and explicit landing/cabin entry metadata. Wing names are stable aliases, not inferred entry signs.
- One receiving landing owned by the floor at that elevation. The lower module does not duplicate an upper landing; native interlocks must retain the actual receiving module. The bottom floor retains a foundation slab when `has_lower_floor=false`.
- Full incoming headroom cutouts through the5.10m rear midlanding. An independent review caught the initial5.00m cut, which could place a ceiling over a full capsule near the back guard; that candidate was corrected before native testing.

The caller appends this geometry to its own single floor Kit/body, then commits it normally with the full source context/leases. It must exclude this entire bank polygon from other room/corridor slab geometry to avoid duplicates. Incoming/outgoing floors must share the same source-tower own-axis frame, datum and core pose. Floor support and dry volumes remain separately registered; this helper does not mark outdoor land/water or teleport actors.

`source_stair_gates.gd` extends the tested interlock and accepts only completed explicit-core modules. It re-derives the full portal contract, checks exact pose/routes/aliases and actual receiving heights/generation, then places each stair's leaves/frame under its rigid pose. Native opening/closing occupancy, static-leaf sweep, source-generation and retirement guards are inherited unchanged. Both independent leaves and both stair aliases are required. `geometry_descriptor()` explicitly marks its gate coordinates stair-local and supplies the stair-to-floor transform plus floor-local approach point; legacy callers must not interpret those points as old common-axis coordinates.

This is not yet wired into FloorStack, Hotel or the default SourceWorld. The source floor planner must retain every room/program and supply source-conforming geometry before that coupled change. Native fixture authoring is in progress. Native parsing, rotated continuous Player traversal, low-height rear-landing headroom, actual receiving-floor dependencies, moving gates and rendered appearance remain pending; no component result is invented while the Studio streaming guard prevents engine launches.
