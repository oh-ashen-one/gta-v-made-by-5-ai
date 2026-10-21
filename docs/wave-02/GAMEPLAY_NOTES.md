# Wave 2 gameplay and verification notes

These notes describe the mission-integrity work inside the shared Astra checkout. They are evidence-bounded, and do not certify visual fidelity, human game feel, public asset clearance, or a release.

## Verified evidence so far

- `tests/regressions-r2.json` and `.log`: **57/57** checks passed, process exit **0**, wall time **10.39 s**, child PID **91576** reaped. The JSON records the base commit, working-tree diff hash, per-source-file SHA256 values, and the explicit fixture-repositioning disclosure. These regressions check control and state contracts, not a golden path.
- `tests/route-r2-headless-pass/capture_log.json`: the **actual controls-only mission route reached DONE with zero deaths**, three mission combatants killed, approximately **641 m driven** and **604 m flown**. Recorded route duration **335.04 s**; bounded process duration **336.73 s**, exit **0**, PID **91704** reaped. It includes pickup, real weapon damage, car entry/driving/exit, helicopter boarding/flight/landing/exit, and explicit on-foot delivery interaction. This was **headless**; its frame intervals are not rendered-performance evidence.
- `tests/route-r1-failed/`: retained failure evidence. The first route killed the guards and drove 184 m, then a road obstruction and repeated stationary collision damage disabled the car. The harness returned **exit 2**, rather than walking to the helicopter and claiming success. Parent world work subsequently removed random tree colliders from the avenue; drivetrain collision response was corrected.
- The successful second route spent around 115 seconds maneuvering against the compound approach before its already-earned drive gate was assessed. The current driver now stops as soon as that real driving prerequisite is reached. The current vehicle controller also has a hull-tested 0.24 m low-kerb step for human and AI drivers. These later changes require the final integrated rerun.

## Gameplay changes

- Player control position and collision changes are owned by the root agent. The occupant now follows the controlled vehicle, global position follows it, and the hidden occupant collision is disabled while seated. NPC firing explicitly aims at the controlled actor and includes vehicle bodywork in the ray mask, so a hidden occupant is not shot at the old entry position. Cars and aircraft accept damage.
- The mission measures continuous vehicle travel. Arrival on foot cannot finish the driving leg. A death restores the reached checkpoint and requires the unfinished transport leg again. Package visibility, carried-package flags, objectives, landed state, and checkpoint recovery are restored together. Delivery requires the actual on-foot interaction within reach.
- Mission restart releases control, restores health/ammunition, clears response actors, respawns the three mission guards, restores the pickup, and returns the helicopter to its primary pad. Saving while in a vehicle returns to an honest on-foot checkpoint when loaded, because vehicle simulation state is not serialized.
- Helicopters honor pause, provide damped assisted hover with neutral lift, descend at a controlled speed, reject airborne exit, and avoid applying the same impact repeatedly every tick. The scripted pilot uses ordinary lift/yaw/translation controls.
- Car collision damage uses closing speed before contact. The drivetrain is then reduced to the permitted post-contact speed; holding throttle against a wall no longer invents repeated full-speed impacts. Normal car exit changes ownership only after an exit candidate has been selected.
- Civilian lane targets are at the destination end of a road, and the fifth grid row has neighbors. Civilian traffic cruises at 12 m/s, stops for blocking actors, and follows a 28-second two-axis junction cycle. Police response is capped at two cars and at most five officers. These simulation signal phases are **not yet connected to the visible lamp meshes**.
- Pedestrians advance their lane waypoint only when they reach it. Mission combatants respond to actual damage/gunfire. Fire and aim now use real mouse-button input mappings; predecessor code incorrectly created keyboard events for the mouse numeric codes.

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

Optional continuous recording writes viewport JPEGs at a requested 10 Hz, a `frames.jsonl` with each actual monotonic timestamp and sequence number, and `recording.json`. It is capped at 7,200 frames, 720 seconds, and approximately 1 GiB. **The encoder must use timestamp durations**, because requested 10 Hz is not proof of delivered 10 Hz. Frame timing reports distinguish intervals including capture overhead from intervals unaffected by readback/encoding. Continuous recording still needs a rendered smoke check and integrated route verification.

## Remaining limitations

- The demonstrated golden path is automated, headless, and from the startup source snapshot recorded in its packet. A rendered uninterrupted pass and the final integrated source regression run remain separate gates.
- No three-completion same-process replay, 30-minute soak, human game-feel judgment, or independent acceptance follows from these results.
- Junction simulation is simple; visible signal lamps still need phase integration. Pursuit routing remains direct and can be blocked by buildings. The capture driver’s obstacle avoidance is an automated playtester feature, not autonomous player driving.
- Car and helicopter exits now require a supported, clear player capsule and an unobstructed path; when every candidate is blocked, control remains seated. The integrated regression suite passes normal exits, but fully enclosed-vehicle fixtures remain to be added. Helicopter flight is an assisted kinematic model rather than a rotorcraft simulation.
- Godot’s headless dummy renderer emits a null-material warning during deferred actor removal. Verbose inspection identified remaining exit leaks as audio stream/playback references; explicit test audio cleanup is being verified. Bounded process completion is confirmed independently of those resource warnings.
