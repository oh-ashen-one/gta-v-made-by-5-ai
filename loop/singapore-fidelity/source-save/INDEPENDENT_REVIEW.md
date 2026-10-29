# Independent source-save review

Observed 2026-10-29T04:00:47.942612+00:00. Reviewer: `/root/public_lobby_builder`, read-only implementation review; no engine, GPU, Git, UI or source mutation. The root owns Game/controller/integration; `/root/geography_stream_builder` owns the active service/test fixes. Stair/Public/full-route sources remain frozen.

Review snapshots: service SHA256`a383e20801837389ad64011de05474a439e119eaff505d6c01f105bc97e59b4c`; test SHA256`efc84d092a6a70ae36a899c14f7a566a76c283b0c18a7395eeda0b5263e3caa8`. These are evolving author files, not a claim that all current bytes were loaded by the prior native run. Root-native R1 used checkpoint`e29f76a4055eef4f4a5414ed256d44ae8597c900`, service`46da3407e30f3c0a293a075c8fde314fc838e839df74dab0b128a8d60bdd436d`and test`efc84d092a6a70ae36a899c14f7a566a76c283b0c18a7395eeda0b5263e3caa8`. Its actual report is48checks/0failures; supervisor exit0/no fatal/no timeout/child reaped. That native fixture is explicitly synthetic B2, uses declared setup relocations and is not city/MBS traversal or visual acceptance.

## Findings requiring changes or an explicit enforced policy

### 1. Pending healthy load and lethal damage need one consistent transaction policy

In the reviewed version, `load()` creates a healthy pending load and holds controls, but incoming Game damage could still make health0 before native application. `Game.respawn()` then requests death recovery; `request_recovery()`refuses because the pending transaction is a load. A later load retry restores its saved health/death counter without a death recovery event. The R1 test changes health/pose manually before load and tests death separately; it does not exercise actual lethal damage during a pending load.

Root explicitly chose the policy on this review: a deliberate source loading/recovery hold suspends incoming damage as well as controls, equivalent to a scoped load pause. Root is guarding `Game.damage_player`only when the explicit `_source_recovery_hold`is set AND an actual bound source Player exists; legacy behavior is unchanged. This avoids discarding a death-token race rather than silently selecting an arbitrary transaction after the fact. The author has been asked for a native assertion using actual lethal`Game.damage_player()`during a pending healthy load: health/death count/actor/files stay unchanged, the hold stays owned, and the original load token applies once after real readiness. This finding is POLICY RESOLVED / IMPLEMENTATION AND NATIVE ASSERTION PENDING at review handoff; do not claim R1 covered it.

### 2. A staged, rejected service must not mutate the current owner's world or slot

`configure()`correctly permits staging a service without taking over Game. However, reviewed mutating methods checked only`is_bound_to(runtime,player)`. A second serviceB can configure against the same actual runtime/player/sibling while serviceA is installed. `Game.install_source_session(B)`rejects B, but B's direct`save`/`capture_anchor`/`load`/`request_recovery`/`retry_pending`can still proceed. `_set_hold()`silently ignores Game's ownership rejection; a physics-boundary restore can then change Player/Game despite never acquiring the current owner's hold. B can also overwrite A's same sibling slot. Exact runtime binding is not installed-session ownership.

Root accepted this finding and is exposing`Game.source_session_owns(service)->bool`, meaning exact current bound ownership. Author was asked to gate every mutating slot/anchor/pending/recovery/application operation on that ownership, while keeping pure configure/staging independent and never auto-installing or replacing A. Recheck authority again before an asynchronous pending apply, not only when issuing the request. Diagnostic`last_result`changes on refusal are acceptable; actor/Game, owner hold, anchors and both slots must remain intact.

Required negative native cases: configure B while A owns the exact runtime/player/slot; verify rejected installation and every B mutation refuses without changing actor/stats/v1/v2 or A's hold. Also queue a legitimate A token, uninstall A, then verify a stale retry cannot restore or clear another owner's hold. This finding is ACCEPTED / AUTHOR FIX AND NATIVE ASSERTIONS PENDING at review handoff.

## Already known issues, not counted as new findings

The root/author already identified malformed JSON schema/type variants that can reach string operations, and replacement of a previously ready recovery anchor by a pending-water candidate. The author is fixing those; this review does not duplicate them or treat the pending fixes as completed native proof.

The source transaction comment's claim of no callback inside Runtime application is stronger than the actual call chain. `Runtime.restore_player_pose()`calls production`Player.respawn_at()`, which may force-exit a vehicle, emit mode/notification events and reset presentation; `_apply_stats()`calls`reset_action_state(false)`, which emits ammo before the service's final public events. The root already tracks this known guarded synchronous-callback issue. `_busy`must remain held throughout those internal callbacks and reentrant mutations must refuse. Do not describe the interval as callback-free. The later public health/wanted/settings/state signals occur after final commit; this distinction should remain documented.

## Positive correctness observations within the declared scope

The sibling naming keeps source-v2 separate from v1; the service never invokes the v1 parser or interprets legacy local XYZ. QA binds to the actual explicit private session and rejects owner-slot fallback. Existing/dangling symlink and unsafe-path rejection are checked before publication. Same-directory owned temporary write/flush/complete-byte verification followed by one rename preserves the previous v2 until publication; it is not a power-loss/directory-fsync or adversarial OS O_EXCL guarantee, as the author already documents. Native R1 preserves exact v1 sentinel bytes through its tested operations.

Load validates the complete exact envelope/stat/pose structures before any native application and retains the originally read file hash across pending waits. Changed frame/dataset/vertical/floor identity stays blocked; cold floor/support/clearance/water data stays pending. A fresh synchronous Runtime query decides whether the actual capsule may be restored; no actor pose or scalar-stat writes occur on those refusal paths. The native same-support-body low ceiling test is valuable because it prevents whole-floor-body exclusion from disguising clearance failures.

Recovery deliberately refreshes current ammo/settings/elapsed/seed across waiting rather than restoring an obsolete live-stat snapshot. Completed issued recovery tokens are retained; same-token replay does not reapply or count a death twice, and cancelled/unissued tokens are distinct. Disabled-aircraft recovery actually force-exits the real vehicle without adding a death; selected SMG survives transient clearing. Pending/blocked load files remain unchanged, and no source recovery writes the v1 checkpoint.

## Additional useful test edges, not additional confirmed defects

- Change the v2 file after a valid load queues, then retry the exact token: require `source_slot_changed_during_pending_restore`, no actor/stat/file write and safe retained/cancellable hold. Implementation has the hash check; R1 does not exercise that race.
- Verify wrong pending token, cancellation and completed-token replay while a DIFFERENT transaction is pending cannot clear that current hold or apply the wrong document. R1 covers successful completed death replay but not the cross-transaction permutations.
- Inject an ordinary owned temporary/publication failure and verify byte-for-byte preservation of the previous v2 plus exact owned-temp cleanup. R1 proves successful publication, not every failure exit.
- When reviewing the author's ready-anchor fix, exercise a good retained anchor followed by supported outdoor unknown-water or same-body blocked candidate; require prior ready anchor unchanged and tagged refusal. This is the already-known anchor finding, not new broader hydrology scope.

Mission/courier/door/vehicle/NPC/national streaming/rebase state is explicitly outside the current save envelope; this review does not count those declared omissions as defects or claim they are migrated. Full-game source persistence, rendered acceptance and root wiring remain separate gates.
