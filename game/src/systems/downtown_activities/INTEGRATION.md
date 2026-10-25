# Bayfront Courier

Optional, repeatable errand between the heritage waterfront and MBS Event Plaza. It does not change Harbour Relay stages, checkpoints, enemies, or objective markers. Walking, driving and helicopter travel use existing controls. Handover is an explicit on-foot E action within 4.5 m and unobstructed line of sight.

## Bootstrap

After player/world setup, instantiate `res://src/systems/downtown_activities/courier.gd`, add it to the scene, then call `setup(world, player)`. It registers in group `downtown_activity`. The system builds two existing-asset handover points and its own status card. No HUD or mission modifications are required.

- `stations.heritage`: `(-144, DowntownPlan.QUAY_TOP, DowntownPlan.LEGACY.promenade_z)`.
- `stations.bayfront`: `DowntownPlan.anchor("mbs_event_plaza") + Vector3(0, 0.06, 10)`.
- `changed` signal; `is_active()`, `current_objective()`, `objective_position()` for inspection.
- Stages: `IDLE=0`, `OUTBOUND=1`, `RECEIPT=2`.
- Heritage E starts, cancels an outbound parcel, or completes a returned receipt. MBS E delivers the parcel and gives the return receipt.

## Save integration

Include `serialize_state()` as optional `downtown_activity` in the existing atomic Game save. Validate that field with the script's static `valid_state(Variant)` before any Game state mutation. `restore_state(Dictionary)` independently rejects invalid input without changing the current state. Missing fields in old saves should call `reset_state()`. New Game calls `reset_state()`; death and Restart Harbour Relay preserve the optional errand. Progress saves after every successful interaction using `Game.save_game()`; the Game hook must be present for cross-launch persistence.

The payload is `{version: 1, stage: 0..2, completed_runs: 0..1000000}`. It contains no player/vehicle transforms and cannot teleport a player. Receipt completion increments once; pressing E again begins a new run.

## Controls-based verification

Run with a disposable QA save directory only:

```sh
python3 game/tools/bounded_run.py --seconds 1200 --log /private/tmp/astra6-activities/route.log -- godot --headless --path game res://src/systems/downtown_activities/tests/courier_route.tscn -- --qa-session /private/tmp/astra6-activities/route-session
```

The dedicated scene loads the full game from its normal spawn, creates the activity only if the integration hook is absent, and uses movement/E input. It checks range, line of sight, pause/busy and actor guards, JSON restoration, cancellation/repeat, then walks via Jubilee and Helix to MBS and back. No respawn/position assignment is used in its traversal. The only temporary fixture is a wall for the line-of-sight rejection check; it is removed before travel. Headless success is functional evidence, not rendered quality or vehicle-route acceptance.

The optional `--courier-baseline-curb-jump` switch records one real-input jump at the legacy waterfront lip, solely to diagnose downstream access on an unpatched baseline. The default route does not jump. Intermediate waypoints use the existing downtown review's 3 m reach tolerance so the driver does not demand walking into the Helix balustrade; both handover approaches require 2 m.

## Local MBS access fixture

`res://src/systems/downtown_activities/tests/mbs_approach.tscn` starts explicitly at the MBS north corridor and walks ingress to the destination ring and egress. It isolates the physical ramp before spending time on the complete route; it does not prove courier progression or end-to-end travel. Use the same bounded runner and isolated `--qa-session` as above. The full courier test always starts at the normal heritage spawn.

`res://src/systems/downtown_activities/tests/jubilee_return.tscn` is a second explicit local fixture: it starts at Jubilee's east approach, ray-probes the landing lip, then walks through Merlion Park to Heritage Waterfront. It isolates the reverse landing and remaining return leg without representing a full courier run.

## Optional real-camera courier stills

Add `--courier-stills-dir=<absolute path>` to the full route. The output must be a new child directory beneath the explicit private-temp `--qa-session` directory; normalized `/tmp/` aliases are accepted. Symlink redirects and existing named PNGs are rejected. Headless runs skip all screenshot waits and writes. This option does not start a renderer or replace the shared lease protocol.

Example for the parent-owned rendered lane (do not add the unrelated `--capture` route flag):

```sh
bash loop/render.sh courier-route 1400 /private/tmp/astra6-courier-render -- res://src/systems/downtown_activities/tests/courier_route.tscn -- --qa-session /private/tmp/astra6-courier-render/session --courier-stills-dir=/private/tmp/astra6-courier-render/session/stills --qa-render-size=1280x720
```

Six PNGs come directly from the active player camera's viewport: `01_dispatch_arrival`, `02_parcel_collected`, `03_mbs_arrival`, `04_mbs_delivered`, `05_receipt_return`, `06_courier_completed`. The log records dimensions, player position, courier state, physics frame and any failed assertions for each image; the final result includes the capture list. Expected fixture toasts are cleared only before the parcel-collected frame, only if all assertions still pass, with an explicit log. Assertion history is never cleared. Screenshot failures fail the test.

Fast headless guard smoke: use `res://src/systems/downtown_activities/tests/stills_guard.tscn` with a fresh private-temp `--qa-session` and its child `--courier-stills-dir`. This checks path acceptance/rejection and confirms headless requests never wait for rendering or create captures.

## Real occupied-vehicle handover fixture

This separate scene leaves the full-route test untouched. It loads production main/courier/Car, collects through E, walks to and enters the real car through E, drives a short local throttle/handbrake movement, and saves/loads while occupied. It verifies the normal honest foot-checkpoint fallback, reboards through E, then explicitly relocates the occupied car near MBS. Seated handover must be rejected without mutation; a safe native E exit followed by actual on-foot E delivery must succeed. Receipt save/load is also checked.

With `--courier-helicopter-check`, the existing production helicopter is explicitly placed at MBS for E boarding with the receipt, then relocated to heritage. Native descend input settles it; seated receipt completion must fail, native E exit must succeed, and on-foot E completes the receipt. Fixture moves and deliberate pre-load state perturbations are logged. No mode, occupant or landed flags are forged. This is **not continuous driving or flight evidence**.

```sh
python3 game/tools/bounded_run.py --seconds 180 --log /private/tmp/astra6-activities/vehicle-handover.log -- godot --headless --path game res://src/systems/downtown_activities/tests/vehicle_handover.tscn -- --qa-session /private/tmp/astra6-activities/vehicle-handover-session --courier-helicopter-check
```

The car-only run passed 27/27; the combined run passed 38/38. Summary and script hash: VEHICLE_VERIFICATION.json.
