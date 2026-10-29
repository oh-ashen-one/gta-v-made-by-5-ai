# Canonical source-v2 save and recovery service — author candidate

`game/src/world/geography/source_save_service.gd` is a new production service. It owns a separate source-v2 sibling slot and canonical recovery anchor. It does not call the legacy parser, reinterpret local coordinates, write the v1 slot, edit main/Game/Player/Runtime, or claim mission/door/whole-city save migration.

The child authored the service and native fixture. Parsing, native execution, fresh independent critique and integration are pending Root. No child engine/GPU/Git operation occurred.

## Root API and lifecycle

- `configure(runtime, player, legacy_save_path="", qa_session="") -> bool` binds an actual source-bound production Player, verified capsule profile, shared native runtime/context/world and one sibling slot. It does not install itself into Game or replace another session. Root configures first, then calls `Game.install_source_session(service)`.
- `is_bound_to(runtime, player) -> bool` checks the exact retained live binding. Root's source-mode routing must hold/refuse when missing rather than use v1.
- `metadata()` returns exact absolute `slot_path` and `legacy_path`, scope, QA root, anchor readiness and pending token/reason. `pending_token()` is the current transaction token.
- `capture() -> Dictionary` returns a fully validated source-v2 document without writing or changing Game. `capture_anchor() -> bool` records an actual supported/clear on-foot pose and its current restore-readiness result. It rejects occupied, hidden, busy, dead or cabin proxies.
- `save() -> bool` returns true only after complete same-directory atomic publication. It refuses while a restore transaction is pending.
- `has_save() -> bool` means the sibling contains a completely valid source-v2 document. A valid older geometry can still exist; load reports its blocked version explicitly instead of hiding/deleting it.
- `load() -> bool` and `retry_pending(token="") -> bool` return true only when applied, or for an exactly matching completed replay. Pending/blocked returns false with tagged `last_result`. `cancel_pending(exact_token)` clears only that transaction/control hold, never its slot or Game state.
- `request_recovery(reason="death"|"disabled_aircraft", token="") -> bool` reuses the canonical on-foot anchor, never the raw occupied passenger position. An empty-token current death requires health<=0. The issued token is retained across streaming waits and deduplicated after completion. Disabled-aircraft recovery does not add a death. A pending disabled-aircraft transaction can promote to death under the same token.

`restore_required(reason, context_pose, token)` exposes exact source identity/pose for Root's async floor/tile/origin preparation. Root calls `retry_pending` at a controlled physics boundary after that work. `restored(reason,token)` and `recovery_committed(reason,token,death_count)` fire only after successful state commit. The service calls Root's ownership-checked `Game.set_source_recovery_hold(self,true)` for pending transactions and false after successful apply/cancel; an uninstalled/foreign service cannot take control.

## Exact restore transaction

The complete envelope and all permitted stats validate before any actor/Game mutation. Current source frame/snapshot/elevation, geometry and vertical identities must match. Missing floor/residency returns pending; changed versions, missing support or blocked capsule return tagged refusal. No pending/blocked path writes the slot, applies stats or moves the player. Pending file loads also verify that their originally read bytes still identify the current sibling file.

At `Engine.is_in_physics_frame()`, the service synchronously calls the existing `Runtime.restore_player_pose`. That performs a fresh same-tick source-context preflight and actual production `respawn_at` only when ready. After it returns applied, the service commits the already validated stats without a yield, then calls `Player.reset_action_state(false)` to clear transient inputs/reload/aim without resetting the selected weapon. UI/events are emitted after the complete commit. No source pose is copied into Game's fictional `last_safe_position` as a fallback.

Recovery keeps current ammo/settings/elapsed/seed through the wait, restores healthMAX and clears pursuit heat/search under the declared game policy, and increments the current death counter only after native application. Replayed issued completed tokens do not apply again or increment. Cancelled/unissued tokens are not counted completed. Exact token history is bounded to65,536issued recovery requests per service lifetime; at that exceptional capacity it refuses new requests explicitly rather than evicting history and risking duplicate accounting.

An anchor captured outdoors with unknown hydrology remains data with an explicitly pending cold-restore state. The service does not relabel it dry. The existing Context preflight still requires dry/above-surface resolution; local vehicle exits have a distinct Root policy. If no valid canonical anchor exists, recovery remains pending with a token and request instead of inventing a local checkpoint. Root should capture the initial source on-foot anchor before enabling owner travel, and keep UI/controls held while actual required data is prepared.

## File isolation and atomic publication

Given `orchard_reach_save.json`, the service writes only `orchard_reach_save.source-v2.json`. Legacy bytes are never opened for parsing or writing. Existing/dangling symlink path components, source-slot directories, unsafe paths and invalid filename scopes are rejected. QA requires the actual absolute `--qa-session` root and a sibling beneath it; a QA request cannot fall back to the owner's user slot or an unrelated explicit save path.

Source-v2 documents have exact schema/version/scope keys and a65,536byte bound. The service validates finite/ranged complete stats, writes a new same-directory owned temporary file, flushes it, verifies its complete bytes, then performs a single rename. Until rename, the previous v2 remains intact. This is atomic publication on the supported local filesystem, not an fsync-directory/power-loss guarantee or OS-level O_EXCL guarantee against adversarial same-process races. It does not create or truncate v1. Temporary cleanup targets only the exact owned temporary name.

## Permitted state and explicit omissions

The exact saved stats are health, death_count, wanted_level/heat with consistent thresholds, elapsed_seconds, seed, modeFOOT, selected pistol/SMG, exact two-weapon ammo with capacity bounds, the four supported settings, search_timer and since_damage. All numeric fields reject NaN/Infinity/string/bool coercion; enums, integer ranges and exact nested keys are checked. Wanted tier must match heat; magazine counts cannot exceed12/30. The source pose includes current frame/snapshot/elevation and context/floor geometry identities, canonical float64 XYZ and heading/feature/floor/room IDs.

Mission/courier/checkpoint/door/guestroom/cabin/vehicle/NPC/traffic state is not included. Existing mission/courier fields are not silently reset or claimed restored. Root must add separately versioned validated source consumers before claiming complete game persistence. Pursuit actor visibility/local target caches are not serialized; player_seen is cleared on apply, with the current actual player position used for the live last-seen cache. Whole-source rebase/cache migration remains Root.

## Root-run native fixture

`res://src/systems/fidelity_tests/source_save_test.tscn`, with a new private `--qa-session` beneath `/private/tmp/singapore-fidelity/`, uses the actual production Player/Helicopter/Runtime on explicitly synthetic native dry B2 geometry. It checks canonical save/load, all-stat/SMG restore, idle-to-physics pending behavior, exact v1 byte preservation, occupied/hidden and native-stamped cabin rejection, actual vehicle recovery, missing floor→native lease commit→retry, changed source geometry refusal, same-support-body ceiling refusal, malformed/corrupt JSON and invalid complete stats, QA path isolation, pending lethal recovery and exactly-once death tokens. Fixture setup relocations are explicitly labeled; this is not a continuous city route, real MBS floorplan, rendered quality or whole-game persistence pass.

At author freeze no engine was run by the child. Root must execute the fixture, preserve any failed run and review/fix before normal integration.
