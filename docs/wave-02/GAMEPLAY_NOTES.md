# Wave 2 gameplay and verification notes

These notes describe the mission-integrity work inside the shared Astra checkout. They are evidence-bounded, and do not certify visual fidelity, human game feel, public asset clearance, or a release.

## Verified evidence so far

Evidence is tied to its startup source/asset hashes. Later edits do not inherit an earlier pass.

- `../route-render-r1/qualification.json` and `../route-render-r1/capture_log.json`: a **rendered scripted route reached DONE with zero deaths and three combatant kills**. The process exited **0** after **223.57 s**; gameplay duration **217.92 s**. The timestamp-preserving video is **scripted input automation**, not a native human playtest. Recording overhead, a shared capture slot, and initial overlap with a headless run make this a timing baseline, **not performance acceptance**.
- `tests/regressions-r8.json` and `.log`: **85/85** behavioral assertions passed, process exit **0** under the then-current supervisor, **18.44 s**, PID **5740** reaped. This includes atomic save replacement, malformed-save rejection without mutation, saved settings, actual SMG held-model restoration, rapid mouse events, muzzle obstruction, vehicle ownership, blocked exits, and the precise waterfront walking regression. The JSON records startup source hashes and fixture repositioning. These assertions are not a golden path.
- A later strict-supervisor headless run produced **85/85 assertions but overall exit 2**, because the console contained generic errors. Eleven notification timer errors were traced to freed-label lambda captures and fixed by the root agent with weak references. One material-null diagnostic from Godot's dummy renderer remains under investigation. The actual Metal regression did not reproduce that material diagnostic. Do not call the latest headless aggregate clean until its strict process result says so.
- `tests/route-r2-headless-pass/capture_log.json`: historical controls-only mission success with **zero deaths**, three combatant kills, approximately **641 m driven** and **604 m flown**, **335.04 s** gameplay/**336.73 s** process, exit **0**. It predates later visual/control changes and provides **no rendered-performance evidence**.
- `tests/route-r1-failed/`, `route-r3-failed/`, and `route-r4-failed/` retain real failed attempts. R1 exposed a road tree obstruction and repeated stationary collision damage. R3 exposed the first LOS target-exclusion implementation. R4 completed driving and flight but its helicopter followed/pinned the disembarked player. These were failures, not mission passes.
- `tests/regressions-r6.*` proves the exact R4 waterfront landing/exit pose can walk **4.003 m in one second**, versus the reproduced **0.066 m** before the fix. Vehicle bodies now inherit only world-layer platforms, and passenger collision is disabled synchronously before boarding reposition. The passenger can no longer become the vehicle's moving floor.
- `tests/soak-bound-negative/`: a short smoke stopped at **30.003 s**, returned nonzero, and recorded **zero** completions against the required three. It does not certify a 30-minute soak. The full soak mode is described below and still needs its actual long run and resource-trend review.

## Gameplay changes

- Player control position and collision changes are owned by the root agent. The occupant now follows the controlled vehicle, global position follows it, and the hidden occupant collision is disabled while seated. NPC firing explicitly aims at the controlled actor and includes vehicle bodywork in the ray mask, so a hidden occupant is not shot at the old entry position. Cars and aircraft accept damage.
- The mission measures continuous vehicle travel. Arrival on foot cannot finish the driving leg. A death restores the reached checkpoint and requires the unfinished transport leg again. Package visibility, carried-package flags, objectives, landed state, and checkpoint recovery are restored together. Delivery requires the actual on-foot interaction within reach.
- Mission restart releases control, restores health/ammunition, clears response actors, respawns the three mission guards, restores the pickup, and returns the helicopter to its primary pad. Saving while in a vehicle returns to an honest on-foot checkpoint when loaded, because vehicle simulation state is not serialized.
- Helicopters honor pause, provide damped assisted hover with neutral lift, descend at a controlled speed, reject airborne exit, and avoid applying the same impact repeatedly every tick. The scripted pilot uses ordinary lift/yaw/translation controls.
- Car collision damage uses closing speed before contact. The drivetrain is then reduced to the permitted post-contact speed; holding throttle against a wall no longer invents repeated full-speed impacts. Normal car exit changes ownership only after an exit candidate has been selected.
- Civilian lane targets are at the destination end of a road, and the fifth grid row has neighbors. Civilian traffic cruises at 12 m/s, stops for blocking actors, and follows a 28-second two-axis junction cycle. Tagged visible lamps now follow green/amber/all-red phases; regression assertions inspect the resulting emissive material states. Police response is capped at two cars and at most five officers.
- Pedestrians advance their lane waypoint only when they reach it. Spawns interpolate along segments instead of piling at junction endpoints; a focused market perimeter and damageable/reactive seated diners add activity. Current population is an explicit `PED_COUNT + DINER_COUNT` budget, and the test verifies unique actor identities. Density and rendering cost still require visual/profiling evidence. Mission combatants respond to actual damage/gunfire. Fire and aim now use real mouse-button input mappings; predecessor code incorrectly created keyboard events for the mouse numeric codes.

## Test and capture commands

Always coordinate engine ownership first. Use the project’s bounded process wrapper and an explicit writable Godot log path; the sandboxed native logger previously crashed trying to open its default user-directory log. Test and capture commands below are examples for a **new** evidence directory, not permission to launch alongside another owned engine.

```sh
python3 game/tools/bounded_run.py --seconds 75 \
  --log /tmp/orchard-tests.log -- \
  godot --headless --log-file /tmp/orchard-engine.log --path game -- \
  --test --test-report=/tmp/orchard-tests.json
```

`SelfTest` has a 40-second in-engine watchdog plus the external supervisor. Assertions have one JSON entry each, with a machine-derived total; no prose-maintained 33/34 count is inherited. Fixture repositioning is explicitly disclosed and never used by the golden-path driver. A failed parse occurs before the in-engine watchdog exists, so the external bound is still essential.

```sh
python3 game/tools/bounded_run.py --seconds 735 \
  --log /tmp/orchard-route.log -- \
  godot --log-file /tmp/orchard-route-engine.log --path game -- \
  --capture --capture-dir=/absolute/new/route-captures \
  --record-frames=/absolute/new/route-frames
```

The rendered form above needs the shared GPU slot protocol. Add `--headless` only for simulation debugging; it suppresses screenshots and cannot measure rendered performance.

`capture_director.gd` never writes player/vehicle transforms, health, wanted state, or mission stages. It injects input actions with fractional strengths and directly sets the camera-look yaw/pitch state. This is **scripted input automation**, not an ordinary native-input human golden path. It fails immediately on death or a disabled controlled vehicle, checks each transition, records state once per second, and has a 720-second wall-clock bound. Failure exits are nonzero. A route progress JSON is written while running; it is not a completion certificate.

Optional continuous recording writes viewport JPEGs at a requested 10 Hz, a `frames.jsonl` with each actual monotonic timestamp and sequence number, and `recording.json`. It is capped at 7,200 frames, 720 seconds, and 1 GiB. **The encoder must use timestamp durations**, because requested 10 Hz is not proof of delivered 10 Hz. Frame timing reports distinguish intervals including capture overhead from intervals unaffected by readback/encoding. The initial continuous-recording implementation was exercised by rendered route R1. The later strict byte/duration-cap implementation has a valid-JPEG buffer smoke test; verify any changed recording candidate in a new rendered run.

## Thirty-minute soak mode

Use `--capture --soak` with the same ownership/slot protocol and a bounded outer process limit of **1880 seconds**. Pass an explicit engine `--log-file ABSOLUTE_ENGINE_LOG` and the matching user argument `--qa-engine-log=ABSOLUTE_ENGINE_LOG` after `--`, plus a task-owned `--save-path=/tmp/...json`. Godot consumes recognized engine flags before exposing the remaining argument array; omitting the QA copy caused the retained first soak failure. Default evidence is per-gate screenshots, a still every five minutes, and one-second state/resource samples. There is **no continuous 30-minute video claim**. Optional JPEG recording has its own independent 720-second/7200-frame/1-GiB limits.

The driver must complete the genuine mission **three times**, calling the real `Mission.restart()` between attempts. Each completion record contains its own gates, combat kills, driving/flight distances and death status. Position discontinuities during a mission fail the attempt. Only the real final delivery gate can append a completion record.

After those records are sealed, a clearly labelled `fixture_assisted` phase checks pause, atomic checkpoint writing, malformed-load rejection and on-foot drive-stage rejection. Its explicit relocations and stage restoration do **not** contribute to completion count or free-roam distance. It then performs input-driven walking, driving, and flight/landing/exit free roam. The final three minutes are reserved for recovery to walking and an observation period.

Functional acceptance requires all of the following:

- At least **1800 actual monotonic seconds**, independently of any shorter smoke timeout. A `--soak-seconds` override below 1800 can never pass acceptance.
- Exactly three uninterrupted mission records, all fixture checks, and at least 100 m foot/200 m car/200 m aircraft free-roam movement.
- A real car destination/exit/same-car reboard/exit cycle and a completed free-roam aircraft destination/landing/exit cycle. Disabled controlled vehicles and failed transport gates fail.
- Terminal healthy on-foot control with the player camera, at least 30 seconds of final observation, at least 15 m of **horizontal** walking in the final 60 seconds, and walking within the last second. Earlier accumulated mileage cannot hide a late softlock.
- No unhandled runtime error found in the explicit engine log, plus a clean outer supervisor exit. The known macOS sandbox CA diagnostic is preserved/classified; other generic errors remain failures.

The driver records available Godot `Performance` monitors for objects, nodes, orphan nodes, resources, static/peak memory, render video/texture/buffer memory, draw calls and FPS. Their integer IDs were verified from the running Godot 4.7.1 class database. Renderer-only values are `null` in headless mode. The outer supervisor separately samples RSS/CPU when permitted. **Process exit is not a leak verdict:** memory/resource trends require review, and `memory_leak_acceptance_valid` remains false until that review.

## Remaining limitations

- A rendered automated route has passed for its recorded candidate; human feel/acceptance and fidelity matching remain open. Later source and asset changes need their own validation.
- The full 30-minute/three-completion soak is not implied by the short timeout smoke, the 85-assertion fixture suite, or a prior mission completion.
- Traffic remains a simplified graph simulation. Pursuit routing is direct and can be blocked by buildings. The capture driver's obstacle avoidance is an automated playtester feature, not autonomous player driving.
- Vehicles use kinematic arcade motion. The helicopter uses assisted hover, rather than rotorcraft simulation. Safe exits use a supported capsule and path checks; fully blocked car exits preserve ownership and are regression tested.
- The dummy renderer's material-null diagnostic remains unresolved in the full headless scene; a smaller actor spawn/hit/death/weapon-swap/free probe did not reproduce it. Native Metal logs must be checked separately. Do not silently whitelist the issue or convert passing assertions into a clean aggregate result.
- Builder inspection of R1 pixels found the on-foot post-helicopter camera occluded by the aircraft and the objective beacon still visible after completion. Root is correcting those presentation issues. The large realism gap versus all three approved concepts remains a visual acceptance gate, not something these mechanics tests can pass.
