# Independent source session controller review

Read-only review observed 2026-10-29T04:11:33.686733+00:00 by`/root/public_lobby_builder`. Only this document is written. No engine/GPU/Git/UI or production/test edits; the root's full outside route remains a separate live gate. These evolving files are unparsed/current author snapshots, not a claimed native controller pass:

- `game/src/world/geography/source_session_controller.gd`: `6056500e9aea0192379c544d64ad5fea5ec073bf64de488171ee5068da175aa9`
- `game/src/world/geography/source_world.gd`: `2de37bbad005e37750d18e54ac27550e591cdc51284ee0b4dd1cab7413d86f7e`
- `game/src/world/geography/source_save_service.gd`: `5ccf5e4b4fba09406c671ecc12c33bdcbb3aa3b603e5b3f184ee63b45c808766`
- `game/src/core/game_state.gd`: `8ce3468cf892d97dae4056abf1b3bd9783922fc7f9ff01f2a582ab7f857c89d5`

## Concrete findings

### P1 — Terminal retry refusals without a signal can leave a manual load held forever

Controller`_physics_process()`clears`_retry`, calls`service.retry_pending()`, then returns whenever the pending token is nonempty. It does not inspect a false return or tagged`last_result`. The service's correct`source_slot_changed_during_pending_restore`hash refusal returns`blocked`WITHOUT emitting`restore_required`. A valid F6 load that queues and whose sibling bytes change before the retry therefore remains pending with controls/damage held, no further retry scheduled and no cancellation. Repeated F6 retries the same blocked transaction; the wrapper suppresses its no-save toast because a token exists. A correct stale-file refusal must not become a permanent manual-load freeze.

Root should inspect each exact-token retry result and route terminal`blocked`/`invalid`manual-load failures through the same cancel/release path even when no signal fires. Preserve current pose/stats/files and never silently read a new document under the old token. Native case: queue valid load, replace v2 bytes before its physics retry, then verify refusal, safe cancellation/released controller pins/hold and untouched actor/stats/v1/current v2.

### P1 — A failed preparation permanently suppresses re-preparation of a recovery floor

`_on_restore_required()`sets`_prepared_tokens[token]`BEFORE preparation. Any failed`ensure_floor()`leaves that marker. Death recovery remains held, but subsequent observations cannot queue another ensure for that token. The only regular wake is`floor_committed`, which need not occur when a transient block clears: capacity can become available after an explicit pin releases or a native transition/door reaches its safe state, and a busy lifecycle can end without a new floor commit. The controller then never retries actual floor preparation despite retaining the target pin and the user's recovery hold.

Keep one preparation coroutine per exact token, but distinguish successfully prepared from attempted. Add bounded/backoff/event-driven re-preparation for declared transient statuses while preserving one owner pin and no duplicate active ensure calls. Manual unsupported loads may cancel; death must stay safely held with an observable retry policy. Native case: genuine first ensure failure on protected/busy capacity, clear that actual condition WITHOUT a floor-commit notification, and prove the SAME token eventually prepares/restores exactly once. Do not use a fake-ready callback or new token.

### P1/P2 — Missing loader returns without the promised manual-load cancellation

`_on_restore_required()`can queue an inventory MBS floor even if the normal world has no valid floor stack. `_prepare_floor()`then combines current-token/missing-stack cases in one early return, merely clearing`_preparing`. The current manual load stays pending/held with`_prepared_tokens[token]`set and no notification or scheduled retry. This is reachable with the explicit`build_mbs=false`world configuration loading an otherwise matching saved MBS pose, or an unavailable/replaced loader; source identity currently does not depend on that build option. It contradicts the stated unsupported-load policy of preserving current play and cancelling.

Separate stale-token no-op from CURRENT-token loader-unavailable failure. The latter should use the normal refusal/cancel/release path for a manual load, while death remains explicitly held/pending. Do not create a floor substitute or use legacy fallback. Verify a controller with no stack does not leave a healthy current source actor frozen after F6.

### P2 — External cancellation is not reconciled with controller-owned pins

The controller releases pins on`restored`, on its own manual-refusal handler, or when an in-flight ensure returns and observes a stale token. The service has no cancellation signal connected here. If another authorized caller invokes`service.cancel_pending(token)`AFTER preparation completes but before apply, controller`_pinned[token]`and`_prepared_tokens[token]`remain indefinitely. Its later physics pass sees no pending token and starts periodic anchors without releasing the stale floor pin. Repeated cancel cycles can exhaust the floor pin/capacity budget.

Add exact-token cancellation notification or per-physics reconciliation against the service's current token. Release only this controller's exact owner strings; don't touch foreign pins. Reconcile completed preparation, queued/deferred work and in-flight work without allowing an old completion to clear a newer token's state. Native case: prepare/pin A, cancel A after ensure returns, then start B and verify no A pin remains, B stays protected and stale A completion/callback cannot release B.

### P2 — Stale controller wrappers can operate a replacement owner's slot

`save_game()`and`load_game()`only check that their service Node is valid, then call GLOBAL`Game.save_game/load_game`. After a legitimate ownership switch, that global routing targets the NEW service, so a still-live old controller can operate another owner's slot. Its own service's strict refusal does not guard these wrappers. Add`Game.source_session_owns(service)`before F5/F6 and before physics/preparation side effects. Current-token equality alone is not session authority. Test an old controller after explicit owner replacement; its wrappers must refuse without touching the new owner's files/hold/actor.

### P2 — First playable frame is advertised before a ready recovery anchor exists

Normal SourceWorld configures the controller, then sets`ready_for_play=true`, clears`Game.simulation_paused`, captures input and emits`source_consumers_ready/source_world_ready`. The controller deliberately waits for its NEXT physics callback before capturing the initial anchor. Death or vehicle entry in that window on a fresh slot can leave recovery without any on-foot checkpoint; capture then refuses a dead/occupied proxy. The source bootstrap already commits real collision, so prefer one awaited, verified initial native anchor boundary while input remains held BEFORE advertising playable readiness. Failure remains explicit; do not invent a local checkpoint or demand a new owner approval. Test a fresh no-save boot and immediate ready-event lethal/boarding input, preserving initial anchor or safely retaining boot loading until it exists.

## Teardown and callback observations

The normal owned-pin release uses exact owner strings and WeakRef stack references, and Game uninstall checks the exact service. Those are appropriate. Game also now refuses uninstall while`metadata.transaction_busy`is true. Controller`_exit_tree()`currently ignores that return after already releasing its pins. Ordinary queued shutdown usually happens after the synchronous transaction ends, but an immediate tree removal/scene transition inside an internal Runtime mode/notification callback needs an explicit lifecycle test: do not destroy the service or drop its pins while uninstall refuses busy. A public shutdown/deferred teardown protocol should wait for that transaction boundary;`_exit_tree`alone cannot undo a Node destruction already in progress. This is a targeted callback/teardown risk, not a reproduced ordinary-quit failure.

Known Runtime internal callbacks are not newly discovered here: production`respawn_at`may emit mode/notify/vehicle-exit behavior inside the guarded synchronous restore; the service holds`transaction_busy`across that interval. Preserve that guard and don't claim the interval is callback-free. Controller nested refusal cancellation is otherwise presently after busy has cleared on the inspected failure paths.

## Positive observations and explicit limits

The controller does not fabricate a rebase or national tile load. Supported exterior restoration uses an explicit service policy; unknown hydrology remains labelled unknown. Native MBS preparation uses actual inventory IDs, real FloorStack ensure and target pins, not a translated floor, fake ready result or actor relocation. Fresh physics retries are scheduled to a real physics callback rather than recursively retrying inside`restore_required`. Normal successful restore releases the matching token pin and leaves foreign pins alone. F5/F6 normal SourceWorld wiring is present and quit avoids implicit v1 save.

The current normal SourceWorld boot still contains the explicit known-rejected road identity guard; no successful normal-world controller boot follows from its source wiring. The source-service synthetic fixture and the separate actual public/core traversal do not exercise this new controller's lifecycle. Root needs real component/native lifecycle gates and later the corrected approved normal SourceWorld boot. No full-city/save-migration/visual acceptance is claimed by this review.
