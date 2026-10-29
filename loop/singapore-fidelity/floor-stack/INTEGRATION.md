# Actual-source floor stack — frozen component, native gate pending

This is new floor streaming for the active unbounded Singapore/MBS goal. It is not a new four-hour pass. The worker changed only `floor_stack.gd`, the new dedicated test/scene and this folder. No engines, GPU, UI, Git, protected factories/site/context/runtime, accounts, assets, purchases or user save files were touched. Root must commit frozen code before its normal helper run and obtain actual results/critique before acceptance.

## Common source authority and configuration

Add a fresh `FloorStack` to the same live World3D and call:

```gdscript
var ok = stack.configure(frame, context, runtime, 0.0,
    "Reconstructed MBS hotel L1=0; external surveyed vertical datum unresolved",
    {"max_active_floors": 6, "max_pending_requests": 3, "auto_stream": true})
```

The base elevation is required and finite; the caller supplies its datum provenance explicitly. Zero is the current staged L1 reference, not surveyed height or Skadi/EGM96 conversion. Frame, Context, Runtime and World3D must be the same actual objects; duplicate stack geometry authorities in one context are refused. Unit metres are required. The stack never commits a SourceFrame origin, rebases, translates an existing floor, reparents/relocates an actor, assigns actor velocity or touches a save file.

Hotel T1/T2/T3 anchors use the actual double-valued `site_reference.DATA.towers[].centroid_world_xz`, original OSM way IDs and common south/bayward double basis arrays. Canonical anchors remain arrays. Only after `frame.to_local()` subtracts the current origin is a Vector3 assigned to the owned floor node's global transform, before factory construction. Projections are epoch-checked before and throughout native commit. Old-epoch retained floors fail closed with a root-transaction state; this component does not implement the root's floating-origin transaction.

The factory record is copied, retaining IDs, facts and upper-floor atrium voids. The actual adjacent inventory elevation difference replaces only the copied `storey_height_m`; terminal program floors use receiving-only stairs. Hotel L1 perimeter recipes activate an explicit historical40/20/10m atrium void so loading L1 does not add a low slab/ceiling across the public loft. That is an explicit reconstruction adaptation, not a current survey. Root still owns actual openings/doorways joining those perimeter programs to the public envelope and can supply complete `geometry_overrides` by floor ID.

## Loading, readiness and limits

- `await ensure_floor(id)` preflights the requested floor and immediate previous/next inventory levels before constructing. It serializes lifecycle mutations, bounds pending requests and live floor count, and evicts only safe unneeded floors. Fresh GuestFloor/ProgramFloor nodes actually build; no plan is substituted for a loaded floor.
- Native readiness waits at least three physics boundaries, validates every owned collision body's actual World3D/RID and static pose, waits for restored door poses and probes both real corridor floors in physics. It registers source geometry, then commits the complete actual collision body set and static support stamps through Runtime, waits another boundary and checks again. No cache-only readiness.
- `floor_ready(id)` is synchronous and requires current-epoch native commitment of that floor **and both actual immediate neighbours**. `get_floor(id)` returns only a locally committed node. `floor_state(id)` reports current readiness, source anchor/way ID, neighbours, actual floor probes, body/support count and generation.
- `ready_for_floor(id)` returns exactly `{ready: bool, floor_id: String, collision_generation: String, travel_ready: false}`. The generation comes from an actual runtime support stamp and changes on cold reload. It never asserts shaft/cabin travel readiness.
- Defaults are six active floors and three bounded pending requests; supported cap is3–12floors,1–4requests. Auto streaming can request the nearby source Player/Helicopter floor at a bounded cadence/backoff, but cannot invent missing source data or exceed protected capacity. Missing data is a transient non-ready state.

The root must load/retain the adjacent destination and hold unavailable **outer** stair connections before traversal. Immediate-neighbour readiness is not transitive readiness for every building level. Source Runtime regions describe complete owned floor neighbourhoods, not national/city geometry outside the owned floor assembly. The caller must compose the real world streamer and actual movement/transition boundaries. No whole-world or performance acceptance follows from this component.

## Collision and dry-volume registry

The body list enumerates every owned nonzero-layer CollisionObject3D, including animated landing/room doors. Only stable StaticBody3D paths receive support IDs; a vertical door is not a floor. Static support stamps are checked live before reporting ready. Ordinary moving doors need valid current physics RIDs without falsely requiring an idle transform; restored poses are settled at initial load.

Canonical upright OBoxes are created from actual built wing rectangles, core-approach floors and the exact bounded U-stairwell footprints. Pool holes are subtracted from program-wing dry rectangles. No dry box spans the entire atrium void, whole rotated-site AABB or pool footprint. The broad runtime residency bounds are never substituted for dry architectural volumes. Canonical axes/centres stay double arrays until projection; no absolute Vector3 is used to define source boxes.

Floor registrations are immutable architecture data, retained after unload by SourceContext. Reload must match the registered geometry/support IDs, else a new context is required. Geometry identity uses the root's explicit context geometry manifest plus copied recipe/placement/volumes/datum; it does not rely on stripped GDScript source introspection in PCK builds. Root must provide a correctly versioned geometry manifest.

## Retirement, occupancy and cabin coordination

`await unload_floor(id)` refuses protected occupancy, stair neighbours, pins, in-progress mutations, live transition doors and invalid/refusing root unload guards. Bound source Players and Helicopters are detected read-only; manual `set_actor_floor(actor,id)`/`clear_actor_floor(actor)` claims and `pin_floor(id,owner)`/`unpin_floor(id,owner)` protect the requested floor plus immediate neighbours. Pins remain the root's responsibility during cabin/pilot transitions. A mixed-origin epoch with bound actors refuses retirement rather than inferring wrong occupancy.

Use `set_unload_guard(root_callable)` when connecting cabins. The root's composite guard must call `cabins.unbind_floor(id)` only for controllers whose `report().bound_floor_ids` actually contains the ID; unserved/unbound controllers returnfalse. The guard runs after occupancy/pin checks. It must close/interlock actual landing doors and refuse active/open/moving destinations. The stack then retains pure door state, calls `runtime.retire_region()` **before** emitting `floor_retired` or `queue_free`, and waits for native destruction. It never frees a protected floor to satisfy the cap. Scene teardown also retires owned region tokens before owned-node destruction; root controls actor/cabin teardown order.

Cabin `floor_requested` should trigger the async load from the root, not await it inside a physics readiness callback. Root combines the exact synchronous floor result with `cabins.shaft_collision_ready()` and its own retained shaft/cabin geometry proof. Keep `travel_ready:false` until that conjunction is actually true. No floor-only result may authorize a cabin route.

## Pure door data and source mapping

`serialize_state()` produces only versioned floor-ID door data, including current loaded states and retained unloaded states. `restore_state(data)` validates inventory identity, bounded IDs/booleans and excludes transition-door revival; it is accepted only on an empty, idle configured stack. Root owns source-pose/context save validation, safe bytes, disk writes and migration. No local transform is saved.

The27resort records require explicit root mapping; the stack does not use ProgramFloor's invented geometric fallback. Supply `resort_mappings` at configure or `install_resort_mapping(floor_id, mapping)` before that floor identity has registered. Each mapping requires `source_anchor_xz` as a two-number double array, unit/right-handed `axis_x_xyz`/`axis_z_xyz`, complete `geometry` and provenance. Y is the explicit common base plus inventory elevation. Missing/partial/unsupported mapping returns transient `pending_root_source_mapping` or recipe-change status without a permanent placeholder.

The six hotel B2/B2M recipe intervals have only2.5m actual inventory rise while current complete recipes need3.28m clear-height+slab. They return `pending_root_recipe_change` with IDs/rise/required headroom before construction. Root has chosen **partial mezzanine platforms/vertical zones**, not flattened overlapping full floors. The independent static audit lists all six affected rows. These reconstructed inventory assumptions can be revised by the root; no survey claim is made. Recessed roof pools also require root coordination with L56 ceiling/structure and water behavior; this loader/fixture does not certify that clearance or swimming.

## Root native gate

Commit frozen code first. Only use the **current** shared/private lease helper; no raw/unleased engine command and no old four-hour wrapper:

```sh
bash loop/singapore-fidelity/run_engine.sh mbs-floor-stack-r1 900 /private/tmp/singapore-fidelity/mbs-floor-stack-r1 -- --headless res://src/systems/fidelity_tests/mbs_floor_stack_test.tscn -- --qa-session /private/tmp/singapore-fidelity/mbs-floor-stack-r1/session --mbs-floor-stack-report=/private/tmp/singapore-fidelity/mbs-floor-stack-r1/report.json
```

The fixture shares the real national domain, source frame/context/runtime and existing source public site. It performs actual cold native commitments for spa-void/roof-pool dry exclusions, then two full adjacent guest levels T2-L24/L25 at the true source basis with the origin at `[441.6952525684337,80.9,-1046.407586580947]`. It checks no premature/shaft readiness, duplicate authority rejection, transient missing resort/mezzanine data, all actual source anchors, static-only stable stamps, native E/LOS, real Player room/stair ascent/full receiving floor/descent, occupied/neighbour/pin/callback guards, bounded LRU, generation changes and actual retire-before-free stamp removal.

For door reload, the remote **empty** T3-L24 state is explicitly seeded through its factory API while the actual Player stays at T2. This is pure state-fixture setup, not a claimed native E action at a remote actor position. Actual native E is exercised separately at the Player's real source room. There is one labeled initial actor setup and no relocation/reparent/rebase during tracked walking. The fixture does not prove exterior-to-upper-floor continuity, every level, cabin travel, pilot landing, water/swimming, mezzanine resolution, visual fidelity, performance or owner play.

Worker checks so far: independent Python double source/inventory arithmetic and readable JSON only. No engine compile/native/render pass yet. `STATIC_SOURCE_GEOMETRY.json` is source arithmetic, not residency/collision proof. Root's actual results and fresh review must supersede this pending state without erasing failures.

Final source-ID review corrected guest door JSON validation: inventory guest IDs are `R-T2-L24-01`, with exact `-bath` and suite `-bedroom-N` derivatives, rather than only a floor-ID prefix. Native fixture now accepts a legitimate R-prefixed unit state on an empty stack and rejects another floor's unit without partial mutation. Restored metadata cannot assert private as-built verification. This is pure door data; it never opens a remote door to bypass the actual native E route.
