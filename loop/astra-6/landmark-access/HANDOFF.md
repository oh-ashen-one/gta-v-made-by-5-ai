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

## Rendered critic follow-up: signs and a lived-in viewing area

Inspected parent captures `ground_lift_approach.png` and `public_terrace_arrival.png` from `/private/tmp/astra6/render-skypark-r1/shots`. The white canopy projected in front of the lower lift sign line. Both lift sign panels/text are now above the canopy (panel center 3.65 m, 1.1 m tall; enlarged text), below the existing pavilion roof height. The test lets the deliberate arrival-obstruction warning expire normally before positive-flow stills and asserts it is gone. It never clears the HUD or unrelated message history.

The western viewing area now has two small planted beds, existing benches, a visible viewing/return-lift sign and three actual NPC visitors using the existing CharacterVisual/CrowdPeople APIs. Local visitor subclasses retain native animation, damage and panic, constrain flee motion to x32..43 relative to MBS, then return to idle rather than adopting a street lane. They are not part of the global traffic/crowd pool. Added metal posts every ~3 m and a hand-height rail make the existing glass windscreen legible; collision bounds are unchanged. No new purchased assets or textures.

The optional capture run adds `terrace_viewing_area.png`: the player actually walks to the viewing area and looks toward the visitors, before the panic fixture. The original four captures remain. The original arrival view still faces the bay, so this additional view is important for reviewing the western seating area honestly.

Final r10: **126/126**, **121.82 s**, exit 0, zero engine errors. All prior 116 checks remain. Added checks prove notification expiry, three physical NPCs with loaded characters/floors, a walk to the seating area, and a full 13-second panic-to-idle cycle with visitors outside aircraft clearance and supported on the roof. Evidence: `verification-r10.json`, `access-r10-checks.txt`. No renderer was launched for this follow-up; parent fresh render and critic acceptance remain open.

## Native combat diagnostic follow-up — FAILED ragdoll gates retained

Only tests and an inaccurate flee-clamp comment changed after `781e149`; normal damage, stagger, ragdolls and world collision are unchanged. The clamp bounds voluntary flee velocity. Native CombatFx stagger calls move_and_collide separately, and lethal hits start physical ragdolls; neither is guaranteed confined by that velocity clamp.

The test now dispatches the actual `Events.shot_fired` signal and checks all visitors react. Native nonlethal `take_damage(45, ..., false)` fixtures exercise maximum-clamped stagger from four viewing-area bounds, with explicit fresh-health/position setup for each. One native lethal150-damage fixture at the eastern viewing bound pushes toward the pad. Damaging fixtures run after all positive-flow screenshots and native scene/load checks. The optional `combat_ragdoll_after_fallback.png` is **diagnostic casualty evidence only**, never gameplay-progress imagery.

- R11 full: 136/138, exit1, zero engine errors. Far observer. Native guard +1; min PhysicalBone3D node y198.835, nearest bone to pad9.995m. Its initial bone-count assertion wrongly used13 from the native file header; actual `Ragdoll.BODIES` contains12. The corrected test follows the native schema and keeps stability/floor criteria separately.
- R12 full: 140/142, exit1, zero engine errors,140.18s. Observer takes E lift and walks near NPCs. Maximum-strength live nonlethal clearance passed (closest11.951m). Native guard +1, min bone-node y198.049, nearest corpse bone9.990m. Both native ragdoll stability and bone-node floor gates FAIL.
- R13 full: 140/142, exit1, zero engine errors,140.46s. Same two FAIL gates. Min bone `PB_upper_arm_l`, frame33 after the initial5-frame wait: node and PhysicsServer RID origins both(-74.26186,199.0729,-698.5929); actor root y199.9801, visual/skeleton roots y200.0002. Closest corpse bone9.357m remains outside9m clearance.
- R14 final-source focused probe: 14/16, exit1, zero engine errors,32.01s. Same hard FAIL gates retained. This diagnostic starts sampling2 physics frames after lethal damage and records183 physics/process samples. It adds simulator state, influence, guard state, physics RID transform and corresponding skeletal pose. It is not a replacement for the full R13 suite.

R14 phase distinction: active-simulation samples468; minimum bone-node y199.717575, minimum PhysicsServer body y198.294739. After fallback both minima are198.294739. Worst node sample is `PB_head` at frame39: node/RID(-74.41492,198.2947,-700.0572), simulation=false, influence=0, guard.tripped=true; corresponding skeletal pose(-74.95982,200.6415,-699.5052), visual/skeleton root y200.0002, actor root y199.9801. Native guard says `y=-1.83 h=2.14 PB_head`. Nearest corpse bone10.115m, live nonlethal nearest11.951m: aircraft-clearance checks PASS. The low post-fallback physical-bone-node value does **not** establish visible-mesh penetration; no rendered casualty frame was captured. The active RID minimum and instability fallback remain an unresolved native physics limitation.

The existing MBS deck collider is8m thick (200 down192), so no speculative thin-floor change was made. Baseline `/private/tmp/astra6-traffic/test-r2b.log:89` also reports a native guard fallback (`y=-1.16 ... PB_upper_arm_r`) while its older self-test accepts the authored end-pose result. Our stronger stability gate intentionally continues to fail rather than hiding that fallback or claiming a new SkyPark-only defect.

Evidence is preserved in `access-r11-checks.txt`, `access-r12-checks.txt`, `access-r13-checks.txt`, `access-r14-probe-checks.txt`, and `combat-verification.json`. Reproduce the quick diagnostic with the normal test scene, isolated `--qa-session`, and `--skypark-combat-probe`. No renderer or foreign process was touched.
