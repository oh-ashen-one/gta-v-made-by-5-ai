# Independent source context/runtime review

Reviewed 2026-10-28, read-only except this review. Current inherited Codex model; no alternate-model claim. No Git, engines, GPU, UI or services were used by this reviewer. The root owns implementation, running QA and integration.

**Decision: do not install this adapter in the normal world yet.** The isolated context/actor results are useful, but the P2 items below need resolution or an explicit enforceable integration contract. No new P1 was found. Full Singapore, complete MBS, Game v1 save/respawn migration and comprehensive actor/cache rebasing remain unfinished root work; they are not accepted by this review.

## Actual evidence checked

- `source-context-r3`: 478 checks, no failures; engine/supervisor 0, fatal errors empty, child reaped. Current context source matches that run.
- `source-actor-r1`: 19/20; unpiloted basement aircraft landing failed. This failure remains valid historical evidence.
- `source-actor-r2`: 20/20; engine/supervisor 0, fatal errors empty, child reaped. Actual production Player walked 8.568322m at approximately local X1500/Y-20, actual resting pose capture/restore succeeded, cold/unloaded state held the actor, and actual unpiloted Helicopter landed. Only the fixture's loaded lower extent changed from -24 to -40; the resulting larger complete-aircraft residency envelope is an honest fixture correction, not actor-code evidence for arbitrary underground worlds.
- `source-actor-r3`: FAILED, engine/supervisor 1, child reaped. Fatal: `Invalid call. Nonexistent function 'enter_vehicle' in base 'CharacterBody3D (Helicopter)'`. The report then records the bounded-test failure. The native production boarding method is `Helicopter.interact(player)`. This QA call-site failure prevents accepting the new actual boarding/negative-elevation exit test. Root was notified immediately; preserve R3 and rerun the corrected production call.
- Evidence roots: `/private/tmp/singapore-fidelity/source-context-r3`, `/private/tmp/singapore-fidelity/source-actor-r1`, `source-actor-r2`, `source-actor-r3`.

Reviewed current hashes, all matched actor R3 at inspection:

| File | SHA256 |
| --- | --- |
| `game/src/world/geography/source_world_context.gd` | `bdac6bf9350997a105e161826c8689ce050afbbedfb120bca3cd056da6cbc3f7` |
| `game/src/world/geography/source_runtime.gd` | `606467400783f444f82d07f817d7205bc5ed2a8b2c9ae5676c75e4107a0ce04c` |
| `game/src/actors/player.gd` | `f7ecb147582ab1d7c8d6faa5b0330aa97a8de4d421adc1786a00473b922d1f4b` |
| `game/src/actors/helicopter.gd` | `a28ef14aa65dd542b4ff4673a1f7d259d4ab579c247a376b3d05bf1f9e71895c` |
| `game/src/systems/fidelity_tests/source_actor_test.gd` | `c8becfe93a153d26d514b3262ac10d7e5a1f34d7450b309d9e1516823af1e9a7` |

The root is actively editing. Findings refer to this snapshot and the line references below, not later unreviewed repairs. R2 does not validate the newer runtime/heli exit helper.

## P2 findings, prioritized

### 1. A fully loaded neighboring region does not allow crossing its seam

`source_runtime.gd:94-106,124-135,168-177`.

`_resident` requires the full actor envelope to fit inside **one** region. With two complete adjacent resident regions X=[0,100] and X=[100,200], an actor centered at X100 fits neither region: Player requires +/-0.8m; aircraft requires +/-8m. `motion_allowed` therefore holds the actor in a dead band even though all required collision is present. This blocks ordinary travel across source chunk boundaries unless the future streamer creates a rigorously complete overlapping neighborhood rather than committing individual source chunks.

Overlapping envelopes also need care: `_resident` chooses the first containing region, while `_native_player_observations` recognizes a support only when its owning region token equals that selected token. A valid floor owned/stamped by the other overlapping region can be reported unsupported. `_supports` permits only one owner per body, so merely listing a neighbor body in multiple neighborhood body lists does not solve token selection.

**Repair/gate:** either implement coverage over the union of live regions plus native-contact ownership validation, or define and enforce neighborhood commits with collision halos and deterministic contact/region resolution. Run actual Player walking and Helicopter flight across two adjacent fully loaded cells in both insertion orders, then restore/capture a pose on the neighbor-owned floor. Verify no artificial hold or unsupported result. Separately unload one required neighbor and require a safe hold/pending result.

### 2. Losing a source runtime silently reenables legacy recovery

`player.gd:499-518`; `helicopter.gd:337-355,450-452,659-661`.

The only mode test is `is_instance_valid(source_world_runtime)`. Once a previously bound runtime is freed or lost, a source Player in a valid dry basement immediately reaches the old Y<-8 / fictional rectangle branch. A source aircraft below Y-3 can teleport to its old last-good/fixed fictional position. The same loss reenables the old sea clamp and exit-water test. This is a failure mode of an installed source actor, distinct from intentionally leaving the untouched legacy bootstrap on null.

**Repair/gate:** keep an explicit source-mode/binding latch or equivalent world-mode authority. A source actor with a missing/unconfigured runtime must hold and request recovery/rebinding; only an explicit validated migration may return it to legacy mode. Test ordinary initially-null legacy actors separately from source-bound actors whose adapter is freed, retired or invalidated. The latter must not die, teleport or use legacy water/bounds.

### 3. Capsule profile and actor binding are not enforced throughout query/restore

`source_runtime.gd:27-48,122-163,192-225`.

`bind_player` checks the actor basis, capsule resource dimensions and child position, but not the CollisionShape3D's own basis/scale or other enabled collision shapes. A production capsule child rotated 90 degrees or scaled independently can pass the claimed upright-profile bind. Later native queries simply select the first enabled capsule. Profile/binding is not revalidated at restore, and `inspect_player`/`restore_player_pose` do not require `actor.source_world_runtime == self` or the actor's World3D to equal this adapter's World3D. A foreign/unbound Player can therefore be probed against this runtime's physics world and have a pose applied in its different world; a different or subsequently weakened capsule can be used as the clearance probe while the observation remains labeled with the configured production-profile hash.

**Repair/gate:** one checked actor-binding predicate should enforce the current world/runtime relationship, upright unit actor and child transforms, exact enabled collision shape contract and dimensions/offset, and current native masks/policy as appropriate. Use it at bind and immediately before inspect/capture/restore/exit preflight. Reject foreign-world, unbound, rotated/scaled child, weakened capsule and extra enabled shape fixtures without moving the actor. A legitimate seated player's disabled collision layer/mask needs a deliberate exit-query policy, not an accidental weakening of the profile.

### 4. The new actor harness does not use the repaired private report-path guard

`source_actor_test.gd:24-28,149-151`.

The harness checks only a lexical prefix and whether the session itself presently exists, then calls recursive mkdir and opens the report without an ancestor/leaf recheck. A path containing `..` can retain the prefix while resolving outside it; a linked existing ancestor can redirect creation of a fresh session. The report leaf is unchecked at write time. This repeats the class of evidence-path problem already repaired in source-frame/context QA, although the recorded R1-R3 invocations used the expected owned paths.

**Repair/gate:** reuse the fresh normalized session/linked-ancestor/dangling-leaf/existing-entry guard and actual guarded writer already exercised by the other two scenes. Require successful output creation and complete write; do not report process success if a report failed to open/write. Use only owned scratch sentinels for the negative cases.

## Source-level repair received during review

The original source-helicopter exit bug was concrete: `landing_exit_position` rejected every negative-elevation candidate through `DowntownPlan.WATER_LEVEL + 0.15`, even when the new runtime correctly landed on a dry basement slab. Root changed the source branch to `runtime.landing_exit_safe(candidate)` and retained the old water check only for the legacy branch.

At the reviewed hash, `landing_exit_safe` does a canonical conversion, a fresh query, native production-capsule/support observation, named-floor restore-pose construction and current-context preflight. This is the right source-level replacement for the absolute-Y test. **Runtime verification remains open because actor R3 called nonexistent `enter_vehicle` before it could prove boarding/exit.** Correct that harness call, then exercise actual boarding, landing, candidate query and production exit at negative elevation with no position/Y rewrite. Apply findings 1-3 to this exit helper too.

## Important boundaries and additional integration gates

- The R3 String/StringName **kind** normalization is narrow and appropriate. It normalizes only those two native key types to exact known kinds, rejects arbitrary/duplicate keys, and keeps typed states and identity hashes. The clean 478-check run supports the repaired context path; it is not proof of a full source-world provider.
- Context support queries bind current source point, origin/registry/profile/world and physics tick. Native support and capsule clearance are queried synchronously before root applies a ready restore; there is no intervening await. Floor/geometry/vertical identity mismatches and cold missing collision remain blocked/pending. These are useful foundations.
- A floor's dry architecture envelope is separate from collision residency. This allows a registered supported basement to override an exterior sea column without treating an unloaded room as physical support. Broad AABBs still must not be registered as precise rooms or surveyed flood geometry.
- Dynamic collision-generation ownership remains an explicit loader obligation. `_resident` currently verifies body existence/tree/layer/world, not enabled shape-owner contents, collision-shape transforms or complete wall/ceiling residency. Before streaming integration, test disabling/freeing a floor/ceiling CollisionShape3D while retaining its body; never keep the old region generation advertised as complete after partial unload. Deliberate moving doors need current native clearance; an unloaded ceiling is not an open door. Retire/recommit before changing generation, or enforce equivalent loader/shape-generation checks.
- Source restores here move the actor only. They do not migrate Game's v1 file schema, health/inventory/checkpoint/mission state or whole-world cold-load sequence. Source death/recovery, vehicle wreck recovery and last-safe poses still require canonical root integration. Keep the owner's old save bytes intact.
- Rebase still requires all actors, runtime regions/collider stamps, top-level cameras, motion history, AI targets, FX and source consumers to migrate atomically. Old region origin revisions correctly fail closed after a frame commit; a complete restamp/region transition is not implemented by this adapter.
- The normal bootstrap still uses fictional/compressed geometry. None of these isolated checks accepts national source geometry, real road/bridge traversal, complete MBS interiors, exact private layout, default playability, final rendering or performance.

Policy routing was checked against cached published revision `a67557283f99`; `brain doctor` says not-recently-checked. No fresh cloud-policy verification, publication or shared infrastructure change was performed. This review is the only file written.

## R4 follow-up: original actor repairs exercised; two items remain open

Root supplied further implementation while this review was in progress. The earlier findings and failed R3 above are retained as history. The actual `source-actor-r4` run completed 2026-10-28T23:10:21.874646Z with **27/27, engine/supervisor 0, no fatal errors, child reaped**. Current files matched its source hashes at re-review:

| File | R4 SHA256 |
| --- | --- |
| `source_runtime.gd` | `f9db1a1748d4cafd37d2a6f3036aa46fa0597ceadc3af3cab73e78f987b6da9f` |
| `player.gd` | `c77fd881c2d8850d4de5396cb0c73333fa93f5e31766703eb06618e9fcb9dce0` |
| `helicopter.gd` | `5c70bf9c740c1c7ceaa05ca751eacd23cdee05e4a048fe2e874b51ab3f3980d3` |
| `source_actor_test.gd` | `82ab9a8bea3f1b11770f9775570d875337b7f94ff46a81c1f52b0534fb4788f0` |

Source-level review plus this native fixture closes the **original** seam/missing-runtime/capsule-child-orientation/negative-elevation-exit reproductions, within their tested scope:

- Runtime now subtracts complete live canonical boxes from the required volume, failing closed when uncovered pieces remain; it bounds work to 256 regions/4096 pieces. A swept current-to-target AABB is also required. The subtraction's six-slab decomposition is consistent for adjacent and overlapping positive-volume boxes; it does not replace coverage with a corner-only test. Support token selection now follows the actual native hit's registered region rather than first-region insertion order.
- R4 actually moves production Player from local X1495 across the X1500 seam, 8.5625m, without death or source-coordinate reset. Aircraft is also resident across that seam while landing and exiting. Separate aircraft horizontal flight across a seam, reverse insertion order, holes and partial-neighbor unload still deserve dedicated integration regression; they are not all individually proved by this 27-check scene.
- A persistent `uses_source_world` latch holds Player/Helicopter before legacy branches if their adapter disappears. R4 frees the actual adapter and verifies no movement/death/legacy exit fallback. Initially-null legacy mode remains intentionally separate.
- A shared profile predicate now checks actor upright unit basis, exactly one enabled capsule, identity child basis, actual dimensions/offset and world, and inspection/restore require the actor's runtime relationship. R4 mutates the bound capsule child's orientation and requires both motion and capture refusal. Foreign-world, weakened radius, extra shape and scaled-child negative cases remain code-reviewed rather than separately exercised here.
- The actual production `interact(player)` boarding API replaces R3's nonexistent method. R4 calls native boarding, queries the actual negative-elevation landing-side exit, and invokes actual `exit_vehicle`; the actor returns to the dry supported basement without an absolute water-plane override.

### Remaining P2: shared collision-body ownership is lost on partial region retirement

Current `source_runtime.gd:70-102,126-152,179-200`; R4 fixture `source_actor_test.gd:96-98,145-146`.

R4 commits the SAME slab body in west/east region body lists, but attaches its support only to west. `_supports` remains a single-owner record. Calling `retire_region(west)` alone erases the body's support record and removes its collider stamp even though east still references that live slab and advertises a complete resident neighborhood. An actor on east can still move/stand on the native slab, but source capture/restore reports unsupported. The current test retires both regions together and misses this lifetime case.

**Required contract/repair:** either maintain shared-body support lifetimes/refcounts with safe generation transfer, or reject a region's complete-neighborhood claim when its required physical support depends on a different region that can retire independently. Independent per-cell floor bodies are another valid implementation. Do not leave east advertised as complete while removing its sole floor identity. Add an actual Player capture/restore test after retiring only west; then retire the last genuine dependency and require a hold/pending state. This is a narrower region-lifetime issue remaining after the seam-union repair, not a rejection of the new union arithmetic.

### Remaining P2: actor-harness report path guard

Original finding 4 is still present at the R4 hash: lexical prefix/recursive mkdir and an unchecked report write. The runtime fixes do not repair this independent QA issue. Reuse the proven context/frame report guard and owned sentinel tests before closing it.

The dynamic-shape generation and full Game/save/rebase/default-bootstrap gates above also remain root integration obligations. R4 is a native synthetic actor regression, not a rendered national city/MBS or owner-save acceptance result.

## R5 follow-up: both prior P2s closed; native resting-contact restore case found

`source-actor-r5` completed at 2026-10-28T23:12:25.855194Z: **52/52, engine/supervisor 0, no fatal/classified errors, no timeout, child reaped**, elapsed 25.52s. The stock 75s scene watchdog remains unchanged. All five current source files matched the R5 supervisor's recorded hashes at review:

| File | R5 SHA256 |
| --- | --- |
| `source_runtime.gd` | `f5a71303544900e4a0cff0b83260bff248c7bae1859a7e18be009a0a8099414e` |
| `source_actor_test.gd` | `d96f66449e24b90c55dfa1ba1e72e062c411548e609f09990f8b5f0b28aa977f` |
| `source_world_context.gd` | `bdac6bf9350997a105e161826c8689ce050afbbedfb120bca3cd056da6cbc3f7` |
| `player.gd` | `c77fd881c2d8850d4de5396cb0c73333fa93f5e31766703eb06618e9fcb9dce0` |
| `helicopter.gd` | `5c70bf9c740c1c7ceaa05ca751eacd23cdee05e4a048fe2e874b51ab3f3980d3` |

**CLOSED — original shared-floor retirement P2.** `retire_region` now transfers a still-referenced floor's support lease and current collider stamp to another current-origin region, instead of unconditionally deleting it. R5 retires only west while the actual Player stands on east, observes resident/supported state with `qa-basement-east/generation-2`, and applies the saved native pose successfully. After retiring east as the last region, the actual actor holds and cold restore is pending; freeing the adapter then holds both actors without legacy fallback. This is direct coverage of the original two-live-region reproduction.

**CLOSED — actor report-path guard P2.** The actor scene now uses normalized fresh-session validation, linked-ancestor checks, bounded directory-entry/leaf checks, nonrecursive session creation, a final write-time recheck and complete-write/error validation. Failure to write the report exits 2. The actual writer was exercised against owned directory-link, dangling-leaf, existing-file, report-directory, reuse and late-link fixtures. Independent filesystem inspection found both sentinel contents unchanged, both missing targets still absent, dangling/late links intact, directory leaf preserved and the positive regular report intact. This retains the same explicit single-owner/check-before-open scope as the previously reviewed context/frame guard, not an O_EXCL/adversarial filesystem-swap guarantee.

### Fresh P2: legitimate native resting floor contact is classified as blocked clearance

R5 `run.log`, the `actual Player remains alive...` and `native registered support...` records; current `source_runtime.gd:190-222`, `source_world_context.gd:470-475`, actor test `:104-127`.

The actual production Player, after 90 untouched physics frames, is on the native floor at local `(1495.0, -20.026237487793, -6.0)`. The next inspection reports **resident, supported, dry_indoor, but clearance=blocked**. The floor slab top is Y=-20, capsule height1.75 and center offset0.9, so the actual capsule bottom is approximately -20.001237: about **1.24mm of native resting floor penetration**. There is no nearby wall/ceiling at this initial pose (the fixture wall is at X1480). This is recorded real physics evidence, not an invented geometry scenario.

The current QA only captures/restores after walking, when its settled root is -20.024160 and the bottom clears the slab. Consequently its passing restore does not cover an idle pose saved immediately at the original resting contact. A preflight for that original point currently consumes the recorded blocked-clearance classification and returns `capsule_clearance_blocked`, although the production actor is stably on its registered floor.

**Required native repro/gate:** immediately after the initial resident/supported/dry inspection and before walking, call production `capture_player_pose` and same-tick `restore_player_pose` on that exact native pose, without modifying saved Y. Add an ordinary cold-source restore of that pose with the same verified geometry. Separate bounded legitimate foot/support contact tolerance from wall/ceiling/body penetration using actual contact geometry and the production collision policy. Do not solve this by arbitrarily raising the saved pose, shrinking the actor, relaxing all overlaps, or excluding an entire support collider that may also contain walls/ceilings. Preserve the existing ceiling-blocked/unknown/unloaded negative tests. Root was notified with the exact R5 values; this reproduction has not been newly executed by the reviewer.

Thus the two repairs requested for R5 are verified and closed, but this newly observed native clearance/resting-pose case remains open before source save/restore is treated as generally ready. Full source-world/default-bootstrap/MBS assembly and Game v1 save/recovery migration are still outside this component acceptance.
