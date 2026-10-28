# Source-world context component

Status: **parent R1 and R2 FAILED**. R1 recorded446 successful checks but an unchecked QA `.status` access raised a script error. R2 recorded452 checks, one strict ceiling-block failure and another fatal unchecked `.support` access. R2 diagnostics established that the native ray/capsule did find supported blocked clearance and both query/save validated; the observation map was rejected before composition because its newly dot-assigned provider key did not have TYPE_STRING. Current R3 normalizes only String/StringName exact known provider names and tests explicit named keys and newly dot-assigned maps. The restore API retains its `invalid` tag and native ceiling/support checks remain strict. **R3 runtime and independent review remain pending.** No engine, GPU, UI, Git, shared Player/main/Game-save edit, service or purchase was performed by this builder.

The full goal remains all of Singapore and an explorable MBS recreation. This is the context/semantics stage required by [the migration contract](../source-world-migration/CONTRACT.md); it does not replace the fictional bootstrap or finish the city, terrain, interiors, streaming, recovery, animations or actor rebasing.

## Identity and coordinate contract

`game/src/world/geography/source_world_context.gd` composes the frozen `source_frame.gd` API. `configure(frame, geometry_manifest_sha256, vertical_manifest_sha256, restore_profile, physics_world)` succeeds once. The frame must already contain the exact uncompressed EPSG:3414 frame, source-manifest hash and explicit elevation-reference metadata. Geometry and vertical-manifest hashes identify declared input versions; neither a hash nor this module proves a surveyed datum, source rights, real terrain or as-built/private geometry. Synthetic QA manifests are explicitly labeled fixtures.

All canonical source positions, volume bounds, contacts and normals use double-valued Array/PackedFloat64Array inputs. The context normalizes stored positions to double Arrays. It never makes an absolute engine Vector3 before subtracting the active origin; `begin_query` delegates projection to the frame's checked sample API. Native vectors are immediate local physics values only.

The context keeps its frame object, source snapshot, geometry manifest, vertical manifest, restore-capsule profile and optional `World3D` identity. A null World3D supports data-only classification, never trusted physics or a ready restore. Its registered providers and floor records cannot be replaced. Registry additions increment a revision and invalidate earlier queries. A genuinely changed geometry/frame/provider catalog needs a new context and an explicit handoff, not mutation disguised as the same data.

## Public APIs

| API | Result and responsibility |
| --- | --- |
| `configure(...) -> bool` | Immutable identity and explicit restore profile/world. `metadata()` returns detached descriptions, including `elevation_verified_by_context=false`. |
| `register_provider(kind, provider_id, source_reference)` | One explicit adapter descriptor for `territory`, `land`, `water`, `physics`. No callback invocation, fetching or automatic provider choice. |
| `register_floor(definition)` / `floor_record(feature_id,floor_id)` | Immutable named floor, collision-geometry hash, stable support IDs, canonical 3D volumes with explicit dry flags, and provenance. Architectural identity is independent of loaded collision. |
| `begin_query(source_xyz)` / `validate_query(query)` | Query bound to context/frame/snapshot/profile, registry/origin revision, checked local sample, physics tick, physics space, canonical point and checksum. A stale/foreign query is an error requiring a new query, never evidence of outside-city/void. |
| `bind_observation(query,kind,state,payload)` | Typed envelope/checksum helper for an adapter's **fresh** result. Not a signature, provider authentication or substitute for querying physics. |
| `evaluate(query,observations={})` | Independent territory, land, water, residency, support, clearance, indoor and unresolved states. Missing/malformed/stale observations stay unknown. |
| `make_collider_stamp(feature_id,floor_id,support_id,residency_token)` | Returns metadata for an owned collider after the caller commits its actual geometry/transform to physics. It does **not** stamp or move any object. Metadata key is `Context.COLLIDER_META`. |
| `make_restore_pose(source_xyz,heading,feature_id,floor_id,room_id="")` | Source pose data with frame/snapshot/elevation identity plus geometry/vertical/floor-geometry hashes. Requires a named registered floor containing the point. No Game save/file write. |
| `validate_restore_pose(saved)` / `prepare_restore(saved)` | Reject implicit dataset/legacy-save migration. Cold missing floor is `pending`; known changed floor geometry is `blocked`; a valid locally projected target returns `query_required`. Validation failures in `prepare_restore` are `ok:false,status:invalid,error:...`. |
| `preflight_restore(saved,query,observations)` | Always tagged: `ready`, `pending`, `blocked`, or `ok:false,status:invalid,error:...` for invalid input/query. Ready requires current resident supported floor, correct IDs, capsule clearance, covered territory, and dry/above-water 3D classification. The result carries the current checked sample and physics tick; it applies nothing. |
| `prepare_transition(new_origin,current_samples)` | Pure frame plan plus checked cache previews. No origin commit or movement. |
| `activate_transition(transition)` | Checked cache samples only after root explicitly commits the exact frame plan. No body/camera/cache assignment, stamping or movement. |

All returned dictionaries/arrays are detached. Checksums catch accidental mutation and context/epoch mistakes; they are not an adversarial same-process security boundary. The context is a single-owner main-thread component, not a thread synchronization primitive.

Provider-kind names accept Godot `String` or `StringName` and normalize to an exact canonical String from the four-kind allowlist. This includes observation maps assembled using `observations.physics = ...`. No arbitrary coercion, case folding or whitespace trimming occurs; non-name keys, unknown names and duplicate normalized names are rejected. All source identities/checksums and state payload validation remain unchanged. R3 records the actual key Variant types in `metrics.native_dictionary_provider_key_types`; it also tests explicit `&"physics"` independent of the engine's dot-key spelling. Godot documents [Dictionary dot/index access](https://docs.godotengine.org/en/stable/classes/class_dictionary.html) and the separate [StringName type](https://docs.godotengine.org/en/stable/classes/class_stringname.html).

## Independent domain states

- Territory: `inside`, `outside`, `unknown`. Administrative coverage never asserts land or physical support.
- Land: `land`, `non_land`, `unknown`. Land says nothing about floor/terrain elevation, current collision or capsule clearance.
- Physics residency: `resident`, `unloaded`, `unknown`. A missing cache/chunk is neither outside-country nor unsupported void. An unloaded observation cannot carry a contact.
- Support: `supported`, `unsupported`, `unknown`. Unsupported is an actual resident-query result; it does not trigger death/recovery. Stale/invalid contacts become unknown.
- Clearance: `clear`, `blocked`, `unknown`, bound to the configured profile and the live physics tick.
- Water: `dry`, `submerged`, `above_surface`, `dry_indoor`, `unknown`. A water column has a finite bottom/surface and matched horizontal coverage; below its known bottom is unresolved underground, not an invented sea plane. Dry indoor volumes have canonical XYZ bounds, so they do not exempt the same footprint above/below the floor. Conflicting floor identities remain ambiguous until live support disambiguates them.

A registered, dry, physically supported basement below `Y=-8` can be ready even when land classification is non-land or unresolved and an exterior sea column covers the same XY. A dry architectural volume alone cannot make collision resident or authorize restore into empty space. There is no Y death plane, origin clamp, invented ground or `ignore_bounds` flag here.

## Floor and provider payloads

Floor definition keys are exact:

```text
feature_id, floor_id, geometry_sha256,
support_ids: [stable collision IDs...],
volumes: [{volume_id, min_xyz:[x,y,z], max_xyz:[x,y,z], dry:bool}, ...],
provenance: explicit source-supported/reconstructed explanation
```

Floor volumes are **architectural envelopes, not country/coast/terrain polygons**. Conservative box unions are supported in this first component. Do not use a building footprint stretched through all floors as proof that its underground/atrium/roof regions are dry and occupied. A complex polygonal or flooded volume requires a precise future provider rather than a falsely broad dry registration. The current floor scan is intended for a bounded active architecture catalog; it is not a national spatial index or an unbounded streaming implementation.

Provider state/payload pairs:

```text
territory: inside|outside|unknown, {}
land: land|non_land|unknown, {}
water: dry|unknown, {}
water: water_column, {body_id, bottom_y, surface_y}
physics: unloaded|unknown, {}
physics: resident, {
  residency_token: current collision-generation string,
  clearance: clear|blocked|unknown,
  support: {state: unsupported|unknown}
        OR {state:supported, feature_id, floor_id, support_id,
            collider_instance_id:int,
            contact_source_xyz:[x,y,z], normal_source_xyz:[x,y,z]}
}
```

The territory/land/water adapters must check source coverage and versioned actual data. `water_column` asserts that **this query** is within the specified water body's actual horizontal coverage; the context then applies bottom/surface in 3D. A provider's `dry` result must reflect complete relevant hydrology at that point, not merely a miss in one body/cache. Where coast/inland water/terrain/tidal reference is unresolved, return unknown. These adapters do not exist merely because their descriptors register.

The actual physics adapter must guarantee all of the following before calling `bind_observation`:

1. Execute a new native support query and capsule-clearance query in the query's exact World3D at the same controlled physics boundary/tick. Do not rebind old hit dictionaries, trust `is_on_floor` from a prior relocation, or treat expected floor boxes as physics contacts.
2. The whole required collision neighborhood is committed/resident, including floor, walls, ceilings and a safety margin for motion. An optimistic floor-only load is not a resident capsule neighborhood. The token must identify that collision generation and change when it is unloaded/rebuilt.
3. Test the exact configured capsule dimensions, offset, orientation/scale policy, collision masks and shape exclusion policy. The initial profile models a world-up upright capsule. A profile or actor orientation outside that contract needs an appropriate adapter/profile, not a `clear` assertion from the wrong shape. Clearance must be nonpenetrating and include doors, ceilings and relevant dynamic obstacles.
4. Return the native live collider and contact/normal converted from current local physics to canonical source doubles through the active frame. Resolve stable feature/floor/support identity from the source collision registry, not proximity or a decorative mesh name.
5. After the integrator has really committed that collider and transform, attach `make_collider_stamp(...).stamp` to that owned collider under `COLLIDER_META`. Never refresh a stamp first to make an old body appear rebased. The context checks live instance/tree/nonzero collision layer, physics space, source/frame/geometry/vertical/profile identity, origin/revision and floor-geometry/residency token, plus finite unit normal and bounded foot/slope offsets.

Those validations reject stale/context-mismatched evidence, but **cannot prove an arbitrary same-process adapter really performed its native queries**. The native QA adapter demonstrates the expected ray/shape-query pattern. No assertions here certify full collision residency, all supports, bridges, flood state or national terrain.

The restore profile has exact keys `profile_id`, `radius_m`, `height_m`, `center_offset_xyz`, `min_support_normal_y`, `max_support_drop_m`, `max_support_rise_m`, `max_support_lateral_m`. Build it from the actual runtime actor shape and policy. Current Player source uses radius .36, height1.75 and offset[0,.9,0]; the fixture mirrors this shape without instantiating or exercising Player's existing recovery.

## Root integration sequence

1. Create the true source frame and context from actual immutable source, geometry and vertical-version manifests. Keep unknown/reconstructed provenance visible. Install real coverage/coast/3D-water/streaming-physics adapters. Do not make this component a permanent second fictional world or automatically switch normal gameplay to an incomplete patch.
2. Register actual active floor/envelope/support identities before creating source saves. Place production geometry after origin subtraction. Commit floor/neighbor collision on the main physics thread, then stamp the **actually committed** owned colliders with their current residency generation. Source registries remain distinct from collision residency.
3. Replace Player's hardcoded negativeY recovery and helicopter's negativeY/clamp decisions through the coupled context policy. On unknown/unloaded state, hold safe motion and request residency/prefetch; do not kill/teleport, invent ground or fall through empty chunks. Native support and dry indoor volumes permit real basements. Keep support-required policies separate from ordinary airborne flight.
4. At save time derive feature/floor IDs from fresh valid physical support. Wrap canonical pose with `make_restore_pose`. Preserve all existing owner save bytes. Version1 fictional local coordinates cannot be reinterpreted as source positions; no automatic migration is provided.
5. At cold restore, call `prepare_restore`; load the requested floor identity and collision neighborhood while keeping the current safe actor unchanged. Request a fresh query/adapters. At the controlled application boundary, call `preflight_restore`; only apply a `ready` result on that same physics tick/revision and after last-moment dynamic clearance/residency checks. Re-run preflight after any yield/commit. A returned dictionary is not a durable permission ticket.
6. For rebases, collect **every** retained checked local sample and all actual actor/camera/FX/target/traffic/interpolation/support state. Purely prepare/validate the frame plan and all previews, stage physical transforms, then commit and update all consumers atomically at one controlled boundary. Re-stamp only truly rebased colliders, activate cache previews, invalidate old observations, and query support again. Context functions move nothing and cannot prove that all consumers were enumerated.
7. Run normal exterior/bridge/door/interior/roof/flight and cold-load routes with source names/identities across seams and repeated rebases. Test actual Player/aircraft/NPC recovery, floor support, whole-neighborhood residency and owner-save preservation. This isolated fixture is not those integration gates.

## Parent-run QA

Run sequentially through the task's existing engine driver, using a **new** evidence directory and session:

```sh
bash loop/singapore-fidelity/run_engine.sh source-context-r3 75 \
  /private/tmp/singapore-fidelity/source-context-r3 -- \
  --headless res://src/systems/fidelity_tests/source_context_test.tscn -- \
  --qa-session /private/tmp/singapore-fidelity/source-context-r3/session
```

The scene has a45-second internal watchdog. It loads the actual source frame/manifest identity and tests typed invalid input, independent domain unknowns, indoor 3D exclusions, cold restore/version/floor waits, stale query/contact context/snapshot/origin/tick, pure checked-cache transitions, and no implicit actor movement. It creates only its own small native slab/capsule/ceiling fixture. The capsule settles aroundY=-20; the prospective restore root is5cm above that settled pose so native capsule clearance is nonpenetrating while its support ray still reaches the same slab. A real ceiling overlap must block restore. This is a source-context test, **not a production Player/basement route or rendered scene**.

The report writer requires a fresh owned explicit private session, rejects symlink ancestors, dangling/existing report leaves, rechecks before writing, and uses only owned sentinels for negative fixtures. This is not OS-level `O_EXCL` or protection from an adversarial same-user path swap after the final check. All QA evidence stays separate from owner saves.

Require both clean supervisor/engine logs and the report's check results. Green arithmetic assertions do not override a script error. The earlier source-frame R1 bool/float error remains a failed historical run; source-frame R3's clean456 checks are a separate frozen component result and do not certify this new context.

The context's failed R1 and R2 evidence is preserved at `/private/tmp/singapore-fidelity/source-context-r1` and `source-context-r2`, with selected facts in `R1_FAILURE.json` and `R2_FAILURE.json`. R2 exposes the rejected provider map and correctly retains a strict native ceiling assertion failure. R3 must satisfy that test, finish the old-collider/native-no-movement gates, and exit with clean supervisor/engine logs. An error result in the final support assertion is now safely a failure rather than a fatal property access.
