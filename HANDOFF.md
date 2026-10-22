# Singapore relay — wave 5 (final, Opus 5.5) — IN PROGRESS

> **BLOCKER — manager action requested:** no shared renderer capacity for any wave-5 render, because the foreign `veyr-review-fable-20261021` loop holds four Blender renderers and refills its slots. See [`waves/05/BLOCKER_RENDER_CAPACITY.md`](waves/05/BLOCKER_RENDER_CAPACITY.md).

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

## Wave-5 changes (all pushed on `feature/wave-05-opus`)

1. Route automation parse error fixed (incoming blocker). Landing and exit gates wait for the mission's own tick.
2. Driving and parking: kerbside cars sit on the carriageway (they had been astride the 16 cm platform edge in the pedestrian lane). Lane-corridor traffic perception runs at about 8 Hz. AI stuck recovery checks behind before reversing.
3. **Opening identity.** The run starts outdoors on a new heritage shophouse five-foot way facing the inhabited hawker hall across the x=-160 avenue, with HDB slabs behind. The camera is framed so the Marina Bay Sands silhouette clears the HUD and the player. MBS (real proportions, about 196 m), the ArtScience lotus and the Singapore Flyer stand on the far shore of the bay. The Supertree Grove is in the bayside garden beside the sightline, and the Merlion is on the promenade pier. Supporting signage: Tembusu Food Centre board and street-name blades.
4. Performance: NPC/car simulation LOD, parked-car sleep, NPC draw range plus animation pause beyond 150 m. 10,161 static meshes merged into 1,107 MultiMesh draws (district mesh instances 11,064 → 909). `--no-static-batching` turns the merge off for A/B.
5. Vehicles and pursuit: articulated overlay wheels, seated drivers, junction-grid police pursuit with committed waypoints and a mid-block endgame, pursuit telemetry.
6. World: landable far shore, helicopter aerial envelope and ditch recovery, Singapore kerb markings, five-foot-way pedestrians.
7. Audio: click-free engine/rotor loop seams, a whole-cycle siren, a soft-saturated gunshot, objective seam and peak checks (no listening).
8. QA: sightline, perf, census, wheel and two-process save/relaunch probes. QA entry points fail fast. The regression suite is up to 96 checks.
9. Four fresh-context critic passes (Opus subagents, code-only; the last was a whole-diff release review): 8 major/high and 11 minor/low findings fixed or documented (`waves/05/evidence/critic_review_*.md`).
10. A 30-minute headless soak found and drove a real fix: carjacked drivers had stood frozen in the road, and invulnerable pedestrians wrecked the car. Vehicles now injure or scatter pedestrians, displaced drivers rejoin a pavement, and there is one impact per person per 0.6 s.
11. Title screen shows the opening skyline; notifications sit below it. Far-shore planting clears the landmarks. A downed out-of-bounds pilot is recovered.

## Verified evidence (headless only, unless a rendered capture is linked)

- Headless scripted route: success, 0 deaths, 13/13 gates, about 149 s on every build since the recomposition.
- 96/96 regressions, exit 0.
- Packaging pipeline dry run at `2b0331c`: export, ad-hoc signed private copy, **95/95 packaged regressions**, packaged two-process save/relaunch, packaged headless route success at 149.0 s. The final package is rebuilt from the final commit.
- Sightline probe of the real opening camera: all three MBS towers and the SkyPark, Supertree crowns, Flyer, hawker hall, heritage row and HDB in frame. Batching is geometry-equivalent in five views.
- CPU (shared, loaded machine): physics tick about 11.3 → 4.5–4.9 ms; route CPU frame p95 18.0 → 12.0 ms.

## Rendered capture plan / status

- No rendered frame yet. Four foreign Blender renders hold the shared capacity. The coordinator's 4-hour max-hold limit ends their leases at about 01:58 UTC (one) and 03:35–03:37 UTC (three).
- A gated runner (`scratchpad/bin/auto_render2.sh`: lease → `render_gate.py` → `bounded_run.py`, one engine at a time, no launches after 03:50:30 UTC) captures, in order: candidate opening/gameplay photos, the **unchanged wave-4 baseline** (`aerial_district` (250,95,250)→(-40,0,-60) FOV 62, then the wave-4 opening), candidate fixed views, then a rendered candidate route. It uses the signed final package only after that package is marked final. See `waves/05/BASELINE_W4.md`.

## Known incidents

- One save-probe run without `--qa-session`, at 00:55 UTC, wrote the game's default user save slot (`~/Library/Application Support/Godot/app_userdata/Orchard Reach/orchard_reach_save.json`) with probe data. The file was removed, and the probe now refuses to run without a task-owned path. If a player save existed there before 00:55 UTC, it was overwritten at that point; it cannot be restored.

## Safety

Shared coordinator `GPU_SLOT_DIR=/Users/midir/sm2-n1/_scratch/gpu`, `render_gate.py` inside the lease, `bounded_run.py`. No foreign process touched. No provider credits spent. No main merge.
