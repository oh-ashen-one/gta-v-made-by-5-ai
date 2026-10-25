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
