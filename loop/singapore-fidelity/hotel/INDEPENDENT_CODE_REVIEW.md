# Independent source Hotel/cabin integration code review

Reviewed 2026-10-29. Current inherited model; no Opus/alternate-model claim. Read-only inspection; only this new review file was written in this folder. No engines/GPU/UI/Git or implementation edits were performed. The separate stair-gate builder remains untouched.

**Decision: first native Hotel/CabinR2 validation remains pending.** Code is not runtime acceptance. Four concrete P2 findings were reported during review; root supplied source repairs for those four. Their specific native/PCK gates remain pending. One remaining construction/retry P2 is described below. No P1 found.

## Source snapshots

| Source | Reviewed identity |
| --- | --- |
| Initial `hotel.gd` before reported fixes | `e50878c0bcaa3d4b92f5bbeaeaab248f64b26f2342283a97dd9cd6d05f421f45` |
| Latest Hotel after first four source repairs | `2ae1769047c8cbfa8a0f7b240e55e9fbb680062cbb45c80bd32b2cd7b837b9eb` |
| FloorStack | `c1d484dd61be229d37476b7aee4c2359b87250cbd6fa7941d509e2b013a0e526` |
| Cabins | `9b3a1694fbd5bba77a942709db4f713bc6e17fb6bfe845bdf6bd08afbd989ae6` |
| Runtime with new `region_status` | `138c23f905d5bbec164eda4e86d517a73b51cc86875d945b1cd733394f432e25` |
| New Hotel test | `8029b1c7b5d2d44b87091da121aecc1bf95f087bb66cc88a6f51b943e22aef7f` |

Root was editing while this review ran. These hashes distinguish the repaired source from earlier lines/findings. Native Hotel/Stack/CabinR2 tests were queued under the root's helper and foreign-process cap; no new pass is claimed. Prior source public entry30/core298/context571/actor56 and isolated floor/cabin fixtures remain distinct evidence scopes.

## Reported P2s now repaired in source, native proof still required

### Production geometry identity depended on readable GDScript

Initial `hotel.gd:111` read `res://.../cabins.gd` text to construct the CABIN floor hash. That can fail or change identity in an exported/compiled PCK even if geometry is unchanged. Root replaced it with an explicit context geometry-manifest identity plus versioned shaft recipe/descriptor/canonical placement, and fixed the same production pattern in Site. The latest reviewed `hotel.gd:112-118` no longer reads script source for the production shaft identity.

**Source repair accepted; native/PCK gate pending.** Compare the actual resulting geometry/floor identities and native build behavior between source and release export with the same declared manifest. The new source QA fixture intentionally hashes source to version its fixture context; it is not the production build-data manifest and must not be reused as that manifest in the package.

### Travel readiness trusted a historical registration boolean

Initial `_ready_for_cabin` accepted `entry.registered` plus the cabin's RID/space/shape-count proof. Runtime region retirement could therefore leave `travel_ready=true` while the bodies still existed; an old-origin registration could also be mistaken for a current source lease.

Root now stores the exact runtime residency token and requires `runtime.region_status(region_id)` to be live with that token and the current origin revision, in addition to floor/neighbor readiness and the cabin's own native shaft proof. `region_status` checks region presence/current origin, live owned bodies/server space and current support stamps.

**Source repair accepted; native gate pending.** The new Hotel test retires only the source shaft region while retaining native cabin bodies and requires `travel_ready=false`. Also retain current-origin/changed-generation refusal when integrating real rebases. A complete rebase transaction is still root work.

### Wrong native World3D was rejected too late

Initial build checked frame/context/stack references and base, but not the Hotel node's own World3D before constructing shafts/registering architectural context data. A Hotel in a different SubViewport world could mutate the shared context before Runtime eventually rejected its bodies.

The latest build now compares Hotel, Stack, Runtime and Context native space before assigning implementation fields or creating children.

**Source repair accepted; native gate pending.** The new test uses an actual separate-World SubViewport and requires no children or registered-floor-count mutation on refusal.

### Hotel-owned floor pins leaked on teardown

Initial `_exit_tree` retired shaft regions but did not release the pin owner keys installed by `_refresh_pins`. Keeping Stack/context alive while replacing Hotel could leave old pinned floors permanently protected, including when a replacement controller reused the shaft IDs.

The latest teardown unpins only IDs/owner keys retained by this Hotel, clears its own pin ledger, then retires its owned regions. It does not remove another owner's pins.

**Source repair accepted; native gate pending.** The new test destroys Hotel while retaining Stack, then checks the relevant owner keys are gone. Root must still close/interlock live landing doors and control actor/cabin teardown order; this pin cleanup is not an authorization to destroy occupied transport.

## Remaining P2: partial/duplicate construction can poison a retained context and replace a live guard

Current `hotel.gd:46-93,99-132`; compare FloorStack's upfront same-context authority refusal and immutable-floor reuse at `floor_stack.gd:68-69,495-502`.

Hotel has no upfront same-context geometry-authority check. It builds physical shafts, connects callbacks and installs its unload guard **before** all native shaft floor/region registrations succeed. `_configured` is set before the awaited registration phase. `_register_native_shaft` unconditionally calls `context.register_floor` rather than reusing an identical immutable existing definition.

A normal duplicate/retry reproduction is a second Hotel using the same live Stack/Context and shaft specification: it constructs duplicate physical cabins/shafts and replaces the original Stack unload guard, then fails when its first CABIN floor ID is already registered. Failed owned geometry remains in the world and can obstruct the original cabin's sweep. A mid-registration failure similarly leaves `_configured=true`, immutable partial floor records and no retry/rollback operation. A fresh instance in the retained context then encounters those existing records again. This is not arbitrary malformed-number fuzz; it is constructor failure/retry and the same single-authority constraint already enforced by FloorStack.

**Required repair/gate:** reserve/refuse a second Hotel authority before children, context or existing guard mutation; delay guard takeover until a committed controller is ready, or use an explicit root ownership handoff. Provide a bounded retry/rollback contract: reuse identical registered architectural definitions, retire only owned region generations, clean or explicitly retain inaccessible failed geometry, and do not leave an apparent configured controller after a failed build. Add a native duplicate-controller test with no child/context/guard mutation, and a controlled registration-failure/retry test that proves one geometry authority and no stale travel readiness. A caller may intentionally retain failed geometry for diagnosis, but it must not silently take over a live floor guard or create a second active collision authority.

## Other source contracts assessed

- Source tower placement is canonical double data before local vector creation. Per-tower shaft roots receive the common source basis and projected global placement; descriptor stop Y values remain relative to the explicit common base. Inventory/core/cabin alignment is validated by Cabins before binding a floor.
- Each dynamic cabin support has a distinct source feature/`CABIN` identity, registered shaft volume, actual native body and current runtime token. Native contact positions still determine support. A dry shaft volume alone is not physical support or a permission to restore a moving cabin pose.
- The floor callback carries the exact requested floor ID and actual Stack generation. Floor-only results cannot independently authorize travel. Cabins require a bound matching native portal, native closed gates/landing doors, destination residency and shaft proof before motion; Hotel requests asynchronous floor loads outside the synchronous readiness callback.
- Floor unload preflights every relevant bound controller, refuses open landing fractions/moving destination/ready door, and unbinds before retirement. A refused partial unbind schedules rebinding while leaving the floor loaded. The root's upcoming composite stair/cabin guard must preserve these interlocks; this review does not replace that active work.
- Hotel target/open-door pins protect Stack floor/neighbor resources. Defaults remain bounded and protected-capacity failures correctly avoid deleting occupied data. Before broad transport acceptance, root should choose/test a budget for a parked helicopter neighborhood plus current/destination neighborhoods, and provide useful unavailable-capacity behavior rather than calling repeated non-readiness a successful ride.
- Node-owned callbacks depend on controller tree lifetime; the FloorStack's explicit unload guard fails closed if its controller disappears. The earlier RefCounted source-domain ownership repair remains in Runtime. No new external messaging, account or provider surfaces were used.

## Native and integration acceptance still required

The prepared Hotel test targets one source-positioned T3 east guest lift and actual production Player: normal floor E/LOS, a cold destination loaded through manager callback, physical boarding/platform carry/arrival/exit, moving CABIN source support, exact upper-floor support after exit, occupied-unload refusal, retired-lease refusal and owned-pin teardown. It must actually compile/run with clean supervisor metadata/source hashes before any of those become native passes. The new test is not itself proof.

Keep floor-stack native U-stair/door/LRU/retire gates and standalone CabinR2 motion/door-blockage tests separate. No actor velocity/pose assignment, reparenting, teleport, relaxed test or invented native pass can substitute for them. Source-to-PCK geometry identity also remains an explicit gate.

Physical stair-gate composition, source public-envelope cuts/hollow source MBS exterior/guest/program assembly, actual city/terrain, whole-building file-save/checkpoint/recovery and atomic camera/actor/physics rebases are still root work. This vertical-system review does not certify a complete MBS, all1850 rooms, default Singapore city, visual quality, performance or owner play acceptance.

Shared routing used cached published revision `a67557283f99`; no fresh cloud-policy verification/publication claim. Root owns source checkpoint/push and queued engine validation.

## Native Hotel R2 follow-up: original findings repaired and exercised

`mbs-hotel-integration-r2` completed2026-10-29T01:40:19.497697Z with **28/28, engine/supervisor0, no fatal errors, no timeout, child reaped**, elapsed25.03s. The following current source identities matched the supervisor at the start of re-review:

| File | R2 SHA256 |
| --- | --- |
| `hotel.gd` | `16009eae0dd9136a3c492e6c1ece94ded0597309a35a2357ed578091fe4bfabb` |
| `mbs_hotel_test.gd` | `647b48e4fb51bec9a44cc361e3e05cf2db1d02b161e865b9418b347c6ea61769` |
| `floor_stack.gd` | `b9f13864b3f887d7a99a478ac25170a4fb4cf63a80b821f93aef688fc9232795` |
| `cabins.gd` | `9b3a1694fbd5bba77a942709db4f713bc6e17fb6bfe845bdf6bd08afbd989ae6` |
| `stair_gates.gd` | `bf7a5ca1156c8ee6d4d1cee6266685500a09d56cbb5134f3eeeabb2be78e38a5` |
| `source_runtime.gd` | `7e70c9062aba58545c7cf3f635181ee39a80a96082e117dc269de586e18e94b3` |

R1 remains failed: parser/class-resolution errors prevented the test from running; supervisor/engine ended-15 after66.19s and the child was reaped. Explicit bool typing repaired the two inferred boolean declarations. Do not relabel R1 as a clean runtime pass.

### Original Hotel P2 disposition

- **Authority/partial-build/retry P2 CLOSED for the exercised reproduction.** Hotel reserves one same-context authority before constructing/yielding, rejects duplicate controllers before children/context/guard mutation, remembers the build origin revision, and delays Stack guard takeover until native registrations have succeeded. Controlled failure after the first of two shaft registrations retires owned regions, frees owned children, releases its authority/configuration state and leaves Stack's previous guard unchanged. Immutable matching architectural definitions are reused for an exact retry. Native R2 exercises failure, verifies clean owned geometry and retained definitions, retries successfully, then refuses a second live authority without mutation.
- **Wrong-World P2 CLOSED.** Native separate-World SubViewport construction is refused with zero children/context registrations.
- **Historical registered-bool travel P2 CLOSED.** Travel now requires the actual current-origin Runtime region plus exact stored residency token and native shaft proof. R2 retires the shaft's source region while native bodies remain and requires travel readiness false.
- **Leaked owned pins P2 CLOSED.** R2 tears down Hotel while retaining Stack and confirms its shaft owner keys are absent. Other owners' pins are not removed.
- **Production script-text geometry-ID P2 source repair accepted; source-to-PCK gate remains pending.** Production Site/Hotel identities use explicit versioned manifest/recipe data. This headless source run is not release-PCK identity proof.

### Actual native ride scope

The production Player starts exactly once at the actual source-positioned T3-L5 landing, uses native E/LOS on the real landing door and panel, walks into the physical cabin and requests T3-L6. The manager actually loads the previously cold L7 neighbor before destination readiness. The actual platform carries the actor, then the actor walks onto the native upper floor.

- Initial actor spawns1; maximum physics step **0.0600327m**; no death or QA post-spawn relocation/reparenting.
- Native platform samples **258/258 supported**; peak actor-to-platform vertical offset **0.057501m**; measured native platform velocity reaches about2.00008m/s.
- Source support samples **258/258 identify the actual CABIN as supported/dry** during travel, then native support changes to the exact upper inventory floor after exit.
- Occupied destination unload, retired shaft lease, duplicate authority, failed-build rollback/retry, wrong-world refusal and owned-pin teardown all have passing actual checks.

This earns bounded approval for that source-positioned integrated guest-lift ride and those original repairs. It does not prove the default twelve shafts, every inventory stop, service-lift travel, a public L1-to-upper route, all stair gates, source city, release package, owner controls/feel, visual fidelity or performance. The public-core/L1 worker's later disjoint configuration changes are not silently covered by the R2 hashes.

### Narrow remaining P2: an invalid previous unload guard is released to no guard on Hotel teardown

R2 Hotel `:337-340` restores a previous guard only if `_previous_guard_set` is true **and** that Callable is still valid. If a previously installed Node controller disappears during Hotel's lifetime, `_before_floor_unload` correctly refuses retirement because that prior guard is unavailable. But Hotel teardown takes the `else` branch and calls `release_unload_guard(own)`, leaving the retained Stack with no guard at all. That changes an explicit unknown/unavailable safety decision into permission to retire when ordinary occupancy/pin checks do not express that old controller's constraint.

The native R2 fixture starts with no previous guard, so its passing teardown check does not cover this case. This issue does not invalidate the actual source ride or original owned-pin repair.

**Required repair/gate:** distinguish no previous guard from a previous guard that has become invalid. Only the former may release to none. Preserve an explicit guard-unavailable/fail-closed state for the latter until root resolves ownership; leaving the owned callback to become invalid is safer than implicitly erasing the requirement. A valid previous guard should still be restored exactly. Add a focused Node-callback lifetime test: install a guard, build Hotel, free the original guard owner, confirm refusal while Hotel lives, then remove Hotel and confirm the same unavailable-guard refusal remains. Test ordinary no-prior-guard cleanup and valid-prior-guard restoration separately. No engine was launched by this reviewer for this new case.

All other broad root assembly/save/rebase/render/package limitations above remain. Source readiness dictionaries, native source tests and whole-game acceptance remain distinct.
