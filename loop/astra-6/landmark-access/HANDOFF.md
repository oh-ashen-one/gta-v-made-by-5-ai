# SkyPark public access — Astra-6

Builder: inherited Codex session model. Branch `Astra-6/landmark-access`.
Shared brain `3338091d3754` verified via sync 2026-10-25. Parent owns rendered lane and main integration.

## Integration

After player/world creation, load `res://src/world/downtown/skypark_access.gd`, add the Node3D to main, call `setup(world, player)`. The module registers the two lift stations in `interactables` and itself in `skypark_access`. It adds no input handler: normal player E selection calls it.

- Ground arrival `(-78, 1.6, -658)`; lift station 2 m toward the Shoppes.
- Roof arrival `(-39, 200.1, -698)`; return station 2 m landward.
- Enclosed public terrace: x `-88..-34`, z `-707..-689`, existing deck top y `200`.
- Small helicopter landing marking `(-63, 200, -698)`, radius 5 m. Exit permission only within 2.5 m of center.
- World location keys: `skypark_public_lift`, `skypark_public_terrace`, `helipad_skypark`.

No Game/player/save-file API change. Transit changes position, orientation and motion only; health/wanted/story/courier remain intact. The regular save stores the exact new position; native save/load tested. The safe death recovery checkpoint is the ground arrival. No position-clamping of legitimate saves.

## Plan amendment (parent approved)

Only `HELIPADS.skypark` and the optional per-pad `exit_radius` lookup changed in plan.gd. Other pads retain radius+4 default. SkyPark status `public` deliberately skips Bounds._helipads, which only builds `new` pads and assumes ground y=0. The access module paints the roof ring/H on the existing deck, adds no landing slab, and provides the necessary public return lift. Do not integrate the pad change without the main setup hook.

## Geometry

Preserves original MBS towers/hull/pool/palms/pavilions; no imported models or purchases. Existing roof has a supporting collision box but its glass rails/pavilions were visual only. New 2.4 m glass screens and matching collision enclose the limited public terrace between the center/south pavilions, excluding the pool and planter beds. The compact lift headhouse uses existing landmark materials. Rooftop entry and return use explicitly labelled in-game lift transitions.

## Verification and remaining gate

Dedicated test: `game/src/systems/skypark_tests/access_test.tscn`. It labels all initial test fixture placements; the flight leg uses only inputs after the initial airborne fixture. This is not evidence of walking from the heritage start.

Run bounded headless with `--qa-session <private-dir>`; optional parent-rendered screenshots use `--skypark-stills-dir=<absolute-dir>`. Screenshot names: `ground_lift_approach`, `public_terrace_arrival`, `flight_landed_pad`, `flight_pilot_on_terrace`.

The test proves the existing Event Plaza ramp works without jumping; real E up/down; remote/LOS/dead/paused/busy/occupied/mode/foreign-actor guards; arrival obstruction rejection; exact native saved position; continuous terrace floor; controller walking/jumping against all four screens; eight helicopter headings and safe pilot exits; a conservative 6 m rotor/tail clearance cylinder; controls-based climb/approach/descent/landing, E exit, walk to return lift, E to ground. Headless physics is not rendered visual/performance approval. Parent must capture and independently review appearance and whole-city integration.

Final headless candidate r6: **48/48**, exit 0, zero engine errors, 74.83 s. Evidence: `verification.json`, `access-r6-checks.txt`. North promenade ramp (separate commit `297043d`) also passed a real controller no-jump crossing from x=-325 to x=-310 at z=-632. Flight touchdown (-63,199.701,-697.9833), max step 0.180 m, no aircraft damage. Final test source hashes recorded with evidence.

R4's sole failed floor probe hit the newly added viewing bench at y=200.5 instead of the deck. The structural floor grid now excludes only the access module's furniture collision body while ray-testing the unchanged MBS deck beneath it; the physical bench and rail collision remain enabled for actual movement tests. R5/r6 passed.

## Critic follow-up: production integration and recovery coverage

Parent hook `0cf9289` was cherry-picked here as `8a79c7f` solely to test the actual production main. **Do not cherry-pick `8a79c7f` back into the parent**, which already owns that change. The follow-up test commit contains only the test and its evidence/documentation.

The test now asserts that main created the SkyPark access node; missing integration fails immediately, with no automatic bootstrap. It uses actual E exits at eight center headings and eight permitted boundary fixtures, checking aircraft floor contact separately for every case, followed by pilot floor contact, visibility, collision masks and foot mode. Four outside-boundary fixtures exercise actual E refusal. Cardinal boundary cases use exactly 2.50 m; diagonals use 2.49 m to avoid floating-point rounding ambiguity.

The normal lethal-damage path is exercised after taking the lift up. The test checks one death, recovery on the ground, full health, visible/alive player, normal collision and controls, walking away/back, and lift reuse. Finally it saves a distinct rooftop position, destroys the entire game scene, verifies player/access removal, rebuilds normal main, native-loads the exact rooftop position, checks physical floor support and controls, walks back, and returns via E.

Fixture placements remain explicitly labelled; no added human-playtest or full-city traversal claim. The rendered visual/performance gate remains separate. No production behavior change was needed for this follow-up.

Final follow-up r8: **116/116**, exit 0, zero engine errors, **101.25 s**, including exact cardinal 2.50 m exit boundaries and full fresh-scene native save/load. Evidence: `verification-r8.json`, `access-r8-checks.txt`. Prior expanded r7 also passed 116/116 (100.43 s) with its cardinal samples just inside the boundary.
