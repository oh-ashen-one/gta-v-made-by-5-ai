# Physical MBS cabin component

Status: parent R1 parsed and ran without a script fatal, but **FAILED at15 checks** while waiting for the absent upper floor. The cabin correctly remained held open as obstructed after the fixture blocker was removed; no full ride was reached. Current R2 corrects the intended landing-door exclusion assignment and adds paired same-tick native overlap/shape/bounds diagnostics. It is **not yet run**. This builder ran no engine/GPU/UI/Git. All four agent slots were occupied during initial review, so no independent critic was spawned. Parent runtime/visual verification and independent review remain required before integration acceptance.

Owned new files are `game/src/world/mbs_interior/cabins.gd`, `fidelity_tests/mbs_cabin_test.gd/.tscn`, and this directory. Existing context/runtime/public/guest/program/main/actor/save files are unchanged by this builder. The broader source Singapore/MBS goal remains open.

## Source placement and descriptor

One `Cabins` Node3D builds one shaft, physical moving cabin and interlocked landing safety grilles. Root may create multiple shafts using the same component. Root supplies the final upright unit parent source transform; all descriptor coordinates are already local metres after origin subtraction. No global canonical Vector3 is constructed here.

`Cabins.inventory_descriptor(tower,wing,kind,initial_floor_id="")` reads the actual current inventory's fixed vertical core axes and explicit relative `elevation_m` values, including B5 and terminal L57. It rejects changing core axes. It does not invent a uniform height step or compress travel. Current T3-L5/L6 elevations are15.35/18.8m; T3-B5/L57 are−22.5/194.75m. These remain **reconstructed relative vertical geometry, not a surveyed datum or private as-built lift system**.

Descriptor exact keys:

```text
{
  schema:"mbs_physical_cabin_v1", shaft_id:String,
  center_xz:[local double x,z], entry_sign:+1|-1,
  initial_floor_id:String,
  stops:[{floor_id, elevation_m, label, portal_id, kind, height_status}, ...],
  speed_mps:finite .2..5, acceleration_mps2:finite .2..3
}
```

Stop kinds are `guest_lift` or `service_lift`; IDs are unique, elevations finite and distinct, and the initial ID must exist. Supported local coordinates/elevations stay within±2048m. The helper's default speed2m/s and acceleration1.25m/s² are explicit game reconstruction choices. Coincident levels need a parent alias plan; dimensions or floor heights are not silently adjusted.

The current geometric reconstruction uses a2.20×2.80m cabin,2.70m clear height and1.30×2.35m gate. The plate/wall/ceiling envelope is set back from the existing fixed-core frame so it can physically pass closed landings; its floor threshold gap is12cm, to be verified with the actual production capsule in QA. Dimensions/clearances are not factual MBS measurements. It reuses the existing Kit, granite/timber/bronze materials and native door concept; no human animation, asset service, purchase or generated model is involved.

## Runtime interfaces

1. Add a new cabin node under its final owned source parent, then `build(descriptor, ready_for_floor_callable)`. The whole descriptor validates before children/state are built. Initial body transforms are supplied before entering physics, not warped from world zero.
2. `bind_floor(id,node,portal_id)` binds an actually built GuestFloor/ProgramFloor via its native `transition_requested(floor_id,portal_id,kind)` and `confirm_transition_ready` APIs. It checks physics world, expected cabin center and threshold alignment. The node/portal must match the descriptor and be in the tree.
3. `request_floor(id)` queues a physical trip/call. It never touches an actor. The native landing E door dispatches this through the floor signal. The cabin's normal E panel opens a scrollable stop list; click a floor, or press E again to confirm the focused default next stop. Esc closes. Emergency stop and explicit safety retry buttons are included. Mouse mode is restored on close. Root should route general gameplay/UI input consistently with its main HUD; this isolated component does not rewrite Player's input router.
4. `floor_requested(shaft_id,id)` tells root to call its asynchronous floor streamer **outside the physics callback**. When loading/physics commit finishes, root binds that floor and its readiness becomes true.
5. `arrived(shaft_id,id)` means stopped and native-aligned with a ready floor; gate animation begins from there. Root must still wait for actual open gates for traversal. `state_changed` and `report()` expose waiting, motion, emergency, queue and native blockage diagnostics.
6. `unbind_floor(id)` is the explicit pre-unload handshake. It refuses an open landing and an active moving destination. Root must pin cabin destination, occupied floors and required neighbors. Keep floor/door collision until all passengers have cleared and the landing closes. An invalid freed old binding can be replaced only after its owned landing grille closes.

### Exact synchronous readiness callback

The callback is a **nonblocking observation**, not an async load:

```text
ready_for_floor(id) -> {
  ready:bool,
  floor_id:exact requested String,
  collision_generation:nonempty String,
  travel_ready:bool
}
```

No additional diagnostic fields belong in this four-field adapter result. Root can retain richer floor-stack diagnostics separately. Unknown/malformed/unbound states hold doors closed and request the floor.

`ready` must mean destination floor, landing and required collision neighborhood actually committed, with a retained collision generation. The floor-stack worker correctly keeps its own `travel_ready:false`; floors alone do not prove a shaft. Root composes `travel_ready` with `cabin.shaft_collision_ready()` and its path/floor pin policy. That helper requires at least three physics ticks after build, upright unit placement and all owned body RIDs belonging to this World3D. The cabin internally checks that helper as well. A fresh native body sweep tests each real motion step against relevant world collision.

Do not return ready from a file/cache/node existence check, silently unbind/unload while a gate is open, or declare a missing neighbor safe. A provider that revokes/removes collision while a passenger stands across its doorway violates the retained-floor lease; root must preserve/restore that collision, not rely on a door closing to repair absent ground.

## Physics and safety behavior

The cabin floor/walls/ceiling share one layer1 `AnimatableBody3D`; moving gate leaves also use layer1 bodies. Initial setup and each physics step submit **one complete Transform3D per body** using independent commanded scalar state, preserving the known `sync_to_physics` setter requirement. No actor position, transform, respawn, teleport, velocity adjustment or reparent call exists in the component. Normal CharacterBody3D platform mechanics must carry the player; QA measures that actual behavior.

Departure requires physical native cabin/grille closure and the bound floor's actual hinged-door command/native orientation closed. Gate closure is checked relative to the actual cabin transform, not an ahead-of-physics command position. Every landing grille stays behind the existing E door, preserving that door's interaction ray while the lift is absent.

Open gates require stopped, native-aligned cabin and resident floor. Only the occupied aligned landing opens; all other shaft apertures retain physical grilles. A threshold shape query excludes the component's own gates/enclosure and the external landing leaves while detecting actors/foreign obstacles. A blocked doorway reopens at its safe landing, retaining the queued request. A two-second dwell permits actual exits before queued calls depart.

Motion uses actual elevation difference, bounded acceleration/braking and incremental y steps. A missing collision/travel lease, invalid placement, delayed physics step or blocked native sweep causes an emergency hold, never a destination snap. Manual retry rechecks readiness and closed doors before continuing from the held height. Game simulation pause holds cabin motion. The native sweep excludes this component's own shaft/gates (which deliberately overlap moving gate pockets) but tests external floor/world blockers; whole-cabin dimensions must continue to clear actual loaded architecture.

Root still owns source-world dynamic support/dry-volume registration for moving cabins, actor canonical state, floor/room identity while between landings, bridges, source-origin rebasing, save/reload, occupied-floor pinning, full-shaft manager scheduling and UI integration. Do not treat a guest-floor registry entry as a permanently correct cabin support identity mid-shaft. No source/city/whole-building or NPC-passenger completion is claimed. Multi-shaft rendering/physics cost is not measured.

## Parent-run verification command

The helper has not been executed by this builder:

```sh
bash loop/singapore-fidelity/cabins/run.sh mbs-cabin-r2
```

It invokes the existing sequential task driver with a180-second supervisor limit, headless scene `res://src/systems/fidelity_tests/mbs_cabin_test.tscn`, and fresh `/private/tmp/singapore-fidelity/mbs-cabin-r2/session`. The scene has a150-second watchdog and guarded fresh report path. Use another tag on rerun; never overwrite evidence.

Prepared QA builds actual GuestFloor T3-L5 and initially leaves L6 genuinely absent, uses production Player with exactly one declared initial spawn, calls via native E, walks in/out, selects trips through the native E cabin panel, waits for missing floor collision, then builds/binds L6 and rides up/down through native platform motion. It measures incremental player steps, actual platform velocity, support fraction and cabin/player height offset. It also exercises a doorway obstruction, actual ceiling sweep stop, explicit safe resume and native E queued return. No actor pose assignment occurs after initial spawn. This is a local physical fixture, not actual source-site/city or basement Player recovery proof.

Require the complete report plus clean engine/supervisor logs; a green partial count never overrides a script error, premature exit or uncompleted native gate. Root should independently review code and actual renders after the sequential native run. All present runtime/performance/visual gates remain **unverified**.

## R1 failure and R2 native diagnostic

R1 evidence remains `/private/tmp/singapore-fidelity/mbs-cabin-r1`: engine/supervisor exit1, no script fatal, child reaped,15 checks with the absent-floor wait failure. The production Player had walked to(23.80592,15.32585,−13.90717), about1.44m behind the threshold. The failed wait never established upward/downward platform carry. Selected facts are preserved in `R1_FAILURE.json`.

The code assigned `query.exclude` to owned RIDs, then called `query.exclude.append(bound_door_rid)`. Godot documents that [PhysicsShapeQueryParameters3D.exclude returns a copy](https://docs.godotengine.org/en/stable/classes/class_physicsshapequeryparameters3d.html); modifying that returned array does not update the property. Thus the intended external landing-leaf exclusion was not installed. An open SwingDoor leaf can overlap the full doorway sensor at its edge. R1 did not record native hit IDs, so its exact overlapping body is not claimed as measured there.

R2 builds the complete intended exclusion list locally and assigns the property once. It changes no sensor dimensions, collision mask, actor pose, residency gate or physical interlock. A same-tick paired query records both the previous effective owned-only filter and the intended filter, including body IDs/RIDs, collider shape IDs/names/classes, native and node origins, relative cabin poses, native box/capsule bounds and expected/actual exclusion counts. This identifies whether the removed false positive really is the bound external leaf or another object; it does not silently filter foreign floor geometry or actors.

The positive blocker assertion now requires that the controlling query actually identifies `QaDoorwayObstruction`. After actual fixture removal, the controlling query must be empty while the paired legacy filter must identify the external leaf. The original cold-floor wait and every native platform/door/ceiling/lease/queue assertion remain unchanged. These R2 diagnostics and all uncompleted ride gates require the fresh parent run; no successful ride is inferred from the source repair.
