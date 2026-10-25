# Bayfront Courier worker handoff

Updated 2026-10-25 20:20 UTC. Branch `Astra-6/downtown-activities`. Functional walking/E loop verified; ready for parent integration/visual critique.

## Implemented

- Optional heritage waterfront → MBS Event Plaza parcel → heritage receipt loop, repeatable; outbound cancellation at dispatch.
- Existing E contract with 4.5 m range, line of sight, actor identity, on-foot, alive, unpaused and non-busy guards.
- Independent card/destination badge; no Harbour Relay stage/objective/marker mutation.
- Validated versioned snapshots, completion count, reset API and explicit warning if autosave fails.
- Existing shipped crate asset reused. No asset purchases, downloads, shared geometry edits or renderer launches by this worker.

## Verified

Full r8: **31/31 PASS**, normal heritage spawn, real Player movement and E interaction. **3683.21 m**, **603.65 s**, maximum physics-step displacement **0.18395 m**, **0 jumps**, **0 deaths**, **0 teleport steps**. Bounded runner exit **0**, no timeout, **0 fatal errors**, child reaped (605.52 s including startup/exit).

The route physically crosses Jubilee and Helix, reaches the MBS ring, delivers through E, rejects duplicate delivery, preserves the story objective, restores the receipt snapshot, returns to dispatch, completes once, starts another run, cancels it without losing the completed count, and resets activity state. Range/actor/pause/busy/vehicle-mode/wall guards and invalid/fractional save payload rejection pass. Final isolated save retains one completed run and idle courier state while Harbour Relay remains stage 0/checkpoint 0.

Local fixtures: MBS ramp ingress/egress **5/5**, 446.82 m, no jumps/deaths; Jubilee → Merlion Park → heritage remainder **3/3**, 433.14 m, no jumps/deaths. These use explicitly labelled local initial spawns and do not substitute for the complete normal-spawn r8 proof.

Evidence summary and source hashes: `VERIFICATION.json`. Raw evidence: `/private/tmp/astra6-activities/route-r8-integrated.log` and `.meta.json`; local logs `mbs-local-r1.log`, `jubilee-local-r4.log`. Earlier failed logs preserve the discovered one-way lips and test-driver corrections.

## Parent-owned integrations included

- `35ba160`: bootstrap/save/New Game hooks + heritage avenue ramps (local duplicate `ddaa6fc`).
- `297043d`: MBS north promenade ramp (local duplicate `5ae259f`).
- `be86c9e`: Jubilee east landing join (local duplicate `6f7be26`).
- `667921e`: Fullerton-to-heritage promenade join (local duplicate `e206cb1`).

Do not cherry-pick those duplicate commits back into the parent. Worker-owned source/test commits are `f7933ae`, `91e5f74`, `a89d3e5`, `d051d6f`, `4909da7`, plus the final evidence commit containing this file. Root already integrated through `4909da7` per parent messages.

## Remaining gates

Actual driving/helicopter routes, rendered card/marker/prop appearance, performance, integrated roof/traffic changes and owner gameplay judgement remain with the parent loop. Headless success is not visual or owner acceptance. No worker engine remains running. API/run commands are in `INTEGRATION.md`. Private asset/reference symlinks were never staged.

## Optional stills follow-up (20:27 UTC)

Added a test-only `--courier-stills-dir=<abs>` path for six actual player-camera frames along the full route. It is disabled without the option and on headless renderers. Capture guards, metadata, toast-clearing policy and the leased render command are documented in INTEGRATION.md. The seven-case path smoke and headless no-readback/no-write check passed with exit 0, zero fatal errors in 1.76 s (`/private/tmp/astra6-activities/stills-guard-r2.log`). No GPU launch was made. The 31/31 full-route evidence above predates this optional capture-only patch; parent performs the actual rendered validation.

## Actual vehicle follow-up (20:43 UTC)

Added dedicated `tests/vehicle_handover.tscn/.gd`; full-route/capture scripts and all production files remain unchanged. Relevant production Game, Player, Car and courier code matched parent `356fc5f` at comparison time. Car-only fixture passed 27/27. Combined car + landed-helicopter fixture passed **38/38**, **33.57 s**, **zero deaths**, bounded exit **0**, **zero fatal errors** (35.49 s wrapper). It uses actual E collection/boarding/exit/delivery, 1.19 m native car throttle/handbrake movement in the combined run, actual occupied-car Game.save/load, seated handover rejection for both vehicles, native helicopter descend/set-down, and on-foot receipt completion. Initial placements and cross-city occupied-vehicle relocations are explicit local fixtures, not continuous driving/flight. Summary/hash: VEHICLE_VERIFICATION.json; raw log `/private/tmp/astra6-activities/vehicle-handover-r4.log` and metadata. No production defect or edit was required; no renderer was launched.
