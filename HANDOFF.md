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

## Wave-5 changes so far (all pushed on `feature/wave-05-opus`)

1. Route automation parse error fixed (incoming blocker); landing/exit gates wait for the mission's own tick (tree-order race).
2. Kerbside parked cars on the carriageway (were astride the 16 cm platform edge in the pedestrian lane); lane-corridor traffic perception at ~8 Hz; AI stuck recovery.
3. **Opening identity:** the run now starts outdoors on a new heritage shophouse five-foot way (x=-180 row) facing the inhabited hawker hall across the x=-160 avenue, HDB slabs behind. Marina Bay Sands (real proportions, ~196 m), the ArtScience lotus and the Singapore Flyer stand on the far shore of the bay (CONCEPT-03 geography); one Supertree Grove sits in the bayside garden block beside the opening sightline; Merlion on the promenade pier facing the bay. Near-shore office towers restored on the east waterfront block.
4. Headless tools: `sightline_probe.gd` (ray-cast semantic map of what a camera sees — geometric, not a render), `perf_probe.gd` (CPU attribution), `mesh_census.gd`, `wheel_probe.gd`.
5. Performance: NPC/car simulation LOD, parked-car sleep; static batching of 9,705 primitive/prop meshes into 1,153 chunked MultiMesh draws (`--no-static-batching` disables it for A/B).
6. Articulated overlay wheels on moving provider cars, seated driver silhouettes, road-graph police pursuit, helicopter aerial envelope + ditch recovery, landable far shore, Singapore kerb markings (double yellow lines broken by white parking lots), five-foot-way pedestrians.
7. Regression suite extended to 92 checks (7 new wave-5 checks).

## Verified evidence (this wave, headless only)

- Headless scripted route: success, 0 deaths, all 13 gates, ~149–153 s on each build since the recomposition (`waves/05/evidence/headless-route*/`). Scripted input automation, not a human run, no pixels.
- 92/92 regressions, exit 0.
- Sightline probe of the real opening camera: all three MBS towers + SkyPark visible (77% of silhouette), Supertree crowns, hawker hall, heritage row, HDB (`waves/05/evidence/sightlines-headless/`). Batching verified geometry-equivalent across five views (category shares within 0.3 pp).
- CPU: headless physics tick ~11.3 → ~6.8 ms; route CPU frame p95 18.0 → 12.0 ms (shared, loaded machine).

## Not yet verified / open

- **Any rendered capture** (shared capacity still occupied by four foreign Blender renders — their leases record a 4 h max hold from 23:34–23:36 UTC). A gated auto-runner captures the unchanged wave-4 baseline the moment capacity frees.
- Rendered opening identity, materials/lighting of the recomposed skyline, rendered frame time, packaged build launch, OS-input playtest, audio listening.

## Safety

Shared coordinator `GPU_SLOT_DIR=/Users/midir/sm2-n1/_scratch/gpu`, `render_gate.py` inside the lease, `bounded_run.py`. No foreign process touched. No provider credits spent. No main merge.
