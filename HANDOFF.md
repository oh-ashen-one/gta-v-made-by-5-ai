# Orchard Reach — Opus 5.5 enhancement loop (rolling handoff)

## Milestones
- **Week 1 DONE as of 2026-10-23T21:13:30Z** (owner, 2026-10-23). Final state: `main` @ `639ef5c` (git tag `week-1`), build
  `~/Builds/OrchardReach-639ef5c.zip` on the Studio. Covers the five-AI relay waves 1-5 and Opus 5.5 runs 1-2 (waves P-T,
  central Singapore / Marina Bay core). **Week 2 starts with the first session after this timestamp**; its work goes on a new
  branch cut from `main` (e.g. `week-2/<topic>`), and it should begin from the owner's playtest notes on 639ef5c plus the
  "next biggest gaps" below.

## Run 2 STOPPED and merged to `main` (owner, 2026-10-23 ~20:55Z)
- The owner stopped the loop (usage limit) and asked for everything to go to `main` with old branches cleaned up.
  `Opus-5.5-enhancements` was fast-forwarded into `main` (main had not moved since `2c66caa`).
- Wave T (performance T1, traffic-flow T1, downtown-fill T2, characters T3) is merged with integrator seam fixes
  (lane cars vs. people beside the body, downtown-fill view wedges + near-field turf, zebra holds give up after 8 s).
  **The wave T integration checks were stopped by the owner before they ran** (he tests himself): the last fully verified
  state is wave S (`8b561f8`, below). Wave T is NOT regression-tested or rendered.
- Every blind A/B round vs GTA V so far is a loss; none wowed. Best build so far, north star not accepted.
- Next biggest gaps (wave T critics): hero character close-up (skin detail, expression, hair strands, cloth folds, hand
  poses); near-field plaza floor + props (use `plaza_granite_pavers`); near-tower facades (use `tower_curtainwall_mullion`
  and `tower_stone_punched`); reflective car paint, long sun shadows, skyline haze layers. Generated textures are listed in
  `loop/GENERATED_ASSETS.md` (git-ignored images, Mac Studio only).
- Unmerged piece branches were archived as tags `archive/opus55-*` before their branches were deleted.
- Records: [`loop/RUN.md`](loop/RUN.md), [`loop/PIECES.md`](loop/PIECES.md), `progress/index.html`. Render only through
  `loop/render.sh` (shared GPU lease). Machine: Mac Studio, Godot 4.7.1 Forward+.

## What is merged now (wave S, 2026-10-23)

| Piece | Merged commit (merge) | Critic vs GTA V | Better than baseline (critic) | Notes |
| --- | --- | --- | --- | --- |
| characters | S1 `6a4a45e` (`5913ed7`) | OURS LOSES S1 | **yes** | Civilians on the baked look mesh (bake `r1s`, git-ignored, present in this checkout). The street-life person is mapped to look-shader parameters. |
| performance | S1 `47280d2` (`45da451`) | OURS LOSES S1 | no (felt fps, startup stall, test flake) | Occlusion culling, threaded preload, PerfDirector, packaged look-bake fix. Draws -43 %, load -49 %. |
| downtown-life | S1 `5e15dc5` on `opus55/street-life-fix` (`96113a3`) | OURS LOSES S1 | no (floating walker, zebra stops, group poses) | Crowds at the lens downtown, plaza benches/carts/photo groups, lane cars seeded near the focus. |
| downtown-polish | S1 `ae78533` (`35a03b9`) | OURS LOSES S1 | no (aerial dark planes / floating slabs, sunk cars, lamps, deadlocks) | Layered planting, altitude-aware sun shadows, denser Marina Centre, corner plaza, Helix ramps. |

Seam fixes: `cb1b1d4` and `8b561f8` (details in PIECES.md):
- Walkers' plaza lines and walk-backs are checked for ground, so nobody crosses the river in mid-air.
- The tower ground-shadow overlay is a depth-tested decal that fades out from the air (no dark planes on the bay, no floating podiums, no torn fragments).
- Downtown lane cars follow the bridges' cosine deck profile and pitch with it (no cars sunk in the decks).
- Brake lamps are seated on the provider body surface (they no longer hover behind the boot).

Earlier waves (M, Q, P, run 1) are all on this line; see PIECES.md. Still parked: `opus55/aerial` (`572317a`, rR1 OURS LOSES).

## Verified (game code `8b561f8`)

### Headless
- `--import` clean. `--test` **255/255**: once on the four-merge head and 3 of 3 runs after the seam fixes. The perf critic's 1-in-4 traffic flake did not recur in these 4 runs.
- `--capture` route **13/13**, 0 deaths:
  - 155.2 s on the merge head.
  - 205.5 s after the fixes. That run had three suites running alongside it, and a box-in at the aviation gate cost ~30 s; the driver backed out.
- `--downtown-review`:
  - The walk (36/36 to MBS) and the flight (land at NS Square, get out) pass.
  - The drive did **not** finish within 1,200 s: it was stuck at the Raffles Ave / Bayfront Ave corner (-775, -799).
- The tests were run on the combined four-merge head, not after each merge separately.

### Rendered (1280x720 Metal through `loop/render.sh`; lease `contaminated=no-exclusive-lock`; other work had the GPU 48-79 % busy)
- `--capture` route **13/13, 0 deaths, 161.9 s, 0 engine errors**.
- Frame times excluding readback, over 6,209 frames: mean **25.5** / p50 **23.2** / p95 **34.5** / p99 **64.8** ms. Max draw calls **10,527**. Load (`world_ui_ready`) **7.9 s**.
  - For comparison, M: 30.8 / 30.4 / 47.7 / 60.1 ms, 12,786 draws, 13.6 s load. Q (before downtown): 14.5 / 20.5 p50/p95.
  - Better than M, but still well above Q.
  - Startup stall 1124 + 758 ms (M 1020 + 822); the perf branch alone had 1562 ms.
- `--photos` 29 and `--gameplay-photos` 7: exit 0, 0 script errors. photo_29 and dtx_heli_bayfront match M again, with longer shadows.
- `--downtown-review`:
  - The **drive loop completed** in 662.8 s, but 317.5 s of it was spent waiting, with 4 tows of ambient cars stalled at Collyer Quay.
  - **Walk 36/36** to MBS. **Heli landed at NS Square** and the player got out.
  - Perf sweep p50 16.4-20.1 ms.
  - Cars on the Esplanade and Bayfront decks now sit on the deck.
- JPEGs (quality 70, 1280 wide) are in `progress/img/integration/S/`, with the same names as `integration/M/`, plus extra `downtown_*` drive and walk stills.

## Honest status against GTA V
Every blind round in run 2, including all four S1 rounds, returned **OURS LOSES**, and no judge was wowed. The latest named gaps:
1. **Hero materials and light:** the player car needs sharp clear-coat and glass reflections, crisp panel gaps, and no stray stripe on the trunk. The scene needs late-day raking light (long shadows, warm/cool grade) instead of flat high-noon light. (performance S1, downtown-polish S1)
2. **Dressed street frontage:** lit shopfronts with interior content, signs, awnings and pavement props within 15 m. (downtown-life S1)
3. **Characters at 2 m:** skin specular breakup and SSS, hair clumps, anatomical arms, wrapped grips. (characters S1)
4. **Aerials:** boxy uniform towers, flat ground and sparse identical trees make the city read as a scale model.

## Open issues
- **Downtown traffic deadlocks:** at the Fullerton/Collyer Quay x Cecil St junction (4 tows in the rendered drive), and at the Raffles/Bayfront corner (headless drive stuck). Cars also stop on zebra crossings (Marina Blvd, Cecil/Market).
- **Performance:** rendered p95 34.5 ms on a busy shared GPU, against a 22 ms target. physics_ms is 7-9 ms per frame. gpu_ms reads 0 on Metal.
- **Packaged first launch:** 12.3 s (build_grid lap 3.5 s); measured by the perf critic, not re-measured here.
- **Not yet fixed from the critics:**
  - talking-group pose artifacts (jagged hems, arms through torsos)
  - street-sign text cut by its pole (`Esplana|e Drive`)
  - civilians in the airborne 'jump' clip when not on the floor (pre-existing)
  - an orphaned shopping bag when its carrier is near-lens culled
  - skirts as shells over trousers, and flat card backpacks
  - female fixtures with a male haircut
  - the MBS arrival is a dead frame (no entrance or people)
  - Merlion Park / NS Square are empty
  - the helicopter rotor is nearly invisible in chase frames
  - the drive-showcase still 12 puts the camera inside the car
  - the warped Esplanade waterfront paving
  - the 'SALAD STOP' sign echoes a real chain (brand risk)
- **Hygiene:** `.worktrees/characters` held ~2,000 untracked Finder ' 2' duplicates. They were never committed. See the cleanup note in RUN.md.
- Never use the save slot: always pass `--qa-session <own dir>`.

## How to run

```sh
cd <checkout>                     # this directory
godot --headless --path game --import                                   # fresh worktree only
python3 game/tools/bounded_run.py --seconds 400 --log /private/tmp/opus55/<you>/test.log -- \
  godot --headless --path game -- --test --qa-session /private/tmp/opus55/<you>/t
python3 game/tools/bounded_run.py --seconds 500 --log /private/tmp/opus55/<you>/route.log -- \
  godot --headless --path game -- --capture --capture-dir=/private/tmp/opus55/<you>/cap --qa-session /private/tmp/opus55/<you>/r
bash loop/render.sh <label> 600 /private/tmp/opus55/<you>/route -- -- --capture --capture-dir=/private/tmp/opus55/<you>/route/out \
  --qa-render-size=1280x720 --qa-session /private/tmp/opus55/<you>/route/session
```

- Review modes: `--photos`, `--gameplay-photos`, `--character-review`, `--street-review` (+ `--people-review`),
  `--landmark-review`, `--downtown-review`, `--heli-review`, `--combat-review`, `--drive-showcase`, `--locomotion-review`.
- Probes: `--render-budget` (rendered only), `--perf-probe` (headless CPU), `--sightline-probe`, `--soak` with `--capture`.
- A/B switches: `--street-life=off`, `--landmarks-off`, `--blocks-off`.
- Frame times: `<capture-dir>/capture_log.json` (`frame_times` excludes readback) and `frame_stalls.jsonl`.
- A/B switches added in wave S: `--tower-shadows-off`, `--aerial-light-off`, `--facade-sun-off`. Packaged-build renders use `loop/render_packaged.sh`.
- Worktrees: merged piece worktrees are removed after the push; their branches are kept. Still present: `.worktrees/aerial`,
  `.worktrees/street-life` (the older `opus55/street-life`), and any worktree that still held uncommitted work at cleanup (see RUN.md).

## Previous
- **Wave-M integration** (2026-10-23 ~11:45Z, game code `996e35c`): street-life, nearfield R1+R2b, characters R2 (player look mesh); 234/234; route 13/13 headless and rendered; rendered p95 47.7 ms, load 13.6 s.
- **Wave-M downtown pre-integration** (2026-10-23 ~10:40Z, game code `5c30e70`): downtown map, landmarks and blocks merged
  with seam fixes; 203/203; route 13/13 headless and rendered; owner asks (drive the loop, walk onto the Marina Bay side,
  land downtown and get out) PASS headless, heli also rendered. Package `/Users/midir/Builds/OrchardReach-5c30e70.zip`.
- **Wave Q integration** (2026-10-23 ~02:50Z, `359fa91`): driving Q2, combat, locomotion merged; 164/164; rendered p95 20.5 ms.
- **Wave P integration** (2026-10-22 ~20:50Z, `acffbe0`): locomotion, combat, driving, helicopter; rendered p95 19.9 ms.
- **Run 1 final integration C** (2026-10-22 ~11:45Z, `32e08ba`): water, skyline, lighting, materials, on-foot, helicopter,
  driving; rendered p95 18.5 ms.
- **Wave 5** (branch `feature/wave-05-opus`): final candidate `98b41b2`, rendered-verified fallback `d2a6cad`; private
  native macOS packages, provider assets not cleared for public redistribution. See `waves/05/RELEASE_REPORT.md`.
