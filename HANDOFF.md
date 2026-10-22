# Singapore relay — wave 5 (final, Opus 5.5) — IN PROGRESS

Rolling handoff; updated during the wave. Not a final report until marked FINAL.

- Builder: Opus 5.5 (`claude-opus-5-5`) through Claude Code, branch `feature/wave-05-opus`.
- Fixed window: 2026-10-21T23:56:42Z → 2026-10-22T03:56:42Z (final 30 min included; verification/packaging from 03:26:42Z). No extension, no sixth wave.
- Machine: Mac Studio M3 Ultra 256 GB (verified `Mac15,14`). Engine: Godot 4.7.1.stable.official.a13da4feb, Forward+, native macOS.
- Incoming: `6b51a26` (manager archive) over Argon source `a5bf132`. Predecessor handoff preserved in `waves/05/PREDECESSOR_HANDOFF.md`.

## Incoming wave-4 validation (unchanged source, headless only)

- Headless import: clean (no ERROR lines).
- 85/85 headless regressions pass, exit 0 (`waves/05/evidence/incoming-validation/regressions_incoming.json`).
- **Script validation FAILS**: `capture_director.gd:857` parse error (`car_pos` type cannot be inferred). The scripted mission route therefore could not run at all on the incoming checkpoint; the game idled until stopped (`route_incoming_parse_error.log`). Argon's driving fix was never exercised.
- No rendered wave-4 baseline yet: shared renderer capacity has been occupied the whole time by four foreign Blender sessions (`veyr-review-fable-20261021`, actively rendering at 200–1100 % CPU). Mixed cap 2 forbids launching Godot; they are untouched. A pristine detached worktree of `6b51a26` with private assets is staged in the session scratchpad so the unchanged wave-4 `aerial_district` and opening views can be captured the moment capacity frees.

## Wave-5 changes so far

1. Fixed the `capture_director.gd` parse error (typed `car_pos`).
2. Kerbside parked cars moved wholly onto the carriageway (`KERB_PARK_OFFSET = ROAD_HALF - 1.35`). Wave 3/4 spawned them at 8.0 m, astride the 16 cm block-platform edge and inside the busy pedestrian lane — the wave-3 `05_car_entered.png` shows the chosen car on the paver sidewalk among pedestrians.
3. AI traffic perception uses a lane-width corridor instead of a 35° cone (the cone stopped traffic behind cars parked beside the lane) and refreshes at ~8 Hz per car instead of every physics tick.
4. Route automation waits (physics ticks only, no state writes) for the mission to observe touchdown before the landing gate; the helicopter's physics step runs after the mission's in tree order, so the gate raced (route1 FAIL at 206.9 s).

## Verified evidence (this wave)

- Headless scripted route `route2` on the fixed source: **success, 0 deaths, 3 kills, 222.1 s, uninterrupted, no continuity breaks**; driving leg reached the aviation compound at 143 s; flight, landing, exit and delivery passed (`waves/05/evidence/headless-route2/`). Headless = simulation only: no rendering, no screenshots, no frame-time evidence; scripted input automation, not a human run.
- 85/85 headless regressions after fixes, exit 0.

## Not yet verified / open

- Any rendered capture (blocked by shared capacity, see above), opening Singapore identity in real pixels, performance, packaged build, OS-input playtest, audio listening.

## Safety

Shared coordinator `GPU_SLOT_DIR=/Users/midir/sm2-n1/_scratch/gpu`, `render_gate.py` inside the lease, `bounded_run.py`. No foreign process touched. No provider credits spent. No main merge.
