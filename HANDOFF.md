# Orchard Reach — Opus 5.5 enhancement loop (rolling handoff)

- Branch: `Opus-5.5-enhancements` (remote `origin/Opus-5.5-enhancements`). Never merge or push `main`; that needs the owner.
- Run window: START 2026-10-22T06:28:30Z, FEATURE FREEZE 11:43:30Z, DEADLINE 12:28:30Z. The run is **finished**. Run record: [`loop/RUN.md`](loop/RUN.md); pieces and verdicts: [`loop/PIECES.md`](loop/PIECES.md); progress page: `python3 loop/make_progress.py` → `progress/index.html`.
- Machine: Mac Studio (`midirstudio.local`), Godot 4.7.1 Forward+, Metal for renders.
- Last update: final integration C, 2026-10-22 ~11:45Z. Last game-code commit `32e08ba`; the commits after it only add loop/progress/handoff records.

## What is merged

| Piece | Wave | Merged commit (merge) | Critic verdict vs GTA V | Better than baseline (critic) |
| --- | --- | --- | --- | --- |
| water | A | `e3eef3e` (`ca6591d`) | OURS LOSES, 4/4 rounds | yes, every round |
| skyline | A | `5e58313` (`9d849b4`) | OURS LOSES, 4/4 | yes in A3 and A4 |
| lighting | A | `301a7c9` (`ffc3b01`) | OURS LOSES, 4/4 | no; regressions fixed in `4d9af26` |
| materials | B | `24634e2` (`e83385b`), `98490b9` (`e4ab271`) | OURS LOSES, 3/3 | no; B2 regression fixed by its r3 |
| on-foot | C | `35c1ba4` (`bf7929a`) | OURS LOSES, 2/2 | no (prop pass-through, camera clip); judged net-positive |
| helicopter | C | `ceb507a` (`96920d1`) | OURS LOSES, 2/2 | C1 yes, C2 no; photo_09 mast fixed in `32e08ba` |
| driving | C | `f38e77e` (`8017454`) | OURS LOSES, 2/2 | no; C2 critic found no regression in other views |
| street-life | A | **not merged** | OURS LOSES, 2/2 | no |

Street-life: the fix branch `opus55/street-life-fix` (`5a98b9f`, pushed; worktree `.worktrees/street-life-fix` kept) passed a rendered route 13/13, but on the merged line 2 of 4 headless routes failed (player-car/ambient deadlock at the (-160,0,0) junction; the player car destroyed by collisions with ambient traffic). It was not safe to merge before feature freeze.

Seam fixes on the integration line: `4d9af26`, `0c36d4b`, `d3133d1` (wave A: Merlion jet/pier, sky/haze, lighting, water foam/spray, QA save guard, render gate); `32e08ba` (final: helipad flood masts rotated 22.5° so none stands in front of the fixed `photo_09_airfield` camera; the camera itself is unchanged). The driving merge also closes the open "scripted drive runs through the median planters" regression (solid medians, keep-left waypoints; checked in the rendered `06_driving` frame).

## Verified (final game code `32e08ba`)

- **Headless:** `--test` 140/140 PASS (21 s). `--capture` route 13/13, 0 deaths, 153.4 s route time, exit 0, 0 fatal lines. Same results on the driving merge `8017454` before the seam fix.
- **Rendered** (real Metal frames, 1280x720, `loop/render.sh`; the GPU lease reported `contaminated=no-exclusive-lock`, so timings are approximate):
  - `--capture` route on `32e08ba` (the Done-checklist run, no other renderer of mine running): **13/13, 0 deaths, 155.2 s, exit 0, 0 engine errors.** Frame times excluding readback over 11,869 frames: mean 12.8, p50 12.7, p95 18.5, p99 21.4 ms, max 400 ms. The only non-capture stalls are the 3 load frames (388/400/138 ms).
  - `--capture` route on `8017454` (driving merge, before the mast fix): 13/13, 0 deaths, 154.4 s, exit 0, 0 engine errors. Frame times excluding readback over 10,942 frames: mean 13.8, p50 13.2, p95 20.1, p99 25.8 ms, max 1531 ms. Non-capture stalls: the 3 load frames plus 1531 ms at 123.2 s, 332 ms at 134.4 s and 318 ms at 140.2 s. This run overlapped my own --photos/--gameplay-photos renders, and the stalls did not recur in the clean run on `32e08ba`.
  - `--photos` (18 views) on `32e08ba` and `--gameplay-photos` (7 views) on `8017454` (the mast change does not touch those views): exit 0, 0 engine errors.
  - Comparison: wave-5 baseline route 11.8 / 11.7 / 17.1 / 18.7 ms (mean/p50/p95/p99); integration A 15.0 / 14.7 / 22.4 / 26.9 ms.
  - Images: `progress/img/integration/C/` (same names as `progress/img/baseline/`), plus A and B.
- What the integrator saw in the final frames: blue sky with a warm low sun; the bay reads as water with reflections, boats and wakes; a layered far skyline with the rebuilt landmark trio and Supertrees; shophouse streets with parked cars, bins, bike-share bikes, planted medians and SG plates; the scripted car keeps left of the median; the helipad view is unoccluded. Lighting, water, skyline, materials and traffic read as one place in the standard views. No z-fighting or floating props were spotted in the views checked (photo_01/02/06/09, gameplay 01/05, route 05/06/07/09); not every frame was inspected at 100%.

## Honest status against GTA V

All 23 blind critic rounds (water 4, skyline 4, lighting 4, materials 3, street-life 2, on-foot 2, helicopter 2, driving 2) returned **OURS LOSES**, and no critic was wowed. **No piece is preferred over GTA V.** The build is much better than the wave-5 baseline, but it is not close to GTA V. The next biggest gaps, from the latest round notes:

1. **Street life and traffic density** (driving-C2, materials-B1, street-life): junctions are empty. On the rendered drive leg there was no same-direction traffic ahead in 100% of frames, and no moving traffic within 80 m in 92%. Crowds are clones of one model, and some reuse the player's outfit. Street-life is the fix, but it needs deadlock-proof AI first.
2. **Character fidelity** (on-foot-C2): hair, face, skin and cloth folds at close range; faceted shading and self-shadow blotches on the player's shirt and trousers.
3. **Lighting and shadows from the air** (helicopter-C2, lighting-A4): weak lit/shadow face contrast on towers, little specular on glass, aerial perspective too flat beyond about 3 km.
4. **Near-field material fidelity** (materials-B3): blockout-looking kerbs, sign bases and median plants; asphalt mottling.
5. **Hero vehicle** (driving-C2): paint grain, no clear-coat reflections on the trunk or glass, flat-black contact shadow. Collisions stop the car dead with no deformation or debris; oversized spark bars on kerb scrapes.
6. **Helicopter** (helicopter-C2): main rotor invisible in most chase frames; bare dirt lots around the aviation compound; flat white downwash decals on the water.
7. **Placeholders:** primitive scooters, bikes and cart with no collision (on-foot-C2); blank signposts; floating grey cubes above the shophouse roofs and a translucent blue slab on the five-foot-way (driving-C2).

## Open issues

- **Performance:** the final rendered route (p95 18.5 ms) is close to the baseline (17.1 ms) and better than integration A (22.4 ms). One earlier route on `8017454` had a 1.5 s stall at 123 s while two of my renders shared the GPU; it did not recur alone. Timings are from a shared, non-exclusive GPU lease.
- **Collision gaps:** parked scooters and bikes have no collision; the player and an enemy interpenetrate at a hawker table (combat gate).
- **Camera:** the route camera clips into a pedestrian's head at the hawker-centre entrance for about 0.3 s; it sits flush against thin signposts.
- **UI:** "Vehicle entered. [E] to exit." and "[E] Exit vehicle" show at the same time (also in baseline).
- **Harness:** `--heli-review` shows a stale objective. `09_junction_tyre_marks` in `--drive-showcase` puts the camera inside an awning.
- **Save-slot hazard:** other sessions' route runs rewrote the player's real save slot earlier in the run. This branch has the QA save guard; always pass `--qa-session`, and `--save-path=` on branches without the guard.
- **Render gate:** `render_gate.py` counts Homebrew `godot` renderers; expect refusals when other sessions render.

## How to run

```sh
cd <checkout>                     # this directory
godot --headless --path game --import                                   # fresh worktree only
python3 game/tools/bounded_run.py --seconds 300 --log /private/tmp/opus55/<you>/test.log -- \
  godot --headless --path game -- --test --qa-session /private/tmp/opus55/<you>
python3 game/tools/bounded_run.py --seconds 400 --log /private/tmp/opus55/<you>/route.log -- \
  godot --headless --path game -- --capture --capture-dir=/private/tmp/opus55/<you>/cap --qa-session /private/tmp/opus55/<you>
bash loop/render.sh <label> 420 /private/tmp/opus55/<you>/route -- -- --capture --qa-session /private/tmp/opus55/<you>/route \
  --capture-dir=/private/tmp/opus55/<you>/route/cap --qa-render-size=1280x720
```

Other game modes: `--photos`, `--gameplay-photos`, `--drive-showcase`, `--perf-probe`, `--sightline-probe`, and `--soak` together with `--capture`. Lighting diagnostics: `--lighting-off=ssil,ssao,pcss,lut,fog,vfog,glow,skyamb`. Frame-time numbers are in `<capture-dir>/capture_log.json` (`frame_times`, which excludes readback) and `frame_stalls.jsonl`.

Kept branches and worktrees: `.worktrees/street-life` and `.worktrees/street-life-fix` (not merged). The merged piece worktrees were removed; their branches `opus55/{water,skyline,lighting,materials,on-foot,helicopter,driving}` are kept.

## Previous

- **Wave A integration** (~10:40Z): water, skyline and lighting merged with seam fixes; 131/131 regressions; route 13/13 headless and rendered.
- **Wave 5** (Opus 5.5, 2026-10-21/22, branch `feature/wave-05-opus`): final candidate `98b41b2`, rendered-verified fallback `d2a6cad`. Both are private native macOS packages in the git-ignored `package-wave05/`, ad-hoc signed only, not cleared for public redistribution of provider assets. Results: 97/97 regressions; route 13/13 (147.6 s headless, 149.1 s rendered); a 30-minute headless soak completed. Details: [`waves/05/RELEASE_REPORT.md`](waves/05/RELEASE_REPORT.md), [`waves/05/evidence/rendered/README.md`](waves/05/evidence/rendered/README.md). Known incident: a save-probe run at 00:55Z overwrote the player save slot.
